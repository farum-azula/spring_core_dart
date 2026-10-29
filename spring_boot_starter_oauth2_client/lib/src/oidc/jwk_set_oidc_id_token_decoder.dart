import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_oauth2_client/src/core/crypto_primitives.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/oauth2_error.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token_decoder.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token_validator.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// An [OidcIdTokenDecoder] that verifies the ID token's signature with the
/// provider's public keys (its JWK Set), then checks its claims: for ID
/// tokens that did not come straight from the token endpoint.
///
/// An app usually gets its ID token from the token endpoint over TLS, and
/// [TokenEndpointOidcIdTokenDecoder] may trust it without a signature
/// check. A token handed over by someone else is different: Sign in with
/// Apple's sheet gives the app an identity token from the operating
/// system, not from a TLS connection the app opened. This decoder makes
/// such a token trusted the way a server does: the signature must verify
/// with a key of the registration's `jwk-set-uri` (fetched over HTTPS,
/// cached, fetched once more for an unknown `kid`, at most once a
/// minute), with an algorithm of [algorithms] (RS256 by default; ES256
/// can be added). `alg: none`, HS*, keys sent inside the token (`jwk`,
/// `jku`, `x5u`, `x5c`), `crit` headers, RSA keys under 2 048 bits and EC
/// points off their curve are refused. Then [OidcIdTokenValidator]
/// checks the issuer, the audience, `azp`, the expiry and the issue time.
/// The `nonce` is the caller's to check
/// ([OidcIdTokenValidator.validateNonce]).
///
/// `spring_boot_starter_flutter_security` uses it for Sign in with
/// Apple's identity token. Servers keep the security starter's
/// `OidcIdTokenDecoderFactory`, which does the same with the full JOSE
/// code of the resource server.
///
/// ```dart
/// final decoder = JwkSetOidcIdTokenDecoder(transport);
/// final idToken = await decoder.decode(appleRegistration, identityToken);
/// ```
///
/// Spring (Java): `OidcIdTokenDecoderFactory` (a `NimbusJwtDecoder` on
/// the registration's JWK Set URI per registration), of which this is
/// the part an app needs.
final class JwkSetOidcIdTokenDecoder implements OidcIdTokenDecoder {
  /// A decoder fetching the keys through [transport], accepting
  /// [algorithms] (`RS256` and `ES256` are known); [clockSkew] and
  /// [clock] go to the claim checks.
  ///
  /// Throws an [ArgumentError] for an empty or unknown algorithm.
  JwkSetOidcIdTokenDecoder(
    this.transport, {
    Set<String> algorithms = const {'RS256'},
    this.clockSkew = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : algorithms = Set.unmodifiable(algorithms),
       _clock = clock ?? DateTime.now {
    if (algorithms.isEmpty ||
        algorithms.any((a) => a != 'RS256' && a != 'ES256')) {
      throw ArgumentError.value(
        algorithms,
        'algorithms',
        'must be RS256 and/or ES256',
      );
    }
  }

  /// The transport of the JWK Set requests.
  final HttpTransport transport;

  /// The signature algorithms accepted.
  final Set<String> algorithms;

  /// The tolerance of the time checks.
  final Duration clockSkew;

  final DateTime Function() _clock;
  final Map<String, _KeySet> _keys = {};

  static const int _maxJwkSetBytes = 512 * 1024;
  static const _refetchInterval = Duration(minutes: 1);
  static const Set<String> _embeddedKeyHeaders = {
    'jwk',
    'jku',
    'x5u',
    'x5c',
    'crit',
  };

  @override
  Future<OidcIdToken> decode(
    ClientRegistration registration,
    String tokenValue,
  ) async {
    Never fail(String description) => throw OAuth2AuthenticationException(
      OAuth2Error(OAuth2ErrorCodes.invalidIdToken, description),
    );
    final jwkSetUri = registration.providerDetails.jwkSetUri;
    if (jwkSetUri == null || jwkSetUri.isEmpty) {
      fail(
        'Failed to find a Signature Verifier for Client Registration: '
        "'${registration.registrationId}'. Check to ensure you have "
        'configured the JwkSet URI.',
      );
    }
    final OidcIdToken idToken;
    try {
      idToken = OidcIdToken.parse(tokenValue);
    } on FormatException catch (e) {
      fail(
        'An error occurred while attempting to decode the Jwt: ${e.message}',
      );
    }
    final parts = tokenValue.split('.');
    final header = _json(parts[0]) ?? fail('Malformed JWS header');
    final alg = header['alg'];
    if (alg is! String || !algorithms.contains(alg)) {
      fail('The JWS algorithm is not accepted');
    }
    if (header.keys.any(_embeddedKeyHeaders.contains)) {
      fail('Keys or critical extensions inside the token are not accepted');
    }
    final kid = header['kid'];
    if (kid != null && kid is! String) {
      fail('Malformed kid');
    }
    final Uint8List signature;
    try {
      signature = base64Url.decode(base64Url.normalize(parts[2]));
    } on FormatException {
      fail('Malformed JWS signature');
    }
    final input = Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}'));
    var candidates = await _candidates(jwkSetUri, alg, kid as String?, false);
    if (candidates.isEmpty && kid != null) {
      // A key not seen yet: the provider may have rotated its keys.
      candidates = await _candidates(jwkSetUri, alg, kid, true);
    }
    if (candidates.isEmpty) {
      fail('No key of the JWK Set matches the token');
    }
    if (!candidates.any((key) => key.verify(alg, input, signature))) {
      fail('Signed JWT rejected: Invalid signature');
    }
    final result = OidcIdTokenValidator(
      registration,
      clockSkew: clockSkew,
      clock: _clock,
    ).validate(idToken);
    if (result.hasErrors) {
      throw OAuth2AuthenticationException(result.errors.first);
    }
    return idToken;
  }

  Future<List<_Key>> _candidates(
    String jwkSetUri,
    String alg,
    String? kid,
    bool refetch,
  ) async {
    final now = _clock();
    var set = _keys[jwkSetUri];
    if (set == null ||
        (refetch && now.difference(set.fetchedAt) >= _refetchInterval)) {
      set = _KeySet(await _fetch(jwkSetUri), now);
      _keys[jwkSetUri] = set;
    }
    return [
      for (final key in set.keys)
        if (key.accepts(alg) && (kid == null || key.kid == kid)) key,
    ];
  }

  Future<List<_Key>> _fetch(String jwkSetUri) async {
    Never fail(String description) => throw OAuth2AuthenticationException(
      OAuth2Error(OAuth2ErrorCodes.invalidIdToken, description),
    );
    final HttpResponse response;
    try {
      response = await transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse(jwkSetUri),
          headers: HttpHeaders({
            HttpHeaders.acceptHeader:
                'application/json, application/jwk-set+json',
          }),
          followRedirects: false,
        ),
      );
    } on HttpTransportException catch (e) {
      fail('The JWK Set could not be fetched: ${e.message}');
    }
    if (response.statusCode != 200 ||
        response.bodyBytes.length > _maxJwkSetBytes) {
      fail('The JWK Set could not be fetched (${response.statusCode})');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      fail('The JWK Set is not JSON');
    }
    if (json is! Map<String, Object?> || json['keys'] is! List<Object?>) {
      fail('The JWK Set has no keys');
    }
    return [
      for (final jwk in json['keys']! as List<Object?>)
        if (jwk is Map<String, Object?>) ?_Key.of(jwk),
    ];
  }

  static Map<String, Object?>? _json(String part) {
    try {
      final value = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(part))),
      );
      return value is Map<String, Object?> ? value : null;
    } on FormatException {
      return null;
    }
  }
}

