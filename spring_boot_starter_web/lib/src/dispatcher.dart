import 'dart:async';

import 'package:spring_boot_starter_web/src/request_mapping.dart';
import 'package:spring_boot_starter_web/src/response_writer.dart';
import 'package:spring_boot_starter_web/src/web_exceptions.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// A filter around every request, like a servlet `Filter` (or WebFlux's
/// `WebFilter`). Declare beans of this type; they run in `@Order`, before
/// the handler is looked up. Spring Security's filter chain is one.
///
/// ```dart
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
abstract interface class WebFilter {
  /// Handles [request]: calls `chain.doFilter` to go on (possibly with a
  /// wrapped request or response), or answers through [response].
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  );
}

/// The rest of the filters, then the handler.
abstract interface class WebFilterChain {
  /// Passes [request] on.
  Future<void> doFilter(ServerHttpRequest request, ServerHttpResponse response);
}

/// A [WebFilter] that runs once per request and can skip requests, like
/// Spring's `OncePerRequestFilter`.
abstract class OncePerRequestFilter implements WebFilter {
  /// Whether [request] skips this filter.
  bool shouldNotFilter(ServerHttpRequest request) => false;

  /// The filter's work.
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

/// The application's [HttpHandler], like Spring's `DispatcherServlet`:
/// runs every request in its own `Zone` (`RequestContextHolder`), through
/// the [WebFilter]s, to the first [HandlerMapping] that has a handler, and
/// answers errors (`@ExceptionHandler` methods, else a `ProblemDetail`).
final class DispatcherHandler implements HttpHandler {
  /// A dispatcher over [handlerMappings] (in order) behind [filters].
  DispatcherHandler({
    required this.handlerMappings,
    required this.requestMapping,
    required this.writer,
    this.filters = const [],
    this.contextPath = '',
  });

  /// The filters, in order.
  final List<WebFilter> filters;

  /// The handler mappings, in order.
  final List<HandlerMapping> handlerMappings;

  /// The controllers' mapping (its exception handlers answer errors of
  /// the other mappings too).
  final RequestMappingHandlerMapping requestMapping;

  /// Writes errors.
  final ResponseWriter writer;

  /// `server.servlet.context-path`: a prefix every request must have.
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
