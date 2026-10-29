import 'package:spring_boot_starter_flutter_security/src/web/browser_page.dart';
import 'package:spring_boot_starter_flutter_security/src/web/flutter_web_security_properties.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// An [HttpTransport] that sends the CSRF token of the server's
/// `XSRF-TOKEN` cookie back in the `X-XSRF-TOKEN` header, on the requests
/// that change something (`POST`, `PUT`, `PATCH`, `DELETE`, ...) to the
/// app's server.
///
/// A web app logged in by its server holds a session cookie, which the
/// browser sends with every request to that server, also with requests a
/// foreign page makes it send. Spring Security therefore wants a CSRF
/// token with every unsafe request; with `CookieCsrfTokenRepository` it
/// hands the token out in a cookie scripts may read, and a script proves
/// it runs on the app's page by copying it into a header (what Angular
/// does by itself). This decorator does the copying for the Feign clients
/// and the web login, so no app code handles the token.
///
/// - Only requests to [server]'s origin get the header: the token never
///   goes to the provider or any other API.
/// - `GET`, `HEAD`, `OPTIONS` and `TRACE` get none, as Spring Security's
///   `CsrfFilter` asks for none.
/// - Without the cookie the request goes as it is (the server answers
///   `403`): the server must send the cookie before the first unsafe
///   request (Spring's single-page-app recipe writes it on every
///   response).
/// - A header the request already has is kept.
///
/// On the web the package declares it as the `httpTransport` bean, around
/// the browser's transport (which sends the cookies to a server on
/// another origin, `FetchCredentials.include`), unless the application
/// declares its own [HttpTransport]. An application with its own wraps it
/// itself:
///
/// ```dart
/// @Bean()
/// HttpTransport httpTransport(BrowserPage page) => CsrfCookieHttpTransport(
///   MyLoggingTransport(
///     platformHttpTransport(credentials: FetchCredentials.include),
///   ),
///   page: page,
///   server: Uri.parse('https://api.neon.books'),
/// );
/// ```
///
/// Spring has no client side for it: this is the browser's half of
/// `CookieCsrfTokenRepository.withHttpOnlyFalse()`, with its cookie and
/// header names.
final class CsrfCookieHttpTransport implements HttpTransport {
  /// Sends the requests through [delegate], adding the header to the
  /// unsafe ones to [server]'s origin; [page] gives the cookie (and the
  /// page's address, against which relative URLs are resolved).
  CsrfCookieHttpTransport(
    this.delegate, {
    required this.page,
    required this.server,
    this.cookieName = defaultCookieName,
    this.headerName = defaultHeaderName,
  });

  /// `XSRF-TOKEN`, the cookie of Spring's `CookieCsrfTokenRepository`.
  static const defaultCookieName = 'XSRF-TOKEN';

  /// `X-XSRF-TOKEN`, the header Spring Security reads the token from.
  static const defaultHeaderName = 'X-XSRF-TOKEN';

  /// The methods Spring Security's `CsrfFilter` lets through without a
  /// token.
  static const safeMethods = {
    HttpMethod.get,
    HttpMethod.head,
    HttpMethod.options,
    HttpMethod.trace,
  };

  /// The transport that sends the requests.
  final HttpTransport delegate;

  /// The page whose cookie holds the token.
  final BrowserPage page;

  /// The app's server; only requests to its origin get the token.
  final Uri server;

  /// The cookie with the token.
  final String cookieName;

  /// The header the token is sent in.
  final String headerName;

  @override
  Future<HttpResponse> send(HttpRequest request) =>
      delegate.send(withToken(request));

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) =>
      delegate.stream(withToken(request));

  @override
  void close() => delegate.close();

  /// [request] with the token header when it needs one, else [request]
  /// itself.
  HttpRequest withToken(HttpRequest request) {
    if (safeMethods.contains(request.method) ||
        request.headers.contains(headerName)) {
      return request;
    }
    final url = request.url.hasScheme
        ? request.url
        : page.location.resolveUri(request.url);
    if (!FlutterWebSecurityProperties.sameOrigin(url, server)) {
      return request;
    }
    final token = page.cookie(cookieName);
    if (token == null || token.isEmpty) {
      return request;
    }
    return HttpRequest(
      method: request.method,
      url: request.url,
      headers: request.headers.copy()..set(headerName, token),
      body: request.body,
      timeout: request.timeout,
      readTimeout: request.readTimeout,
      followRedirects: request.followRedirects,
    );
  }
}
