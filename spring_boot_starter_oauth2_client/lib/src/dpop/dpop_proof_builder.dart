import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_boot_starter_oauth2_client/src/core/sha256.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_key.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_proof_claims.dart';

// The private members a JWK may have (RFC 7518 §6.2.2, §6.3.2, §6.4.1):
// none of them may reach a proof's header.
const _privateMembers = {'d', 'p', 'q', 'dp', 'dq', 'qi', 'oth', 'k'};

/// Writes DPoP proofs (RFC 9449 §4): the short signed JWTs that prove a
/// request comes from the holder of the [key].
///
/// A proof names one request (its method and URL), the time it was made,
/// a one-time id and, on API calls, the hash of the access token it goes
/// with; the server checks all of it and that the signature matches the
/// public key in the proof's header. Each request needs a new proof. The
/// token response clients, the user services and the Feign interceptor
/// of this starter build them; build one yourself for a call they do not
/// make (an `HttpTransport` request of your own, a WebSocket handshake).
///
/// ```dart
/// // A call with a DPoP token: Authorization and a proof for it.
/// final proof = await DPoPProofBuilder(key).build(
///   method: 'GET',
///   url: Uri.parse('https://api.example.com/orders?page=2'),
///   accessToken: token.tokenValue,
/// );
/// headers
///   ..set('Authorization', 'DPoP ${token.tokenValue}')
///   ..set('DPoP', proof);
/// ```
///
/// A proof is not a secret, but it is a credential for one request for a
/// short time: it is never logged.
///
/// Spring (Java): no such type; Spring Security has no DPoP on the
/// client's side yet (spring-security#18228). In Java code Nimbus'
/// `DefaultDPoPProofFactory` does this.
final class DPoPProofBuilder {
  /// A builder signing with [key]; [clock] gives the `iat` (the current
  /// time by default).
  DPoPProofBuilder(this.key, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The key that signs the proofs.
  final DPoPKey key;

  final DateTime Function() _clock;
  static final _random = Random.secure();

  /// A proof for a [method] request to [url]: header `{"typ": "dpop+jwt",
  /// "alg": ..., "jwk": ...}`, claims `jti` (24 random bytes), `htm`,
  /// `htu` ([url] without query and fragment), `iat`, `ath` (the base64url
  /// SHA-256 of [accessToken], when given) and [nonce] (when the server
  /// asked for one); `base64url(header).base64url(claims).base64url(
  /// signature)`.
  ///
  /// A `ws` or `wss` [url] (a WebSocket handshake) goes into `htu` as
  /// `http` or `https`: `htu` is the HTTP URI of the request (RFC 9449
  /// §4.2), and a handshake is an HTTP `GET` of that URI (RFC 6455 §4.1),
  /// which the server sees as `http(s)`.
  ///
  /// A [LoadableDPoPKey] is loaded first (made on its first use).
  ///
  /// Throws a [StateError] when the key's public JWK holds a private
  /// member or its signature has the wrong size, an [ArgumentError] for an
  /// empty [method] or a [url] that is not absolute `http(s)` or `ws(s)`.
  Future<String> build({
    required String method,
    required Uri url,
    String? accessToken,
    String? nonce,
  }) async {
    final target = switch (url.scheme.toLowerCase()) {
      'ws' => url.replace(scheme: 'http'),
      'wss' => url.replace(scheme: 'https'),
      _ => url,
    };
    final key = this.key;
    if (key is LoadableDPoPKey) {
      await key.load();
    }
    final jwk = key.publicJwk;
    if (jwk.keys.any(_privateMembers.contains)) {
      throw StateError('The public JWK of the DPoP key has a private member');
    }
    final claims = DPoPProofClaims(
      jti: _jti(),
      htm: method,
      htu: target,
      iat: _clock(),
      ath: accessToken == null ? null : sha256Base64Url(accessToken),
      nonce: nonce,
    );
    final header = {'typ': 'dpop+jwt', 'alg': key.algorithm, 'jwk': jwk};
    final input = '${_json(header)}.${_json(claims.toJson())}';
    final signature = await key.sign(Uint8List.fromList(ascii.encode(input)));
    final expected = switch (key.algorithm) {
      'ES256' => 64,
      'ES384' => 96,
      'ES512' => 132,
      _ => null,
    };
    if (expected != null && signature.length != expected) {
      throw StateError(
        'The DPoP key returned a ${signature.length}-byte signature; '
        '${key.algorithm} needs the raw R || S of $expected bytes',
      );
    }
    return '$input.${_b64(signature)}';
  }

  static String _jti() =>
      _b64(List<int>.generate(24, (_) => _random.nextInt(256)));

  static String _json(Map<String, Object?> value) =>
      _b64(utf8.encode(jsonEncode(value)));

  static String _b64(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  @override
  String toString() => 'DPoPProofBuilder [alg=${key.algorithm}]';
}
