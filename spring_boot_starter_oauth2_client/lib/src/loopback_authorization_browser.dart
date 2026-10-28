import 'package:spring_boot_starter_oauth2_client/src/authorization_browser.dart';
import 'package:spring_boot_starter_oauth2_client/src/loopback_platform_stub.dart'
    if (dart.library.io) 'package:spring_boot_starter_oauth2_client/src/loopback_platform_io.dart'
    as platform;

/// Whether [LoopbackAuthorizationBrowser] works here (`dart:io` exists).
const bool loopbackAuthorizationBrowserSupported = platform.supported;

/// Opens a URI in the system's browser; see [LoopbackAuthorizationBrowser].
typedef SystemBrowserOpener = Future<void> Function(Uri uri);

/// An [AuthorizationBrowser] for the Dart VM and desktop apps: it opens the
/// provider's page in the system's browser and receives the redirect on a
/// one-shot server on `127.0.0.1` (OAuth 2.0 for Native Apps, RFC 8252
/// §7.3).
///
/// For each login it binds `127.0.0.1` on a free port, makes the redirect
/// URI `http://127.0.0.1:<port><path of the configured redirect URI>`,
/// opens the provider's page, and answers the first `GET` on that path
/// with a page saying the window can be closed; then it stops listening.
/// Other paths (the browser's `favicon.ico`) get a 404. Nothing of the
/// request is echoed in the page. After [timeout] (5 minutes) without a
/// redirect, the login fails with an [AuthorizationCancelledException].
///
/// The provider must accept a loopback redirect with any port (RFC 8252
/// §7.3; Keycloak: a redirect URI `http://127.0.0.1/*`, Google: desktop
/// clients). A redirect URI with an explicit port
/// (`http://127.0.0.1:8400/callback`) keeps that port, for providers that
/// want it exact.
///
/// The starter declares it where `dart:io` exists and no other
/// [AuthorizationBrowser] bean does; the Flutter starter declares the
/// platform's own (the system browser session of iOS, macOS and Android).
/// In a web page (no `dart:io`) [authorize] throws an [UnsupportedError]:
/// there the server logs the user in (`oauth2Login()` of the security
/// starter) and the page keeps only the session cookie.
///
/// ```dart
/// // A command-line tool that logs in: the starter's browser, or by hand.
/// final browser = LoopbackAuthorizationBrowser(
///   timeout: const Duration(minutes: 2),
/// );
/// ```
///
/// Spring has no counterpart (Spring Security logs in browsers, not apps).
class LoopbackAuthorizationBrowser implements AuthorizationBrowser {
  /// A browser opening pages with [openBrowser]
  /// ([openSystemBrowser] by default) and waiting [timeout] for the
  /// redirect.
  LoopbackAuthorizationBrowser({
    SystemBrowserOpener? openBrowser,
    this.timeout = const Duration(minutes: 5),
  }) : _open = openBrowser ?? openSystemBrowser;

  /// How long to wait for the redirect.
  final Duration timeout;

  final SystemBrowserOpener _open;

  /// Opens [uri] in the default browser: `open` on macOS, `xdg-open` on
  /// Linux, `rundll32 url.dll,FileProtocolHandler` on Windows, each
  /// started directly with the URI as one argument (never through a
  /// shell, where `&` in a URI would start commands).
  ///
  /// Throws an [ArgumentError] for a URI that is not `http` or `https`
  /// (a `file:` URI would open a program), an [UnsupportedError] on
  /// another system and in a web page.
  static Future<void> openSystemBrowser(Uri uri) =>
      platform.openSystemBrowser(uri);

  @override
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  }) => platform.authorize(
    redirectUri: redirectUri,
    authorizationUri: authorizationUri,
    open: _open,
    timeout: timeout,
  );
}
