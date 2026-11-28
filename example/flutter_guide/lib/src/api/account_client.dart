import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// Logging in and out: Spring Security's form login of the server, as an
/// API client uses it (204 on success, 401 on failure; no redirects).
@HttpExchange('/api')
abstract interface class AccountClient {
  /// `POST /api/login` with `username=ada&password=...` (the parameters
  /// are the fields of the form body). The answer sets the session
  /// cookie, which `SessionTransport` keeps (the browser keeps it on the
  /// web).
  @PostExchange.of(
    url: '/login',
    contentType: MediaType.applicationFormUrlencoded,
  )
  Future<ResponseEntity<void>> login(
    @RequestParam() String username,
    @RequestParam() String password,
  );

  /// `POST /api/logout`: 204. (The web app logs out through the starter's
  /// `OAuth2LoginService`, which follows the server's answer to
  /// Keycloak's logout.)
  @PostExchange('/logout')
  Future<ResponseEntity<void>> logout();

  /// `GET /api/me`: who the session belongs to.
  @GetExchange('/me')
  Future<Me> me();
}
