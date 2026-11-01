// Only dart:io has the socket, so the hash may use 64-bit integers.
// ignore_for_file: avoid_js_rounded_ints

import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_test/src/containers/container_runtime.dart';
import 'package:spring_boot_starter_test/src/containers/docker_client.dart';
import 'package:spring_boot_starter_test/src/containers/docker_endpoint.dart';
import 'package:spring_boot_starter_test/src/containers/docker_exception.dart';
import 'package:spring_boot_starter_test/src/containers/tar_archive.dart';
import 'package:spring_boot_starter_test/src/containers/wait.dart';

/// A container that can say how an application connects to it: the
/// properties `@ServiceConnection()` puts into the test's context.
///
/// `PostgresContainer` and `KeycloakContainer` implement it. A container
/// of your own does too, to be used with `@ServiceConnection()`.
///
/// Spring Boot: `ConnectionDetails` and `ContainerConnectionDetailsFactory`.
abstract interface class ServiceConnectionProperties {
  /// The properties that point an application at the started container,
  /// such as `spring.datasource.url`. Read after the container started: the
  /// values hold its host and mapped ports.
  Map<String, String> get connectionProperties;
}

/// Any Docker image, started for a test: its environment, command, ports
/// and files set with fluent methods, and a wait strategy that decides when
/// it is ready.
///
/// `start()` pulls the image when it is missing, creates the container
/// with the ports published on random free ports of the host (on the
/// loopback interface), copies the files in, starts it, and returns when
/// the wait strategy says it is ready; `stop()` removes it. Every container
/// is labelled with the id of the test run, so the reaper removes it when
/// the process dies without stopping it (see [ContainerRuntime]). As a
/// `@Container()` field of a test class it is started once before the
/// class's context and stopped after it.
///
/// The fluent methods return the container itself, as `GenericContainer`:
/// on a module such as `PostgresContainer` write cascades (`..withReuse(true)`)
/// to keep its own type.
///
/// ```dart
/// // Redis, from the plain image: a log line says it is ready.
/// final redis = GenericContainer('redis:7.4-alpine')
///     .withExposedPorts([6379])
///     .waitingFor(Wait.forLogMessage(r'Ready to accept connections'));
/// await redis.start();
/// final url = 'redis://${redis.host}:${redis.mappedPort(6379)}';
/// // ...
/// await redis.stop();
/// ```
///
/// Testcontainers (Java):
/// ```java
/// GenericContainer<?> redis = new GenericContainer<>("redis:7.4-alpine")
///     .withExposedPorts(6379)
///     .waitingFor(Wait.forLogMessage(".*Ready to accept connections.*", 1));
/// redis.start();
/// String host = redis.getHost();
/// Integer port = redis.getMappedPort(6379);
/// ```
class GenericContainer implements WaitTarget {
  /// A container of [image] (`postgres:17`, `quay.io/keycloak/keycloak:26.8`);
  /// nothing happens until [start].
  GenericContainer(this.image);

  /// The image the container is created from.
  final String image;

  final Map<String, String> _environment = {};
  final List<int> _ports = [];
  final List<_Copy> _copies = [];
  final Map<String, String> _labels = {};
  List<String>? _command;
  List<String>? _entrypoint;
  WaitStrategy _wait = Wait.forListeningPort();
  Duration _timeout = const Duration(seconds: 60);
  bool _reuse = false;
  ({List<String> test, Duration interval, Duration timeout, int retries})?
  _healthCheck;

  DockerClient? _docker;
  String? _id;
  DockerContainerState? _state;
  Stopwatch? _clock;

  /// Sets the environment variable [name].
  GenericContainer withEnv(String name, String value) {
    _environment[name] = value;
    return this;
  }

  /// Sets several environment variables.
  GenericContainer withEnvironment(Map<String, String> variables) {
    _environment.addAll(variables);
    return this;
  }

  /// Replaces the image's default command (`CMD`) with [command].
  GenericContainer withCommand(List<String> command) {
    _command = List.of(command);
    return this;
  }

