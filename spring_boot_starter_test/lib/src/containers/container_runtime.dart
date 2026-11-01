import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:spring_boot_starter_test/src/containers/docker_client.dart';
import 'package:spring_boot_starter_test/src/containers/docker_exception.dart';

/// What every container of one test process shares: the connection to the
/// daemon, the id of the run, and the reaper that removes the run's
/// containers when the process dies.
///
/// A run is one isolate, which is one test file under `dart test`. Every
/// container is labelled `org.testcontainers.sessionId=<run id>`. Before
/// the first container of the run, a reaper starts: a container of
/// Testcontainers' own image, `testcontainers/ryuk`, that listens on a TCP
/// port. The run connects, sends the label filter and keeps the connection
/// open; when the process ends, however it ends (even `kill -9`), the
/// connection drops, and Ryuk removes every container, network and volume
/// with the label ten seconds later (unless the run connects again) and
/// exits. The run's own `stop()` removes its containers at once; Ryuk is
/// the safety net.
///
/// The connection closes with the last running container, so a script that
/// stopped everything can exit; a later start connects again to the same
/// Ryuk when it is still there, or starts a new one. Opt out with
/// `TESTCONTAINERS_RYUK_DISABLED=true`; the image is
/// `TESTCONTAINERS_RYUK_CONTAINER_IMAGE` (default
/// `testcontainers/ryuk:0.14.0`).
///
/// Testcontainers (Java): `ResourceReaper` and `RyukResourceReaper`.
final class ContainerRuntime {
  ContainerRuntime._();

  /// The runtime of this isolate.
  static final ContainerRuntime instance = ContainerRuntime._();

  /// The label every container of this run carries.
  static const sessionLabel = 'org.testcontainers.sessionId';

  /// The label of containers a test library made.
  static const markerLabel = 'org.testcontainers';

  /// The label that says which library made the container.
  static const langLabel = 'org.testcontainers.lang';

  /// The label with the hash of the configuration of a reusable container.
  static const reuseLabel = 'org.testcontainers.reuse.hash';

  static const _ryukLabel = 'org.testcontainers.ryuk';
  static const _ryukImage = 'testcontainers/ryuk:0.14.0';
  static const _ryukPort = 8080;

  /// This run's id.
  final String sessionId = _newSessionId();

  static String _newSessionId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<DockerClient>? _client;
  Future<void>? _reaperStart;
  Socket? _reaperSocket;
  ({String host, int port})? _ryuk;
  int _protected = 0;

  /// Whether the reaper is switched off (`TESTCONTAINERS_RYUK_DISABLED`).
  static bool get reaperDisabled =>
      (Platform.environment['TESTCONTAINERS_RYUK_DISABLED'] ?? '')
          .toLowerCase() ==
      'true';

  /// The labels a container of this run gets.
  Map<String, String> get labels => {
    markerLabel: 'true',
    langLabel: 'dart',
    sessionLabel: sessionId,
  };

  /// The client of the daemon, connected on first use; a failure to
  /// connect is not remembered, so a later call tries again.
  Future<DockerClient> client() async {
    final pending = _client ??= DockerClient.connect();
    try {
      return await pending;
    } on Object {
      _client = null;
      rethrow;
    }
  }

  /// Makes sure the reaper watches this run, before a container of the run
  /// is created, and counts the container: call [release] when it is
  /// removed. Does nothing but count when the reaper is disabled.
  Future<void> protect() async {
    _protected++;
    if (reaperDisabled) {
      return;
    }
    try {
      if (_reaperSocket == null) {
        await (_reaperStart ??= _connectReaper().whenComplete(
          () => _reaperStart = null,
        ));
      }
    } on Object {
      _protected--;
      rethrow;
    }
  }

  /// Counts a container less; with none left the connection to the reaper
  /// closes.
  void release() {
    if (_protected > 0 && --_protected == 0) {
      _reaperSocket?.destroy();
      _reaperSocket = null;
    }
  }

  Future<void> _connectReaper() async {
    final docker = await client();
    if (_ryuk case final known?) {
      try {
        _reaperSocket = await _register(known.host, known.port, 3);
        return;
      } on Object {
        _ryuk = null; // it is gone: start a new one
      }
    }
    final image =
        Platform.environment['TESTCONTAINERS_RYUK_CONTAINER_IMAGE'] ??
        _ryukImage;
    try {
      if (!await docker.imageExists(image)) {
        await docker.pullImage(image);
      }
      // The reaper needs the daemon's socket: the VM's of Docker Desktop
      // and Colima, the real one on Linux.
      final socket = docker.endpoint.isUnix && Platform.isLinux
          ? docker.endpoint.socketPath!
          : '/var/run/docker.sock';
      final id = await docker.createContainer(
        DockerContainerConfig(
          image: image,
          exposedPorts: const [_ryukPort],
          labels: const {
            ContainerRuntime.markerLabel: 'true',
            ContainerRuntime.langLabel: 'dart',
            _ryukLabel: 'true',
          },
          binds: ['$socket:/var/run/docker.sock'],
          autoRemove: true,
          publishIp: docker.endpoint.publishIp,
        ),
      );
      await docker.startContainer(id);
      final port = (await docker.inspectContainer(id)).mappedPort(_ryukPort);
      if (port == null) {
        throw DockerException('The reaper container published no port');
      }
      final host = docker.endpoint.containerHost;
      _ryuk = (host: host, port: port);
      _reaperSocket = await _register(host, port, 30);
    } on DockerException catch (e) {
      throw DockerException(
        'The reaper (Ryuk, which removes the containers of a test run that '
        'died) did not start: ${e.message}. Set '
        'TESTCONTAINERS_RYUK_DISABLED=true to run without it.',
        statusCode: e.statusCode,
      );
    }
  }

  // Connects to Ryuk, which may still be starting, sends the label filter
  // and waits for its ACK. The connection stays open: its end is the
  // signal to clean up.
  Future<Socket> _register(String host, int port, int seconds) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    Object? last;
    while (DateTime.now().isBefore(deadline)) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 2),
        );
        final acknowledged = Completer<void>();
        final text = StringBuffer();
        socket.listen(
          (data) {
            text.write(utf8.decode(data, allowMalformed: true));
            if (text.toString().contains('ACK') && !acknowledged.isCompleted) {
              acknowledged.complete();
            }
          },
          onError: (Object _) {},
          onDone: () {
            if (!acknowledged.isCompleted) {
              acknowledged.completeError(
                const SocketException('The reaper closed the connection'),
              );
            }
            if (identical(_reaperSocket, socket)) {
              _reaperSocket = null;
            }
          },
        );
        socket.write('label=$sessionLabel=$sessionId\n');
        await acknowledged.future.timeout(const Duration(seconds: 3));
        return socket;
      } on Exception catch (e) {
        last = e;
        socket?.destroy();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw DockerException('Cannot reach the reaper at $host:$port: $last');
  }
}
