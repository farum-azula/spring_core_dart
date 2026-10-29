// The cryptography of this package, and the only file of it that imports
// `pointycastle`: Bouncy Castle's Dart port, a third-party package allowed
// as an exception until a Dart team package covers what the security
// packages need (docs/dependencies.md). It comes with spring_security_core
// anyway. Here: SHA-256 (PKCE, the OpenID Connect nonce, RFC 7638
// thumbprints, DPoP's `ath`), ECDSA on P-256 (the software DPoP key, the
// JWT client secret, and its verification for ID tokens that did not come
// from the token endpoint), RSASSA-PKCS1-v1_5 SHA-256 verification (RS256
// ID tokens of the same kind) and the PKCS #8 reading of an EC private
// key. Replacing it means rewriting this file alone; the RFC 7636 vector
// of test/token_endpoint_test.dart, the RFC 6979 vector of
// test/dpop_client_test.dart and the RFC 7515 vectors of
// test/jwt_client_secret_test.dart check the result.
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart'
    show
        ASN1Integer,
        ASN1ObjectIdentifier,
        ASN1OctetString,
        ASN1Parser,
        ASN1Sequence;
import 'package:pointycastle/ecc/ecc_fp.dart' as fp;
import 'package:pointycastle/export.dart'
    show
        ECCurve_secp256r1,
        ECDSASigner,
        ECPrivateKey,
        ECPublicKey,
        ECSignature,
        HMac,
        PrivateKeyParameter,
        PublicKeyParameter,
        RSAPublicKey,
        RSASignature,
        RSASigner,
        SHA256Digest;

/// The SHA-256 digest of [bytes].
Uint8List sha256(List<int> bytes) =>
    SHA256Digest().process(Uint8List.fromList(bytes));

final _p256 = ECCurve_secp256r1();

/// The order `n` of the P-256 group: private keys are in `[1, n - 1]`.
BigInt get p256Order => _p256.n;

/// A new P-256 private key: a uniformly random number in `[1, n - 1]`,
/// drawn from the platform's cryptographically secure generator by
/// rejection sampling.
BigInt p256GeneratePrivateKey() {
  final random = Random.secure();
  final n = _p256.n;
  while (true) {
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    final d = unsignedBigInt(bytes);
    if (d > BigInt.zero && d < n) {
      return d;
    }
  }
}

/// The public point `d × G` of the P-256 private key [d], as its affine
/// coordinates.
({BigInt x, BigInt y}) p256PublicKey(BigInt d) {
  final point = (_p256.G * d)!;
  return (x: point.x!.toBigInteger()!, y: point.y!.toBigInteger()!);
}

/// The ECDSA P-256 SHA-256 signature (ES256) of [input] by the private key
/// [d], as `r` and `s`.
///
/// The nonce `k` is derived deterministically from the key and the
/// message (RFC 6979, HMAC-SHA-256): no random number is drawn, so a weak
/// or repeated random number can never reveal the key, and two different
/// messages never share a `k`.
({BigInt r, BigInt s}) p256Sign(BigInt d, Uint8List input) {
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(true, PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(d, _p256)));
  final signature = signer.generateSignature(input) as ECSignature;
  return (r: signature.r, s: signature.s);
}

