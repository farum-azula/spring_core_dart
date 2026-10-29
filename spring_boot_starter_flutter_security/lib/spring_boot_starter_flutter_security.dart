/// Security for Flutter apps built on `spring_boot_starter_flutter`: the
/// app login with OAuth 2.0 / OpenID Connect, the platform code that
/// keeps secrets and opens the login window, a template for the app's
/// own secrets, and widgets that follow the logged-in user.
///
/// An app without a login does not need it, and carries none of its
/// native code (Swift, Kotlin, the Android activities). An app that logs
/// its user in, or keeps secrets, adds this one package:
///
/// - [OAuth2LoginService], the app login, the same calls on every
///   platform: on phones and desktops [NativeOAuth2LoginService] (the
///   authorization code flow with PKCE in the system's login window, the
///   user restored at startup from the stored tokens, the logout with
///   token revocation); in a browser [ServerOAuth2LoginService] (the
///   app's server logs the user in and keeps the tokens, the page holds
///   a session cookie; [CsrfCookieHttpTransport] sends the CSRF token),
///   or, for an app without a server of its own, [SpaOAuth2LoginService]
///   (the browser logs in as a public client with PKCE, the tokens in the
///   tab's memory, DPoP with a non-extractable [WebCryptoDPoPKey]).
///   Spring Security logs in browsers on a server; this is the app's side
///   of a login, on the OAuth2 client's registrations, token endpoint
///   clients and user services.
/// - [AuthorizationWindow], where the provider's login page opens:
///   [PlatformAuthorizationWindow] (a Safari sheet on iOS and macOS, a
///   Chrome tab on Android) or [LoopbackAuthorizationWindow] (the default
///   browser and a one-shot server on `127.0.0.1`, on Windows and Linux).
/// - [SecretStore], small secrets by key: [PlatformSecretStore] in the
///   Keychain (iOS, macOS), the Android Keystore, DPAPI (Windows) or the
///   Secret Service (Linux). The login keeps its tokens there
///   ([SecretStoreOAuth2AuthorizedClientService]); [SecretTemplate]
///   keeps the app's own objects (a PIN, an API key) there as JSON, under
///   a namespace of its own.
/// - [PlatformDPoPKey], the key DPoP-bound tokens are tied to (RFC 9449):
///   in the Secure Enclave or the Keychain, the Android Keystore, or the
///   [SecretStore] on desktops ([SecretStoreDPoPKey]); kept across
///   restarts, deleted at logout.
/// - [PrincipalNotifier], `context.principal`, [PrincipalBuilder] and
///   [PrincipalView]: widgets that follow the logged-in user, for display
///   only (the server checks access).
/// - [LoginForm], a user name and password form on the
///   `AuthenticationManager`; [OAuth2LoginButton], a button for any
///   registration; [GoogleLoginButton], [AppleLoginButton],
///   [MicrosoftLoginButton] and [GitHubLoginButton] in the look their
///   providers' branding rules fix. They follow the app's design
///   (Material, Cupertino or plain widgets, [LoginDesign]).
///
/// ```dart
/// // Signs in with Keycloak in the system's login window, shows the
/// // user's name afterwards.
/// @Service()
/// class Account {
///   Account(this._login);
///   final OAuth2LoginService _login;
///
///   Future<void> start() => _login.restore();
///   Future<void> signIn() => _login.login('keycloak');
///   Future<void> signOut() => _login.logout();
/// }
///
/// PrincipalBuilder(
///   builder: (context, authentication) => authentication == null
///       ? const SignInButton()
///       : Text('Hello, ${authentication.name}'),
/// )
/// ```
///
/// In a browser no token reaches the page by default: the server logs the
/// user in (`oauth2Login()` of `spring_boot_starter_security`); in spa
/// mode the tokens stay in the tab's memory. [SecretTemplate] throws
/// there (a browser has no secure storage).
///
/// This import re-exports `spring_boot_starter_flutter` (and through it
/// `spring_boot_dart` and logging), `spring_boot_starter_oauth2_client`
/// (the registrations, the authorized clients, Feign) and
/// `spring_security_core` (`SecurityContextHolder`, `@PreAuthorize`), so
/// an app lists and imports only this package. As in the Flutter starter,
/// Boot's `Banner` and the constraint `Size` are left out (they clash
/// with Flutter's); `SizeConstraint` is the constraint.
///
/// Spring has no Flutter; the package is the app side of Spring Security,
/// on Spring Boot's `spring-boot-starter-oauth2-client`.
library;

export 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
export 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    hide Banner, Size;

export 'src/dpop/platform_dpop_key.dart';
export 'src/dpop/secret_store_dpop_key.dart';
export 'src/dpop/stored_dpop_key.dart' show DPoPKeyStorage;
export 'src/login/apple_id_sign_in.dart';
export 'src/login/native_oauth2_login_service.dart';
export 'src/login/oauth2_login_service.dart';
export 'src/login/oauth2_token_revocation_client.dart';
export 'src/login/secret_store_oauth2_authorized_client_service.dart';
export 'src/principal/principal_notifier.dart';
export 'src/principal/principal_widgets.dart';
export 'src/screens/brand_buttons.dart' hide BrandButton;
export 'src/screens/login_design.dart' show LoginDesign;
export 'src/screens/login_form.dart' hide PlainLoginButton;
export 'src/screens/oauth2_login_button.dart';
export 'src/secret_store/platform_secret_store.dart';
export 'src/secret_store/secret_store.dart';
export 'src/secret_store/secret_template.dart';
export 'src/window/authorization_window.dart';
export 'src/window/loopback_authorization_window.dart';
export 'src/web/browser_page.dart' show BrowserPage;
export 'src/web/csrf_cookie_http_transport.dart';
export 'src/web/flutter_web_security_properties.dart';
export 'src/web/server_oauth2_login_service.dart';
export 'src/web/spa_browser_page.dart';
export 'src/web/spa_oauth2_login_service.dart';
export 'src/web/tab_oauth2_authorized_client_service.dart';
export 'src/web/web_crypto_dpop_key.dart';
export 'src/window/platform_authorization_window.dart'
    show PlatformAuthorizationWindow, AuthorizationWindowException;
