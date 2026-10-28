import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/api/account_client.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// Checks a user name and password with the server, like a Spring
/// `AuthenticationProvider` that asks a remote system: the server's form
/// login (`POST /api/login`), then `GET /api/me` for the roles. Being an
/// `AuthenticationProvider` bean, it makes the security starter build the
/// `AuthenticationManager` around it (which also publishes the
/// authentication events).
@Component()
@Log(topic: 'neon.account')
class ServerAuthenticationProvider implements AuthenticationProvider {
  ServerAuthenticationProvider(this._account, this._cookies);

  final AccountClient _account;
  final CookieJar _cookies;

  @override
  bool supports(Authentication authentication) =>
      authentication is UsernamePasswordAuthenticationToken;

  @override
  Future<Authentication?> authenticate(Authentication authentication) async {
    final username = authentication.name;
    final password = '${authentication.credentials ?? ''}';
    try {
      if (_cookies['XSRF-TOKEN'] == null) {
        // The login is a POST, so it needs the CSRF token; any answer of
        // the server brings the XSRF-TOKEN cookie. (In a browser the
        // cookie jar stays empty, the page has the cookie: one extra GET.)
        await _probe();
      }
      await _account.login({'username': username, 'password': password});
      final me = await _account.me();
      log.info('logged in', fields: {'user': me.name, 'roles': me.roles});
      return _authenticated(me);
    } on FeignUnauthorized {
      throw BadCredentialsException();
    } on FeignException catch (error) {
      throw AuthenticationServiceException('The server answered $error', error);
    }
  }

  /// The user of the session the server already has (`GET /api/me`), or
  /// `null` when it has none (401). The web app asks at startup: its page
  /// comes back from the server's Keycloak login with a session cookie,
  /// and a reload keeps the cookie (the browser holds it, not the app).
  Future<Authentication?> current() async {
    try {
      return _authenticated(await _account.me());
    } on FeignUnauthorized {
      return null;
    }
  }

  static Authentication _authenticated(Me me) =>
      UsernamePasswordAuthenticationToken.authenticated(me.name, null, [
        for (final role in me.roles)
          SimpleGrantedAuthority(
            role.startsWith('ROLE_') ? role : 'ROLE_$role',
          ),
      ]);

  Future<void> _probe() async {
    try {
      await _account.me();
    } on FeignUnauthorized {
      // expected: nobody is logged in yet
    }
  }
}
