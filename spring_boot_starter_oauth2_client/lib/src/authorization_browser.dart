/// Opens the login page of an OAuth 2.0 provider and waits until the
/// provider sends the browser back to the app.
///
/// An app logs in with the authorization code flow: it opens the
/// provider's authorization URI in the system browser, the user logs in
/// there (the app never sees the password), and the provider redirects to
/// the app's redirect URI with a `code` (or an `error`). This interface is
/// that round trip. `OAuth2LoginService` builds the authorization URI and
/// checks what comes back.
///
/// Implementations: the Flutter starter's, on the platform's browser
/// session (`ASWebAuthenticationSession` on iOS and macOS, Custom Tabs on
/// Android), and `LoopbackAuthorizationBrowser`, which receives the
/// redirect on a one-shot server on `127.0.0.1` (the VM, Windows,
/// Linux). There is none for a web page: there the server logs the user
/// in (`oauth2Login()` of the security starter).
///
/// Spring has no such type: Spring Security logs in browsers, not apps.
abstract interface class AuthorizationBrowser {
  /// Opens the provider's page and completes with the URI the provider
  /// redirected to, query included.
  ///
  /// [redirectUri] is the registration's redirect URI. Some browsers have
  /// to change it (a loopback server takes a free port), so the
  /// authorization URI is built by [authorizationUri] from the redirect
  /// URI actually used; that URI must also go into the token request.
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