  /// Replaces the image's entry point with [entrypoint].
  GenericContainer withEntrypoint(List<String> entrypoint) {
    _entrypoint = List.of(entrypoint);
    return this;
  }

  /// Publishes the container's TCP [ports] on random free ports of the
  /// host; [mappedPort] says which.
  GenericContainer withExposedPorts(List<int> ports) {
    for (final port in ports) {
      if (!_ports.contains(port)) {
        _ports.add(port);
      }
    }
    return this;
  }

  /// Copies the file at [hostPath] to [containerPath] in the container
  /// before it starts. A relative [hostPath] starts at the working
  /// directory (the package, under `dart test`); the file is read at
  /// [start]. [mode] is the permission (`0644` by default, as `0x1A4`).
  GenericContainer withCopyFile(
    String hostPath,
    String containerPath, {
    int mode = 420,
  }) {
    _copies.add(_Copy(containerPath, mode, hostPath: hostPath));
    return this;
  }

  /// Creates the file [containerPath] with [content] (a `String` or bytes)
  /// in the container before it starts.
  GenericContainer withCopyContent(
    Object content,
    String containerPath, {
    int mode = 420,
  }) {
    _copies.add(
      _Copy(
        containerPath,
        mode,
        content: content is String
            ? utf8.encode(content)
            : content as List<int>,
      ),
    );
    return this;
  }

  /// Adds the label [name]=[value] to the container.
  GenericContainer withLabel(String name, String value) {
    _labels[name] = value;
    return this;
  }

  /// Decides when the started container counts as ready: see [Wait]. By
  /// default `Wait.forListeningPort()`.
  GenericContainer waitingFor(WaitStrategy strategy) {
    _wait = strategy;
    return this;
  }

