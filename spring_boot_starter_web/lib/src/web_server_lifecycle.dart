import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/web_server.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.server');

/// The name of the property, `spring.test.web-environment`, that tells
/// whether a test starts a real server.
///
/// `springBootTest(webEnvironment:)` of the test starter sets it; a test
/// with `ApplicationContextRunner` may set it by hand. Its values:
///
/// - `mock`: no server; `MockMvc` calls the dispatcher in memory (the
///   default of `springBootTest`);
/// - `random-port`: a real server on a free port;
/// - `defined-port`: a real server on `server.port`;
/// - `none`: no server.
///
/// Any other value starts no server either. When the property is not
/// set, as in a normal run, the server starts unless
/// `spring.main.web-application-type=none`.
const webEnvironmentProperty = 'spring.test.web-environment';

/// Starts the HTTP server when the application context is ready and
/// stops it when the context closes.
///
/// The starter declares it as the `webServerStartStopLifecycle` bean, so
/// the server follows the context and nobody calls `start` by hand. Its
/// phase, Spring Boot's, makes the server start before the lifecycle
/// beans of the default phase and stop after them. When it stops, the
/// server shuts down as `server.shutdown` says, gracefully by default.
///
/// The socket is bound asynchronously, so `start` returns before the
/// server listens; [started] completes when it does. The port is then
/// published as the `local.server.port` property and in a
/// [WebServerInitializedEvent]. `SpringApplication` waits for it
/// ([AsyncStartup]): a failure to start, such as a port in use, fails the
/// start as in Spring Boot, with the startup report, no
/// `ApplicationReadyEvent`, no runners, and the error thrown by
/// `runAsync` (the program ends with a non-zero exit code). In a context
/// started without `SpringApplication`, the failure is logged as a
/// startup report and closes the context.
///
/// In a Flutter app the context pauses in the background: the server
/// stops (freeing the port) and starts again when the app comes back.
///
/// ```dart
/// // A test that needs the real server before it calls it.
/// final lifecycle = context.getBean<WebServerStartStopLifecycle>();
/// final server = await lifecycle.started;
/// final uri = Uri.parse('http://localhost:${server!.port}/api/books');
/// ```
///
/// Spring Boot's counterparts are `WebServerStartStopLifecycle` and, for
/// the graceful shutdown, `WebServerGracefulShutdownLifecycle`.
final class WebServerStartStopLifecycle
    with SmartLifecycle
    implements ApplicationContextAware, AsyncStartup {
  /// A lifecycle that starts a server of [factory] for [handler], when
  /// [environment] says a server should run.
  WebServerStartStopLifecycle(
    this.factory,
    this.handler,
    this.environment, {
    this.shutdownTimeout,
  });

  /// Creates a server at each start.
  final WebServerFactory factory;

  /// Answers every request; in the application, the `dispatcherHandler`.
  final HttpHandler handler;

  /// The configuration that decides whether the server runs
  /// (`spring.main.web-application-type`, `spring.test.web-environment`),
  /// and that receives the `local.server.port` property.
  final Environment environment;

  /// How long a graceful shutdown waits for running requests
  /// (`spring.lifecycle.timeout-per-shutdown-phase`); `null` lets the
  /// server use its own default, 30 seconds for the `dart:io` server.
  final Duration? shutdownTimeout;

  ApplicationContext? _context;
  WebServer? _server;
  var _running = false;
  Completer<WebServer?> _started = Completer<WebServer?>();
  // Whether [awaitStartup] handed the current start's failure to its
  // caller (SpringApplication), which then reports it.
  var _claimed = false;

  @override
  void setApplicationContext(ApplicationContext context) => _context = context;

  /// `SmartLifecycle.defaultPhase - 2048`, Spring Boot's phase for the
  /// server: it starts before the lifecycle beans of the default phase
  /// and stops after them.
  @override
  int get phase => SmartLifecycle.defaultPhase - 2048;

  @override
  bool get isRunning => _running;

  /// The server while it runs or starts; `null` when stopped, when no
  /// server should run, or after it failed to start.
  WebServer? get webServer => _server;

  /// Completes with the server once it listens, with `null` when no
  /// server runs (`spring.main.web-application-type=none`, a mock web
  /// environment) or when it was stopped while starting. Fails with the
  /// error when the server could not start. Each start gives a new
  /// future.
  Future<WebServer?> get started => _started.future;

  /// The current start, for `SpringApplication`: completes once the
  /// server listens (or when no server runs), fails when it cannot start.
  /// The caller reports the failure and closes the context.
  @override
  Future<void> awaitStartup() {
    _claimed = true;
    return _started.future.then((_) {});
  }

  /// Whether a server should run: not when
  /// `spring.main.web-application-type=none`, and in a test only for
  /// the `random-port` and `defined-port` web environments (see
  /// [webEnvironmentProperty]).
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
      _claimed = false;
    }
    if (!isEnabled) {
      _started.complete(null);
      return;
    }
    final server = factory.getWebServer(handler);
    _server = server;
    final started = _started;
    unawaited(
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
          final scheme =
              environment.getProperty('server.ssl.certificate') == null
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
          final claimed = _claimed;
          if (!started.isCompleted) {
            started.completeError(error, stackTrace);
            // Nobody may listen (a plain run): no unhandled error then.
            started.future.ignore();
          }
          if (claimed) {
            // SpringApplication reports it and closes the context.
            return;
          }
          _report(error, stackTrace);
          final context = _context;
          if (context is ConfigurableApplicationContext && context.isActive) {
            unawaited(context.closeAsync());
          }
        },
      ),
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
    unawaited(
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
          .whenComplete(callback),
    );
  }
}
