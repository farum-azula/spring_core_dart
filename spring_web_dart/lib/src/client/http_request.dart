import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';

/// A request for an `HttpTransport`: method, URL, headers, body and
/// timeouts. Like Spring's `ClientHttpRequest`.
///
/// Two timeouts, both optional: [readTimeout] is the longest wait for data
/// — for the response to start and then between two chunks of the body,
/// like Spring's and Feign's read timeout (`SO_TIMEOUT`); [timeout] is a
/// deadline for the whole exchange, however steadily data arrives.
///
/// ```dart
/// final request = HttpRequest(
///   method: HttpMethod.post,
///   url: Uri.parse('https://api.neon.books/books'),
///   headers: HttpHeaders({HttpHeaders.contentTypeHeader: MediaType.applicationJson}),
///   body: utf8.encode('{"isbn":"1"}'),
///   readTimeout: const Duration(seconds: 60),
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
  /// A request; [timeout] covers sending it and reading the whole
  /// response, [readTimeout] each wait for data.
  HttpRequest({
    required this.method,
    required this.url,
    HttpHeaders? headers,
    this.body,
    this.timeout,
    this.readTimeout,
    this.followRedirects = true,
  }) : headers = headers ?? HttpHeaders();

  /// The HTTP method.
  final HttpMethod method;

  /// The full URL, query included.
  final Uri url;

  /// The request headers.
  final HttpHeaders headers;

  /// The body bytes, if any.
  final List<int>? body;

  /// The limit for the whole exchange (a deadline); `null` for none.
  final Duration? timeout;

  /// The longest wait for data: for the status and headers after the
  /// request was sent, then between two chunks of the body (an idle
  /// timeout, not a deadline); `null` for none.
  final Duration? readTimeout;

  /// Whether redirects (`3xx` with `Location`) are followed by the
  /// transport, like Feign's `Request.Options.isFollowRedirects()`.
  final bool followRedirects;

  @override
  String toString() => '${method.value} $url';
}
