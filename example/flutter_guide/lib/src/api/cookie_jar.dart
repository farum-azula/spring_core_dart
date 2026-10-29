import 'package:neon_books_app/main.spring.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The server's cookies, as a browser would keep them: `JSESSIONID` (the
/// session, so the server knows who is logged in) and `XSRF-TOKEN` (the
/// CSRF token Spring Security's `CookieCsrfTokenRepository` hands out).
/// One server, so names are enough; `Max-Age=0` deletes a cookie.
@Component()
@Log(topic: 'neon.api.cookies')
class CookieJar {
  final _cookies = <String, String>{};

  /// The cookie [name], or `null`.
  String? operator [](String name) => _cookies[name];

  /// The `Cookie` header for the next request, or `null` without cookies.
  String? get header => _cookies.isEmpty
      ? null
      : [for (final MapEntry(:key, :value) in _cookies.entries) '$key=$value']
            .join('; ');

  /// Takes in the `Set-Cookie` values of a response.
  void store(Iterable<String> setCookies) {
    for (final setCookie in setCookies) {
      final attributes = setCookie.split(';');
      final pair = attributes.first;
      final equals = pair.indexOf('=');
      if (equals <= 0) {
        continue;
      }
      final name = pair.substring(0, equals).trim();
      final value = pair.substring(equals + 1).trim();
      final expired = attributes
          .skip(1)
          .any((attribute) => attribute.trim().toLowerCase() == 'max-age=0');
      if (expired || value.isEmpty) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
      log.debug('cookie $name ${expired ? 'deleted' : 'stored'}');
    }
  }

  /// Forgets every cookie (logout).
  void clear() => _cookies.clear();
}
