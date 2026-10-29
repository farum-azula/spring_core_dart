import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/desktop_secret_stores.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/method_channel_secret_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';

/// A [SecretStore] in the secure storage of the platform the app runs on:
/// what it keeps survives a restart of the app, and other apps and users
/// cannot read it.
///
/// An app that logs its user in keeps the tokens of the login here, so
/// the user stays logged in after the app is closed; `OAuth2LoginService`
/// does that by itself. The app's own small secrets (a PIN, an API key,
/// the key of an encrypted database) go here too, best through the
/// `SecretTemplate` bean, which writes objects and keeps the app's keys
/// apart from the login's. The package's auto-configuration makes this
/// the app's [SecretStore] bean on Android, iOS, macOS, Windows and
/// Linux. Most apps never create one; they declare their own
/// [SecretStore] bean only to store elsewhere.
///
/// It is for small secrets, not data: every value is a Keychain item, an
/// encrypted preference, a file or a keyring entry, and every call may be
/// slow. To protect much data, encrypt it and keep only its key here.
///
/// Where the values go:
///
/// - **iOS, macOS:** the Keychain, as generic passwords of the service
///   `<bundle id>.spring_secret_store`, readable after the first unlock,
///   on this device only (not in iCloud Keychain, not in backups moved to
///   another device).
/// - **Android:** encrypted with an AES-256-GCM key that the Android
///   Keystore generates and never lets out, in a private preferences file
///   of the app. A value that can no longer be decrypted (restored from a
///   backup on another phone, the key gone) is deleted and read as
///   missing: the user logs in again.
/// - **Windows:** encrypted for the current Windows user with DPAPI, one
///   file per key under `%LOCALAPPDATA%\<app>\spring_secret_store`.
/// - **Linux:** the Secret Service (GNOME Keyring, KWallet) through
///   `libsecret`, which must be installed; without it, or without a
///   running Secret Service, every call throws a
///   [PlatformSecretStoreException]. The values never go to a plain file.
/// - **Web:** none; the constructor throws. A browser has no secure
///   storage, so a Flutter web app keeps no tokens: its server logs the
///   user in and holds them.
///
/// [keys] lists only this app's keys and [deleteAll] removes only this
/// app's values, on every platform.
///
/// ```dart
/// // A service that keeps an API key the user typed in.
/// @Service()
/// class ApiKeys {
///   ApiKeys(this._store); // the PlatformSecretStore bean
///   final SecretStore _store;
///
///   Future<void> remember(String key) => _store.write('app.api-key', key);
///   Future<String?> current() => _store.read('app.api-key');
/// }
/// ```
///
/// Spring has no such type: Java servers keep secrets in a database or a
/// vault, and Java has no apps.
class PlatformSecretStore implements SecretStore {
  /// The store of the current platform.
  ///
  /// Throws an [UnsupportedError] on the web and on Fuchsia, which have no
  /// secure storage; [isSupported] tells beforehand.
  PlatformSecretStore() : _platform = _platformStore();

  final SecretStore _platform;

  /// Whether the current platform has a secure storage: `false` on the
  /// web and on Fuchsia.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.fuchsia;

  static SecretStore _platformStore() {
    if (!isSupported) {
      throw UnsupportedError(
        'PlatformSecretStore: '
        '${kIsWeb ? 'the web' : defaultTargetPlatform.name} '
        'has no secure storage. In a browser the server logs the user in '
        'and keeps the tokens (oauth2Login()).',
      );
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => windowsSecretStore(),
      TargetPlatform.linux => linuxSecretStore(),
      _ => const MethodChannelSecretStore(),
    };
  }

  /// The value stored under [key], or `null` when there is none (or it
  /// could not be decrypted any more, and was deleted).
  ///
  /// Throws a [PlatformSecretStoreException] when the storage fails.
  @override
  Future<String?> read(String key) => _platform.read(_checked(key));

  /// Stores [value] under [key], replacing the old value.
  ///
  /// Throws a [PlatformSecretStoreException] when the storage fails.
  @override
  Future<void> write(String key, String value) =>
      _platform.write(_checked(key), value);

  /// Removes the value of [key]; nothing happens when there is none.
  ///
  /// Throws a [PlatformSecretStoreException] when the storage fails.
  @override
  Future<void> delete(String key) => _platform.delete(_checked(key));

  /// The keys of this app that have a value.
  ///
  /// Throws a [PlatformSecretStoreException] when the storage fails.
  @override
  Future<Set<String>> keys() => _platform.keys();

  /// Removes every value of this app: the login's tokens and the app's
  /// own secrets.
  ///
  /// Throws a [PlatformSecretStoreException] when the storage fails.
  @override
  Future<void> deleteAll() => _platform.deleteAll();

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
/// Thrown by [PlatformSecretStore]. The message says what failed; it never
/// contains the stored values.
class PlatformSecretStoreException implements Exception {
  /// An exception with what failed ([message]) and, from the platform
  /// code, a short [code].
  const PlatformSecretStoreException(this.message, {this.code});

  /// What failed, for the log.
  final String message;

  /// The platform's code (`keychain`, `keystore`, `libsecret`,
  /// `dpapi`, ...), or `null`.
  final String? code;

  @override
  String toString() => code == null
      ? 'PlatformSecretStoreException: $message'
      : 'PlatformSecretStoreException ($code): $message';
}
