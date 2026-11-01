import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/cors.dart';
import 'package:spring_boot_starter_web/src/request_mapping.dart';
import 'package:spring_boot_starter_web/src/request_timeout.dart';
import 'package:spring_boot_starter_web/src/response_writer.dart';
import 'package:spring_boot_starter_web/src/web_exceptions.dart';
import 'package:spring_boot_starter_web/src/web_logging.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.servlet.DispatcherServlet');

/// Code that runs around every request, before the request reaches a
/// controller.
///
/// Use a filter for work that concerns all requests rather than one
/// endpoint: adding a header, logging, checking a token, rejecting
/// requests early, or wrapping the request or response. Declare it as a
/// bean; the starter runs every `WebFilter` bean in `@Order`, before the
/// handler is looked up, so a filter also sees requests that end in a 404.
/// The security starter's filter chain is one such filter. For work tied
/// to the controllers (with the handler at hand, or after its result),
/// a `HandlerInterceptor` fits better.
///
/// An exception thrown by a filter skips the `@ExceptionHandler` methods
/// and the `HandlerExceptionResolver` beans, and gets the default error
/// answer.
///
/// ```dart
/// // Every answer carries an id the logs can be searched by.
/// @Component()
/// @Order(Ordered.highestPrecedence)
/// class RequestIdFilter implements WebFilter {
///   @override
///   Future<void> doFilter(request, response, chain) {
///     response.headers.set('X-Request-Id', newId());
///     return chain.doFilter(request, response);
///   }
/// }
/// ```
///
/// Spring (Java), with a servlet filter:
/// ```java
/// @Component
/// @Order(Ordered.HIGHEST_PRECEDENCE)
/// class RequestIdFilter implements Filter {
///   public void doFilter(ServletRequest request, ServletResponse response,
///       FilterChain chain) throws IOException, ServletException {
///     ((HttpServletResponse) response).setHeader("X-Request-Id", newId());
///     chain.doFilter(request, response);
///   }
/// }
/// ```
abstract interface class WebFilter {
  /// Handles [request]: call `chain.doFilter` to pass it on (the same
  /// request, or a wrapped one such as a `ServerHttpRequestDecorator`),
  /// or answer through [response] and return without calling the chain.
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  );
}

/// What comes after a filter: the remaining filters, then the handler.
///
/// A [WebFilter] receives it in `doFilter` and calls it to let the request
/// go on; not calling it stops the request at that filter.
abstract interface class WebFilterChain {
  /// Runs the next filter (or, after the last, the handler) with
  /// [request] and [response], and completes when they are done.
  Future<void> doFilter(ServerHttpRequest request, ServerHttpResponse response);
}

/// A base class for a [WebFilter] that does its work at most once per
/// request and can leave some requests alone.
///
/// Extend it rather than implementing [WebFilter] when a filter should
/// skip some paths ([shouldNotFilter]), or must not run twice when the
/// same request passes the filters again. It marks the request with an
/// attribute named after the filter's class, so a second pass goes
/// straight on down the chain.
///
/// ```dart
/// // Requests are timed, except the health checks of the load balancer.
/// @Component()
/// @Log()
/// class TimingFilter extends OncePerRequestFilter {
///   @override
///   bool shouldNotFilter(ServerHttpRequest request) =>
///       request.path == '/health';
///
///   @override
///   Future<void> doFilterInternal(request, response, chain) async {
///     final watch = Stopwatch()..start();
///     await chain.doFilter(request, response);
///     log.info('${request.path} took ${watch.elapsed}');
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class TimingFilter extends OncePerRequestFilter {
///   protected boolean shouldNotFilter(HttpServletRequest request) {
///     return request.getRequestURI().equals("/health");
///   }
///
///   protected void doFilterInternal(HttpServletRequest request,
///       HttpServletResponse response, FilterChain chain) { ... }
/// }
/// ```
abstract class OncePerRequestFilter implements WebFilter {
  /// Whether [request] passes this filter untouched; `false` by default.
  /// Override it to exclude paths or methods.
  bool shouldNotFilter(ServerHttpRequest request) => false;

  /// The filter's work, called instead of [doFilter] for the requests it
  /// handles: call `chain.doFilter` to go on, as in [WebFilter.doFilter].
  Future<void> doFilterInternal(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  );

  String get _attribute => '$runtimeType.FILTERED';

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    if (request.attributes.containsKey(_attribute) ||
        shouldNotFilter(request)) {
      return chain.doFilter(request, response);
    }
    request.attributes[_attribute] = true;
    return doFilterInternal(request, response, chain);
  }
}

