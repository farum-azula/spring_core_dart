// Test keys and a token signer for the JWT tests (the application under
// test only gets the public keys). Signing is test-only code.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

SecureRandom _secureRandom() {
  final random = Random.secure();
  return FortunaRandom()..seed(
    KeyParameter(
      Uint8List.fromList(List.generate(32, (_) => random.nextInt(256))),
    ),
  );
}

String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String b64Json(Object json) => b64(utf8.encode(jsonEncode(json)));

Uint8List _bytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

/// An RSA key pair for RS*/PS* tokens.
final class RsaTestKey {
  RsaTestKey._(this.publicKey, this.privateKey, this.kid);

  factory RsaTestKey.generate({int bits = 2048, String kid = 'rsa-1'}) {
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
          _secureRandom(),
        ),
      );
    final pair = generator.generateKeyPair();
    return RsaTestKey._(pair.publicKey, pair.privateKey, kid);
  }

  final RSAPublicKey publicKey;
  final RSAPrivateKey privateKey;
  final String kid;

  RsaVerificationKey get verificationKey =>
      RsaVerificationKey(publicKey.modulus!, publicKey.exponent!, keyId: kid);

  Map<String, Object?> get jwk => {
    'kty': 'RSA',
    'kid': kid,
    'use': 'sig',
    'n': b64(
      _bytes(publicKey.modulus!, (publicKey.modulus!.bitLength + 7) ~/ 8),
    ),
    'e': b64(_bytes(publicKey.exponent!, 3)),
  };

  Uint8List sign(String alg, List<int> input) {
    final digest = switch (alg.substring(2)) {
      '256' => SHA256Digest(),
      '384' => SHA384Digest(),
      _ => SHA512Digest(),
    } as Digest;
    if (alg.startsWith('PS')) {
      final signer =
          PSSSigner(
            RSAEngine(),
            digest,
            switch (alg.substring(2)) {
              '256' => SHA256Digest(),
              '384' => SHA384Digest(),
              _ => SHA512Digest(),
            } as Digest,
          )..init(
            true,
            ParametersWithSaltConfiguration(
              PrivateKeyParameter<RSAPrivateKey>(privateKey),
              _secureRandom(),
              digest.digestSize,
            ),
          );
      return signer.generateSignature(Uint8List.fromList(input)).bytes;
    }
    final info = {
      '256': '0609608648016503040201',
      '384': '0609608648016503040202',
      '512': '0609608648016503040203',
    }[alg.substring(2)]!;
    final signer = RSASigner(digest, info)
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return signer.generateSignature(Uint8List.fromList(input)).bytes;
  }
}

/// An EC key pair for ES* tokens.
final class EcTestKey {
  EcTestKey._(this.domain, this.publicKey, this.privateKey, this.kid, this.crv);

  factory EcTestKey.generate({String crv = 'P-256', String kid = 'ec-1'}) {
    final domain = switch (crv) {
      'P-256' => ECCurve_secp256r1(),
      'P-384' => ECCurve_secp384r1(),
      _ => ECCurve_secp521r1(),
    } as ECDomainParameters;
    final generator = ECKeyGenerator()
      ..init(
        ParametersWithRandom(ECKeyGeneratorParameters(domain), _secureRandom()),
      );
    final pair = generator.generateKeyPair();
    return EcTestKey._(domain, pair.publicKey, pair.privateKey, kid, crv);
  }

  final ECDomainParameters domain;
  final ECPublicKey publicKey;
  final ECPrivateKey privateKey;
  final String kid;
  final String crv;

  int get size => (domain.curve.fieldSize + 7) ~/ 8;

  EcVerificationKey get verificationKey => EcVerificationKey(
    crv,
    publicKey.Q!.x!.toBigInteger()!,
    publicKey.Q!.y!.toBigInteger()!,
    keyId: kid,
  );

  Map<String, Object?> get jwk => {
    'kty': 'EC',
    'kid': kid,
    'crv': crv,
    'x': b64(_bytes(publicKey.Q!.x!.toBigInteger()!, size)),
    'y': b64(_bytes(publicKey.Q!.y!.toBigInteger()!, size)),
  };

  Uint8List sign(String alg, List<int> input) {
    final digest = switch (alg) {
      'ES256' => SHA256Digest(),
      'ES384' => SHA384Digest(),
      _ => SHA512Digest(),
    } as Digest;
    final signer = ECDSASigner(digest)
      ..init(
        true,
        ParametersWithRandom(
          PrivateKeyParameter<ECPrivateKey>(privateKey),
          _secureRandom(),
        ),
      );
    final signature =
        signer.generateSignature(Uint8List.fromList(input)) as ECSignature;
    return Uint8List.fromList([
      ..._bytes(signature.r, size),
      ..._bytes(signature.s, size),
    ]);
  }
}

/// Signs tokens with [rsa], [ec] or an HMAC [secret].
final class TokenFactory {
  TokenFactory(this.rsa, this.ec, this.secret);

  final RsaTestKey rsa;
  final EcTestKey ec;
  final List<int> secret;

  static int now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// A token with [claims] (an hour of validity by default) signed with
  /// [alg].
  String token({
    String alg = 'RS256',
    Map<String, Object?> claims = const {},
    Map<String, Object?> header = const {},
    String? kid,
  }) {
    final h = {
      'alg': alg,
      'typ': 'JWT',
      if (kid != null)
        'kid': kid
      else if (alg.startsWith('ES'))
        'kid': ec.kid
      else if (!alg.startsWith('HS'))
        'kid': rsa.kid,
      ...header,
    };
    final c = {
      'sub': 'ada',
      'iat': now(),
      'exp': now() + 3600,
      'scope': 'read',
      ...claims,
    };
    final input = '${b64Json(h)}.${b64Json(c)}';
    return '$input.${b64(signature(alg, ascii.encode(input)))}';
  }

  List<int> signature(String alg, List<int> input) {
    if (alg.startsWith('HS')) {
      final mac = HMac(
        switch (alg) {
          'HS256' => SHA256Digest(),
          'HS384' => SHA384Digest(),
          _ => SHA512Digest(),
        } as Digest,
        alg == 'HS256' ? 64 : 128,
      )..init(KeyParameter(Uint8List.fromList(secret)));
      return mac.process(Uint8List.fromList(input));
    }
    if (alg.startsWith('ES')) {
      return ec.sign(alg, input);
    }
    return rsa.sign(alg, input);
  }
}

/// The keys of the JWT test application (generated once per isolate).
final testKeys = TokenFactory(
  RsaTestKey.generate(),
  EcTestKey.generate(),
  List.generate(32, (i) => i * 7 % 256),
);
