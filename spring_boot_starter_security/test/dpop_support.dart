// A DPoP client for the tests: a key pair and the proofs it signs (RFC
// 9449 §4.2), with every part replaceable to build the attacks. Signing
// is test-only code (pointycastle, through the test keys); the starter
// only verifies.
import 'dart:convert';
import 'dart:math';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import 'app/jwt/keys.dart';

final _random = Random.secure();

/// A fresh random `jti`.
String randomJti() => b64(List.generate(16, (_) => _random.nextInt(256)));

/// The holder of a DPoP key: signs proofs with it.
final class ProofSigner {
  /// A signer with a new P-256 key (ES256).
  ProofSigner.ec({String crv = 'P-256'})
    : _ec = EcTestKey.generate(crv: crv),
      _rsa = null;

  /// A signer with [key] (RS256 and PS256).
  ProofSigner.rsa(RsaTestKey key) : _ec = null, _rsa = key;

  final EcTestKey? _ec;
  final RsaTestKey? _rsa;

  /// The public key, as the proof's `jwk` header carries it.
  Map<String, Object?> get publicJwk => _ec?.jwk ?? _rsa!.jwk;

  /// A JWK `d` member made from the private key (only its presence in a
  /// proof matters: the server must refuse it).
  String get privateD => b64(
    utf8.encode('${_ec?.privateKey.d ?? _rsa!.privateKey.privateExponent}'),
  );

  /// The RFC 7638 thumbprint of the key: the `cnf.jkt` of tokens bound to
  /// it.
  String get thumbprint => JwkThumbprint.of(publicJwk);

  /// The default algorithm of the key.
  String get alg => _ec == null
      ? 'RS256'
      : switch (_ec.crv) {
          'P-256' => 'ES256',
          'P-384' => 'ES384',
          _ => 'ES512',
        };

  /// A proof for a [method] request to [url]; [accessToken] sets `ath`.
  ///
  /// [header] and [claims] entries replace the defaults (a `null` value
  /// removes the member); [iat] is in seconds; [signWith] signs with
  /// another signer's key (whatever `jwk` says).
  String proof({
    String method = 'GET',
    String url = 'http://localhost/api/me',
    String? accessToken,
    int? iat,
    String? jti,
    String? alg,
    Map<String, Object?> header = const {},
    Map<String, Object?> claims = const {},
    ProofSigner? signWith,
  }) {
    final algorithm = alg ?? this.alg;
    final h = _withoutNulls({
      'typ': 'dpop+jwt',
      'alg': algorithm,
      'jwk': publicJwk,
      ...header,
    });
    final c = _withoutNulls({
      'jti': jti ?? randomJti(),
      'htm': method,
      'htu': url,
      'iat': iat ?? TokenFactory.now(),
      if (accessToken != null) 'ath': sha256Base64Url(accessToken),
      ...claims,
    });
    final input = '${b64Json(h)}.${b64Json(c)}';
    return '$input.${b64((signWith ?? this)._sign(algorithm, input))}';
  }

  List<int> _sign(String alg, String input) {
    final bytes = ascii.encode(input);
    if (alg == 'none') {
      return const [];
    }
    if (alg.startsWith('HS')) {
      return testKeys.signature(alg, bytes);
    }
    return _ec?.sign(alg, bytes) ?? _rsa!.sign(alg, bytes);
  }

  static Map<String, Object?> _withoutNulls(Map<String, Object?> map) => {
    for (final MapEntry(:key, :value) in map.entries) key: ?value,
  };
}

/// An access token of the test issuer bound to [signer]'s key.
String boundToken(
  ProofSigner signer, {
  Map<String, Object?> claims = const {},
}) => testKeys.token(
  claims: {
    'cnf': {'jkt': signer.thumbprint},
    ...claims,
  },
);

/// The headers of a DPoP request with [token] and [proof].
Map<String, String> dPoPHeaders(String token, String proof) => {
  'authorization': 'DPoP $token',
  'dpop': proof,
};
