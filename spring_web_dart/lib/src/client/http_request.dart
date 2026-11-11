import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';

/// One outgoing HTTP request, complete and ready to send: method, URL,
/// headers, body bytes and timeouts.
///
/// It is what an `HttpTransport` sends. Feign clients build one for every
/// call of an interface method, so most applications never create it.
/// You write one when you call a transport directly, or when you
/// implement a transport and read it.
///
/// There are two timeouts, both off by default. [readTimeout] is the
/// longest wait for data: for the response to start, then between two
/// chunks of the body. It is an idle timeout, the read timeout of Spring
/// and Feign (`SO_TIMEOUT`). [timeout] is a deadline for the whole
/// exchange, however steadily the data arrives.
///
/// ```dart
/// // `transport` is the application's `HttpTransport` bean.
/// final request = HttpRequest(
///   method: HttpMethod.post,
///   url: Uri.parse('https://api.neon.books/books'),
///   headers: HttpHeaders({
///     HttpHeaders.contentTypeHeader: MediaType.applicationJson,
///   }),
///   body: utf8.encode('{"isbn":"1"}'),
///   // Fail if the server goes quiet for a minute.
///   readTimeout: const Duration(seconds: 60),
/// );
/// final response = await transport.send(request);
/// ```
///
/// Spring (Java): `ClientHttpRequest`, which a factory creates and which
/// then sends itself:
/// ```java
/// ClientHttpRequest request = factory.createRequest(uri, HttpMethod.POST);
/// request.getHeaders().setContentType(MediaType.APPLICATION_JSON);
/// request.getBody().write(json);
/// ClientHttpResponse response = request.execute();
/// ```
final class HttpRequest {
  /// A request for [method] on [url]. Without [headers] it starts with an
  /// empty, writable set. [timeout] covers sending the request and reading
  /// the whole response; [readTimeout] covers each wait for data. Both
  /// are `null` (no limit) by default, and redirects are followed. [abort]
  /// lets the caller give the request up while it waits for the response.
  HttpRequest({
    required this.method,
    required this.url,
    HttpHeaders? headers,
    this.body,
    this.timeout,
    this.readTimeout,
    this.followRedirects = true,
    this.abort,
  }) : headers = headers ?? HttpHeaders();

  /// The HTTP method, such as [HttpMethod.get].
  final HttpMethod method;

  /// The full URL, query string included: transports send it as it is.
  final Uri url;

  /// The request headers. They can still be changed until the request is
  /// sent. A transport sets `Content-Length` from [body] itself.
  final HttpHeaders headers;

  /// The body bytes, or `null` to send no body.
  final List<int>? body;

  /// The deadline for the whole exchange, from sending the request to the
  /// last byte of the response; `null` for none. A transport that runs out
  /// of it throws an `HttpTransportException` with `isTimeout` set.
  final Duration? timeout;

  /// The longest wait for data: for the status and headers after the
  /// request was sent, then between two chunks of the body. It is an idle
  /// timeout, not a deadline: a slow download that keeps sending data
  /// never runs out of it. `null` for none.
  final Duration? readTimeout;

  /// Whether the transport follows redirects (a `3xx` with `Location`) by
  /// itself; `true` by default. When `false`, the `3xx` response is
  /// returned (in a browser: an opaque response with status 0). Feign's
  /// `Request.Options.isFollowRedirects()`.
  final bool followRedirects;

  /// Completes when the caller no longer wants the response, or `null`
  /// when it always waits for it. A transport that is still waiting for
  /// the status and headers then gives the request up: it closes the
  /// connection, so the server stops working on an answer nobody reads,
  /// and fails with an `HttpTransportException`. Once the headers have
  /// arrived it has no effect: cancel the subscription of the streamed
  /// body instead.
  ///
  /// Without it a caller that stops waiting (a stream cancelled before
  /// its first byte) would leave the request running until the server
  /// answers. It must not complete with an error. A transport that does
  /// not know it ignores it, so the caller still drops a response that
  /// arrives late.
  ///
  /// ```dart
  /// final gaveUp = Completer<void>();
  /// final answer = transport.stream(
  ///   HttpRequest(method: HttpMethod.get, url: url, abort: gaveUp.future),
  /// );
  /// // The user closed the page before the server answered.
  /// gaveUp.complete();
  /// ```
  ///
  /// In a browser this is the `signal` of `fetch`, an `AbortSignal`.
  final Future<void>? abort;

  @override
  String toString() => '${method.value} $url';
}