/// The entry point of every HTTP request: the [HttpHandler] the server
/// calls, which runs the filters, finds a handler and answers errors.
///
/// For each request it:
///
/// 1. runs the request in its own `Zone`, so that
///    `RequestContextHolder.currentRequest` is the request anywhere in its
///    handling, across `await`s; with [requestTimeout] it runs under a
///    `RequestDeadline` too (see below);
/// 2. strips [contextPath] (a request outside it gets a 404);
/// 3. runs the [filters], in order;
/// 4. asks each of the [handlerMappings] in turn for a handler and calls
///    the first one found (none: a 404);
/// 5. turns an exception into an answer: first through the
///    `@ExceptionHandler` methods of [requestMapping], then through its
///    `HandlerExceptionResolver` beans, else as a `ProblemDetail` written
///    by [writer]. Exceptions from the filters go straight to [writer].
///
/// With [requestTimeout] (`server.request-timeout`) the steps above run
/// under a `RequestDeadline` of that length, which the code they call can
/// read: a Feign call, for one, never outlives it. When it passes before
/// the answer starts, the request is answered with a 503 problem
/// (`AsyncRequestTimeoutException`, a generic detail, logged as a warning
/// like other 5xx answers, at most once per 10 seconds), and everything
/// the handler does to the response afterwards is dropped: no second
/// answer, no error. The handler itself is not interrupted (Dart cannot
/// stop running code): it ends when it reaches its next check or call
/// that reads the deadline, or by itself. A response already committed is
/// left alone, so a response that became a stream (server-sent events, a
/// streamed body) is not cut, and a WebSocket handshake is exempt.
/// `@ExceptionHandler` methods do not see this 503, as the handler still
/// runs. Spring has no such limit for synchronous requests; this is an
/// extension.
///
/// The starter declares it as the `dispatcherHandler` bean, and both the
/// server and `MockMvc` call it. Applications do not create one; they add
/// filters (`WebFilter` beans) and handler mappings (`HandlerMapping`
/// beans) instead. Spring's counterpart is the `DispatcherServlet`.
final class DispatcherHandler implements HttpHandler {
  /// A dispatcher over [handlerMappings] (tried in order) behind
  /// [filters], with no context path by default.
  DispatcherHandler({
    required this.handlerMappings,
    required this.requestMapping,
    required this.writer,
    this.filters = const [],
    this.contextPath = '',
    this.logRequestDetails = false,
    this.requestTimeout,
  });

  /// The longest the filters and the handler may take to answer
  /// (`server.request-timeout`); `null`, the default, for no limit.
  final Duration? requestTimeout;

  /// The filters every request passes, in the order they run (the
  /// `@Order` of the beans).
  final List<WebFilter> filters;

  /// The handler mappings asked for a handler, in order: the controllers
  /// first, then for example the WebSocket endpoints.
  final List<HandlerMapping> handlerMappings;

  /// The controllers' mapping. Its `@ExceptionHandler` methods also
  /// answer the errors of the other mappings and the 404 of a request no
  /// mapping takes; its `HandlerExceptionResolver` beans, the errors of
  /// the other mappings.
  final RequestMappingHandlerMapping requestMapping;

  /// Writes the default error answer (a `ProblemDetail`) when no
  /// `@ExceptionHandler` method or `HandlerExceptionResolver` handles an
  /// exception.
  final ResponseWriter writer;

