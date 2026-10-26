import 'dart:async';

import 'package:spring_web_dart/src/server/server_http_request.dart';
import 'package:spring_web_dart/src/server/server_http_response.dart';

/// Handles one request, like Spring's `HttpHandler`: the web starter's
/// dispatcher is one; a server (or `MockMvc`) calls it for every request.
abstract interface class HttpHandler {
  /// Answers [request] through [response] (and closes it).
  Future<void> handle(ServerHttpRequest request, ServerHttpResponse response);
}

/// An [HttpHandler] from a function.
final class FunctionHttpHandler implements HttpHandler {
  /// Handles requests with [handler].
  const FunctionHttpHandler(this.handler);

  /// The function.
  final Future<void> Function(
    ServerHttpRequest request,
    ServerHttpResponse response,
  )
  handler;

  @override
  Future<void> handle(ServerHttpRequest request, ServerHttpResponse response) =>
      handler(request, response);
}

/// Finds the handler of a request, like Spring's `HandlerMapping`. The web
/// starter asks every `HandlerMapping` bean (in `@Order`) after the
/// filters ran; the controllers' mapping comes at order 0. Other starters
/// add their own: the WebSocket starter maps its endpoints this way.
///
/// ```dart
/// final class HealthMapping implements HandlerMapping {
///   @override
///   HttpHandler? getHandler(ServerHttpRequest request) =>
///       request.path == '/health'
///       ? FunctionHttpHandler((request, response) => response.send(200, 'UP'))
///       : null;
/// }
/// ```
abstract interface class HandlerMapping {
  /// The handler of [request], or `null` when this mapping has none.
  FutureOr<HttpHandler?> getHandler(ServerHttpRequest request);
}

/// The request being handled, available anywhere in its handling (the
/// web starter runs each request in its own `Zone`), like Spring's
/// `RequestContextHolder`.
abstract final class RequestContextHolder {
  static const _key = #spring_web_dart.request;

  /// The current request, or `null` outside a request.
  static ServerHttpRequest? get currentRequest =>
      Zone.current[_key] as ServerHttpRequest?;

  /// Runs [body] with [request] as the current request.
  static R runWith<R>(ServerHttpRequest request, R Function() body) =>
      runZoned(body, zoneValues: {_key: request});
}
