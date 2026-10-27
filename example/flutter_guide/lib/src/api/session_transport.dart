import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// An `HttpTransport` that keeps the server's session, as a browser does:
/// it sends the cookies of the [CookieJar] and stores the ones the server
/// sets, and on `POST` / `PUT` / `PATCH` / `DELETE` it sends the CSRF
/// token of the `XSRF-TOKEN` cookie back in the `X-XSRF-TOKEN` header
/// (Spring Security's recipe for single-page apps).
///
/// A decorator: the requests go on to [_network], the platform's
/// transport. Every Feign client uses it, because it is the primary
/// `HttpTransport` bean (see `ApiConfig`). Tests replace only the network
/// below it with a `MockHttpTransport`, so the cookies are tested too.
class SessionTransport implements HttpTransport {
  SessionTransport(this._network, this._cookies);

  final HttpTransport _network;
  final CookieJar _cookies;

  static const _unsafe = {
    HttpMethod.post,
    HttpMethod.put,
    HttpMethod.patch,
    HttpMethod.delete,
  };

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    final response = await _network.send(_withSession(request));
    _cookies.store(response.headers.getAll(HttpHeaders.setCookieHeader));
    return response;
  }

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
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
    return HttpRequest(
      method: request.method,
      url: request.url,
      headers: headers,
      body: request.body,
      timeout: request.timeout,
      readTimeout: request.readTimeout,
      followRedirects: request.followRedirects,
    );
  }
}
