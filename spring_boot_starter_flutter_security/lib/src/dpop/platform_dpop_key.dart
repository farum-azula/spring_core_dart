import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter_security/src/dpop/method_channel_dpop_key.dart';
import 'package:spring_boot_starter_flutter_security/src/dpop/secret_store_dpop_key.dart';
import 'package:spring_boot_starter_flutter_security/src/dpop/stored_dpop_key.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// The app's DPoP key (RFC 9449) in the safest place the platform has,
/// kept across restarts: the provider binds the tokens to it, so a token
/// stolen from the app is useless without the device.
///
/// With DPoP (a registration's `dpop` property; `auto` by default, on
/// when the provider announces it) every token request and API call
/// carries a proof signed by this key. The OAuth2 client's default key
/// lives only as long as the app runs, so after a restart the stored
/// tokens would be dead; this one survives, and `restore()` keeps the
/// user logged in. The package's auto-configuration declares it as the
/// app's `DPoPKey` bean (`platformDPoPKey`) wherever a registration is
/// configured, except on the web; the token clients, the user services
/// and the Feign interceptor use it. Most apps never touch it.
///
/// Where the key lives:
///
/// - **iOS, macOS:** an EC P-256 key made in the Secure Enclave, where it
///   never leaves the chip (`kSecAttrTokenIDSecureEnclave`, permanent,
///   tagged `<bundle id>.spring_dpop_key`, usable after the first unlock,
///   on this device only). Where there is no Secure Enclave (the iOS
///   simulator, Macs without one) or it cannot be used (a macOS build
///   without the data protection keychain's entitlements), a software
///   key of the Keychain with the same tag: the app's code never handles
///   it, but the system's Security framework loads it into the app's
///   process to sign, so it is as safe as the app's memory.
/// - **Android:** an EC P-256 key of the Android Keystore
///   (`PURPOSE_SIGN`, SHA-256), in the StrongBox chip when the phone has
///   one, else in the trusted execution environment.
/// - **Windows, Linux:** a key made in Dart, kept as a private JWK in the
///   `SecretStore` (`oauth2.dpop-key`: DPAPI, the Secret Service), signing
///   in the app's memory ([SecretStoreDPoPKey]).
/// - **Web:** none (the constructor throws); a page logs in on its
///   server, which holds the tokens.
///
/// [storage] tells which, after the first proof.
///
/// The key is made at its first use, not at startup. When it disappears
/// (the Keystore wiped, the app reinstalled on Android, the app restored
/// on another device: the key never leaves the device), the next proof
/// makes a new key; the stored tokens are bound to the old one, so they
/// are dropped (`SecretStoreOAuth2AuthorizedClientService` checks the
/// key's thumbprint) and the user logs in again. A Keychain key outlives
/// the app on iOS (deleting the app keeps it) and is in the device's
/// encrypted backups (restored only to the same device); the package
/// removes it, with the secret store's values, at the first start after
/// a reinstall (the install id in the app's container is gone while the
/// Keychain kept its items), so a reinstalled app starts logged out
/// (not one deleted under 0.4.x, which kept no id).
///
/// `OAuth2LoginService.logout()` deletes the key ([delete]), so the next
/// login gets a new one: RFC 9449 lets a key live across logins, but a
/// new key per login means nothing bound to the old login works any
/// more, and two logins of the device cannot be linked by their key.
/// `SecretStore.deleteAll()` removes the desktop key (it is a value of
/// the store), not the Secure Enclave's or the Keystore's key.
///
/// ```dart
/// // Where did the key end up? (After the first proof.)
/// final key = context.getBean<PlatformDPoPKey>();
/// log.info('DPoP key in ${key.storage?.name}');
/// ```
///
/// Spring has no such type (Spring Security has no DPoP on the client's
/// side, and Java has no apps).
class PlatformDPoPKey implements LoadableDPoPKey {
  /// Kept outside the program, so tokens bound to it survive a restart.
  @override
  bool get persistent => true;

  /// The key of the current platform; on Windows and Linux kept in
  /// [secretStore].
  ///
  /// Throws an [UnsupportedError] on the web and on Fuchsia;
  /// [isSupported] tells beforehand.
  PlatformDPoPKey(SecretStore secretStore)
    : _platform = _platformKey(secretStore);

  final StoredDPoPKey _platform;

  /// Whether the current platform has a place for the key: `false` on
  /// the web and on Fuchsia.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.fuchsia;

  static StoredDPoPKey _platformKey(SecretStore secretStore) {
    if (!isSupported) {
      throw UnsupportedError(
        'PlatformDPoPKey: '
        '${kIsWeb ? 'the web' : defaultTargetPlatform.name} '
        'has no place for a DPoP key.',
      );
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.linux => SecretStoreDPoPKey(secretStore),
      _ => MethodChannelDPoPKey(),
    };
  }

  /// `ES256`.
  @override
  String get algorithm => _platform.algorithm;

  /// The public key as a JWK (`kty`, `crv`, `x`, `y`); throws a
  /// [StateError] before [load].
  @override
  Map<String, Object?> get publicJwk => _platform.publicJwk;

  /// Where the key is, once loaded; `null` before.
  DPoPKeyStorage? get storage => _platform.storage;

  /// Makes the key, or reads the one made earlier. `DPoPProofBuilder`
  /// calls it before every proof; only the first call asks the platform.
  ///
  /// Throws a [PlatformDPoPKeyException] when the platform fails.
  @override
  Future<void> load() => _platform.load();

  /// The raw `R || S` signature of [input] (the platform's DER signature
  /// converted).
  ///
  /// Throws a [PlatformDPoPKeyException] when the platform fails, with
  /// the code `no_key` when the key is gone (the next proof makes a new
  /// one).
  @override
  Future<Uint8List> sign(Uint8List input) => _platform.sign(input);

  /// Removes the key: tokens bound to it can no longer be used, and the
  /// next proof makes a new key. `OAuth2LoginService.logout()` calls it.
  ///
  /// Throws a [PlatformDPoPKeyException] when the platform fails.
  Future<void> delete() => _platform.delete();

  /// The algorithm, the public thumbprint once loaded and the storage;
  /// never the private key.
  @override
  String toString() => _platform.toString();
}

/// The platform failed to make, read, use or delete the DPoP key: the
/// Keychain or the Keystore returned an error, the key is gone
/// ([code] `no_key`), the platform code is missing.
///
/// Thrown by [PlatformDPoPKey]; the request that needed a proof fails.
/// The message says what failed; it never contains key material.
class PlatformDPoPKeyException implements Exception {
  /// An exception with what failed ([message]) and a short [code].
  const PlatformDPoPKeyException(this.message, {this.code});

  /// What failed, for the log.
  final String message;

  /// `dpop_key` (the platform failed), `no_key` (the key is gone; the
  /// next proof makes a new one), `no_plugin`, or `null`.
  final String? code;

  @override
  String toString() => code == null
      ? 'PlatformDPoPKeyException: $message'
      : 'PlatformDPoPKeyException ($code): $message';
}
