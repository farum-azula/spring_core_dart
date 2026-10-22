import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';

/// A request for an `HttpTransport`: method, URL, headers, body and a
/// timeout for the whole exchange. Like Spring's `ClientHttpRequest`.
///
/// ```dart
/// final request = HttpRequest(
///   method: HttpMethod.post,
///   url: Uri.parse('https://api.neon.books/books'),
///   headers: HttpHeaders({HttpHeaders.contentType: MediaType.applicationJson}),
///   body: utf8.encode('{"isbn":"1"}'),
///   timeout: const Duration(seconds: 5),
/// );
/// final response = await transport.send(request);
/// ```
///
/// Spring (Java):
/// ```java
/// ClientHttpRequest request = factory.createRequest(uri, HttpMethod.POST);
/// request.getHeaders().setContentType(MediaType.APPLICATION_JSON);
/// request.getBody().write(json);
/// ClientHttpResponse response = request.execute();
/// ```
final class HttpRequest {
  /// A request; [timeout] covers sending it and reading the whole response.
  HttpRequest({
    required this.method,
    required this.url,
    HttpHeaders? headers,
    this.body,
    this.timeout,
  }) : headers = headers ?? HttpHeaders();

  /// The HTTP method.
  final HttpMethod method;

  /// The full URL, query included.
  final Uri url;

  /// The request headers.
  final HttpHeaders headers;

  /// The body bytes, if any.
  final List<int>? body;

  /// The limit for the whole exchange; `null` for none.
  final Duration? timeout;

  @override
  String toString() => '${method.value} $url';
}
