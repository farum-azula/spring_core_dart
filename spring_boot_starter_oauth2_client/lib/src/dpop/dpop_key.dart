import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_oauth2_client/src/core/crypto_primitives.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/jwk_thumbprint.dart';

/// The key pair that signs an app's DPoP proofs (RFC 9449): DPoP-bound
/// tokens are useless to whoever steals them without it.
///
/// With DPoP the provider binds the access and refresh tokens to this
/// key: every token request and every API call carries a proof signed by
/// it. The private part should never leave the key: on phones it lives in
/// the Secure Enclave or the Android Keystore, which sign without ever
/// exporting it; elsewhere [SoftwareDPoPKey] keeps it in memory. Most
/// applications never touch this type: the starter declares a `DPoPKey`
/// bean, and the token clients, the user services and the Feign
/// interceptor use it. Declare a bean of your own to use a key kept
/// elsewhere (a hardware key, a key the app stored).
///
/// ```dart
/// // A key the application keeps (loaded from secure storage at
/// // startup), so its tokens stay usable after a restart.
/// @Bean()
/// DPoPKey dPoPKey(AppKeys keys) => SoftwareDPoPKey.fromJwk(keys.dPoPJwk);
/// ```
///
/// Spring (Java): no such type; Spring Security has no DPoP on the
/// client's side yet (spring-security#18228).
abstract interface class DPoPKey {
  /// The JWS algorithm of the signatures, as named in the proof's `alg`
  /// header: `ES256`.
  String get algorithm;

  /// The public key as a JWK, such as `{"kty": "EC", "crv": "P-256",
  /// "x": ..., "y": ...}`: the proof's `jwk` header. It has no private
  /// member.
  Map<String, Object?> get publicJwk;

  /// The signature of [input] (the ASCII of `header.payload`), as JOSE
  /// wants it: for ES256 the raw `R || S`, 32 + 32 bytes, not DER. A key
  /// that signs in DER converts with [ECDSA.transcodeSignatureToConcat].
  Future<Uint8List> sign(Uint8List input);

  /// Whether the key outlives the program: kept in the Secure Enclave, the
  /// Android Keystore, WebCrypto's IndexedDB or secure storage, so tokens
  /// bound to it can still be refreshed after a restart.
  ///
  /// `dpop=auto` turns DPoP on only for such a key: a key made in memory
  /// for one run (the starter's default on servers) keeps `Bearer` tokens
  /// unless a registration says `dpop=true`.
  bool get persistent;
}

/// A [DPoPKey] that is made or read on first use, asynchronously: a key
/// in the platform's keystore (the Secure Enclave, the Android Keystore),
/// or a key kept in secure storage, whose public part is not known until
/// the platform answered.
///
/// `DPoPProofBuilder` awaits [load] before it reads [publicJwk], so the
/// key costs nothing until the first proof, and an app whose providers
/// do not use DPoP never makes one. Applications never call it; a key of
/// their own implements it when it cannot know its public key at once.
///
/// ```dart
/// final class KeystoreKey implements LoadableDPoPKey {
///   Map<String, Object?>? _jwk;
///
///   @override
///   Future<void> load() async => _jwk ??= await platform.publicJwk();
///
///   @override
///   Map<String, Object?> get publicJwk =>
///       _jwk ?? (throw StateError('not loaded'));
///   // algorithm, sign ...
/// }
/// ```
///
/// Spring (Java): no such type (see [DPoPKey]).
abstract interface class LoadableDPoPKey implements DPoPKey {
  /// Makes the key, or reads the one made earlier, when that is not done
  /// yet; afterwards [publicJwk] answers. Calls while one runs share it.
  ///
  /// Throws when the platform cannot make or read the key; the request
  /// that needed a proof fails, and the next call tries again.
  Future<void> load();
}

