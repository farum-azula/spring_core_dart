import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_security/src/jwt/signature_primitives.dart';
import 'package:spring_security_core/spring_security_core.dart'
    show constantTimeEquals;

/// An algorithm a JWT can be signed with, as named in its `alg` header.
///
/// RS*, PS* and ES* use the identity provider's private key and are
/// checked with its public key; HS* use a secret shared between the
/// issuer and this server. A decoder accepts only the algorithms you
/// allow (`jws-algorithms`, RS256 by default). `none` does not exist
/// here: an unsigned token is never accepted.
///
/// Spring (Java): `SignatureAlgorithm` and `MacAlgorithm`.
enum JwsAlgorithm {
  /// RSASSA-PKCS1-v1_5 with SHA-256.
  rs256('RS256', _Family.rsa, 256),

  /// RSASSA-PKCS1-v1_5 with SHA-384.
  rs384('RS384', _Family.rsa, 384),

  /// RSASSA-PKCS1-v1_5 with SHA-512.
  rs512('RS512', _Family.rsa, 512),

  /// RSASSA-PSS with SHA-256.
  ps256('PS256', _Family.rsaPss, 256),

  /// RSASSA-PSS with SHA-384.
  ps384('PS384', _Family.rsaPss, 384),

  /// RSASSA-PSS with SHA-512.
  ps512('PS512', _Family.rsaPss, 512),

  /// ECDSA on P-256 with SHA-256.
  es256('ES256', _Family.ec, 256),

  /// ECDSA on P-384 with SHA-384.
  es384('ES384', _Family.ec, 384),

  /// ECDSA on P-521 with SHA-512.
  es512('ES512', _Family.ec, 512),

  /// HMAC with SHA-256.
  hs256('HS256', _Family.hmac, 256),

  /// HMAC with SHA-384.
  hs384('HS384', _Family.hmac, 384),

  /// HMAC with SHA-512.
  hs512('HS512', _Family.hmac, 512);

  JwsAlgorithm(this.name, this._family, this._bits);

  /// The name in the `alg` header, such as `RS256`.
  final String name;

  final _Family _family;
  final int _bits;

  /// The algorithm named [name] (`RS256`, case-sensitive), or `null` for
  /// an unknown name (including `none`).
  static JwsAlgorithm? from(String name) {
    for (final algorithm in values) {
      if (algorithm.name == name) {
        return algorithm;
      }
    }
    return null;
  }

  /// Whether it uses a shared secret (HS*) rather than a public key.
  bool get isMac => _family == _Family.hmac;

  /// The JWK `kty` of the keys that verify it: `RSA`, `EC` or `oct`.
  String get keyType => switch (_family) {
    _Family.rsa || _Family.rsaPss => 'RSA',
    _Family.ec => 'EC',
    _Family.hmac => 'oct',
  };

  /// The EC curve of an ES algorithm (`P-256` for ES256); `null` for the
  /// others.
  String? get curve => switch (this) {
    es256 => 'P-256',
    es384 => 'P-384',
    es512 => 'P-521',
    _ => null,
  };
}

enum _Family { rsa, rsaPss, ec, hmac }

/// A key that verifies JWT signatures: an [RsaVerificationKey], an
/// [EcVerificationKey] or a [SecretVerificationKey].
///
/// Usually parsed from the identity provider's JWK Set. Build one by hand
/// for `NimbusJwtDecoder.withPublicKey` or a `StaticJwkSource`.
sealed class VerificationKey {
  const VerificationKey({this.keyId, this.algorithm, this.use});

  /// The key id (`kid`) tokens name to pick this key, or `null`.
  final String? keyId;

  /// The one algorithm (`alg`) this key may verify, or `null` for any that
  /// fits it.
  final String? algorithm;

  /// The JWK `use`: `sig` for signatures, `enc` for encryption (never
  /// used to verify), or `null`.
  final String? use;

  /// Whether this key may verify tokens signed with [jws]: the right key
  /// type, curve and size.
  bool fits(JwsAlgorithm jws);
}

/// An RSA public key, for RS* and PS* tokens.
///
/// Keys shorter than 2048 bits, or with an exponent of 1, never verify
/// anything.
///
/// ```dart
/// // The provider's public key, from its `n` and `e` JWK members.
/// final key = RsaVerificationKey(
///   BigInt.parse(modulusHex, radix: 16),
///   BigInt.from(65537),
/// );
/// final decoder = NimbusJwtDecoder.withPublicKey(key);
/// ```
final class RsaVerificationKey extends VerificationKey {
  /// The key with [modulus] and [exponent], optionally named [keyId] and
  /// restricted to [algorithm].
  RsaVerificationKey(
    this.modulus,
    this.exponent, {
    super.keyId,
    super.algorithm,
    super.use,
  });

