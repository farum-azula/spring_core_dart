import 'dart:async';
import 'dart:io';

import 'package:spring_boot_starter_test/src/containers/docker_client.dart';
import 'package:spring_boot_starter_test/src/containers/docker_exception.dart';

/// What a [WaitStrategy] can look at: the started container, the ports
/// published for it and the time left to become ready.
///
/// `GenericContainer` implements it for the strategies it runs; custom
/// strategies use only this.
abstract interface class WaitTarget {
  /// The client of the daemon the container runs on.
  DockerClient get docker;

  /// The container's id.
  String get containerId;

  /// The host the published ports are reached on.
  String get host;

  /// The container ports published with `withExposedPorts`.
  List<int> get exposedPorts;

  /// The host port the container's [port] is published on.
  int mappedPort(int port);

  /// How long the strategy may still take; it is the container's startup
  /// timeout, less the time already spent.
  Duration get remaining;

  /// The container's state, as the daemon reports it now.
  Future<DockerContainerState> inspect();

  /// The container's output from its start, following it until it stops.
  Stream<DockerLogLine> logs();

  /// Calls [check] every [interval] until it returns `true`.
  ///
  /// Throws a [ContainerLaunchException] when the container exited in the
  /// meantime, or when [description] did not come true within [remaining].
  Future<void> poll(
    String description,
    Future<bool> Function() check, {
    Duration interval = const Duration(milliseconds: 100),
  });
}

/// Decides when a started container counts as ready for the test: a port
/// that accepts connections, a log line, an HTTP answer, a health check.
///
/// Set one with `GenericContainer.waitingFor`; the [Wait] class makes the
/// ready-made ones. A strategy returns when the container is ready and
/// throws a [ContainerLaunchException] when it cannot become so.
///
/// Testcontainers (Java):
/// `org.testcontainers.containers.wait.strategy.WaitStrategy`.
abstract interface class WaitStrategy {
  /// Returns when [target] is ready, within [WaitTarget.remaining].
  Future<void> waitUntilReady(WaitTarget target);
}

/// The ready-made wait strategies.
///
/// ```dart
/// GenericContainer('redis:7.4-alpine')
///     .withExposedPorts([6379])
///     .waitingFor(Wait.forLogMessage(r'Ready to accept connections', 1));
/// ```
///
/// Testcontainers (Java): `Wait` (`Wait.forListeningPort()`,
/// `Wait.forLogMessage(regex, times)`, `Wait.forHttp(path)`,
/// `Wait.forHealthcheck()`).
abstract final class Wait {
  /// Ready when every published port accepts a connection (the default of
  /// a container; with no published port, when the container runs).
  static WaitStrategy forListeningPort() => const _ListeningPortWait();

  /// Ready when [regex] has matched [times] lines of the container's
  /// output (standard output and error). A `String` is a regular
  /// expression, matched anywhere in the line.
  static WaitStrategy forLogMessage(Pattern regex, [int times = 1]) =>
      _LogMessageWait(regex is String ? RegExp(regex) : regex, times);

  /// Ready when an HTTP request to [path] answers with an expected status
  /// (200 unless [HttpWaitStrategy.forStatusCode] says otherwise), on the
  /// first published port unless [HttpWaitStrategy.forPort] says otherwise.
  static HttpWaitStrategy forHttp(String path) => HttpWaitStrategy._(path);

  /// Ready when the image's `HEALTHCHECK` reports `healthy`. An image
  /// without one fails the start, and so does an `unhealthy` answer.
  static WaitStrategy forHealthcheck() => const _HealthcheckWait();

  /// Ready when all of [strategies] are, one after the other.
  static WaitStrategy forAll(List<WaitStrategy> strategies) =>
      _AllWait(List.unmodifiable(strategies));
}

/// Waits for an HTTP answer: made by `Wait.forHttp(path)`.
///
/// ```dart
/// Wait.forHttp('/realms/neon').forPort(8080).forStatusCode(200)
/// ```
final class HttpWaitStrategy implements WaitStrategy {
  HttpWaitStrategy._(this._path);

  final String _path;
  int? _port;
  String _method = 'GET';
  bool _tls = false;
  final List<int> _statuses = [];
  bool Function(int status)? _matcher;

  /// Requests the container's [port] instead of its first published port.
  HttpWaitStrategy forPort(int port) {
    _port = port;
    return this;
  }

  /// Accepts [status] as ready; call it again to accept more. Without any,
  /// 200 is the expected status.
  HttpWaitStrategy forStatusCode(int status) {
    _statuses.add(status);
    return this;
  }

  /// Accepts every status [matches] says yes to (`(s) => s < 500`).
  HttpWaitStrategy forStatusCodeMatching(bool Function(int status) matches) {
    _matcher = matches;
    return this;
  }

  /// Sends [method] (`HEAD`, `POST`...) instead of `GET`.
  HttpWaitStrategy usingMethod(String method) {
    _method = method;
    return this;
  }

