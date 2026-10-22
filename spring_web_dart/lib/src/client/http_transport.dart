import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/platform_transport_stub.dart'
    if (dart.library.io) 'package:spring_web_dart/src/client/platform_transport_io.dart'
    if (dart.library.js_interop) 'package:spring_web_dart/src/client/platform_transport_web.dart'
    as platform;

/// Sends HTTP requests: what Feign clients (and later other clients) talk
/// to. Like Spring's `ClientHttpRequestFactory`. Implementations:
/// `IoHttpTransport` (VM, Flutter mobile and desktop;
/// `package:spring_web_dart/io.dart`), `FetchHttpTransport` (web;
/// `package:spring_web_dart/browser.dart`), `MockHttpTransport` (tests;
/// `package:spring_web_dart/testing.dart`) — or your own, e.g. on Dio.
///
/// ```dart
/// final transport = platformHttpTransport();
/// final response = await transport.send(
///   HttpRequest(method: HttpMethod.get, url: Uri.parse('https://api.neon.books/books/1')),
/// );
/// transport.close();
/// ```
///
/// Spring (Java):
/// ```java
/// ClientHttpRequestFactory factory = new JdkClientHttpRequestFactory();
/// ClientHttpResponse response = factory.createRequest(uri, HttpMethod.GET).execute();
/// ```
abstract interface class HttpTransport {
  /// Sends [request] and reads the whole response. Any status code is a
  /// response; network failures and timeouts throw
  /// [HttpTransportException].
  Future<HttpResponse> send(HttpRequest request);

  /// Releases connections; the transport is not used afterwards.
  void close();
}

/// The transport of the current platform: `IoHttpTransport` with `dart:io`
/// (VM, Flutter mobile and desktop), `FetchHttpTransport` on the web.
/// [connectTimeout] limits opening a connection (ignored by `fetch`).
///
/// ```dart
/// final transport = platformHttpTransport(connectTimeout: const Duration(seconds: 3));
/// ```
///
/// Spring (Java): Spring Boot picks a `ClientHttpRequestFactory` from the
/// classpath (`ClientHttpRequestFactories.get(settings)`).
HttpTransport platformHttpTransport({Duration? connectTimeout}) =>
    platform.createTransport(connectTimeout: connectTimeout);

/// A request that failed without a response: the connection could not be
/// made, broke, or took longer than the request's timeout. Like Spring's
/// `ResourceAccessException`.
///
/// ```dart
/// try {
///   await transport.send(request);
/// } on HttpTransportException catch (error) {
///   if (error.isTimeout) { ... }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// catch (ResourceAccessException e) { ... }
/// ```
class HttpTransportException implements Exception {
  /// A failure of [request] described by [message].
  HttpTransportException(
    this.message, {
    this.request,
    this.cause,
    this.isTimeout = false,
  });

  /// What went wrong.
  final String message;

  /// The request that failed, when known.
  final HttpRequest? request;

  /// The underlying error, if any.
  final Object? cause;

  /// Whether the request ran out of time.
  final bool isTimeout;

  @override
  String toString() =>
      'HttpTransportException: $message${request == null ? '' : ' ($request)'}';
}