  /// The modulus n.
  final BigInt modulus;

  /// The public exponent e, usually 65537.
  final BigInt exponent;

  @override
  bool fits(JwsAlgorithm jws) =>
      (jws._family == _Family.rsa || jws._family == _Family.rsaPss) &&
      modulus.bitLength >= 2048 &&
      exponent > BigInt.one;
}

/// An elliptic-curve public key on P-256, P-384 or P-521, for ES* tokens.
///
/// A point that is not on its curve never verifies anything, so a forged
/// key cannot be used for invalid-curve attacks.
final class EcVerificationKey extends VerificationKey {
  /// The point ([x], [y]) on [curve], optionally named [keyId] and
  /// restricted to [algorithm].
  EcVerificationKey(
    this.curve,
    this.x,
    this.y, {
    super.keyId,
    super.algorithm,
    super.use,
  });

  /// The curve: `P-256`, `P-384` or `P-521`.
  final String curve;

  /// The x coordinate of the point.
  final BigInt x;

  /// The y coordinate of the point.
  final BigInt y;

  /// Whether the point satisfies the curve's equation; `false` for an
  /// unknown curve.
  bool get isOnCurve {
    final parameters = curveParameters(curve);
    if (parameters == null) {
      return false;
    }
    final (:p, :a, :b, fieldBytes: _) = parameters;
    if (x.isNegative || y.isNegative || x >= p || y >= p) {
      return false;
    }
    return (y * y - (x * x * x + a * x + b)) % p == BigInt.zero;
  }

  @override
  bool fits(JwsAlgorithm jws) =>
      jws._family == _Family.ec && jws.curve == curve && isOnCurve;
}

/// A secret shared with the token issuer, for HS* tokens.
///
/// It verifies an algorithm only when it has at least as many bits as the
/// algorithm's hash: 256 for HS256, 512 for HS512.
final class SecretVerificationKey extends VerificationKey {
  /// The secret, copied from [bytes].
  SecretVerificationKey(List<int> bytes, {super.keyId, super.algorithm})
    : bytes = Uint8List.fromList(bytes);

  /// The secret bytes.
  final Uint8List bytes;

  @override
  bool fits(JwsAlgorithm jws) =>
      jws._family == _Family.hmac && bytes.length * 8 >= jws._bits;
}

/// A token split into its parts and decoded, before its signature is
/// checked; nothing in it can be trusted yet.
final class ParsedJws {
  ParsedJws._(this.header, this.claims, this.signingInput, this.signature);

  /// The token's header.
  final Map<String, Object?> header;

  /// The token's payload: the claims, a JSON object.
  final Map<String, Object?> claims;

  /// The bytes the signature covers: `base64url(header).base64url(payload)`
  /// as sent.
  final Uint8List signingInput;

  /// The decoded signature.
  final Uint8List signature;

  /// The `alg` of the header.
  String? get algorithmName => header['alg'] as String?;

  /// The `kid` of the header, or `null`.
  String? get keyId => header['kid'] as String?;
}

/// A token was refused while it was parsed, before any signature check:
/// too long, not three base64url parts, not JSON, or a forbidden header.
///
/// The decoder turns it into a `BadJwtException` (a 401).
class JoseException implements Exception {
  /// A refusal for [message].
  JoseException(this.message);

  /// What was wrong with the token.
  final String message;

  @override
  String toString() => message;
}

/// The longest token accepted, in characters: 64 KiB, so an oversized
/// token costs no decoding work.
const int maxTokenLength = 64 * 1024;

/// Splits and decodes [token] (`header.payload.signature`) without
/// checking the signature.
///
/// Throws a [JoseException] for a token over [maxTokenLength], an
/// encrypted (five-part) or otherwise malformed token, base64url that is
/// not strict, a header or payload that is not a JSON object, a `crit`
/// header, a nested JWT (`cty: JWT`), a missing `alg`, or a `kid` that is
/// not a string.
ParsedJws parseJws(String token) {
  if (token.length > maxTokenLength) {
    throw JoseException('The token is too long');
  }
  final parts = token.split('.');
  if (parts.length == 5) {
    throw JoseException('Encrypted JWTs (JWE) are not supported');
  }
  if (parts.length != 3) {
    throw JoseException('Invalid JWT serialization: Missing dot delimiter(s)');
  }
  final headerBytes = _base64Url(parts[0], 'header');
  final payloadBytes = _base64Url(parts[1], 'payload');
  final signature = _base64Url(parts[2], 'signature');
  final header = _jsonObject(headerBytes, 'header');
  final claims = _jsonObject(payloadBytes, 'payload');
  if (header.containsKey('crit')) {
    throw JoseException('Unsupported critical header parameters');
  }
  final cty = header['cty'];
  if (cty is String && cty.toUpperCase() == 'JWT') {
    throw JoseException('Nested JWTs are not supported');
  }
  if (header['alg'] is! String) {
    throw JoseException('The JWS header has no algorithm');
  }
  if (header.containsKey('kid') && header['kid'] is! String) {
    throw JoseException('The JWS header kid is not a string');
  }
  return ParsedJws._(
    header,
    claims,
    Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}')),
    signature,
  );
}

