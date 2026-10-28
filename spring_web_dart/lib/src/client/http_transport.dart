import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/platform_transport_stub.dart'
    if (dart.library.io) 'package:spring_web_dart/src/client/platform_transport_io.dart'
    if (dart.library.js_interop) 'package:spring_web_dart/src/client/platform_transport_web.dart'
    as platform;
import 'package:spring_web_dart/src/client/streamed_http_response.dart';

/// The low-level HTTP client: it sends an [HttpRequest] over the network
/// and gives back the response, without knowing about JSON, annotations
/// or error handling.
///
/// It exists so that the clients built on it (Feign clients today) do not
/// depend on how a platform does HTTP. Three implementations come with
/// this package:
///
/// - `IoHttpTransport` on `dart:io` (the VM, Flutter on mobile and
///   desktop), from `package:spring_web_dart/io.dart`;
/// - `FetchHttpTransport` on the browser's `fetch`, from
///   `package:spring_web_dart/browser.dart`;
/// - `MockHttpTransport` for tests, from
///   `package:spring_web_dart/testing.dart`.
///
/// Most applications never call it. The Feign starter declares an
/// `httpTransport` bean from [platformHttpTransport] and its clients use
/// it. You implement this interface to put Feign on another HTTP library
/// (Dio, `package:http`, a client with certificate pinning) and declare
/// your implementation as a bean: the starter then uses it instead.
///
/// ```dart
/// // A one-off call outside any Feign client.
/// final transport = platformHttpTransport();
/// try {
///   final response = await transport.send(
///     HttpRequest(
///       method: HttpMethod.get,
///       url: Uri.parse('https://api.neon.books/books/1'),
///     ),
///   );
///   log.info(response.bodyText);
/// } finally {
///   transport.close(); // Frees the pooled connections.
/// }
/// ```
///
/// Spring (Java): `ClientHttpRequestFactory`, the layer under
/// `RestTemplate` and `RestClient`:
/// ```java
/// ClientHttpRequestFactory factory = new JdkClientHttpRequestFactory();
/// ClientHttpResponse response =
///     factory.createRequest(uri, HttpMethod.GET).execute();
/// ```
abstract interface class HttpTransport {
  /// Sends [request] and reads the whole response into memory.
  ///
  /// Every status code, `4xx` and `5xx` included, completes normally with
  /// an [HttpResponse]. The future fails with an [HttpTransportException]
  /// only when there is no response: the connection could not be opened
  /// or broke, or the request's `timeout` or `readTimeout` ran out.
  Future<HttpResponse> send(HttpRequest request);

  /// Sends [request] and completes as soon as the status and headers have
  /// arrived. The body is then read from [StreamedHttpResponse.body] as it
  /// comes.
  ///
  /// Use it for responses that are long or never end: server-sent events,
  /// large downloads. The request's `timeout` and `readTimeout` cover only
  /// the wait for the headers, so a stream may then stay quiet as long as
  /// it likes. A failure before the headers throws an
  /// [HttpTransportException]; a failure later arrives as an
  /// [HttpTransportException] error on the body stream.
  Future<StreamedHttpResponse> stream(HttpRequest request);

  /// Releases the transport's connections. Call it when the transport is
  /// no longer needed (the Feign starter does when the application stops);
  /// do not use the transport afterwards.
  void close();
}

/// Creates the HTTP transport that suits the platform the code runs on:
/// an `IoHttpTransport` where `dart:io` exists (the VM, Flutter on mobile
/// and desktop), a `FetchHttpTransport` in the browser.
///
/// It lets code shared between Flutter mobile and Flutter web create a
/// transport without conditional imports. The Feign starter calls it for
/// its default `httpTransport` bean. [connectTimeout] limits how long
/// opening a connection may take; `fetch` has no such setting, so it is
/// ignored in the browser. On a platform with neither `dart:io` nor
/// `dart:js_interop` it throws an [UnsupportedError]: pass your own
/// [HttpTransport] there.
///
/// ```dart
/// // Fail fast when the server cannot be reached.
/// final transport =
///     platformHttpTransport(connectTimeout: const Duration(seconds: 3));
/// ```
///
/// Spring (Java): Spring Boot picks a `ClientHttpRequestFactory` from the
/// libraries on the classpath (`ClientHttpRequestFactories.get(settings)`).
///
/// [credentials] matters in the browser only: whether `fetch` sends
/// cookies to the server (see [FetchCredentials]).
HttpTransport platformHttpTransport({
  Duration? connectTimeout,
  FetchCredentials credentials = FetchCredentials.sameOrigin,
}) => platform.createTransport(
  connectTimeout: connectTimeout,
  credentials: credentials,
);

