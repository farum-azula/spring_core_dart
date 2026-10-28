import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter/src/secure_storage/desktop_token_stores.dart';
import 'package:spring_boot_starter_flutter/src/secure_storage/method_channel_token_store.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// A [TokenStore] in the secure storage of the platform the app runs on:
/// what it keeps survives a restart of the app, and other apps and users
/// cannot read it.
///
/// An app that logs its user in keeps the tokens of the login (and other
/// secrets of the user) here, so the user stays logged in after the app
/// is closed. The OAuth2 client does that by itself: the starter's
/// auto-configuration makes this the app's [TokenStore] bean on Android,
/// iOS, macOS, Windows and Linux, in place of the in-memory default.
/// Most apps never create one; they declare their own [TokenStore] bean
/// only to store elsewhere.
///
/// Where the values go:
///
/// - **iOS, macOS:** the Keychain, as generic passwords of the service
///   `<bundle id>.spring_token_store`, readable after the first unlock,
///   on this device only (not in iCloud Keychain, not in backups moved to
///   another device).
/// - **Android:** encrypted with an AES-256-GCM key that the Android
///   Keystore generates and never lets out, in a private preferences file
///   of the app. A value that can no longer be decrypted (restored from a
///   backup on another phone, the key gone) is deleted and read as
///   missing: the user logs in again.
/// - **Windows:** encrypted for the current Windows user with DPAPI, one
///   file per key under `%LOCALAPPDATA%\<app>\spring_token_store`.
/// - **Linux:** the Secret Service (GNOME Keyring, KWallet) through
///   `libsecret`, which must be installed; without it, or without a
///   running Secret Service, every call throws a
///   [SecureTokenStoreException]. The values never go to a plain file.
/// - **Web:** none; the constructor throws. A browser has no secure
///   storage, so a Flutter web app keeps no tokens: its server logs the
///   user in and holds them.
///
/// ```dart
/// // A service that keeps an API key the user typed in.
/// @Service()
/// class ApiKeys {
///   ApiKeys(this._store); // the SecureTokenStore bean
///   final TokenStore _store;
///
///   Future<void> remember(String key) => _store.write('api.key', key);
///   Future<String?> current() => _store.read('api.key');
/// }
/// ```
///
/// Spring has no such type: Java servers keep secrets in a database or a
/// vault, and Java has no apps.
class SecureTokenStore implements TokenStore {
  /// The store of the current platform.
  ///
  /// Throws an [UnsupportedError] on the web and on Fuchsia, which have no
  /// secure storage; [isSupported] tells beforehand.
  SecureTokenStore() : _platform = _platformStore();

  final TokenStore _platform;

  /// Whether the current platform has a secure storage: `false` on the
  /// web and on Fuchsia.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.fuchsia;

  static TokenStore _platformStore() {
    if (!isSupported) {
      throw UnsupportedError(
        'SecureTokenStore: ${kIsWeb ? 'the web' : defaultTargetPlatform.name} '
        'has no secure storage. In a browser the server logs the user in '
        'and keeps the tokens (oauth2Login()).',
      );
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => windowsTokenStore(),
      TargetPlatform.linux => linuxTokenStore(),
      _ => const MethodChannelTokenStore(),
    };
  }

  /// The value stored under [key], or `null` when there is none (or it
  /// could not be decrypted any more, and was deleted).
  ///
  /// Throws a [SecureTokenStoreException] when the storage fails.
  @override
  Future<String?> read(String key) => _platform.read(_checked(key));

  /// Stores [value] under [key], replacing the old value.
  ///
  /// Throws a [SecureTokenStoreException] when the storage fails.
  @override
  Future<void> write(String key, String value) =>
      _platform.write(_checked(key), value);

  /// Removes the value of [key]; nothing happens when there is none.
  ///
  /// Throws a [SecureTokenStoreException] when the storage fails.
  @override
  Future<void> delete(String key) => _platform.delete(_checked(key));

  static String _checked(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
    return key;
  }
}

/// The platform's secure storage failed: the Keychain or the Keystore
/// returned an error, `libsecret` is missing on Linux, no Secret Service
/// runs, a file could not be written.
///
/// Thrown by [SecureTokenStore]. The message says what failed; it never
/// contains the stored values.
class SecureTokenStoreException implements Exception {
  /// An exception with what failed ([message]) and, from the platform
  /// code, a short [code].
  const SecureTokenStoreException(this.message, {this.code});

  /// What failed, for the log.
  final String message;

  /// The platform's code (`keychain`, `keystore`, `libsecret`,
  /// `dpapi`, ...), or `null`.
  final String? code;

  @override
  String toString() => code == null
      ? 'SecureTokenStoreException: $message'
      : 'SecureTokenStoreException ($code): $message';
}