  /// The prefix every request path must start with
  /// (`server.context-path`, such as `/shop`); it is removed
  /// before routing, so the mappings do not repeat it. Empty: no prefix.
  final String contextPath;

  /// Whether the log lines show the request's parameters and headers
  /// (`spring.mvc.log-request-details`); without it they show `masked`,
  /// as in Spring. Values of credentials (`Authorization`, cookies,
  /// names with `token`, `password` ...) are never shown.
  final bool logRequestDetails;

  void _logRequest(ServerHttpRequest request) {
    _log.debug(() {
      final parameters = logParameters(
        request.queryParameters,
        logRequestDetails,
      );
      final shown = logRequestDetails
          ? logHeaders(request.headers)
          : '{masked}';
      final headers = _log.isEnabled(SpringLogLevel.trace)
          ? ', headers=$shown'
          : '';
      return '${request.method.value} ${logQuoted(request.path)}, '
          'parameters=$parameters$headers';
    });
  }

  void _logResult(ServerHttpResponse response, Object? failure) {
    _log.debug(() {
      if (failure != null) {
        return 'Failed to complete request: ${failure.runtimeType}';
      }
      final status = HttpStatus.resolve(response.statusCode);
      return 'Completed ${response.statusCode}'
          '${status == null ? '' : ' ${status.reasonPhrase}'}';
    });
  }

  @override
  Future<void> handle(ServerHttpRequest request, ServerHttpResponse response) =>
      RequestContextHolder.runWith(request, () async {
        _logRequest(request);
        try {
          await _handleWithinDeadline(request, response);
          _logResult(response, null);
        } on Object catch (error) {
          _logResult(response, error);
          rethrow;
        }
      });

  // The request under server.request-timeout: the filters and the handler
  // run in a RequestDeadline; when it passes before the response is
  // committed, the answer is a 503 and the handler's response becomes a
  // black hole ([_DeadlineResponse]), so its late result and its late
  // error change nothing. Streams and WebSocket handshakes are not timed.
  Future<void> _handleWithinDeadline(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    final timeout = requestTimeout;
    if (timeout == null || request.isWebSocketUpgrade) {
      return _handle(request, response);
    }
    final guarded = _DeadlineResponse(response);
    final outcome = Completer<void>();
    RequestDeadline.run(timeout, () {
      final deadline = RequestDeadline.current!;
      late final Timer timer;

      void answerTimeout() {
        if (outcome.isCompleted || guarded.abandoned) {
          return;
        }
        guarded.abandon();
        _log.debug(() => 'The request passed its deadline');
        unawaited(
          writer
              .writeError(
                requestTimeoutError(),
                StackTrace.current,
                request,
                response,
              )
              .then(outcome.complete, onError: outcome.completeError),
        );
      }

      timer = Timer(timeout, () {
        // Nothing to answer once the response is committed (the answer or
        // a stream is on its way), or when the deadline was released.
        if (!response.isCommitted && !deadline.isReleased) {
          answerTimeout();
        }
      });
      unawaited(
        _handle(request, guarded).then(
          (_) {
            timer.cancel();
            if (!outcome.isCompleted) {
              outcome.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            timer.cancel();
            if (outcome.isCompleted || guarded.abandoned) {
              _log.debug(
                () =>
                    'The handler failed after the request deadline: '
                    '${error.runtimeType}',
              );
            } else {
              outcome.completeError(error, stackTrace);
            }
          },
        ),
      );
    });
    return outcome.future;
  }

  Future<void> _handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    var current = request;
    if (contextPath.isNotEmpty) {
      final path = request.path;
      if (path != contextPath && !path.startsWith('$contextPath/')) {
        await writer.writeError(
          NoHandlerFoundException(request.method, path),
          StackTrace.current,
          request,
          response,
        );
        return;
      }
      final rest = path.substring(contextPath.length);
      current = _ContextPathRequest(request, rest.isEmpty ? '/' : rest);
    }
    try {
      await _Chain(this, 0).doFilter(current, response);
    } on Object catch (error, stackTrace) {
      if (response is _DeadlineResponse && response.abandoned) {
        // The request was answered with a 503 already.
        _log.debug(
          () => 'The request failed after its deadline: ${error.runtimeType}',
        );
        return;
      }
      await writer.writeError(error, stackTrace, current, response);
    }
  }

