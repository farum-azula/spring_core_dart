import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/account/sso_properties.dart';
import 'package:neon_books_app/src/api/account_client.dart';
import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// Published after a login, a payload event (any object can be one).
class LoggedIn {
  const LoggedIn(this.user);

  final String user;
}

/// Published after a logout.
class LoggedOut {
  const LoggedOut(this.user);

  final String user;
}

/// Who is logged in, for the widgets: `context.session.isAdmin`.
///
/// The user itself lives where Spring Security keeps it, in the
/// `SecurityContextHolder` (one context for the whole app outside any
/// zone), so `@PreAuthorize` on the app's beans sees it. This bean puts it
/// there and tells the widgets (a `@ChangeNotifierComponent`: they rebuild
/// after `login` and `logout`).
///
/// Three ways in, the same user afterwards (a name and `ROLE_*`
/// authorities in the context):
///
/// - [login]: a name and password, the server's form login (the default).
/// - [signInWithKeycloak] with the `sso` profile, through the starter's
///   `OAuth2LoginService`, the same call everywhere: a native app logs in
///   itself in the system's login window, keeps its tokens in the
///   platform's secure storage and sends the access token with its Feign
///   calls; the web app leaves for the server, which logs it in at
///   Keycloak and sends it back with a session cookie, and [restore]
///   finds the user when it starts again.
/// - [restore] at startup: a native app's stored Keycloak login, or, on
///   the web, whoever holds the server's session (a form login too).
@ChangeNotifierComponent()
@BuildContextAccess(name: 'session')
@Log(topic: 'neon.account')
class Session {
  Session(
    this._authenticationManager,
    this._account,
    this._cookies,
    this._events,
    this._sso,
    this._login,
  );

  final AuthenticationManager _authenticationManager;
  final AccountClient _account;
  final CookieJar _cookies;
  final ApplicationEventPublisher _events;
  final SsoProperties _sso;

  /// The starter's login: on the web always (the server logs in), in the
  /// native apps where a registration is configured (the `sso` profile).
  final OAuth2LoginService? _login;

  Authentication? get _authentication {
    final authentication = SecurityContextHolder.getContext().authentication;
    return authentication != null && authentication.isAuthenticated
        ? authentication
        : null;
  }

  /// Whether someone is logged in.
  bool get isLoggedIn => _authentication != null;

  /// The user's name, or `null`.
  String? get user => _authentication?.name;

  /// Whether the user has the role `ADMIN`. Only decides what the app
  /// shows: the server checks every admin request again.
  bool get isAdmin =>
      _authentication?.authorities.any(
        (authority) => authority.authority == 'ROLE_ADMIN',
      ) ??
      false;

  /// Whether the Login screen offers Keycloak (`neon.sso.enabled`, the
  /// `sso` profile) instead of the name and password.
  bool get usesKeycloak => _sso.enabled;

  /// Logs in with the server; throws a `BadCredentialsException` for a
  /// wrong name or password (any other `AuthenticationException` when
  /// the server cannot be asked).
  Future<void> login(String username, String password) async {
    final result = await _authenticationManager.authenticate(
      UsernamePasswordAuthenticationToken.unauthenticated(username, password),
    );
    SecurityContextHolder.setContext(SecurityContextImpl(result));
    _events.publishEvent(LoggedIn(result.name));
  }

  /// "Sign in with Keycloak". A native app opens Keycloak's page in the
  /// system's login window and waits for the user (an
  /// `AuthorizationCancelledException` when they close it, an
  /// `OAuth2AuthenticationException` when the login fails). The web app
  /// leaves for the server's login and starts again afterwards.
  Future<void> signInWithKeycloak() async {
    if (_restoring case final restoring?) {
      await restoring;
    }
    final login =
        _login ??
        (throw StateError('No Keycloak login: run with the sso profile'));
    final result = await login.login(_sso.registrationId);
    if (result != null) {
      log.info('logged in with Keycloak', fields: {'user': result.name});
      _events.publishEvent(LoggedIn(result.name));
    }
  }

  /// At startup: the user of an earlier login, if any. A native app with
  /// Keycloak reads its stored tokens (refreshing them if needed); a web
  /// app asks the server whose session its cookie is (after the server's
  /// Keycloak login, a form login, or a page reload). Elsewhere nobody is
  /// logged in after a start.
  @EventListener()
  Future<void> restore(ApplicationReadyEvent event) async {
    final restoring = _restoring = _restore();
    await restoring;
    if (identical(_restoring, restoring)) {
      _restoring = null;
    }
  }

  // The restore of the start while it runs, which a login or logout
  // waits for (the login service runs one of them at a time).
  Future<void>? _restoring;

  /// Completes when the restore of the start has finished.
  Future<void> get restored => _restoring ?? Future.value();

  Future<void> _restore() async {
    try {
      if (await _login?.restore() case final user?) {
        log.info('logged in from before', fields: {'user': user.name});
        _events.publishEvent(LoggedIn(user.name));
      }
    } on Object catch (error) {
      // An app starts offline too: then nobody is logged in.
      log.warning('no login restored: ${error.runtimeType}');
    }
  }

  /// Logs out through the starter's login where there is one: a native
  /// app's Keycloak login revokes its tokens at Keycloak, forgets them and
  /// ends Keycloak's session in the system's login window; the web app
  /// posts the server's logout (after a Keycloak login the page then goes
  /// on to Keycloak's logout, which comes back to the app). A native app
  /// without Keycloak posts the server's logout itself. Then the app
  /// forgets the user and the cookies.
  Future<void> logout() async {
    if (_restoring case final restoring?) {
      await restoring;
    }
    final authentication = _authentication;
    if (_login case final login?) {
      final postLogout = _sso.postLogoutRedirectUri;
      await login.logout(
        endSession: postLogout != null,
        postLogoutRedirectUri: postLogout == null
            ? null
            : Uri.parse(postLogout),
      );
    } else {
      try {
        await _account.logout();
      } on FeignException catch (error) {
        log.warning('logout failed on the server: $error');
      }
    }
    _cookies.clear();
    SecurityContextHolder.clearContext();
    if (authentication != null) {
      _events.publishEvent(LoggedOut(authentication.name));
    }
  }
}
