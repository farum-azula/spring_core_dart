import 'dart:async';

import 'package:spring_boot_starter_web/src/request_mapping.dart';
import 'package:spring_boot_starter_web/src/response_writer.dart';
import 'package:spring_boot_starter_web/src/web_exceptions.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

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
/// and gets the default error answer.
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
///    handling, across `await`s;
/// 2. strips [contextPath] (a request outside it gets a 404);
/// 3. runs the [filters], in order;
/// 4. asks each of the [handlerMappings] in turn for a handler and calls
///    the first one found (none: a 404);
/// 5. turns an exception into an answer: first through the
///    `@ExceptionHandler` methods of [requestMapping], else as a
///    `ProblemDetail` written by [writer]. Exceptions from the filters go
///    straight to [writer].
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
  });

  /// The filters every request passes, in the order they run (the
  /// `@Order` of the beans).
  final List<WebFilter> filters;

  /// The handler mappings asked for a handler, in order: the controllers
  /// first, then for example the WebSocket endpoints.
  final List<HandlerMapping> handlerMappings;

  /// The controllers' mapping. Its `@ExceptionHandler` methods also
  /// answer the errors of the other mappings and the 404 of a request no
  /// mapping takes.
  final RequestMappingHandlerMapping requestMapping;

  /// Writes the default error answer (a `ProblemDetail`) when no
  /// `@ExceptionHandler` method handles an exception.
  final ResponseWriter writer;

  /// The prefix every request path must start with
  /// (`server.servlet.context-path`, such as `/shop`); it is removed
  /// before routing, so the mappings do not repeat it. Empty: no prefix.
  final String contextPath;

  @override
  Future<void> handle(ServerHttpRequest request, ServerHttpResponse response) =>
      RequestContextHolder.runWith(request, () async {
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
          await writer.writeError(error, stackTrace, current, response);
        }
      });

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
