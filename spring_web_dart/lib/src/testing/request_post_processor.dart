import 'package:spring_web_dart/src/testing/mock_server_http.dart';

/// Changes a request before `MockMvc` performs it, like Spring's
/// `RequestPostProcessor` (the security starter's `user(...)`, `jwt()` and
/// `csrf()` are ones). Here, not in the test starter, so a starter can
/// offer post-processors without depending on test libraries.
abstract interface class RequestPostProcessor {
  /// The request to perform instead of [request] (usually it, changed).
  MockServerHttpRequest postProcessRequest(MockServerHttpRequest request);
}

/// A [RequestPostProcessor] from a function.
final class FunctionRequestPostProcessor implements RequestPostProcessor {
  /// Applies [process].
  const FunctionRequestPostProcessor(this.process);

  /// The function.
  final MockServerHttpRequest Function(MockServerHttpRequest request) process;

  @override
  MockServerHttpRequest postProcessRequest(MockServerHttpRequest request) =>
      process(request);
}
