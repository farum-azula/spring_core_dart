import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

const _unsafe = {
  HttpMethod.post,
  HttpMethod.put,
  HttpMethod.patch,
  HttpMethod.delete,
};

/// An `HttpTransport` that keeps the server's session in the native apps,
/// as a browser does:
/// it sends the cookies of the [CookieJar] and stores the ones the server
/// sets, and on `POST` / `PUT` / `PATCH` / `DELETE` it sends the CSRF
/// token of the `XSRF-TOKEN` cookie back in the `X-XSRF-TOKEN` header
/// (Spring Security's recipe for single-page apps).
///
/// A decorator: the requests go on to [_network], the platform's
/// transport. Every Feign client uses it, because it is the primary
/// `HttpTransport` bean (see `ApiConfig`). Tests replace only the network
/// below it with a `MockHttpTransport`, so the cookies are tested too.
///
/// Not on the web: there the browser keeps the cookies (the session
/// cookie is `HttpOnly`, out of the app's reach), and the starter's
/// `CsrfCookieHttpTransport` copies the CSRF token.
///
/// Only requests to the server ([_server], `api.base-url`) get the
/// session: the OAuth2 client sends its requests to Keycloak through the
/// same bean, and the server's cookies are none of Keycloak's business.
class SessionTransport implements HttpTransport {
  SessionTransport(this._network, this._cookies, this._server);

  final HttpTransport _network;
  final CookieJar _cookies;
  final Uri _server;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    if (!_isServer(request.url, _server)) {
      return _network.send(request);
    }
    final response = await _network.send(_withSession(request));
    _cookies.store(response.headers.getAll(HttpHeaders.setCookieHeader));
    return response;
  }

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    if (!_isServer(request.url, _server)) {
      return _network.stream(request);
    }
    final response = await _network.stream(_withSession(request));
    _cookies.store(response.headers.getAll(HttpHeaders.setCookieHeader));
    return response;
  }

  @override
  void close() => _network.close();

  HttpRequest _withSession(HttpRequest request) {
    final headers = request.headers.copy();
    if (_cookies.header case final cookies?) {
      headers.set(HttpHeaders.cookieHeader, cookies);
    }
    if (_unsafe.contains(request.method)) {
      if (_cookies['XSRF-TOKEN'] case final token?) {
        headers.set('X-XSRF-TOKEN', Uri.decodeComponent(token));
      }
    }
    return _copy(request, headers);
  }
}

bool _isServer(Uri url, Uri server) =>
    url.scheme == server.scheme &&
    url.host == server.host &&
    url.port == server.port;

HttpRequest _copy(HttpRequest request, HttpHeaders headers) => HttpRequest(
  method: request.method,
  url: request.url,
  headers: headers,
  body: request.body,
  timeout: request.timeout,
  readTimeout: request.readTimeout,
  followRedirects: request.followRedirects,
);
