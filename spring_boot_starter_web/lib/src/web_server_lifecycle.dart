import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/web_server.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.server');

/// Which web server a test (or a run) starts: `spring.test.web-environment`,
/// set by `springBootTest(webEnvironment:)`.
///
/// - `mock`: no server; `MockMvc` calls the dispatcher in memory (the test
///   default);
/// - `random-port`: a real server on a free port;
/// - `defined-port`: a real server on `server.port`;
/// - `none`: no server.
///
/// Outside tests the server starts unless
/// `spring.main.web-application-type=none`.
const webEnvironmentProperty = 'spring.test.web-environment';

/// Starts the [WebServer] when the context is ready and stops it first when
/// it closes, like Spring Boot's `WebServerStartStopLifecycle` (with the
/// graceful shutdown of `WebServerGracefulShutdownLifecycle`).
///
/// `dart:io` binds sockets asynchronously: [started] completes once the
/// server listens (tests await it). A failure (a port in use) is reported
/// like a startup failure and closes the context.
///
/// In a Flutter app the context pauses in the background: the server
/// stops (freeing the port) and starts again when the app comes back.
final class WebServerStartStopLifecycle
    with SmartLifecycle
    implements ApplicationContextAware {
  /// Starts a server of [factory] for [handler], configured by
  /// [environment].
  WebServerStartStopLifecycle(
    this.factory,
    this.handler,
    this.environment, {
    this.shutdownTimeout,
  });

  /// Creates the server.
  final WebServerFactory factory;

  /// Answers the requests.
  final HttpHandler handler;

  /// Decides whether the server runs (`spring.main.web-application-type`,
  /// `spring.test.web-environment`) and gets `local.server.port`.
  final Environment environment;

  /// How long a graceful shutdown waits for running requests
  /// (`spring.lifecycle.timeout-per-shutdown-phase`, 30 s by default).
  final Duration? shutdownTimeout;

  ApplicationContext? _context;
  WebServer? _server;
  var _running = false;
  Completer<WebServer?> _started = Completer<WebServer?>();

  @override
  void setApplicationContext(ApplicationContext context) => _context = context;

  /// Spring Boot's phase (`DEFAULT_PHASE - 2048`): the server starts before
  /// the lifecycle beans of the default phase and stops after them.
  @override
  int get phase => SmartLifecycle.defaultPhase - 2048;

  @override
  bool get isRunning => _running;

  /// The running server, or `null`.
  WebServer? get webServer => _server;

  /// Completes with the server once it listens (`null` when no server
  /// runs: `spring.main.web-application-type=none`, a mock web
  /// environment); fails when it could not start.
  Future<WebServer?> get started => _started.future;

  /// Whether a server should run.
  bool get isEnabled {
    final type = environment
        .getProperty('spring.main.web-application-type')
        ?.trim()
        .toLowerCase();
    if (type == 'none') {
      return false;
    }
    final test = environment.getProperty(webEnvironmentProperty)?.trim();
    return test == null || test == 'random-port' || test == 'defined-port';
  }

  @override
  void start() {
    if (_running) {
      return;
    }
    _running = true;
    if (_started.isCompleted) {
      _started = Completer<WebServer?>();
    }
    if (!isEnabled) {
      _started.complete(null);
      return;
    }
    final server = factory.getWebServer(handler);
    _server = server;
    final started = _started;
    server.start().then(
      (_) {
        if (!_running || !identical(_server, server)) {
          // Stopped while the socket was opening: stop() closes it.
          if (!started.isCompleted) {
            started.complete(null);
          }
          return;
        }
        _setLocalPort(server.port);
        final scheme = environment.getProperty('server.ssl.certificate') == null
            ? 'http'
            : 'https';
        _log.info('Web server started on port ${server.port} ($scheme)');
        final context = _context;
        if (context is ConfigurableApplicationContext && context.isActive) {
          context.publishEvent(
            WebServerInitializedEvent(context, server, server.port),
          );
        }
        if (!started.isCompleted) {
          started.complete(server);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _running = false;
        _server = null;
        _report(error, stackTrace);
        if (!started.isCompleted) {
          started.completeError(error, stackTrace);
          // Nobody may listen (a plain run): no unhandled error then.
          started.future.ignore();
        }
        final context = _context;
        if (context is ConfigurableApplicationContext && context.isActive) {
          unawaited(context.closeAsync());
        }
      },
    );
  }

  void _report(Object error, StackTrace stackTrace) {
    final analysis = const PortInUseFailureAnalyzer().analyze(error);
    if (analysis != null) {
      _log.error(analysis.report);
    } else {
      _log.error(
        'Web server failed to start',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _setLocalPort(int port) {
    final environment = this.environment;
    if (environment is ConfigurableEnvironment) {
      final sources = environment.propertySources;
      const name = 'server.ports';
      final existing = sources.get(name);
      final values = <String, Object?>{
        if (existing is MapPropertySource) ...existing.source,
        'local.server.port': '$port',
      };
      if (existing != null) {
        sources.replace(name, MapPropertySource(name, values));
      } else {
        sources.addFirst(MapPropertySource(name, values));
      }
    }
  }

  @override
  void stop() => stopWithCallback(() {});

  @override
  void stopWithCallback(void Function() callback) {
    final server = _server;
    _running = false;
    _server = null;
    if (server == null) {
      callback();
      return;
    }
    server
        .stop(timeout: shutdownTimeout)
        .then(
          (_) => _log.info('Web server stopped'),
          onError: (Object error, StackTrace stackTrace) => _log.warning(
            'Web server failed to stop',
            error: error,
            stackTrace: stackTrace,
          ),
        )
        .whenComplete(callback);
  }
}
