import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// The channel of the plugin's login browser on Android, iOS and macOS.
///
/// One method, `authorize`, with the arguments `url` (the provider's
/// authorization URI), `redirectUri` and `preferEphemeralSession`; it
/// returns the URI the provider redirected to, as a string. Error codes:
/// `cancelled`, `in_progress`, `unsupported`, `redirect_not_configured`,
/// `no_browser`, `no_activity`, `failed`.
const authorizationBrowserChannel = MethodChannel(
  'spring_boot_starter_flutter/authorization_browser',
);

/// An [AuthorizationBrowser] on the platform's own login session: it
/// opens the provider's login page in the system browser and catches the
/// redirect back to the app.
///
/// An app logs its user in with an OAuth 2.0 provider (Keycloak, Google,
/// Okta, ...) by sending them to the provider's page and getting a code
/// back on the app's redirect URI. The page must be the system browser,
/// not a web view inside the app: the app never sees the password, and
/// the user is often logged in there already (single sign-on). The OAuth2
/// client's `OAuth2LoginService` calls this browser; the starter's
/// auto-configuration makes it the app's [AuthorizationBrowser] bean on
/// Android, iOS and macOS. Apps rarely call it themselves.
///
/// - **iOS, macOS:** `ASWebAuthenticationSession`. A custom-scheme
///   redirect (`neonbooks:/oauth2/callback`) needs no setup; an `https`
///   redirect needs iOS 17.4 / macOS 14.4 and the app's associated
///   domain. [preferEphemeralSession] chooses a private session.
/// - **Android:** a Custom Tab (the default browser when no browser
///   supports them). The app declares the plugin's
///   `RedirectReceiverActivity` with an intent filter for its redirect
///   scheme in its `AndroidManifest.xml` (see the README); without it the
///   login fails with an [AuthorizationBrowserException] that says so.
/// - **Windows, Linux:** not here; they receive the redirect on a
///   loopback server (`LoopbackAuthorizationBrowser`).
///
/// One login runs at a time: a second call while one runs throws a
/// [StateError]. The user closing the page throws an
/// [AuthorizationCancelledException].
///
/// ```dart
/// // What OAuth2LoginService does with it (and then it checks `state`
/// // and exchanges the code with the PKCE verifier).
/// final redirect = await browser.authorize(
///   redirectUri: Uri.parse('neonbooks:/oauth2/callback'),
///   authorizationUri: (redirectUri) => Uri.https(
///     'id.neon.books',
///     '/realms/neon/protocol/openid-connect/auth',
///     {
///       'response_type': 'code',
///       'client_id': 'neon-app',
///       'redirect_uri': '$redirectUri',
///       'state': state,
///       'code_challenge': challenge,
///       'code_challenge_method': 'S256',
///     },
///   ),
/// );
/// final code = redirect.queryParameters['code'];
/// ```
///
/// Spring has no such type: Spring Security logs in browsers, not apps.
class PlatformAuthorizationBrowser implements AuthorizationBrowser {
  /// The browser of the current platform.
  const PlatformAuthorizationBrowser({this.preferEphemeralSession = false});

  /// Whether the login page opens in a private browser session that
  /// shares no cookies with the system browser (iOS and macOS only).
  ///
  /// `false` by default, so a user already logged in to the provider in
  /// the browser is not asked again. `true` always asks for the
  /// password, and iOS then shows no "wants to use ... to sign in"
  /// prompt.
  final bool preferEphemeralSession;

  /// Whether the current platform has this browser: Android, iOS and
  /// macOS.
  static bool get isSupported =>
      !kIsWeb &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  static bool _running = false;

  /// Opens the authorization URI that [authorizationUri] builds for
  /// [redirectUri] and completes with the URI the provider redirected to.
  ///
  /// Throws an [AuthorizationCancelledException] when the user closed the
  /// page, a [StateError] when another login is running, an
  /// [UnsupportedError] on a platform without this browser (or an `https`
  /// redirect the OS cannot catch), and an
  /// [AuthorizationBrowserException] for the other failures.
  @override
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
        'PlatformAuthorizationBrowser runs on Android, iOS and macOS; '
        'desktops use LoopbackAuthorizationBrowser, the web logs in on the '
        'server (oauth2Login())',
      );
    }
    if (_running) {
      throw StateError('A login is already running: one at a time');
    }
    _running = true;
    try {
      final String? result;
      try {
        result = await authorizationBrowserChannel.invokeMethod<String>(
          'authorize',
          {
            'url': '${authorizationUri(redirectUri)}',
            'redirectUri': '$redirectUri',
            'preferEphemeralSession': preferEphemeralSession,
          },
        );
      } on PlatformException catch (e) {
        throw switch (e.code) {
          'cancelled' => AuthorizationCancelledException(e.message),
          'in_progress' => StateError(
            'A login is already running: one at a time',
          ),
          'unsupported' => UnsupportedError(e.message ?? e.code),
          _ => AuthorizationBrowserException(e.code, e.message ?? e.code),
        };
      } on MissingPluginException {
        throw const AuthorizationBrowserException(
          'no_plugin',
          'the platform code of spring_boot_starter_flutter is not '
              'registered (a Dart test without the app?)',
        );
      }
      if (result == null) {
        throw const AuthorizationBrowserException(
          'failed',
          'the browser returned no redirect URI',
        );
      }
      return Uri.parse(result);
    } finally {
      _running = false;
    }
  }
}

/// The login page could not be opened or its redirect not caught, for a
/// reason other than the user closing it.
///
/// Thrown by [PlatformAuthorizationBrowser]. Most often an Android app
/// that has not declared the redirect activity
/// (`redirect_not_configured`) or a device without a browser
/// (`no_browser`).
class AuthorizationBrowserException implements Exception {
  /// An exception with the platform's [code] and what happened
  /// ([message]).
  const AuthorizationBrowserException(this.code, this.message);

  /// `redirect_not_configured`, `no_browser`, `no_activity`, `no_plugin`
  /// or `failed`.
  final String code;

  /// What happened and, where it helps, what to do.
  final String message;

  @override
  String toString() => 'AuthorizationBrowserException ($code): $message';
}
