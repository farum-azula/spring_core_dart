import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_edge/src/edge_scheduled.dart';
import 'package:spring_boot_starter_edge/src/fetch/fetch_exchange.dart';
import 'package:spring_boot_starter_edge/src/fetch/fetch_web_server.dart';

const _log = SpringLog('spring.edge');

/// A Spring Boot application behind the fetch API: the context starts
/// once per instance of the function, with the first request (or when the
/// platform's entry asks for it), and every request goes to its
/// dispatcher.
///
/// `runFetchApplication` makes one and gives it to the platform.
/// Applications use it in tests, to call the application as a platform
/// would, without one:
///
/// ```dart
/// final function = FetchApplication(() => springApplication);
/// final response = await function.fetch(
///   FetchRequest('GET', Uri.parse('https://example.com/books')),
///   environment: {'SUPABASE_URL': 'http://127.0.0.1:54321'},
/// );
/// expect(response.status, 200);
/// await function.close();
/// ```
///
/// Spring (Java): the serverless Java container's
/// `SpringBootLambdaContainerHandler`, which starts the application once
/// and proxies every event to its `DispatcherServlet`.
final class FetchApplication {
  /// The function of [application] (the generated `springApplication`),
  /// on [runtime] (`supabase`, `cloudflare`, `aws`; `test` by default)
  /// with [properties] above every other property source.
  FetchApplication(
    this.application, {
    this.runtime = 'test',
    this.properties = const {},
  });

  /// Gives the application to start.
  final SpringApplication Function() application;

  /// The value of `spring.edge.runtime`.
  final String runtime;

  /// Properties above every other source.
  final Map<String, Object?> properties;

  Future<ConfigurableApplicationContext>? _starting;
  ConfigurableApplicationContext? _context;
  FetchWebServer? _server;

  /// The context, once it started.
  ConfigurableApplicationContext? get context => _context;

  /// Starts the context if it has not started, with [environment] as the
  /// environment variables (the platform's: `Deno.env`, the Worker's
  /// `env`, `process.env`). Calls made while it starts wait for the same
  /// start; a start that failed is tried again by the next call.
  Future<ConfigurableApplicationContext> start({
    Map<String, String> environment = const {},
  }) => _starting ??= _start(environment);

  Future<ConfigurableApplicationContext> _start(
    Map<String, String> environment,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final context = await application().runAsync(
        const [],
        systemEnvironment: environment,
        properties: {
          'spring.edge.runtime': runtime,
          // A function has no process to end and no signals to wait for.
          'spring.main.register-shutdown-hook': false,
          ...properties,
        },
      );
      _context = context;
      final factory = context
          .getBeanProvider<FetchWebServerFactory>()
          .getIfAvailable();
      _server = factory?.server;
      if (_server == null) {
        _log.warning(
          'The application has no fetch server (another WebServerFactory '
          'bean, or spring.main.web-application-type=none): every request '
          'is answered with 503',
        );
      }
      _log.info('Function started in ${watch.elapsedMilliseconds} ms');
      return context;
    } on Object {
      _starting = null;
      rethrow;
    }
  }

  /// Answers [request], starting the context first when this is the first
  /// one. Never fails: an application that cannot start is a 500 (logged
  /// with its reason, which the answer does not carry).
  Future<FetchResponse> fetch(
    FetchRequest request, {
    Map<String, String> environment = const {},
  }) async {
    try {
      await start(environment: environment);
    } on Object catch (error, stackTrace) {
      _log.error(
        'The application did not start',
        error: error,
        stackTrace: stackTrace,
      );
      return _problem(500, 'Internal Server Error', null);
    }
    final server = _server;
    if (server == null) {
      return _problem(
        503,
        'Service Unavailable',
        'The application serves no requests',
      );
    }
    return await server.fetch(request);
  }

  /// Hands [event] (the platform ran the function by a schedule) to every
  /// [EdgeScheduledHandler] bean, one after the other, starting the
  /// context first when it has not started. Fails when the application
  /// cannot start or a handler failed, after the other handlers ran: the
  /// platform then records a failed run.
  Future<void> scheduled(
    EdgeScheduledEvent event, {
    Map<String, String> environment = const {},
  }) async {
    final context = await start(environment: environment);
    final handlers = context.getBeansOfType<EdgeScheduledHandler>();
    if (handlers.isEmpty) {
      _log.warning(
        'The platform ran the function by a schedule ($event), and the '
        'application has no EdgeScheduledHandler bean',
      );
      return;
    }
    Object? failure;
    StackTrace? failureTrace;
    for (final MapEntry(:key, :value) in handlers.entries) {
      try {
        await value.onScheduled(event);
      } on Object catch (error, stackTrace) {
        _log.error(
          "The scheduled handler '$key' failed for $event",
          error: error,
          stackTrace: stackTrace,
        );
        failure ??= error;
        failureTrace ??= stackTrace;
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureTrace!);
    }
  }

  /// Closes the context; the next request starts a new one.
  Future<void> close() async {
    final starting = _starting;
    _starting = null;
    _server = null;
    _context = null;
    if (starting == null) {
      return;
    }
    try {
      await (await starting).closeAsync();
    } on Object {
      // It did not start: nothing to close.
    }
  }

  static FetchResponse _problem(int status, String title, String? detail) {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'type': 'about:blank',
          'title': title,
          'status': status,
          'detail': ?detail,
        }),
      ),
    );
    return FetchResponse(status, [
      ('content-type', 'application/problem+json'),
      ('content-length', '${bytes.length}'),
    ], bytes: bytes);
  }
}