/// An ES256 [DPoPKey] made and used in Dart: for the VM, servers and the
/// desktops, where there is no hardware key.
///
/// The key pair is P-256; signatures are ECDSA with SHA-256 and a nonce
/// derived from the key and the message (RFC 6979), so no random number
/// is drawn when signing and a nonce is never reused.
///
/// A new key ([SoftwareDPoPKey.generate]) lives as long as the object:
/// tokens bound to it are dead once it is gone, the refresh token too, so
/// after a restart the user logs in again. An app that wants its login
/// to survive a restart keeps the key with [toJwk] in secure storage (the
/// Keychain, the Keystore, DPAPI, libsecret) and restores it with
/// [SoftwareDPoPKey.fromJwk]. [toJwk] holds the private key: never log it,
/// never send it. [toString] shows only the public thumbprint.
///
/// ```dart
/// // Keep the key with the tokens: the same secure storage.
/// final key = SoftwareDPoPKey.generate();
/// await secrets.write('dpop-key', jsonEncode(key.toJwk()));
/// // At the next start:
/// final restored = SoftwareDPoPKey.fromJwk(
///   jsonDecode((await secrets.read('dpop-key'))!) as Map<String, Object?>,
/// );
/// ```
///
/// Spring (Java): no such type (see [DPoPKey]); Nimbus' `ECKeyGenerator`
/// and `ECDSASigner` play its part in Java code.
final class SoftwareDPoPKey implements DPoPKey {
  SoftwareDPoPKey._(this._d, {required this.persistent});

  /// A new random P-256 key pair, from the platform's secure random
  /// generator. Only the private number is drawn now; the public point is
  /// computed at the first use, so an application that never uses DPoP
  /// pays almost nothing for its key bean.
  factory SoftwareDPoPKey.generate({bool persistent = false}) =>
      SoftwareDPoPKey._(p256GeneratePrivateKey(), persistent: persistent);

  /// The key pair of the private EC JWK [jwk] (`kty` `EC`, `crv` `P-256`,
  /// `x`, `y` and `d`, base64url of 32 bytes each), as [toJwk] writes it.
  ///
  /// Other members (`kid`, `alg`, `use`) are ignored. Throws a
  /// [FormatException] when a member is missing or malformed, `d` is out
  /// of range, or `x` and `y` are not the public key of `d`. The message
  /// never contains the key.
  factory SoftwareDPoPKey.fromJwk(
    Map<String, Object?> jwk, {
    bool persistent = true,
  }) {
    if (jwk['kty'] != 'EC' || jwk['crv'] != 'P-256') {
      throw const FormatException('A DPoP key must be an EC P-256 JWK');
    }
    BigInt member(String name) {
      final value = jwk[name];
      if (value is! String) {
        throw FormatException('The JWK member "$name" is missing');
      }
      final List<int> bytes;
      try {
        bytes = base64Url.decode(base64Url.normalize(value));
      } on FormatException {
        throw FormatException('The JWK member "$name" is not base64url');
      }
      if (bytes.length != 32) {
        throw FormatException('The JWK member "$name" is not 32 bytes');
      }
      return unsignedBigInt(bytes);
    }

    final d = member('d');
    final x = member('x');
    final y = member('y');
    if (d == BigInt.zero || d >= p256Order) {
      throw const FormatException('The JWK member "d" is out of range');
    }
    final public = p256PublicKey(d);
    if (public.x != x || public.y != y) {
      throw const FormatException(
        'The JWK members "x" and "y" are not the public key of "d"',
      );
    }
    return SoftwareDPoPKey._(d, persistent: persistent);
  }

  final BigInt _d;

  /// Whether the key outlives the program: `false` for a key
  /// [SoftwareDPoPKey.generate]d in memory, `true` (by default) for one
  /// read from a stored JWK; the owner of the storage says.
  @override
  final bool persistent;

  @override
  String get algorithm => 'ES256';

  @override
  late final Map<String, Object?> publicJwk = () {
    final public = p256PublicKey(_d);
    return Map<String, Object?>.unmodifiable({
      'kty': 'EC',
      'crv': 'P-256',
      'x': _b64(unsignedBytes(public.x, 32)),
      'y': _b64(unsignedBytes(public.y, 32)),
    });
  }();

  /// The RFC 7638 thumbprint of the public key: the `cnf.jkt` of the
  /// tokens bound to it.
  String get thumbprint => JwkThumbprint.of(publicJwk);