final _base64UrlAlphabet = RegExp(r'^[A-Za-z0-9_-]*$');

Uint8List _base64Url(String text, String what) {
  if (!_base64UrlAlphabet.hasMatch(text) || text.length % 4 == 1) {
    throw JoseException('Invalid base64url in the JWT $what');
  }
  try {
    return base64Url.decode(base64Url.normalize(text));
  } on FormatException {
    throw JoseException('Invalid base64url in the JWT $what');
  }
}

Map<String, Object?> _jsonObject(Uint8List bytes, String what) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw JoseException('The JWT $what is not valid JSON');
  }
  if (json is! Map<String, Object?>) {
    throw JoseException('The JWT $what is not a JSON object');
  }
  return json;
}

/// Whether [key] verifies the signature of [jws] made with [algorithm].
///
/// `false`, never an error, for a key that does not fit the algorithm or
/// is restricted to another one, a key not meant for signatures, a
/// signature of the wrong length, or input the primitives cannot read.
/// HMAC signatures are compared in constant time.
bool verifySignature(
  ParsedJws jws,
  JwsAlgorithm algorithm,
  VerificationKey key,
) {
  if (!key.fits(algorithm) ||
      (key.algorithm != null && key.algorithm != algorithm.name) ||
      (key.use != null && key.use != 'sig')) {
    return false;
  }
  final input = jws.signingInput;
  final signature = jws.signature;
  try {
    switch ((algorithm._family, key)) {
      case (_Family.hmac, final SecretVerificationKey secret):
        return constantTimeEquals(
          hmacSha(algorithm._bits, secret.bytes, input),
          signature,
        );
      case (_Family.rsa, final RsaVerificationKey rsa):
        if (signature.length != (rsa.modulus.bitLength + 7) ~/ 8) {
          return false;
        }
        return verifyRsaPkcs1(
          algorithm._bits,
          rsa.modulus,
          rsa.exponent,
          input,
          signature,
        );
      case (_Family.rsaPss, final RsaVerificationKey rsa):
        if (signature.length != (rsa.modulus.bitLength + 7) ~/ 8) {
          return false;
        }
        return verifyRsaPss(
          algorithm._bits,
          rsa.modulus,
          rsa.exponent,
          input,
          signature,
        );
      case (_Family.ec, final EcVerificationKey ec):
        final size = curveParameters(ec.curve)!.fieldBytes;
        // JWS ECDSA signatures are R || S, each exactly the field size.
        if (signature.length != 2 * size) {
          return false;
        }
        return verifyEcdsa(
          algorithm._bits,
          ec.curve,
          ec.x,
          ec.y,
          input,
          _unsigned(signature.sublist(0, size)),
          _unsigned(signature.sublist(size)),
        );
      default:
        return false;
    }
  } on Object {
    return false; // malformed input to the primitives: not verified
  }
}

BigInt _unsigned(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

/// The unsigned big-endian integer encoded in base64url [text], as in the
/// JWK members `n`, `e`, `x` and `y`.
///
/// Throws a [JoseException] for text that is not strict base64url.
BigInt base64UrlToBigInt(String text) =>
    _unsigned(_base64Url(text, 'key parameter'));

/// The bytes encoded in base64url [text], as in the JWK member `k`.
///
/// Throws a [JoseException] for text that is not strict base64url.
Uint8List base64UrlToBytes(String text) => _base64Url(text, 'key parameter');

/// Whether the compact JWS [token] is signed by [key] with the algorithm
/// named in its header; the payload may be anything, not only claims.
///
/// For test vectors and tools: it checks no claims, so never use it to
/// accept a token.
bool verifyCompactJws(String token, VerificationKey key) {
  final parts = token.split('.');
  if (parts.length != 3 || token.length > maxTokenLength) {
    return false;
  }
  try {
    final header = _jsonObject(_base64Url(parts[0], 'header'), 'header');
    final algorithm = JwsAlgorithm.from('${header['alg']}');
    if (algorithm == null || header.containsKey('crit')) {
      return false;
    }
    final jws = ParsedJws._(
      header,
      const {},
      Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}')),
      _base64Url(parts[2], 'signature'),
    );
    return verifySignature(jws, algorithm, key);
  } on JoseException {
    return false;
  }
}
