import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:spring_boot_starter_flutter_security/src/window/authorization_window.dart';
import 'package:spring_boot_starter_flutter_security/src/window/loopback_authorization_window.dart';

/// The channel of the plugin's login window on Android, iOS and macOS.
///
/// One method, `authorize`, with the arguments `url` (the provider's
/// authorization URI), `redirectUri` and `preferEphemeralSession`; it
/// returns the URI the provider redirected to, as a string. Error codes:
/// `cancelled`, `in_progress`, `unsupported`, `redirect_not_configured`,
/// `no_browser`, `no_activity`, `failed`.
const authorizationWindowChannel = MethodChannel(
  'spring_boot_starter_flutter_security/authorization_window',
);

/// An [AuthorizationWindow] on the platform's own login session: it opens
/// the provider's login page in the system's login window (a Safari sheet
/// on iOS and macOS, a Chrome tab on Android) and waits for the redirect
/// back to the app.
///
/// An app logs its user in with an OAuth 2.0 provider (Keycloak, Google,
/// Okta, ...) by sending them to the provider's page and getting a code
/// back on the app's redirect URI. The page must be shown by the system,
/// not by a web view inside the app: the app never sees the password, and
/// the user is often logged in there already (single sign-on).
/// `OAuth2LoginService` calls this window; the package's
/// auto-configuration makes it the app's [AuthorizationWindow] bean on
/// Android, iOS and macOS. Apps rarely call it themselves.
///
/// - **iOS, macOS:** `ASWebAuthenticationSession`. A custom-scheme
///   redirect (`neonbooks:/oauth2/callback`) needs no setup; an `https`
///   redirect needs iOS 17.4 / macOS 14.4 and the app's associated
///   domain. [preferEphemeralSession] chooses a private session.
/// - **Android:** a Custom Tab, a Chrome (or other browser) tab over the
///   app (the default browser when no browser supports them). The app
///   declares the plugin's `RedirectReceiverActivity` with an intent filter for its redirect
///   scheme in its `AndroidManifest.xml` (see the README); without it the
///   login fails with an [AuthorizationWindowException] that says so.
/// - **Windows, Linux:** not here; they open the default browser and
///   receive the redirect on a loopback server
///   ([LoopbackAuthorizationWindow]).
///
/// One login runs at a time: a second call while one runs throws a
/// [StateError]. The user closing the page throws an
/// [AuthorizationCancelledException].
///
/// ```dart
/// // What OAuth2LoginService does with it (and then it checks `state`
/// // and exchanges the code with the PKCE verifier).
/// final redirect = await window.authorize(
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
class PlatformAuthorizationWindow implements AuthorizationWindow {
  /// The login window of the current platform.
  const PlatformAuthorizationWindow({this.preferEphemeralSession = false});

  /// Whether the login page opens in a private session that shares no
  /// cookies with Safari (iOS and macOS only).
  ///
  /// `false` by default, so a user already logged in to the provider in
  /// Safari is not asked again. `true` always asks for the
  /// password, and iOS then shows no "wants to use ... to sign in"
  /// prompt.
  final bool preferEphemeralSession;

  /// Whether the current platform has this window: Android, iOS and
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
  /// [UnsupportedError] on a platform without this window (or an `https`
  /// redirect the OS cannot catch), and an
  /// [AuthorizationWindowException] for the other failures.
  @override
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
        'PlatformAuthorizationWindow runs on Android, iOS and macOS; '
        'desktops use LoopbackAuthorizationWindow, the web logs in on the '
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
        result = await authorizationWindowChannel.invokeMethod<String>(
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
          _ => AuthorizationWindowException(e.code, e.message ?? e.code),
        };
      } on MissingPluginException {
        throw const AuthorizationWindowException(
          'no_plugin',
          'the platform code of spring_boot_starter_flutter_security is not '
              'registered (a Dart test without the app?)',
        );
      }
      if (result == null) {
        throw const AuthorizationWindowException(
          'failed',
          'the login window returned no redirect URI',
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
/// Thrown by [PlatformAuthorizationWindow]. Most often an Android app
/// that has not declared the redirect activity
/// (`redirect_not_configured`) or a device without a browser
/// (`no_browser`).
class AuthorizationWindowException implements Exception {
  /// An exception with the platform's [code] and what happened
  /// ([message]).
  const AuthorizationWindowException(this.code, this.message);

  /// `redirect_not_configured`, `no_browser`, `no_activity`, `no_plugin`
  /// or `failed`.
  final String code;

  /// What happened and, where it helps, what to do.
  final String message;

  @override
  String toString() => 'AuthorizationWindowException ($code): $message';
}