  @override
  Future<Uint8List> sign(Uint8List input) async {
    final signature = p256Sign(_d, input);
    return Uint8List(64)
      ..setAll(0, unsignedBytes(signature.r, 32))
      ..setAll(32, unsignedBytes(signature.s, 32));
  }

  /// The key pair as a private JWK (the public members and `d`), for the
  /// app's secure storage; [SoftwareDPoPKey.fromJwk] reads it back.
  ///
  /// It contains the private key: whoever has it can use the tokens bound
  /// to it. Never log it, never send it anywhere.
  Map<String, Object?> toJwk() => {
    ...publicJwk,
    'd': _b64(unsignedBytes(_d, 32)),
  };

  /// The algorithm and the public thumbprint; never the private key.
  @override
  String toString() => 'SoftwareDPoPKey [alg=ES256, jkt=$thumbprint]';

  static String _b64(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');
}

/// Conversions of ECDSA signatures between DER, as platform keys write
/// them, and the raw `R || S` of JOSE (RFC 7518 §3.4).
///
/// The Secure Enclave (`SecKeyCreateSignature`), the Android Keystore
/// (`Signature.getInstance("SHA256withECDSA")`) and OpenSSL return an
/// ASN.1 DER `SEQUENCE { INTEGER r, INTEGER s }`;
/// a JWS signature is the two numbers as fixed-size big-endian bytes, one
/// after the other. A [DPoPKey] backed by such a key converts what it
/// gets before returning it.
///
/// ```dart
/// // In a DPoPKey backed by the Android Keystore:
/// @override
/// Future<Uint8List> sign(Uint8List input) async =>
///     ECDSA.transcodeSignatureToConcat(await keystore.sign(input), 64);
/// ```
///
/// Spring (Java): Nimbus' `ECDSA.transcodeSignatureToConcat`, with the
/// same name.
abstract final class ECDSA {
  /// The raw `R || S` of the DER ECDSA signature [der], [outputLength]
  /// bytes long (64 for ES256, 96 for ES384, 132 for ES512).
  ///
  /// Strict: one `SEQUENCE` of two positive, minimally encoded `INTEGER`s
  /// that fit in half of [outputLength], nothing before or after. Throws a
  /// [FormatException] otherwise.
  static Uint8List transcodeSignatureToConcat(
    List<int> der,
    int outputLength,
  ) {
    if (outputLength <= 0 || outputLength.isOdd) {
      throw ArgumentError.value(outputLength, 'outputLength', 'must be even');
    }
    final half = outputLength ~/ 2;
    var offset = 0;
    Never invalid(String why) =>
        throw FormatException('Not a DER ECDSA signature: $why');
    int byte() => offset < der.length ? der[offset++] : invalid('truncated');
    int length() {
      final first = byte();
      if (first < 0x80) {
        return first;
      }
      if (first == 0x81) {
        final value = byte();
        return value >= 0x80 ? value : invalid('non-minimal length');
      }
      return invalid('unsupported length');
    }

    List<int> integer() {
      if (byte() != 0x02) {
        invalid('INTEGER expected');
      }
      final size = length();
      if (size == 0 || offset + size > der.length) {
        invalid('bad INTEGER length');
      }
      var value = der.sublist(offset, offset + size);
      offset += size;
      if (value[0] & 0x80 != 0) {
        invalid('negative INTEGER');
      }
      if (value.length > 1 && value[0] == 0 && value[1] & 0x80 == 0) {
        invalid('non-minimal INTEGER');
      }
      if (value[0] == 0) {
        value = value.sublist(1);
      }
      if (value.length > half) {
        invalid('INTEGER too large');
      }
      if (value.every((b) => b == 0)) {
        invalid('zero INTEGER');
      }
      return value;
    }

    if (byte() != 0x30) {
      invalid('SEQUENCE expected');
    }
    final size = length();
    if (offset + size != der.length) {
      invalid('bad SEQUENCE length');
    }
    final r = integer();
    final s = integer();
    if (offset != der.length) {
      invalid('trailing bytes');
    }
    return Uint8List(outputLength)
      ..setAll(half - r.length, r)
      ..setAll(outputLength - s.length, s);
  }
}
