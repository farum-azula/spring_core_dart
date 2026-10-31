import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:spring_boot_starter_flutter_security/src/dpop/platform_dpop_key.dart';
import 'package:spring_boot_starter_flutter_security/src/dpop/stored_dpop_key.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

const _log = SpringLog('spring.security.oauth2.client');

/// The channel of the plugin's DPoP key on Android, iOS and macOS.
///
/// Methods:
///
/// - `dpopPublicJwk` (no arguments): makes the key when there is none,
///   answers `{"publicKey": bytes, "storage": name}`: the public key as
///   the uncompressed point `0x04 || X || Y` (iOS, macOS:
///   `SecKeyCopyExternalRepresentation`) or the X.509
///   `SubjectPublicKeyInfo` (Android: `PublicKey.getEncoded()`), and where
///   the key is (a [DPoPKeyStorage] name);
/// - `dpopSign` `{"data": bytes}`: the ECDSA P-256 SHA-256 signature of
///   `data` in DER; never makes a key: without one it fails with the code
///   `no_key`;
/// - `dpopDelete` (no arguments): removes the key; `null`.
///
/// Errors are `PlatformException`s with the code `dpop_key` (or
/// `no_key`) and a message that says what failed, never key material.
const dPoPKeyChannel = MethodChannel(
  'spring_boot_starter_flutter_security/dpop_key',
);

/// The prefix of the X.509 `SubjectPublicKeyInfo` of every P-256 public
/// key (`id-ecPublicKey`, `prime256v1`, a 66-byte BIT STRING), before the
/// uncompressed point.
const _p256SpkiPrefix = [
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, //
  0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, //
  0x42, 0x00,
];

final _p = BigInt.parse(
  'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
  radix: 16,
);
final _b = BigInt.parse(
  '5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b',
  radix: 16,
);

/// The public EC JWK (`kty`, `crv`, `x`, `y`) of a P-256 public key given
/// as the uncompressed point `0x04 || X || Y` (65 bytes) or as its X.509
/// `SubjectPublicKeyInfo` (91 bytes).
///
/// Throws a [FormatException] for anything else, or a point that is not
/// on the curve.
Map<String, Object?> p256PublicJwk(List<int> publicKey) {
  var point = publicKey;
  if (point.length == _p256SpkiPrefix.length + 65) {
    for (var i = 0; i < _p256SpkiPrefix.length; i++) {
      if (point[i] != _p256SpkiPrefix[i]) {
        throw const FormatException('Not the public key of a P-256 key');
      }
    }
    point = point.sublist(_p256SpkiPrefix.length);
  }
  if (point.length != 65 || point[0] != 0x04) {
    throw const FormatException('Not an uncompressed P-256 point');
  }
  final xBytes = point.sublist(1, 33);
  final yBytes = point.sublist(33);
  BigInt number(List<int> bytes) =>
      bytes.fold(BigInt.zero, (value, b) => (value << 8) | BigInt.from(b));
  final x = number(xBytes);
  final y = number(yBytes);
  // y² = x³ - 3x + b (mod p)
  if (x >= _p ||
      y >= _p ||
      (y * y - (x * x * x - BigInt.from(3) * x + _b)) % _p != BigInt.zero) {
    throw const FormatException('The point is not on the P-256 curve');
  }
  String b64(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');
  return Map.unmodifiable({
    'kty': 'EC',
    'crv': 'P-256',
    'x': b64(xBytes),
    'y': b64(yBytes),
  });
}

/// The DPoP key of Android, iOS and macOS: made and used by the plugin's
/// platform code through [dPoPKeyChannel], in the Secure Enclave or the
/// Keychain, or in the Android Keystore. The private key never reaches
/// Dart (a software Keychain key is loaded by the system's Security
/// framework into the app's process to sign, outside Dart's heap).
final class MethodChannelDPoPKey implements StoredDPoPKey {
  /// Kept outside the program, so tokens bound to it survive a restart.
  @override
  bool get persistent => true;

  /// The key; nothing is asked of the platform before [load].
  MethodChannelDPoPKey();

  Map<String, Object?>? _jwk;
  DPoPKeyStorage? _storage;
  final SharedLoad _loading = SharedLoad();

  @override
  String get algorithm => 'ES256';

  @override
  DPoPKeyStorage? get storage => _storage;

  /// The public JWK; throws a [StateError] before [load].
  @override
  Map<String, Object?> get publicJwk =>
      _jwk ?? (throw StateError('The DPoP key is not loaded yet'));

  @override
  Future<void> load() => _jwk != null ? Future.value() : _loading.run(_load);

  Future<void> _load() async {
    final answer = await _call<Map<Object?, Object?>>('dpopPublicJwk');
    final publicKey = answer?['publicKey'];
    if (publicKey is! Uint8List) {
      throw const PlatformDPoPKeyException(
        'the platform answered no public key',
        code: 'dpop_key',
      );
    }
    final Map<String, Object?> jwk;
    try {
      jwk = p256PublicJwk(publicKey);
    } on FormatException catch (e) {
      throw PlatformDPoPKeyException(
        'the platform answered an unusable public key: ${e.message}',
        code: 'dpop_key',
      );
    }
    _storage = DPoPKeyStorage.values
        .where((s) => s.name == answer?['storage'])
        .firstOrNull;
    _jwk = jwk;
    _log.debug('DPoP key ready (${_storage?.name ?? 'unknown storage'})');
  }

  /// Signs [input] in the platform (DER) and returns the raw `R || S`.
  ///
  /// When the key is gone (the Keystore wiped, the app's keys removed),
  /// throws a [PlatformDPoPKeyException] with the code `no_key` and
  /// forgets the public key: the next proof makes a new key, and tokens
  /// bound to the old one are refused (the user logs in again).
  @override
  Future<Uint8List> sign(Uint8List input) async {
    await load();
    final Uint8List? der;
    try {
      der = await _call<Uint8List>('dpopSign', {'data': input});
    } on PlatformDPoPKeyException catch (e) {
      if (e.code == 'no_key') {
        _log.warning(
          'The DPoP key is gone; a new one is made for the next proof',
        );
        _forget();
      }
      rethrow;
    }
    if (der == null) {
      throw const PlatformDPoPKeyException(
        'the platform answered no signature',
        code: 'dpop_key',
      );
    }
    try {
      return ECDSA.transcodeSignatureToConcat(der, 64);
    } on FormatException catch (e) {
      throw PlatformDPoPKeyException(
        'the platform answered an unusable signature: ${e.message}',
        code: 'dpop_key',
      );
    }
  }

  @override
  Future<void> delete() async {
    _forget();
    await _call<void>('dpopDelete');
  }

  void _forget() {
    _jwk = null;
    _storage = null;
  }

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await dPoPKeyChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw PlatformDPoPKeyException(e.message ?? e.code, code: e.code);
    } on MissingPluginException {
      throw const PlatformDPoPKeyException(
        'the platform code of spring_boot_starter_flutter_security is not '
        'registered (a Dart test without the app? mock the channel '
        "'spring_boot_starter_flutter_security/dpop_key', or declare "
        'another DPoPKey bean)',
        code: 'no_plugin',
      );
    }
  }

  @override
  String toString() =>
      'MethodChannelDPoPKey [alg=ES256, '
      'jkt=${_jwk == null ? 'not loaded' : JwkThumbprint.of(_jwk!)}, '
      'storage=${_storage?.name}]';
}
