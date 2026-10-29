// The documentation has properties lines, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:spring_boot_starter_flutter_security/src/window/authorization_window.dart';
import 'package:spring_boot_starter_flutter_security/src/window/platform_authorization_window.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// The channel of the plugin's native sign-in sheets on iOS and macOS.
///
/// One method, `appleIdSignIn`, with the arguments `scopes` (`name`,
/// `email`), `nonce` and `state`; it returns a map with `user`,
/// `authorizationCode`, `identityToken`, `state` and, on the first
/// authorization only, `email`, `givenName` and `familyName`. Error codes:
/// `cancelled`, `in_progress`, `failed`.
const nativeSignInChannel = MethodChannel(
  'spring_boot_starter_flutter_security/native_sign_in',
);

/// How the app signs a registration's user in: in the system's login
/// window (a browser, the default), or in a sheet of the operating system.
///
/// Set per registration with
/// `spring.security.oauth2.client.registration.<id>.native-sign-in`:
///
/// ```properties
/// # The default for a registration of the `apple` provider.
/// spring.security.oauth2.client.registration.apple.native-sign-in=apple
/// # The browser for it too (Sign in with Apple's web page).
/// spring.security.oauth2.client.registration.apple.native-sign-in=none
/// ```
///
/// [apple] opens Sign in with Apple's sheet (`ASAuthorizationAppleIDProvider`)
/// on iOS and macOS, where it exists; on Android, Windows and Linux the
/// registration logs in in the browser as any other. Read by
/// `NativeOAuth2LoginService`; the browser flow of a web page is unaffected.
///
/// Spring has no such setting: Spring Security logs browsers in.
enum NativeSignIn {
  /// The system's login window, a browser (`native-sign-in=none`).
  none,

  /// Sign in with Apple's sheet on iOS and macOS (`native-sign-in=apple`).
  apple;

  static const _prefix = 'spring.security.oauth2.client.registration';

  /// The mode named [value] (`none`, `apple`, ignoring case).
  ///
  /// Throws an [ArgumentError] for another value.
  static NativeSignIn parse(String value) =>
      switch (value.trim().toLowerCase()) {
        'none' => none,
        'apple' => apple,
        _ => throw ArgumentError.value(
          value,
          'native-sign-in',
          'must be none or apple',
        ),
      };

  /// The modes of the registrations of [environment] that are not
  /// [none]: the `native-sign-in` property, else [apple] for a
  /// registration whose provider is `apple` (its `provider` property, or
  /// its id).
  ///
  /// Throws an [ArgumentError] for an unknown value.
  static Map<String, NativeSignIn> of(Environment environment) {
    if (environment is! ConfigurableEnvironment) {
      return const {};
    }
    final keys = Binder.get(environment)
        .bind(
          _prefix,
          const MapType<String, String>(
            ClassType<String>(),
            ClassType<String>(),
          ),
        )
        .orElse(const {})
        .keys;
    final modes = <String, NativeSignIn>{};
    for (final id in {for (final key in keys) key.split('.').first}) {
      if (id.isEmpty) {
        continue;
      }
      final set = environment.getProperty('$_prefix.$id.native-sign-in');
      final provider =
          environment.getProperty('$_prefix.$id.provider')?.trim() ?? id;
      final mode = set != null && set.trim().isNotEmpty
          ? parse(set)
          : (CommonOAuth2Provider.of(provider) == CommonOAuth2Provider.apple
                ? apple
                : none);
      if (mode != none) {
        modes[id] = mode;
      }
    }
    return modes;
  }
}

/// What Sign in with Apple's sheet answers: who signed in, and the
/// credentials the app checks and hands to its server.
///
/// [identityToken] is a JWT signed by Apple (`iss`
/// `https://appleid.apple.com`, `aud` the app's bundle id, the `nonce` of
/// the request, `sub` = [user]); [authorizationCode] is valid for five
/// minutes, once, and only with the client secret the app's server signs.
/// [email], [givenName] and [familyName] come on the first authorization
/// of the app only: keep them. Nothing here is printed by [toString].
final class AppleIdCredential {
  /// A credential as the sheet answered it.
  const AppleIdCredential({
    required this.user,
    required this.authorizationCode,
    required this.identityToken,
    this.state,
    this.email,
    this.givenName,
    this.familyName,
  });

