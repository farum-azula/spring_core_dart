// The cryptography of JWS signatures, and the only file of this package
// that imports `pointycastle`: Bouncy Castle's Dart port, a third-party
// package allowed as an exception until a Dart team package covers RSA and
// ECDSA (docs/dependencies.md). Replacing it means rewriting this file
// alone; the RFC 7515 vectors and test/jose_test.dart check the result.
import 'dart:typed_data';

import 'package:pointycastle/ecc/ecc_fp.dart' as fp;
import 'package:pointycastle/export.dart'
    show
        Digest,
        ECCurve_secp256r1,
        ECCurve_secp384r1,
        ECCurve_secp521r1,
        ECDSASigner,
        ECDomainParameters,
        ECPublicKey,
        ECSignature,
        FortunaRandom,
        HMac,
        KeyParameter,
        PSSSignature,
        PSSSigner,
        ParametersWithSaltConfiguration,
        PublicKeyParameter,
        RSAEngine,
        RSAPublicKey,
        RSASignature,
        RSASigner,
        SHA256Digest,
        SHA384Digest,
        SHA512Digest;

/// The numbers that define a NIST prime curve `y² = x³ + ax + b (mod p)`,
/// and how many bytes one coordinate takes (`fieldBytes`); used to check
/// that a public key lies on its curve and to split ECDSA signatures.
typedef CurveParameters = ({BigInt p, BigInt a, BigInt b, int fieldBytes});

/// The parameters of `P-256`, `P-384` or `P-521`; `null` for any other
/// curve name.
CurveParameters? curveParameters(String curve) {
  final domain = _domain(curve);
  if (domain == null) {
    return null;
  }
  return (
    p: (domain.curve as fp.ECCurve).q!,
    a: domain.curve.a!.toBigInteger()!,
    b: domain.curve.b!.toBigInteger()!,
    fieldBytes: (domain.curve.fieldSize + 7) ~/ 8,
  );
}

/// The HMAC-SHA-[bits] of [data] with [key], for [bits] 256, 384 or 512.
///
/// The caller compares it with the token's signature in constant time.
Uint8List hmacSha(int bits, List<int> key, Uint8List data) => (HMac(
  _sha(bits),
  bits == 256 ? 64 : 128,
)..init(KeyParameter(Uint8List.fromList(key)))).process(data);

/// Whether [signature] is the RSASSA-PKCS1-v1_5 SHA-[bits] signature of
/// [input] by the public key ([modulus], [exponent]): the RS* algorithms.
///
/// May throw on malformed input; `verifySignature` treats that as "not
/// verified".
bool verifyRsaPkcs1(
  int bits,
  BigInt modulus,
  BigInt exponent,
  Uint8List input,
  Uint8List signature,
) {
  final signer = RSASigner(_sha(bits), _digestInfo[bits]!)
    ..init(
      false,
      PublicKeyParameter<RSAPublicKey>(RSAPublicKey(modulus, exponent)),
    );
  return signer.verifySignature(input, RSASignature(signature));
}

/// Whether [signature] is the RSASSA-PSS SHA-[bits] signature of [input]
/// by the public key ([modulus], [exponent]): the PS* algorithms, with
/// MGF1 on the same hash and a salt as long as the hash.
///
/// May throw on malformed input; `verifySignature` treats that as "not
/// verified".
bool verifyRsaPss(
  int bits,
  BigInt modulus,
  BigInt exponent,
  Uint8List input,
  Uint8List signature,
) {
  final digest = _sha(bits);
  final signer = PSSSigner(RSAEngine(), digest, _sha(bits))
    ..init(
      false,
      ParametersWithSaltConfiguration(
        PublicKeyParameter<RSAPublicKey>(RSAPublicKey(modulus, exponent)),
        FortunaRandom(), // unused: verifying draws no random numbers
        digest.digestSize,
      ),
    );
  return signer.verifySignature(input, PSSSignature(signature));
}

/// Whether ([r], [s]) is the ECDSA SHA-[bits] signature of [input] by the
/// public key ([x], [y]) on [curve]: the ES* algorithms.
///
/// The caller has checked that the point is on the curve. May throw on
/// malformed input; `verifySignature` treats that as "not verified".
bool verifyEcdsa(
  int bits,
  String curve,
  BigInt x,
  BigInt y,
  Uint8List input,
  BigInt r,
  BigInt s,
) {
  final domain = _domain(curve)!;
  final signer = ECDSASigner(_sha(bits))
    ..init(
      false,
      PublicKeyParameter<ECPublicKey>(
        ECPublicKey(domain.curve.createPoint(x, y), domain),
      ),
    );
  return signer.verifySignature(input, ECSignature(r, s));
}

ECDomainParameters? _domain(String curve) => switch (curve) {
  'P-256' => ECCurve_secp256r1(),
  'P-384' => ECCurve_secp384r1(),
  'P-521' => ECCurve_secp521r1(),
  _ => null,
};

Digest _sha(int bits) => switch (bits) {
  256 => SHA256Digest(),
  384 => SHA384Digest(),
  _ => SHA512Digest(),
};

// DigestInfo prefixes (DER) of PKCS#1 v1.5 signatures.
const _digestInfo = {
  256: '0609608648016503040201',
  384: '0609608648016503040202',
  512: '0609608648016503040203',
};
