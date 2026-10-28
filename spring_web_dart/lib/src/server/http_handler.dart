import 'dart:async';

import 'package:spring_web_dart/src/server/server_http_request.dart';
import 'package:spring_web_dart/src/server/server_http_response.dart';

/// Something that answers an HTTP request: it reads the request and
/// writes the whole response.
///
/// It is the single entry point between a server and the application.
/// Applications do not implement it: the web starter registers one, the
/// `dispatcherHandler` bean, which runs the filters, finds the controller
/// method and writes errors. The server calls it once per request, and so
/// does `MockMvc` in tests, which is how a test reaches the application
/// without a network. A [HandlerMapping] also returns one for each request
/// it accepts.
///
/// ```dart
/// // Calling the application without a server, as MockMvc does.
/// final app = context.getBeanByName('dispatcherHandler') as HttpHandler;
/// final response = MockServerHttpResponse();
/// await app.handle(
///   MockServerHttpRequest(HttpMethod.get, '/api/books'),
///   response,
/// );
/// log.info(response.statusCode); // 200
/// ```
///
/// Spring (Java): `HttpHandler` (Spring WebFlux; on the servlet stack the
/// server calls the `DispatcherServlet`).
abstract interface class HttpHandler {
  /// Answers [request] by writing to [response], and closes the response.
  /// The future completes when the answer is written.
  Future<void> handle(ServerHttpRequest request, ServerHttpResponse response);
}

/// An [HttpHandler] made from a function, for a handler too small to need
/// a class of its own.
///
/// A [HandlerMapping] usually returns one for the requests it accepts; the
/// web starter answers `OPTIONS` and CORS preflight requests this way.
///
/// ```dart
/// // Answers every request it is given with a fixed text.
/// final up = FunctionHttpHandler(
///   (request, response) => response.send(200, 'UP'),
/// );
/// ```
final class FunctionHttpHandler implements HttpHandler {
  /// A handler that calls [handler] for every request.
  const FunctionHttpHandler(this.handler);

  /// The function that answers each request; it must close the response.
  final Future<void> Function(
    ServerHttpRequest request,
    ServerHttpResponse response,
  )
  handler;

  @override
  Future<void> handle(ServerHttpRequest request, ServerHttpResponse response) =>
      handler(request, response);
}

/// Decides which [HttpHandler] answers a request, or says that the request
/// is not its business.
///
/// For every request, after the filters ran, the web starter asks each
/// `HandlerMapping` bean in turn (sorted by `@Order` or `Ordered`), and the
/// first handler returned answers; when no mapping has one, the answer is
/// a 404. The `@RestController` methods are found by the starter's own
/// mapping, at order 0; the WebSocket starter adds one at order 1 for its
/// endpoints. A mapping without an order comes after them.
///
/// Most applications never write one: a controller method is simpler.
/// Write one to answer requests that no controller describes well, such
/// as paths computed at run time.
///
/// ```dart
/// // Answers GET /health without a controller.
/// @Component()
/// final class HealthMapping implements HandlerMapping {
///   @override
///   HttpHandler? getHandler(ServerHttpRequest request) =>
///       request.path == '/health'
///       ? FunctionHttpHandler((request, response) => response.send(200, 'UP'))
///       : null;
/// }
/// ```
///
/// Spring (Java): `HandlerMapping`.
abstract interface class HandlerMapping {
  /// The handler that answers [request], or `null` to let the next mapping
  /// try. It may throw an exception (such as a 405 for a known path with
  /// another method); the web starter then answers with that error.
  FutureOr<HttpHandler?> getHandler(ServerHttpRequest request);
}

/// Gives access to the request being handled from code that was not
/// passed it.
///
/// A controller receives the request as a parameter, but a service it
/// calls, a logger or a helper deep in the call chain does not. The web
/// starter runs every request in its own `Zone`, so [currentRequest]
/// returns that request anywhere in its handling, across `await`s, and
/// `null` outside a request.
///
/// ```dart
/// // An audit service records who asked, without a request parameter.
/// @Service()
/// @Log()
/// class AuditLog {
///   void record(String action) {
///     final request = RequestContextHolder.currentRequest;
///     log.info('$action by ${request?.principal?.name ?? 'anonymous'}');
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// HttpServletRequest request = ((ServletRequestAttributes)
///     RequestContextHolder.currentRequestAttributes()).getRequest();
/// ```
abstract final class RequestContextHolder {
  static const _key = #spring_web_dart.request;

  /// The request being handled, or `null` when the code does not run
  /// inside the handling of a request (at startup, in a scheduled task).
  static ServerHttpRequest? get currentRequest =>
      Zone.current[_key] as ServerHttpRequest?;

  /// Runs [body] in a new zone where [currentRequest] is [request], and
  /// returns what [body] returns. The web starter does this for every
  /// request; call it yourself only to run code as if inside a request,
  /// for example in a test.
  static R runWith<R>(ServerHttpRequest request, R Function() body) =>
      runZoned(body, zoneValues: {_key: request});
}
