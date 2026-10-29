import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// Logs the user of an app in with an OAuth 2.0 or OpenID Connect
/// provider (Keycloak, Google, Auth0, ...), brings them back after a
/// restart, and logs them out: the same three calls on every platform.
///
/// An app logs in differently on a phone and in a browser, but its code
/// does not change: it injects this service and calls [login] with a
/// registration id of its configuration, [restore] at startup and
/// [logout]. The user then is in the `SecurityContextHolder`, where
/// `@PreAuthorize`, the Feign clients, `PrincipalBuilder` and
/// `PrincipalView` see them. The package declares the implementation of
/// the platform as the `oauth2LoginService` bean:
///
/// - On Android, iOS, macOS, Windows and Linux,
///   `NativeOAuth2LoginService`: the app logs in by itself (the
///   authorization code flow with PKCE in the system's login window) and
///   keeps the tokens in the platform's secure storage. Declared when a
///   `spring.security.oauth2.client.registration.*` property is set.
/// - In a browser, `ServerOAuth2LoginService`: a page has no safe place
///   for tokens, so the app's server logs the user in (`oauth2Login()` of
///   `spring_boot_starter_security`), keeps the tokens, and gives the
///   browser an `HttpOnly` session cookie (`spring.flutter.security.web.mode=server`,
///   the default). The registrations are the server's, not the app's.
/// - In a browser without a server of its own, `SpaOAuth2LoginService`
///   (`spring.flutter.security.web.mode=spa`): the browser logs in by
///   itself as a public client with PKCE, keeps the tokens in the tab's
///   memory, and comes back after a reload through the provider's
///   session (`prompt=none`).
///
/// ```dart
/// @Service()
/// class Account {
///   Account(this._login);
///   final OAuth2LoginService _login;
///
///   Future<void> start() => _login.restore(); // logged in from last time?
///   Future<void> signIn() => _login.login('keycloak');
///   Future<void> signOut() => _login.logout();
///   String? get who => _login.authentication?.name;
/// }
/// ```
///
/// Spring has no counterpart: Spring Security's `oauth2Login()` logs
/// browsers in on a server; this is the app's side of a login.
abstract interface class OAuth2LoginService {
  /// The logged-in user's authentication, or `null`.
  Authentication? get authentication;

  /// Whether someone is logged in.
  bool get isLoggedIn;

  /// The authentication after each login, restore and logout (`null`):
  /// for a UI that shows who is logged in. `PrincipalNotifier` and
  /// `context.principal` are usually simpler.
  Stream<Authentication?> get authenticationChanges;

  /// Logs the user in with the registration [registrationId].
  ///
  /// On a phone or desktop the provider's page opens in the system's
  /// login window and the result is the user's authentication. In a
  /// browser the page leaves for the server's login and the result is
  /// `null`: the app starts again when the browser comes back, and
  /// [restore] finds the user.
  ///
  /// [additionalParameters] go to the provider's page (`prompt=login`,
  /// `login_hint=ada@example.com`, `kc_idp_hint=google`); in a browser
  /// they go to the server, which decides whether it passes them on.
  Future<Authentication?> login(
    String registrationId, {
    Map<String, String> additionalParameters = const {},
  });

  /// Brings back the user logged in before, and returns their
  /// authentication; `null` when nobody is. Call it once at startup.
  ///
  /// A phone or desktop reads its stored tokens; a browser asks its
  /// server who holds the session cookie, or in spa mode finishes the
  /// login the provider sent the page back from (or makes a silent trip
  /// to the provider). Publishes an `AuthenticationSuccessEvent`.
  Future<Authentication?> restore();

  /// Logs the user out: ends the login (the stored tokens, or the
  /// server's session), clears the security context and publishes a
  /// `LogoutSuccessEvent`.
  ///
  /// [endSession] and [postLogoutRedirectUri] end the provider's own
  /// session too, on a phone or desktop; in a browser the server decides
  /// that (its logout answer).
  Future<void> logout({bool endSession = false, Uri? postLogoutRedirectUri});
}
