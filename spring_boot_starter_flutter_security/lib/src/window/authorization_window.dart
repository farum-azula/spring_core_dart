/// Opens the provider's login page in the system's login window (a Safari
/// sheet on iOS and macOS, a Chrome tab on Android, the default browser on
/// desktops) and waits for the redirect back to the app.
///
/// An app logs in with the authorization code flow: it shows the
/// provider's authorization URI outside the app, the user logs in there
/// (the app never sees the password, and a login the system already has
/// is reused), and the provider redirects to the app's redirect URI with
/// a `code` (or an `error`). This interface is that round trip.
/// `OAuth2LoginService` builds the authorization URI and checks what
/// comes back; apps rarely call it themselves.
///
/// Implementations: `PlatformAuthorizationWindow`
/// (`ASWebAuthenticationSession` on iOS and macOS, Custom Tabs on
/// Android), and `LoopbackAuthorizationWindow`, which opens the default
/// browser and receives the redirect on a one-shot server on `127.0.0.1`
/// (Windows, Linux). The package's auto-configuration declares the one
/// of the platform as the `AuthorizationWindow` bean. There is none for a
/// web page: there the server logs the user in (`oauth2Login()` of
/// `spring_boot_starter_security`).
///
/// Spring has no such type: Spring Security logs in browsers, not apps.
abstract interface class AuthorizationWindow {
  /// Opens the provider's page and completes with the URI the provider
  /// redirected to, query included.
  ///
  /// [redirectUri] is the registration's redirect URI. Some windows have
  /// to change it (a loopback server takes a free port), so the
  /// authorization URI is built by [authorizationUri] from the redirect
  /// URI actually used; that URI must also go into the token request.
  ///
  /// When the authorization URI carries a `state`, a window that can
  /// tell requests apart waits for the redirect with that `state` (the
  /// provider sends it back, errors included): the loopback server and
  /// Android's redirect activity ignore other requests on the redirect
  /// URI and keep waiting, so another site cannot end a running login
  /// there. `ASWebAuthenticationSession` (iOS, macOS) cannot: it ends at
  /// the first navigation to the redirect URI, whatever its `state`, and
  /// the call completes with it. A redirect with another `state` never
  /// logs anyone in: `OAuth2LoginService` refuses it
  /// (`invalid_state_parameter`), and the user starts the login again.
  ///
  /// Throws an [AuthorizationCancelledException] when the user closed the
  /// page without finishing.
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  });
}

/// The user closed the provider's login page before it redirected back.
class AuthorizationCancelledException implements Exception {
  /// An exception with an optional [message].
  const AuthorizationCancelledException([this.message]);

  /// What happened, for logs; `null` when nothing more is known.
  final String? message;

  @override
  String toString() => message == null
      ? 'AuthorizationCancelledException'
      : 'AuthorizationCancelledException: $message';
}
