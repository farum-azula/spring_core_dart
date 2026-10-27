import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/api/account_client.dart';
import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
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
@ChangeNotifierComponent()
@BuildContextAccess(name: 'session')
@Log(topic: 'neon.account')
class Session {
  Session(
    this._authenticationManager,
    this._account,
    this._cookies,
    this._events,
  );

  final AuthenticationManager _authenticationManager;
  final AccountClient _account;
  final CookieJar _cookies;
  final ApplicationEventPublisher _events;

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

  /// Logs out: the server ends the session, the app forgets the user and
  /// the cookies.
  Future<void> logout() async {
    final user = this.user;
    try {
      await _account.logout();
    } on FeignException catch (error) {
      log.warning('logout failed on the server: $error');
    }
    _cookies.clear();
    SecurityContextHolder.clearContext();
    if (user != null) {
      _events.publishEvent(LoggedOut(user));
    }
  }
}