/// The unsigned big-endian number of [bytes].
BigInt unsignedBigInt(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

/// [value] as exactly [length] big-endian bytes (left-padded with zeros).
///
/// Throws an [ArgumentError] when it is negative or does not fit.
Uint8List unsignedBytes(BigInt value, int length) {
  if (value.isNegative || value.bitLength > length * 8) {
    throw ArgumentError('The number does not fit in $length bytes');
  }
  final bytes = Uint8List(length);
  var rest = value;
  final mask = BigInt.from(0xff);
  for (var i = length - 1; i >= 0; i--) {
    bytes[i] = (rest & mask).toInt();
    rest = rest >> 8;
  }
  return bytes;
}

/// Whether ([r], [s]) is the ES256 signature of [input] by the P-256
/// public key ([x], [y]).
///
/// The caller checks that the point is on the curve
/// ([p256IsOnCurve]); malformed input counts as not verified.
bool p256Verify(BigInt x, BigInt y, Uint8List input, BigInt r, BigInt s) {
  try {
    final signer = ECDSASigner(SHA256Digest())
      ..init(
        false,
        PublicKeyParameter<ECPublicKey>(
          ECPublicKey(_p256.curve.createPoint(x, y), _p256),
        ),
      );
    return signer.verifySignature(input, ECSignature(r, s));
  } on Object {
    return false;
  }
}

/// Whether ([x], [y]) is a point of P-256 other than the point at
/// infinity: a public key that can be trusted to be one.
bool p256IsOnCurve(BigInt x, BigInt y) {
  final curve = _p256.curve;
  final p = (curve as fp.ECCurve).q!;
  if (x.isNegative || y.isNegative || x >= p || y >= p) {
    return false;
  }
  final a = curve.a!.toBigInteger()!;
  final b = curve.b!.toBigInteger()!;
  return (y * y - (x * x * x + a * x + b)) % p == BigInt.zero;
}

/// Whether [signature] is the RSASSA-PKCS1-v1_5 SHA-256 signature (RS256)
/// of [input] by the public key ([modulus], [exponent]).
///
/// Malformed input counts as not verified.
bool rsaPkcs1Sha256Verify(
  BigInt modulus,
  BigInt exponent,
  Uint8List input,
  Uint8List signature,
) {
  try {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(
        false,
        PublicKeyParameter<RSAPublicKey>(RSAPublicKey(modulus, exponent)),
      );
    return signer.verifySignature(input, RSASignature(signature));
  } on Object {
    return false;
  }
}

// id-ecPublicKey and prime256v1 (P-256).
const _ecPublicKeyOid = '1.2.840.10045.2.1';
const _p256Oid = '1.2.840.10045.3.1.7';

/// The private number `d` of the P-256 key in [der], a PKCS #8
/// `PrivateKeyInfo` (the body of a `-----BEGIN PRIVATE KEY-----` PEM,
/// such as the `.p8` key file of an Apple developer account).
///
/// Throws a [FormatException] when [der] is not an EC key on P-256 in
/// PKCS #8, or its number is out of range. The message never contains
/// key material.
BigInt p256PrivateKeyFromPkcs8(Uint8List der) {
  Never fail(String why) =>
      throw FormatException('Not a PKCS #8 P-256 private key: $why');
  try {
    final info = ASN1Parser(der).nextObject();
    if (info is! ASN1Sequence || (info.elements?.length ?? 0) < 3) {
      fail('no PrivateKeyInfo');
    }
    final algorithm = info.elements![1];
    if (algorithm is! ASN1Sequence || (algorithm.elements?.length ?? 0) < 2) {
      fail('no algorithm');
    }
    final type = algorithm.elements![0];
    final curve = algorithm.elements![1];
    if (type is! ASN1ObjectIdentifier ||
        type.objectIdentifierAsString != _ecPublicKeyOid ||
        curve is! ASN1ObjectIdentifier ||
        curve.objectIdentifierAsString != _p256Oid) {
      fail('not an EC key on P-256');
    }
    final octets = info.elements![2];
    if (octets is! ASN1OctetString || octets.octets == null) {
      fail('no private key');
    }
    final ecKey = ASN1Parser(octets.octets).nextObject();
    if (ecKey is! ASN1Sequence || (ecKey.elements?.length ?? 0) < 2) {
      fail('no ECPrivateKey');
    }
    final version = ecKey.elements![0];
    final number = ecKey.elements![1];
    if (version is! ASN1Integer ||
        version.integer != BigInt.one ||
        number is! ASN1OctetString ||
        number.octets == null) {
      fail('no ECPrivateKey');
    }
    final d = unsignedBigInt(number.octets!);
    if (d <= BigInt.zero || d >= _p256.n) {
      fail('the number is out of range');
    }
    return d;
  } on FormatException {
    rethrow;
  } on Object {
    fail('malformed DER');
  }
}
