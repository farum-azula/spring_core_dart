import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// Where a [StoredDPoPKey] keeps its private key, once loaded.
enum DPoPKeyStorage {
  /// The Secure Enclave of an iPhone, iPad or Mac: the key was made there
  /// and never leaves it; the Secure Enclave signs.
  secureEnclave,

  /// The Keychain, as a software key (no Secure Enclave: the iOS
  /// simulator, Macs without one, a macOS build without the entitlements
  /// of the data protection keychain). The app's code never handles it,
  /// but the system's Security framework loads it into the app's process
  /// to sign.
  keychain,

  /// The StrongBox of an Android phone: a separate secure chip.
  strongBox,

  /// The Android Keystore in the phone's trusted execution environment.
  trustedEnvironment,

  /// The Android Keystore without secure hardware (some emulators): the
  /// key is still kept by the system, outside the app's process.
  software,

  /// A software key made in Dart, kept as a JWK in the app's
  /// `SecretStore` (DPAPI on Windows, the Secret Service on Linux) and
  /// signing in the app's memory.
  secretStore,
}

/// A [LoadableDPoPKey] kept by the platform across restarts, which can be
/// deleted (rotated): the next [load] then makes a new one.
///
/// Internal to the package: `PlatformDPoPKey` is the type applications
/// see. Implemented by the platform channel's key and by
/// `SecretStoreDPoPKey`.
abstract interface class StoredDPoPKey implements LoadableDPoPKey {
  /// Where the key is, once [load] completed; `null` before.
  DPoPKeyStorage? get storage;

  /// Removes the key; the next [load] (the next proof) makes a new one.
  /// Tokens bound to the removed key can no longer be used.
  Future<void> delete();
}

/// Shares one running load between callers, and lets the next call try
/// again when it failed.
final class SharedLoad {
  Future<void>? _running;

  /// Runs [load] unless one runs; its errors reach every caller.
  Future<void> run(Future<void> Function() load) {
    final running = _running;
    if (running != null) {
      return running;
    }
    final started = load();
    _running = started;
    return started.whenComplete(() {
      if (identical(_running, started)) {
        _running = null;
      }
    });
  }
}