/// Whether a browser sends its cookies (and HTTP authentication) with a
/// request of a `FetchHttpTransport`: the `credentials` option of `fetch`.
///
/// A web app whose server keeps the login in a session cookie needs it.
/// When the app and its API come from the same origin, the default
/// ([sameOrigin]) is enough. When they have different origins on the same
/// site (`localhost:5050` and `localhost:8080`, `app.example.com` and
/// `api.example.com`), choose [include]; the server must then allow
/// credentials in its CORS configuration (`allowCredentials: true`, with
/// listed origins, never `*`). Browsers drop the cookies of another site
/// whatever this says, so keep the app and the API on one site.
///
/// Ignored outside the browser: `IoHttpTransport` sends only the cookies
/// you put in the headers.
///
/// ```dart
/// // Flutter web at localhost:5050, the API at localhost:8080.
/// final transport =
///     FetchHttpTransport(credentials: FetchCredentials.include);
/// ```
///
/// Spring (Java): no browser in Java. In a browser this is
/// `fetch(url, {credentials: 'include'})`, or `withCredentials` of
/// `XMLHttpRequest`.
enum FetchCredentials {
  /// Never send or store cookies (`omit`).
  omit('omit'),

  /// Cookies for requests to the page's own origin only (`same-origin`),
  /// the browser's default.
  sameOrigin('same-origin'),

  /// Cookies for every request, other origins too (`include`).
  include('include');

  FetchCredentials(this.value);

  /// The value of the `credentials` option of `fetch`.
  final String value;
}

/// Thrown by an [HttpTransport] when a request got no response at all: the
/// connection could not be opened, it broke, or the request's `timeout` or
/// `readTimeout` ran out. In the browser a request blocked by CORS fails
/// this way too.
///
/// It is different from an error status: a `500` is a response, this
/// exception means the server's answer never arrived. Such failures are
/// often temporary, so they are worth retrying. Feign clients wrap it in
/// a `RetryableException`, which a `Retryer` bean can retry (nothing is
/// retried by default); you catch it yourself only when you call a
/// transport directly.
///
/// ```dart
/// try {
///   await transport.send(request);
/// } on HttpTransportException catch (error) {
///   // A slow server and an unreachable one call for different messages.
///   if (error.isTimeout) { ... }
/// }
/// ```
///
/// Spring (Java): `ResourceAccessException`, which `RestTemplate` throws
/// for an I/O error:
/// ```java
/// catch (ResourceAccessException e) { ... }
/// ```
class HttpTransportException implements Exception {
  /// A failure described by [message], of [request] when it is known.
  /// [cause] keeps the platform's own error; set [isTimeout] when a time
  /// limit ran out.
  HttpTransportException(
    this.message, {
    this.request,
    this.cause,
    this.isTimeout = false,
  });

  /// What went wrong, for people, such as `connection failed: Connection
  /// refused` or `no data within 60000 ms (read timeout)`.
  final String message;

  /// The request that failed, or `null` when it is not known.
  final HttpRequest? request;

  /// The error the platform reported (a `SocketException`, a
  /// `TimeoutException`, a JavaScript error), or `null`.
  final Object? cause;

  /// Whether a time limit ran out: the request's `timeout` or
  /// `readTimeout`, or the connection timeout of the platform.
  final bool isTimeout;

  @override
  String toString() =>
      'HttpTransportException: $message${request == null ? '' : ' ($request)'}';
}
