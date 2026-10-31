import 'package:spring_boot_starter_flutter_security/src/web/browser_page.dart';
import 'package:spring_boot_starter_flutter_security/src/web/flutter_web_security_properties.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// An [HttpTransport] for a web app whose server is on another origin than
/// the page: the browser's cookies go with the requests to that server
/// only, never to another API.
///
/// A web app logged in by its server (backend-for-frontend) holds a
/// session cookie; when the server is on another origin (the page at
/// `app.neon.books`, the server at `api.neon.books`), `fetch` sends it
/// only when asked (`credentials: 'include'`). Asking for every request
/// would send the user's cookies to every API the app calls, and a
/// public API that answers `Access-Control-Allow-Origin: *` then fails
/// in the browser (credentials need a listed origin). So this transport
/// decides per request: requests to [server]'s origin go through
/// [serverTransport] (`FetchCredentials.include`), all others through
/// [otherTransport] (`FetchCredentials.sameOrigin`, the browser's
/// default: cookies only for the page's own origin). Relative URLs are
/// resolved against the [page]'s address.
///
/// On the web, in server mode with the server on another origin, the
/// package declares it inside the `httpTransport` bean (a
/// [CsrfCookieHttpTransport] around it); with the server on the page's
/// origin one transport with the default is enough. An application with
/// its own `HttpTransport` bean builds it with [ServerCredentialsHttpTransport.forPage]:
///
/// ```dart
/// @Bean()
/// HttpTransport httpTransport(BrowserPage page) {
///   final server = Uri.parse('https://api.neon.books');
///   return CsrfCookieHttpTransport(
///     ServerCredentialsHttpTransport.forPage(page: page, server: server),
///     page: page,
///     server: server,
///   );
/// }
/// ```
///
/// Spring has no browser side; this is what a browser app does with
/// `fetch(url, {credentials: 'include'})` for its own API only.
final class ServerCredentialsHttpTransport implements HttpTransport {
  /// Sends requests to [server]'s origin through [serverTransport] and
  /// the others through [otherTransport].
  ServerCredentialsHttpTransport({
    required this.serverTransport,
    required this.otherTransport,
    required this.page,
    required this.server,
  });

  /// A transport for the page at [page] and its server [server]: the
  /// browser's `fetch` with `FetchCredentials.include` for the server
  /// and `FetchCredentials.sameOrigin` for the rest ([create] makes
  /// them: `platformHttpTransport` with [connectTimeout] by default).
  factory ServerCredentialsHttpTransport.forPage({
    required BrowserPage page,
    required Uri server,
    Duration? connectTimeout,
    HttpTransport Function(FetchCredentials credentials)? create,
  }) {
    final make =
        create ??
        (credentials) => platformHttpTransport(
          connectTimeout: connectTimeout,
          credentials: credentials,
        );
    return ServerCredentialsHttpTransport(
      serverTransport: make(FetchCredentials.include),
      otherTransport: make(FetchCredentials.sameOrigin),
      page: page,
      server: server,
    );
  }

  /// The transport of the requests to [server]'s origin, which sends the
  /// cookies.
  final HttpTransport serverTransport;

  /// The transport of every other request, which sends cookies to the
  /// page's own origin only.
  final HttpTransport otherTransport;

  /// The page, against whose address relative URLs are resolved.
  final BrowserPage page;

  /// The app's server.
  final Uri server;

  /// The transport [request] goes through.
  HttpTransport transportFor(HttpRequest request) {
    final url = request.url.hasScheme
        ? request.url
        : page.location.resolveUri(request.url);
    return FlutterWebSecurityProperties.sameOrigin(url, server)
        ? serverTransport
        : otherTransport;
  }

  @override
  Future<HttpResponse> send(HttpRequest request) =>
      transportFor(request).send(request);

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) =>
      transportFor(request).stream(request);

  @override
  void close() {
    try {
      serverTransport.close();
    } finally {
      otherTransport.close();
    }
  }
}