  /// The CORS rules of [request] as this dispatcher routes it, for a
  /// filter that checks CORS before the handler is called (the security
  /// starter's `CorsFilter`); `null` when none apply.
  ///
  /// The [handlerMappings] are asked in order, as for the request itself,
  /// and the first that takes it decides:
  ///
  /// - [requestMapping], the controllers: the rules of the handler it
  ///   would call ([RequestMappingHandlerMapping.corsConfigurationFor]);
  /// - another mapping, such as the WebSocket endpoints: those of the
  ///   `corsConfigurationSource` bean where it has some, else none. The
  ///   `addCorsMappings` rules and `@CrossOrigin` are the controllers'; a
  ///   WebSocket endpoint checks the origin of a handshake itself;
  /// - no mapping (a 404): the `addCorsMappings` rules (or the bean's).
  ///
  /// A mapping that throws, such as the controllers' 405 for a known
  /// path with another method, is passed over.
  ///
  /// Spring (Java): `HandlerMappingIntrospector.getCorsConfiguration`.
  Future<CorsConfiguration?> corsConfigurationFor(ServerHttpRequest request) =>
      dispatcherCorsConfiguration(handlerMappings, requestMapping, request);

  Future<void> _dispatch(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    try {
      for (final mapping in handlerMappings) {
        final handler = await mapping.getHandler(request);
        if (handler != null) {
          await handler.handle(request, response);
          return;
        }
      }
      throw NoHandlerFoundException(request.method, request.path);
    } on Object catch (error) {
      if (await requestMapping.handleException(error, request, response)) {
        return;
      }
      rethrow;
    }
  }
}

final class _Chain implements WebFilterChain {
  _Chain(this.dispatcher, this.index);

  final DispatcherHandler dispatcher;
  final int index;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    final filters = dispatcher.filters;
    if (index < filters.length) {
      return filters[index].doFilter(
        request,
        response,
        _Chain(dispatcher, index + 1),
      );
    }
    return dispatcher._dispatch(request, response);
  }
}

final class _ContextPathRequest extends ServerHttpRequestDecorator {
  _ContextPathRequest(super.delegate, this.path);

  @override
  final String path;
}

/// The response a handler sees while the request has a deadline: it passes
/// everything on until the deadline answered with a 503, then drops it
/// all (`isCommitted` is `false` and the headers are a scratch copy, so
/// the late code goes through its motions and nothing reaches the client).
final class _DeadlineResponse extends ServerHttpResponseDecorator {
  _DeadlineResponse(super.delegate);

  var _abandoned = false;
  final _scratch = HttpHeaders();

  /// Whether the 503 was answered and this response now drops writes.
  bool get abandoned => _abandoned;

  /// Stops passing anything on.
  void abandon() => _abandoned = true;

  @override
  set statusCode(int value) {
    if (!_abandoned) {
      super.statusCode = value;
    }
  }

  @override
  HttpHeaders get headers => _abandoned ? _scratch : super.headers;

  @override
  void addCookie(ResponseCookie cookie) {
    if (!_abandoned) {
      super.addCookie(cookie);
    }
  }

  @override
  bool get isCommitted => !_abandoned && super.isCommitted;

  @override
  void add(List<int> bytes) {
    if (!_abandoned) {
      super.add(bytes);
    }
  }

  @override
  void write(String text) {
    if (!_abandoned) {
      super.write(text);
    }
  }

  @override
  Future<void> flush() => _abandoned ? Future.value() : super.flush();

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      _abandoned ? stream.drain<void>() : super.addStream(stream);

  @override
  Future<void> close() => _abandoned ? Future.value() : super.close();
}
