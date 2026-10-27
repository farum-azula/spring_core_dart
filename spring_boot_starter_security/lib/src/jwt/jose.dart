import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_security/src/jwt/signature_primitives.dart';
import 'package:spring_security_core/spring_security_core.dart'
    show constantTimeEquals;

/// A JWS signature algorithm, like Spring's `SignatureAlgorithm` and
/// `MacAlgorithm`. `none` does not exist here: an unsigned token is never
/// accepted.
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

  /// The `alg` header value.
  final String name;

  final _Family _family;
  final int _bits;

  /// The algorithm named [name] (`RS256`), or `null`.
  static JwsAlgorithm? from(String name) {
    for (final algorithm in values) {
      if (algorithm.name == name) {
        return algorithm;
      }
    }
    return null;
  }

  /// Whether it uses a shared secret (HS*).
  bool get isMac => _family == _Family.hmac;

  /// The JWK `kty` of its keys.
  String get keyType => switch (_family) {
    _Family.rsa || _Family.rsaPss => 'RSA',
    _Family.ec => 'EC',
    _Family.hmac => 'oct',
  };

  /// The EC curve (`P-256`) of an ES algorithm.
  String? get curve => switch (this) {
    es256 => 'P-256',
    es384 => 'P-384',
    es512 => 'P-521',
    _ => null,
  };
}

enum _Family { rsa, rsaPss, ec, hmac }

/// A key that verifies signatures: an RSA or EC public key, or an HMAC
/// secret.
sealed class VerificationKey {
  const VerificationKey({this.keyId, this.algorithm, this.use});

  /// `kid`.
  final String? keyId;

  /// The `alg` the key is restricted to, if any.
  final String? algorithm;

  /// `use` (`sig` or `enc`).
  final String? use;

  /// Whether this key may verify [jws] (type, curve, size, restrictions).
  bool fits(JwsAlgorithm jws);
}

/// An RSA public key (at least 2048 bits).
final class RsaVerificationKey extends VerificationKey {
  /// The key with [modulus] and [exponent].
  RsaVerificationKey(
    this.modulus,
    this.exponent, {
    super.keyId,
    super.algorithm,
    super.use,
  });

  /// n.
  final BigInt modulus;

  /// e.
  final BigInt exponent;

  @override
  bool fits(JwsAlgorithm jws) =>
      (jws._family == _Family.rsa || jws._family == _Family.rsaPss) &&
      modulus.bitLength >= 2048 &&
      exponent > BigInt.one;
}

/// An EC public key on P-256, P-384 or P-521 (checked to be on its curve).
final class EcVerificationKey extends VerificationKey {
  /// The point ([x], [y]) on [curve].
  EcVerificationKey(
    this.curve,
    this.x,
    this.y, {
    super.keyId,
    super.algorithm,
    super.use,
  });

  /// `P-256`, `P-384` or `P-521`.
  final String curve;

  /// x.
  final BigInt x;

  /// y.
  final BigInt y;

  /// Whether the point satisfies the curve's equation.
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

/// An HMAC secret (at least as many bits as the hash: 256 for HS256).
final class SecretVerificationKey extends VerificationKey {
  /// The secret [bytes].
  SecretVerificationKey(List<int> bytes, {super.keyId, super.algorithm})
    : bytes = Uint8List.fromList(bytes);

  /// The secret.
  final Uint8List bytes;

  @override
  bool fits(JwsAlgorithm jws) =>
      jws._family == _Family.hmac && bytes.length * 8 >= jws._bits;
}

/// A parsed, not yet verified JWS in compact serialization.
final class ParsedJws {
  ParsedJws._(this.header, this.claims, this.signingInput, this.signature);

  /// The protected header.
  final Map<String, Object?> header;

  /// The payload, a JSON object (the claims).
  final Map<String, Object?> claims;

  /// `base64url(header).base64url(payload)`, what was signed.
  final Uint8List signingInput;

  /// The signature bytes.
  final Uint8List signature;

  /// `alg`.
  String? get algorithmName => header['alg'] as String?;

  /// `kid`.
  String? get keyId => header['kid'] as String?;
}

/// Why a token was refused.
class JoseException implements Exception {
  /// Refused for [message].
  JoseException(this.message);

  /// What was wrong.
  final String message;

  @override
  String toString() => message;
}

/// The longest token accepted (characters).
const int maxTokenLength = 64 * 1024;

/// Parses [token] (`header.payload.signature`): strict base64url, JSON
/// objects, no `crit`, no nested JWT. Throws [JoseException].
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

/// Whether [key] verifies [jws] signed with [algorithm]. `false` for a
/// key that does not fit the algorithm (never "try anyway").
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

/// The big-endian unsigned integer of base64url [text] (JWK `n`, `e`, `x`,
/// `y`).
BigInt base64UrlToBigInt(String text) =>
    _unsigned(_base64Url(text, 'key parameter'));

/// Bytes of base64url [text] (JWK `k`).
Uint8List base64UrlToBytes(String text) => _base64Url(text, 'key parameter');

/// Whether the compact JWS [token] (any payload, not only JWT claims) is
/// signed by [key] with its `alg`; for test vectors and tools.
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
