import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/desktop_secret_stores.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/method_channel_secret_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';

/// A [SecretStore] in the secure storage of the platform the app runs on:
/// what it keeps survives a restart of the app and is encrypted for the
/// current user. On Android and iOS other apps cannot read it either; on
/// macOS, Windows and Linux the separation between apps is weaker (see
/// below).
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
///   another device). The items belong to the app's keychain access
///   group, so other apps cannot read them; a macOS build without the
///   data protection keychain's entitlements (a debug build signed to
///   run locally) falls back to the login keychain, where macOS asks the
///   user before another app reads an item. Keychain items outlive the
///   app (iOS keeps them when the app is deleted; the package removes
///   them at the first start after a reinstall, found by an install id
///   kept in a file of the app's container, so a reinstalled app starts
///   logged out; an update, or cleared preferences, keeps them) and are
///   in the device's encrypted backups (restored only to the same
///   device). On macOS deleting an app keeps its data and its Keychain
///   items, so a reinstalled app finds them.
/// - **Android:** encrypted with an AES-256-GCM key that the Android
///   Keystore generates and never lets out, in a private preferences file
///   of the app. A value that can no longer be decrypted (restored from a
///   backup on another phone, the key gone) is deleted and read as
///   missing: the user logs in again.
/// - **Windows:** encrypted for the current Windows user with DPAPI, one
///   file per key under `%LOCALAPPDATA%\spring_secret_store\<app>` (not
///   in the app's cache folder, which an app may empty, and never in a
///   roaming profile). DPAPI separates users, not apps: any program
///   running as the same user can decrypt the files.
/// - **Linux:** the Secret Service (GNOME Keyring, KWallet) through
///   `libsecret`, which must be installed; without it, or without a
///   running Secret Service, every call throws a
///   [PlatformSecretStoreException]. The values never go to a plain file.
///   The Secret Service separates users, not apps: any program running
///   as the same user can read the items.
/// - **Web:** none; the constructor throws. A browser has no secure
///   storage, so a Flutter web app keeps no tokens: its server logs the
///   user in and holds them.
///
/// On Windows and Linux the app's values are kept apart from other apps'
/// by an application id ([applicationId],
/// `spring.flutter.security.application-id` for the package's bean): by
/// default the app's own (the version resource's company and product on
/// Windows, the GTK application id on Linux), else the executable's name.
/// Set it when two apps could have the same. 0.4.x kept the values under
/// the executable's name, which two apps could share: they are moved to
/// the application id once, at the first call after the update, and the
/// old place is never searched again (on Windows, files the move had to
/// leave, in use or read-only, are tried again at later starts; a value
/// deleted in between never comes back). Android, iOS and macOS keep each
/// app's values apart by themselves.
///
/// [keys] lists only this app's keys and [deleteAll] removes only this
/// app's values: on Android, iOS and macOS by the system's separation, on
/// Windows and Linux those of its application id.
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
  ///
  /// [applicationId] names the app's values on Windows and Linux (see
  /// above); the other platforms ignore it. A blank one is no id: the
  /// app's own is used.
  PlatformSecretStore({String? applicationId})
    : this._(_nonBlank(applicationId));

  PlatformSecretStore._(this.applicationId)
    : _platform = _platformStore(applicationId);

  /// The id the app's values are kept under on Windows and Linux, or
  /// `null` for the app's own (see above).
  final String? applicationId;

  static String? _nonBlank(String? id) =>
      id == null || id.trim().isEmpty ? null : id;

  final SecretStore _platform;

  /// Whether the current platform has a secure storage: `false` on the
  /// web and on Fuchsia.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.fuchsia;

  static SecretStore _platformStore(String? applicationId) {
    if (!isSupported) {
      throw UnsupportedError(
        'PlatformSecretStore: '
        '${kIsWeb ? 'the web' : defaultTargetPlatform.name} '
        'has no secure storage. In a browser the server logs the user in '
        'and keeps the tokens (oauth2Login()).',
      );
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => windowsSecretStore(applicationId),
      TargetPlatform.linux => linuxSecretStore(applicationId),
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
