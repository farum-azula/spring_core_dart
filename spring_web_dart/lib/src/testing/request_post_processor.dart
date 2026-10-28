import 'package:spring_web_dart/src/testing/mock_server_http.dart';

/// A step that changes a test request just before `MockMvc` sends it to
/// the application.
///
/// It lets a test say "this request comes from a logged-in user" or "with
/// a valid CSRF token" in one call, instead of building the headers and
/// attributes by hand each time. The security starter's `user(...)`,
/// `jwt()` and `csrf()` are post-processors; a test adds one with
/// `MockRequestBuilder.with_` or the `postProcessors:` of
/// `MockMvc.webSocket`, or applies some to every request with the
/// `defaultPostProcessors:` of `MockMvc`.
///
/// The interface lives here, not in the test starter, so any starter can
/// offer post-processors without depending on test libraries.
///
/// ```dart
/// // Every request of a test suite carries the tenant header.
/// final class Tenant implements RequestPostProcessor {
///   const Tenant(this.id);
///
///   final String id;
///
///   @override
///   MockServerHttpRequest postProcessRequest(MockServerHttpRequest request) {
///     request.headers.set('X-Tenant', id);
///     return request;
///   }
/// }
///
/// final mvc = MockMvc(handler, defaultPostProcessors: [const Tenant('neon')]);
/// ```
///
/// Spring (Java):
/// ```java
/// mockMvc.perform(get("/api/books").with(user("ada")).with(csrf()));
/// ```
abstract interface class RequestPostProcessor {
  /// Returns the request to perform instead of [request]; usually
  /// [request] itself after changing its headers, cookies, attributes or
  /// principal.
  MockServerHttpRequest postProcessRequest(MockServerHttpRequest request);
}

/// A [RequestPostProcessor] made from a function, for a one-off change
/// that does not need a class.
///
/// ```dart
/// // The request arrives as if through an HTTPS proxy.
/// final viaProxy = FunctionRequestPostProcessor(
///   (request) => request..headers.set('X-Forwarded-Proto', 'https'),
/// );
/// ```
final class FunctionRequestPostProcessor implements RequestPostProcessor {
  /// A post-processor that calls [process] on each request.
  const FunctionRequestPostProcessor(this.process);

  /// The function that changes (or replaces) each request.
  final MockServerHttpRequest Function(MockServerHttpRequest request) process;

  @override
  MockServerHttpRequest postProcessRequest(MockServerHttpRequest request) =>
      process(request);
}
