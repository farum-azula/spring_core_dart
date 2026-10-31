import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:spring_boot_starter_flutter_security/src/window/authorization_window.dart';
import 'package:spring_boot_starter_flutter_security/src/window/loopback_platform_stub.dart'
    if (dart.library.io) 'package:spring_boot_starter_flutter_security/src/window/loopback_platform_io.dart'
    as platform;

/// Opens a URI in the system's browser; see [LoopbackAuthorizationWindow].
typedef SystemBrowserOpener = Future<void> Function(Uri uri);

/// The [AuthorizationWindow] of Windows and Linux apps: it opens the
/// provider's login page in the default browser and waits for the
/// redirect back, which it receives on a one-shot server on `127.0.0.1`
/// (OAuth 2.0 for Native Apps, RFC 8252 §7.3).
///
/// For each login it binds the loopback address on a free port, makes the
/// redirect URI `http://127.0.0.1:<port><path>` (the path of the
/// configured redirect URI), opens the provider's page, and answers the
/// first `GET` on that
/// path that carries the login's `state` with a page saying the window
/// can be closed; then it stops listening. A request on the path with
/// another or no `state` (another site sending the browser there to end
/// the login) gets a 400 and the window keeps waiting; other paths (the
/// browser's `favicon.ico`) get a 404. Nothing of the request is echoed
/// in the page. After [timeout] (5 minutes) without a redirect, the login
/// fails with an [AuthorizationCancelledException].
///
/// The provider must accept a loopback redirect with any port (RFC 8252
/// §7.3; Keycloak: a redirect URI `http://127.0.0.1/*`, Google: desktop
/// clients). A redirect URI naming the host `localhost` or `[::1]` keeps
/// it, and one with an explicit port (`http://127.0.0.1:8400/callback`)
/// keeps that port, for providers that want them exact; any other host
/// becomes 127.0.0.1. `localhost` listens on 127.0.0.1 and, where the
/// system has IPv6, on ::1 with the same port (the browser may resolve
/// it to either): a free port is one free on both, and an explicit port
/// another program holds on ::1 fails the login with a
/// `SocketException` rather than letting the redirect reach that
/// program.
///
/// The package's auto-configuration makes it the app's
/// [AuthorizationWindow] bean on Windows and Linux ([isSupported]);
/// Android, iOS and macOS have a login window of their own
/// (`PlatformAuthorizationWindow`). In a web page (no `dart:io`)
/// [authorize] throws an [UnsupportedError]: there the server logs the
/// user in (`oauth2Login()` of `spring_boot_starter_security`) and the
/// page keeps only the session cookie.
///
/// ```dart
/// // Two minutes to log in instead of five, in place of the default bean.
/// @Bean()
/// AuthorizationWindow authorizationWindow() =>
///     LoopbackAuthorizationWindow(timeout: const Duration(minutes: 2));
/// ```
///
/// Spring has no counterpart (Spring Security logs in browsers, not apps).
class LoopbackAuthorizationWindow implements AuthorizationWindow {
  /// A window opening pages with [openBrowser]
  /// ([openSystemBrowser] by default) and waiting [timeout] for the
  /// redirect.
  LoopbackAuthorizationWindow({
    SystemBrowserOpener? openBrowser,
    this.timeout = const Duration(minutes: 5),
  }) : _open = openBrowser ?? openSystemBrowser;

  /// Whether the package declares this window as the app's
  /// [AuthorizationWindow]: on Windows and Linux.
  static bool get isSupported =>
      !kIsWeb &&
      const {
        TargetPlatform.windows,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);

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