  /// The user's stable identifier for this team (the `sub` of the
  /// identity token).
  final String user;

  /// The authorization code; a credential, never log it.
  final String authorizationCode;

  /// The identity token (a JWT); a credential, never log it.
  final String identityToken;

  /// The `state` of the request, sent back.
  final String? state;

  /// The e-mail (perhaps a private relay address), first authorization
  /// only.
  final String? email;

  /// The given name, first authorization only.
  final String? givenName;

  /// The family name, first authorization only.
  final String? familyName;

  @override
  String toString() =>
      'AppleIdCredential [user=$user, authorizationCode=[PROTECTED], '
      'identityToken=[PROTECTED]]';
}

/// Opens Sign in with Apple's sheet and returns what it answers.
///
/// `NativeOAuth2LoginService` calls it for a registration with
/// `native-sign-in=apple`, then checks the answer (the `state`, the
/// identity token's signature with Apple's keys, its issuer, audience,
/// expiry and `nonce`) and exchanges the code at the registration's
/// token endpoint. Apps rarely call it themselves. The package declares
/// [PlatformAppleIdSignIn] as the bean on iOS and macOS; tests declare a
/// fake.
///
/// Spring has no such type.
abstract interface class AppleIdSignIn {
  /// Opens the sheet for [scopes] (`name`, `email`), with [nonce] (sent
  /// as given; Apple puts it into the identity token) and [state].
  ///
  /// Throws an [AuthorizationCancelledException] when the user closed the
  /// sheet, an [AuthorizationWindowException] for the other failures.
  Future<AppleIdCredential> signIn({
    required Set<String> scopes,
    required String nonce,
    required String state,
  });
}

/// The [AppleIdSignIn] of iOS and macOS, on the plugin's
/// `ASAuthorizationAppleIDProvider` request.
///
/// The app needs the "Sign in with Apple" capability (the
/// `com.apple.developer.applesignin` entitlement, added in Xcode under
/// Signing & Capabilities), and the device an Apple Account; without
/// them the sheet fails (`failed`).
class PlatformAppleIdSignIn implements AppleIdSignIn {
  /// The sheet of the current platform.
  const PlatformAppleIdSignIn();

  /// Whether the current platform has the sheet: iOS and macOS.
  static bool get isSupported =>
      !kIsWeb &&
      const {
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  @override
  Future<AppleIdCredential> signIn({
    required Set<String> scopes,
    required String nonce,
    required String state,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Sign in with Apple has a sheet on iOS and macOS');
    }
    final Map<Object?, Object?>? answer;
    try {
      answer = await nativeSignInChannel.invokeMapMethod<Object?, Object?>(
        'appleIdSignIn',
        {
          'scopes': [
            for (final scope in scopes)
              if (scope == 'name' || scope == 'email') scope,
          ],
          'nonce': nonce,
          'state': state,
        },
      );
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'cancelled' => AuthorizationCancelledException(e.message),
        'in_progress' => StateError('A sign-in is already running'),
        _ => AuthorizationWindowException(e.code, e.message ?? e.code),
      };
    } on MissingPluginException {
      throw const AuthorizationWindowException(
        'no_plugin',
        'the platform code of spring_boot_starter_flutter_security is not '
            'registered (a Dart test without the app?)',
      );
    }
    String? text(String name) => switch (answer?[name]) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };
    final user = text('user');
    final code = text('authorizationCode');
    final token = text('identityToken');
    if (user == null || code == null || token == null) {
      throw const AuthorizationWindowException(
        'failed',
        'Sign in with Apple answered without a user, code or identity token',
      );
    }
    return AppleIdCredential(
      user: user,
      authorizationCode: code,
      identityToken: token,
      state: text('state'),
      email: text('email'),
      givenName: text('givenName'),
      familyName: text('familyName'),
    );
  }
}
