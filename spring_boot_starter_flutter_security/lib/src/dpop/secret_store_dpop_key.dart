import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_flutter_security/src/dpop/stored_dpop_key.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

const _log = SpringLog('spring.security.oauth2.client');

/// A DPoP key made in Dart and kept as a private JWK in a [SecretStore],
/// so the tokens bound to it survive a restart: the app's key on Windows
/// and Linux, which have no keystore that signs for the app.
///
/// The key is made on its first use ([load], called by
/// `DPoPProofBuilder`) and written under [key] (`oauth2.dpop-key`, the
/// login's namespace, which `SecretTemplate` refuses); later starts read
/// it back. On the `PlatformSecretStore` it is encrypted with DPAPI for
/// the Windows user, or kept by the Secret Service on Linux; it signs in
/// the app's memory (a [SoftwareDPoPKey]). A stored value that is not a
/// valid key is replaced by a new key: tokens bound to the old one are
/// then refused, and the user logs in again.
///
/// Applications rarely create one: the package's `PlatformDPoPKey` bean
/// uses it on Windows and Linux. An app on another store (its own
/// `SecretStore` bean) gets it on that store.
///
/// ```dart
/// // A key of the app's own, on its encrypted store.
/// @Bean()
/// DPoPKey dPoPKey(MyEncryptedStore store) => SecretStoreDPoPKey(store);
/// ```
///
/// The stored value holds the private key: it is never logged, and
/// [toString] shows only the public thumbprint. [SecretStore.deleteAll]
/// removes it too (the next proof makes a new key).
///
/// Spring has no such type (Spring Security has no DPoP on the client's
/// side).
final class SecretStoreDPoPKey implements StoredDPoPKey {
  /// Kept outside the program, so tokens bound to it survive a restart.
  @override
  bool get persistent => true;

  /// A key kept in [secretStore] under [key].
  SecretStoreDPoPKey(this.secretStore, {this.key = defaultKey});

  /// The key of the stored JWK by default.
  static const defaultKey = 'oauth2.dpop-key';

  /// Where the key is kept.
  final SecretStore secretStore;

  /// The key of the stored JWK in [secretStore].
  final String key;

  SoftwareDPoPKey? _key;
  final SharedLoad _loading = SharedLoad();

  @override
  String get algorithm => 'ES256';

  @override
  DPoPKeyStorage? get storage =>
      _key == null ? null : DPoPKeyStorage.secretStore;

  /// The public JWK; throws a [StateError] before [load].
  @override
  Map<String, Object?> get publicJwk =>
      (_key ?? (throw StateError('The DPoP key is not loaded yet'))).publicJwk;

  @override
  Future<void> load() =>
      _key != null ? Future.value() : _loading.run(_readOrCreate);

  Future<void> _readOrCreate() async {
    final stored = await secretStore.read(key);
    if (stored != null) {
      try {
        _key = SoftwareDPoPKey.fromJwk(
          (jsonDecode(stored) as Map).cast<String, Object?>(),
        );
        return;
      } on Object {
        // Never log the value: it is a private key.
        _log.warning('The stored DPoP key is unreadable; making a new one');
      }
    }
    final made = SoftwareDPoPKey.generate();
    await secretStore.write(key, jsonEncode(made.toJwk()));
    _key = made;
    _log.debug('Made a new DPoP key in the SecretStore');
  }

  @override
  Future<Uint8List> sign(Uint8List input) async {
    await load();
    return _key!.sign(input);
  }

  @override
  Future<void> delete() async {
    _key = null;
    await secretStore.delete(key);
  }

  /// The algorithm and, once loaded, the public thumbprint; never the
  /// private key.
  @override
  String toString() =>
      'SecretStoreDPoPKey [alg=ES256, '
      'jkt=${_key?.thumbprint ?? 'not loaded'}]';
}