final class _KeySet {
  _KeySet(this.keys, this.fetchedAt);

  final List<_Key> keys;
  final DateTime fetchedAt;
}

// A public signing key of the JWK Set: RSA (2 048 bits or more) or EC on
// P-256. Anything else is left out.
final class _Key {
  _Key._(this.kid, this.alg, {this.n, this.e, this.x, this.y});

  static _Key? of(Map<String, Object?> jwk) {
    final kid = jwk['kid'];
    final alg = jwk['alg'];
    final use = jwk['use'];
    if ((kid != null && kid is! String) ||
        (alg != null && alg is! String) ||
        (use != null && use != 'sig')) {
      return null;
    }
    BigInt? number(String name) {
      final value = jwk[name];
      if (value is! String || value.isEmpty) {
        return null;
      }
      try {
        return unsignedBigInt(base64Url.decode(base64Url.normalize(value)));
      } on FormatException {
        return null;
      }
    }

    switch (jwk['kty']) {
      case 'RSA':
        final n = number('n');
        final e = number('e');
        if (n == null || e == null || n.bitLength < 2048) {
          return null;
        }
        return _Key._(kid as String?, alg as String?, n: n, e: e);
      case 'EC':
        final x = number('x');
        final y = number('y');
        if (jwk['crv'] != 'P-256' ||
            x == null ||
            y == null ||
            !p256IsOnCurve(x, y)) {
          return null;
        }
        return _Key._(kid as String?, alg as String?, x: x, y: y);
      default:
        return null;
    }
  }

  final String? kid;
  final String? alg;
  final BigInt? n;
  final BigInt? e;
  final BigInt? x;
  final BigInt? y;

  bool accepts(String algorithm) =>
      (alg == null || alg == algorithm) &&
      (algorithm == 'RS256' ? n != null : x != null);

  bool verify(String algorithm, Uint8List input, Uint8List signature) {
    if (algorithm == 'RS256') {
      return rsaPkcs1Sha256Verify(n!, e!, input, signature);
    }
    if (signature.length != 64) {
      return false; // JOSE wants raw R || S, never DER
    }
    return p256Verify(
      x!,
      y!,
      input,
      unsignedBigInt(signature.sublist(0, 32)),
      unsignedBigInt(signature.sublist(32)),
    );
  }
}
