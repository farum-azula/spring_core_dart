import 'dart:async';

import 'package:spring_boot_starter_web/src/handler_method.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Turns an error into an answer, for the errors no `@ExceptionHandler`
/// method handles.
///
/// Declare it as a bean (`@Component()`, `@Order` to rank it among the
/// others). When a request fails, the starter asks first the
/// `@ExceptionHandler` methods of the controller and of the
/// `@ControllerAdvice` beans, so the application's own handlers always
/// win; then every resolver in `@Order`, and the first that returns an
/// answer wins; at last the default answer (a 500 without details). It is
/// how a library maps its own exceptions to HTTP without the application
/// writing an advice for them: the data starter, for one, adds a resolver
/// when the application also uses the web starter, which answers a version
/// conflict with a 409 instead of a 500.
///
/// The answer is an [ErrorResponse]: its status, headers and
/// `ProblemDetail`, written as `application/problem+json` the way a
/// `ResponseStatusException` is. Keep the detail generic: it goes to the
/// client, and an exception's own message may hold SQL, names or values.
/// The starter logs the error at debug level (`spring.web.mvc`). Return
/// `null` for an error that is not yours: the next resolver is asked.
///
/// Resolvers see the errors raised while a request is routed and handled
/// (the controllers, their interceptors, the binding of their arguments).
/// They do not see an error that is already an [ErrorResponse] (a
/// `ResponseStatusException`, the 404, 405, 406 and 415 of the router): it
/// carries its answer, as in Spring, where `ResponseStatusExceptionResolver`
/// answers it first. An error thrown by a `WebFilter` skips them too. A
/// resolver that throws is logged and skipped.
///
/// ```dart
/// // A booking that fails because the room is taken answers 409.
/// @Component()
/// class RoomTakenResolver implements HandlerExceptionResolver {
///   @override
///   ErrorResponse? resolveException(
///     ServerHttpRequest request,
///     Object error, {
///     HandlerMethod? handler,
///   }) => error is RoomTakenException
///       ? ResponseStatusException(HttpStatus.conflict, 'The room is taken')
///       : null;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class RoomTakenResolver implements HandlerExceptionResolver {
///   public ModelAndView resolveException(HttpServletRequest request,
///       HttpServletResponse response, Object handler, Exception ex) {
///     if (!(ex instanceof RoomTakenException)) return null;
///     response.setStatus(HttpServletResponse.SC_CONFLICT);
///     return new ModelAndView();
///   }
/// }
/// ```
abstract interface class HandlerExceptionResolver {
  /// The answer to [error], raised while [request] was handled by
  /// [handler] (`null` when the error came before a controller method was
  /// chosen), or `null` to leave it to the next resolver. May be
  /// asynchronous.
  FutureOr<ErrorResponse?> resolveException(
    ServerHttpRequest request,
    Object error, {
    HandlerMethod? handler,
  });
}
