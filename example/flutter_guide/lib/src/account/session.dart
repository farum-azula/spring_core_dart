import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/account/server_authentication_provider.dart';
import 'package:neon_books_app/src/account/sso_properties.dart';
import 'package:neon_books_app/src/api/account_client.dart';
import 'package:neon_books_app/src/api/api_properties.dart';
import 'package:neon_books_app/src/api/browser_page.dart';
import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show OAuth2AuthenticationToken, OAuth2LoginService;
import 'package:spring_security_core/spring_security_core.dart';

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
/// - [signInWithKeycloak], native apps (the `sso` profile): the app logs
///   in itself, `OAuth2LoginService` with the system browser; its tokens
///   stay in the platform's secure storage, and the Feign calls carry the
///   access token.
/// - [signInWithKeycloak] on the web: the page goes to the server, which
///   logs it in at Keycloak and sends it back with a session cookie; the
///   app starts again and [restore] finds the user.
@ChangeNotifierComponent()
@BuildContextAccess(name: 'session')
@Log(topic: 'neon.account')
class Session {
  Session(
    this._authenticationManager,
    this._server,
    this._account,
    this._cookies,
    this._events,
    this._sso,
    this._api,
    this._page,
    this._appLogin,
  );

  final AuthenticationManager _authenticationManager;
  final ServerAuthenticationProvider _server;
  final AccountClient _account;
  final CookieJar _cookies;
  final ApplicationEventPublisher _events;
  final SsoProperties _sso;
  final ApiProperties _api;

  /// The browser page: only on the web (a `web` profile bean).
  final BrowserPage? _page;

  /// The app's own Keycloak login: only where a registration is
  /// configured, the native apps with the `sso` profile.
  final OAuth2LoginService? _appLogin;

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
  /// system browser and waits for the user (an
  /// `AuthorizationCancelledException` when they close it, an
  /// `OAuth2AuthenticationException` when the login fails). The web app
  /// leaves for the server's login and starts again afterwards.
  Future<void> signInWithKeycloak() async {
    if (_restoring case final restoring?) {
      await restoring;
    }
    if (_appLogin case final appLogin?) {
      final result = await appLogin.login(_sso.registrationId);
      log.info('logged in with Keycloak', fields: {'user': result.name});
      _events.publishEvent(LoggedIn(result.name));
    } else if (_page case final page?) {
      page.open(
        Uri.parse(
          '${_api.baseUrl}/oauth2/authorization/${_sso.registrationId}',
        ),
      );
    } else {
      throw StateError('No Keycloak login: run with the sso profile');
    }
  }

  /// At startup: the user of an earlier login, if any. A native app with
  /// Keycloak reads its stored tokens (refreshing them if needed); a web
  /// app asks the server whose session its cookie is (after the server's
  /// Keycloak login, or a page reload). Elsewhere nobody is logged in
  /// after a start.
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
      Authentication? user;
      if (_appLogin case final appLogin?) {
        user = await appLogin.restore();
      } else if (_page != null) {
        user = await _server.current();
        if (user != null) {
          SecurityContextHolder.setContext(SecurityContextImpl(user));
        }
      }
      if (user != null) {
        log.info('logged in from before', fields: {'user': user.name});
        _events.publishEvent(LoggedIn(user.name));
      }
    } on Object catch (error) {
      // An app starts offline too: then nobody is logged in.
      log.warning('no login restored: ${error.runtimeType}');
    }
  }

  /// Logs out: the server ends the session (and, after the web app's
  /// Keycloak login, the page goes to Keycloak's logout, which comes back
  /// to the app); a native app's Keycloak login revokes its tokens at
  /// Keycloak, forgets them and ends Keycloak's session in the system
  /// browser. Then the app forgets the user and the cookies.
  Future<void> logout() async {
    if (_restoring case final restoring?) {
      await restoring;
    }
    final authentication = _authentication;
    final appLogin = _appLogin;
    if (authentication is OAuth2AuthenticationToken && appLogin != null) {
      final postLogout = _sso.postLogoutRedirectUri;
      await appLogin.logout(
        endSession: postLogout != null,
        postLogoutRedirectUri: postLogout == null
            ? null
            : Uri.parse(postLogout),
      );
    } else {
      try {
        final answer = await _account.logout();
        if ((answer.body?.logoutUrl, _page) case (final url?, final page?)) {
          page.open(Uri.parse(url));
        }
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
