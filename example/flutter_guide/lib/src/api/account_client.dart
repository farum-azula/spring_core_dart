import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// Logging in and out: Spring Security's form login of the server, as an
/// API client uses it (204 on success, 401 on failure; no redirects).
@FeignClient('account', url: r'${api.base-url}', path: '/api')
abstract interface class AccountClient {
  /// `POST /api/login` with `username=ada&password=...`. The answer sets
  /// the session cookie, which `SessionTransport` keeps (the browser
  /// keeps it on the web).
  @PostMapping.of(path: '/login', consumes: MediaType.applicationFormUrlencoded)
  Future<ResponseEntity<void>> login(@RequestBody() Map<String, String> form);

  /// `POST /api/logout`: 204. (The web app logs out through the starter's
  /// `OAuth2LoginService`, which follows the server's answer to
  /// Keycloak's logout.)
  @PostMapping('/logout')
  Future<ResponseEntity<void>> logout();

  /// `GET /api/me`: who the session belongs to.
  @GetMapping('/me')
  Future<Me> me();
}