  /// Gives the container a health check, for `Wait.forHealthcheck()` and
  /// for images that define none: [test] is the command in exec form
  /// (`['CMD-SHELL', 'pg_isready -U test']`), run every [interval]; after
  /// [retries] failures the container is `unhealthy`.
  GenericContainer withHealthCheck(
    List<String> test, {
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 3),
    int retries = 10,
  }) {
    _healthCheck = (
      test: List.of(test),
      interval: interval,
      timeout: timeout,
      retries: retries,
    );
    return this;
  }

  /// How long the wait strategy may take (60 seconds by default); the image
  /// pull is not counted.
  GenericContainer withStartupTimeout(Duration timeout) {
    _timeout = timeout;
    return this;
  }

  /// Keeps the container alive after the tests, for the next run to use
  /// again (off by default, and ignored when the `CI` environment variable
  /// is set).
  ///
  /// The container is found again by a hash of its configuration (image,
  /// environment, command, ports, files and labels), so a changed
  /// configuration makes a new one. It carries no run id, so the reaper
  /// leaves it alone, and [stop] does not remove it: remove it by hand with
  /// ``docker rm -f $(docker ps -aq --filter
  /// label=org.testcontainers.reuse.hash)``.
  /// Use it for fast iterations on a laptop; the data inside survives, so
  /// tests must clean up after themselves.
  ///
  /// Testcontainers (Java): `withReuse(true)`, which also needs
  /// `testcontainers.reuse.enable=true` in `~/.testcontainers.properties`.
  GenericContainer withReuse(bool reuse) {
    _reuse = reuse;
    return this;
  }

  /// The wait strategy, for modules that extend it.
  WaitStrategy get waitStrategy => _wait;

  /// Whether [start] succeeded and [stop] was not called since.
  bool get isStarted => _id != null;

  /// The container's id; throws before [start].
  @override
  String get containerId =>
      _id ?? (throw StateError('The container of $image is not started'));

  /// The host the published ports are reached on: `127.0.0.1` for a local
  /// daemon.
  @override
  String get host =>
      _docker?.endpoint.containerHost ??
      DockerEndpoint.resolve()?.containerHost ??
      '127.0.0.1';

  /// The port on [host] that the container's [port] is published on; the
  /// port must be listed in [withExposedPorts], and the container started.
  @override
  int mappedPort(int port) {
    final state = _state;
    if (state == null) {
      throw StateError(
        'The container of $image is not started: call start() before '
        'mappedPort',
      );
    }
    return state.mappedPort(port) ??
        (throw StateError(
          'Port $port of $image is not published: add it with '
          'withExposedPorts([$port]) '
          '(published: ${state.ports.keys.join(', ')})',
        ));
  }

  /// `scheme://host:port` of the container's [port]: `http` unless
  /// [scheme] says otherwise.
  String baseUrl(int port, {String scheme = 'http'}) =>
      '$scheme://$host:${mappedPort(port)}';

  @override
  List<int> get exposedPorts => List.unmodifiable(_ports);

  @override
  DockerClient get docker => _docker ?? (throw StateError('Not started'));

  @override
  Duration get remaining => _timeout - (_clock?.elapsed ?? Duration.zero);

  @override
  Future<DockerContainerState> inspect() async =>
      _state = await docker.inspectContainer(containerId);

  @override
  Stream<DockerLogLine> logs() =>
      docker.containerLogs(containerId, follow: true);

  /// Everything the container printed so far, standard output and error
  /// together.
  Future<String> getLogs() async {
    final lines = await docker.containerLogs(containerId).toList();
    return lines.map((line) => line.text).join('\n');
  }

  /// Runs [command] in the started container and waits for it.
  Future<DockerExecResult> execInContainer(List<String> command) =>
      docker.exec(containerId, command);

  @override
  Future<void> poll(
    String description,
    Future<bool> Function() check, {
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    while (true) {
      final state = await inspect();
      if (!state.running) {
        throw ContainerLaunchException(
          'The container of $image stopped (${state.status}, exit code '
          '${state.exitCode}) before $description',
        );
      }
      if (await check()) {
        return;
      }
      if (remaining <= Duration.zero) {
        throw ContainerLaunchException(
          'The container of $image was not ready after '
          '${_timeout.inSeconds} s: waiting for $description',
        );
      }
      await Future<void>.delayed(interval);
    }
  }

  /// Pulls the image if it is missing, creates the container, copies the
  /// files in, starts it and waits until it is ready.
  ///
  /// Does nothing when it is started already. When it does not become ready
  /// the container is removed and a [ContainerLaunchException] tells why,
  /// with the last lines the container printed. Throws a
  /// [DockerUnavailableException] without a daemon and a [DockerException]
  /// with the daemon's message for its refusals (a missing image, a port in
  /// use).
  Future<void> start() async {
    if (_id != null) {
      return;
    }
    final runtime = ContainerRuntime.instance;
    final docker = await runtime.client();
    _docker = docker;
    final files = [for (final copy in _copies) copy.file()];
    final reusable = _reuse && !_runsOnCi;
    final hash = reusable ? _configurationHash(files) : null;
    String? id;
    if (hash != null) {
      final found = await docker.listContainers(
        labels: ['${ContainerRuntime.reuseLabel}=$hash'],
      );
      id = found.where((c) => c.state == 'running').firstOrNull?.id;
    }
    var protectedByReaper = false;
    try {
      if (id == null) {
        if (!await docker.imageExists(image)) {
          await docker.pullImage(image);
        }
        if (!reusable) {
          await runtime.protect();
          protectedByReaper = true;
        }
        id = await docker.createContainer(
          DockerContainerConfig(
            image: image,
            environment: _environment,
            command: _command,
            entrypoint: _entrypoint,
            exposedPorts: _ports,
            labels:
                {
                  ...runtime.labels,
                  ..._labels,
                  ContainerRuntime.reuseLabel: ?hash,
                }..removeWhere(
                  // A reusable container carries no run id: the reaper must
                  // not remove it.
                  (name, _) =>
                      reusable && name == ContainerRuntime.sessionLabel,
                ),
            publishIp: docker.endpoint.publishIp,
            healthCheck: _healthCheck,
          ),
        );
        _id = id;
        if (files.isNotEmpty) {
          await docker.putFiles(id, files);
        }
        await docker.startContainer(id);
      }
      _id = id;
      _clock = Stopwatch()..start();
      await _refreshPorts();
      await _wait.waitUntilReady(this);
    } on Object catch (error) {
      final logs = await _lastLines();
      await _discard(releaseReaper: protectedByReaper);
      if (error is ContainerLaunchException && logs.isNotEmpty) {
        throw ContainerLaunchException(
          '${error.message}\nLast output of the container:\n$logs',
        );
      }
      rethrow;
    } finally {
      _clock?.stop();
    }
  }

  /// Removes the container (killing it when it still runs). A container
  /// that is not started, or was found again through [withReuse], is left
  /// as it is.
  Future<void> stop() async {
    final id = _id;
    if (id == null) {
      return;
    }
    final reused = _reuse && !_runsOnCi;
    await _discard(releaseReaper: !reused, remove: !reused);
  }

  // The ports of a container the daemon publishes at start; Docker Desktop
  // may report them a moment late.
  Future<void> _refreshPorts() async {
    var state = await inspect();
    for (var tries = 0; tries < 30; tries++) {
      if (_ports.every((port) => state.mappedPort(port) != null)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      state = await inspect();
    }
  }

  Future<String> _lastLines() async {
    final id = _id;
    final docker = _docker;
    if (id == null || docker == null) {
      return '';
    }
    try {
      final lines = await docker.containerLogs(id, tail: 40).toList();
      return lines.map((line) => line.text).join('\n');
    } on Exception {
      return '';
    }
  }

  Future<void> _discard({
    bool releaseReaper = true,
    bool remove = true,
  }) async {
    final id = _id;
    _id = null;
    _state = null;
    if (id == null) {
      return;
    }
    try {
      if (remove) {
        await _docker?.removeContainer(id);
      }
    } finally {
      if (releaseReaper) {
        ContainerRuntime.instance.release();
      }
    }
  }

  static bool get _runsOnCi {
    final ci = Platform.environment['CI'] ?? '';
    return ci.isNotEmpty && ci.toLowerCase() != 'false';
  }

  // Not a cryptographic hash: it only tells configurations apart. Two
  // 64-bit FNV-1a runs with different seeds.
  String _configurationHash(List<TarFile> files) {
    final text = jsonEncode({
      'image': image,
      'env': Map.fromEntries(
        _environment.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
      'cmd': _command,
      'entrypoint': _entrypoint,
      'ports': ([..._ports]..sort()),
      'health': _healthCheck?.test,
      'labels': Map.fromEntries(
        _labels.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
      'files': [
        for (final file in files)
          [file.path, file.mode, _fnv(file.bytes, 0xcbf29ce484222325)],
      ],
    });
    final bytes = utf8.encode(text);
    String hex(int value) => [
      (value >>> 32) & 0xFFFFFFFF,
      value & 0xFFFFFFFF,
    ].map((half) => half.toRadixString(16).padLeft(8, '0')).join();
    return hex(_fnv(bytes, 0xcbf29ce484222325)) +
        hex(_fnv(bytes, 0x84222325cbf29ce4));
  }

  static int _fnv(List<int> bytes, int seed) {
    var hash = seed;
    for (final byte in bytes) {
      hash = (hash ^ byte) * 0x100000001b3;
    }
    return hash;
  }

  @override
  String toString() => 'GenericContainer($image)';
}

/// A file to copy into the container: from the host or from memory.
final class _Copy {
  _Copy(this.containerPath, this.mode, {this.hostPath, this.content});

  final String containerPath;
  final int mode;
  final String? hostPath;
  final List<int>? content;

  TarFile file() {
    if (content case final bytes?) {
      return TarFile(containerPath, bytes, mode: mode);
    }
    final file = File(hostPath!);
    if (!file.existsSync()) {
      throw ArgumentError.value(
        hostPath,
        'hostPath',
        'withCopyFile: no such file (a relative path starts at '
            '${Directory.current.path})',
      );
    }
    return TarFile(containerPath, file.readAsBytesSync(), mode: mode);
  }
}