  /// Requests over `https`; the container's certificate is not checked.
  HttpWaitStrategy usingTls() {
    _tls = true;
    return this;
  }

  bool _accepts(int status) =>
      (_matcher?.call(status) ?? false) ||
      (_statuses.isEmpty ? status == 200 : _statuses.contains(status));

  @override
  Future<void> waitUntilReady(WaitTarget target) async {
    final port = _port ?? target.exposedPorts.firstOrNull;
    if (port == null) {
      throw ContainerLaunchException(
        'Wait.forHttp needs a published port: withExposedPorts([...])',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..badCertificateCallback = ((_, _, _) => _tls);
    Uri uri() => Uri(
      scheme: _tls ? 'https' : 'http',
      host: target.host,
      port: target.mappedPort(port),
      path: _path.startsWith('/') ? _path : '/$_path',
    );
    try {
      await target.poll('$_method $_path answering ${_expected()}', () async {
        try {
          final request = await client.openUrl(_method, uri())
            ..followRedirects = false; // the status itself counts
          final response = await request.close();
          await response.drain<void>();
          return _accepts(response.statusCode);
        } on Exception {
          return false; // not listening yet, or the connection was cut
        }
      });
    } finally {
      client.close(force: true);
    }
  }

  String _expected() => _matcher != null
      ? 'as expected'
      : '${_statuses.isEmpty ? [200] : _statuses}';
}

final class _ListeningPortWait implements WaitStrategy {
  const _ListeningPortWait();

  @override
  Future<void> waitUntilReady(WaitTarget target) async {
    if (target.exposedPorts.isEmpty) {
      // Nothing to connect to: the container only has to be running.
      await target.poll('the container running', () async => true);
    }
    for (final port in target.exposedPorts) {
      // The mapped port is read after the check that the container still
      // runs: a container that exited has no published ports.
      await target.poll(
        'port $port accepting connections',
        () => _accepts(target.host, target.mappedPort(port)),
      );
    }
  }

  // Docker Desktop's port forwarder accepts a connection even when nothing
  // listens in the container, and drops it at once: a connection that
  // stays open for a moment counts as listening.
  static Future<bool> _accepts(String host, int port) async {
    final Socket socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 2),
      );
    } on Exception {
      return false;
    }
    final dropped = Completer<bool>();
    socket.listen(
      (_) {},
      onError: (_) {
        if (!dropped.isCompleted) {
          dropped.complete(true);
        }
      },
      onDone: () {
        if (!dropped.isCompleted) {
          dropped.complete(true);
        }
      },
      cancelOnError: true,
    );
    final result = await Future.any([
      dropped.future,
      Future<bool>.delayed(const Duration(milliseconds: 150), () => false),
    ]);
    socket.destroy();
    return !result;
  }
}

final class _LogMessageWait implements WaitStrategy {
  const _LogMessageWait(this.pattern, this.times);

  final Pattern pattern;
  final int times;

  @override
  Future<void> waitUntilReady(WaitTarget target) async {
    var seen = 0;
    final ready = Completer<void>();
    final shown = pattern is RegExp ? (pattern as RegExp).pattern : pattern;
    final what = "$times log line(s) matching '$shown'";
    final subscription = target.logs().listen(
      (line) {
        if (!ready.isCompleted &&
            pattern.allMatches(line.text).isNotEmpty &&
            ++seen >= times) {
          ready.complete();
        }
      },
      onError: (Object error) {
        if (!ready.isCompleted) {
          ready.completeError(error);
        }
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(
            ContainerLaunchException(
              'The container stopped printing before $what ($seen seen)',
            ),
          );
        }
      },
    );
    try {
      await ready.future.timeout(
        target.remaining,
        onTimeout: () => throw ContainerLaunchException(
          'No $what within the startup timeout ($seen seen)',
        ),
      );
    } finally {
      // Not awaited: the daemon ends a followed log only when the container
      // does, and cancelling waits for that.
      unawaited(subscription.cancel());
    }
  }
}

final class _HealthcheckWait implements WaitStrategy {
  const _HealthcheckWait();

  @override
  Future<void> waitUntilReady(WaitTarget target) async {
    await target.poll('the health check reporting healthy', () async {
      final health = (await target.inspect()).health;
      switch (health) {
        case null:
          throw ContainerLaunchException(
            'Wait.forHealthcheck: the image defines no HEALTHCHECK',
          );
        case 'unhealthy':
          throw ContainerLaunchException(
            'The container reports unhealthy',
          );
        default:
          return health == 'healthy';
      }
    });
  }
}

final class _AllWait implements WaitStrategy {
  const _AllWait(this.strategies);

  final List<WaitStrategy> strategies;

  @override
  Future<void> waitUntilReady(WaitTarget target) async {
    for (final strategy in strategies) {
      await strategy.waitUntilReady(target);
    }
  }
}
