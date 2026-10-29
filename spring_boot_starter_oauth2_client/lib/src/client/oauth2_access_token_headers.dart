import 'package:spring_boot_starter_oauth2_client/src/core/tokens.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_key.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_nonces.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_proof_builder.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Writes the headers that carry an access token on one request:
/// `Authorization: Bearer <token>`, or for a DPoP-bound token
/// (`TokenType.dpop`) `Authorization: DPoP <token>` and a fresh `DPoP`
/// proof for that request, signed by [dPoPKey].
///
/// The Feign interceptor of the starter uses it for every call. Use it
/// for a request the framework does not make: a WebSocket handshake (the
/// proof's `htu` is then the `http(s)` form of the `ws(s)` URL), an
/// `HttpTransport` call of your own. Which kind a token is comes from the
/// token itself, so the same code works whether the provider bound the
/// token or not.
///
/// ```dart
/// // The chat's handshake as the logged-in user: the token from the
/// // manager (refreshed when needed), the headers for this handshake.
/// final client = await manager.authorize(request);
/// final headers = await OAuth2AccessTokenHeaders(dPoPKey: key).of(
///   client!.accessToken,
///   method: 'GET',
///   url: handshake.url,
/// );
/// headers.forEach(handshake.headers.set);
/// ```
///
/// Browsers cannot set headers on a WebSocket handshake; a page sends its
/// session cookie instead (the server keeps the tokens).
///
/// The headers hold the token and a proof: never log them.
///
/// Spring (Java): no such type; Spring Security's
/// `OAuth2ClientHttpRequestInterceptor` writes the `Bearer` header of a
/// `RestClient` call, and has no DPoP.
final class OAuth2AccessTokenHeaders {
  /// A writer signing the proofs of DPoP-bound tokens with [dPoPKey]
  /// (`null` when the application has none: a DPoP-bound token then
  /// fails); `clock` gives the proofs' time (the current time by
  /// default).
  OAuth2AccessTokenHeaders({this.dPoPKey, this._clock});

  /// The key of the DPoP proofs, or `null`.
  final DPoPKey? dPoPKey;

  final DateTime Function()? _clock;

  /// The headers for a [method] request to [url] with [token]:
  /// `Authorization`, and `DPoP` for a DPoP-bound token (with [nonce] in
  /// the proof when the server asked for one).
  ///
  /// Throws a [StateError] for a DPoP-bound token without a [dPoPKey].
  Future<Map<String, String>> of(
    OAuth2AccessToken token, {
    required String method,
    required Uri url,
    String? nonce,
  }) async {
    if (token.tokenType != TokenType.dpop) {
      return {HttpHeaders.authorizationHeader: 'Bearer ${token.tokenValue}'};
    }
    final key = dPoPKey;
    if (key == null) {
      throw StateError(
        'The access token is DPoP-bound and there is no DPoPKey to sign '
        'its proofs',
      );
    }
    return {
      HttpHeaders.authorizationHeader: 'DPoP ${token.tokenValue}',
      dPoPHeader: await DPoPProofBuilder(key, clock: _clock).build(
        method: method,
        url: url,
        accessToken: token.tokenValue,
        nonce: nonce,
      ),
    };
  }

  @override
  String toString() =>
      'OAuth2AccessTokenHeaders [dPoP=${dPoPKey?.algorithm ?? 'none'}]';
}
