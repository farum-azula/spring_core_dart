import 'dart:convert';
import 'dart:math';

/// The parameter names of OAuth 2.0 requests and responses (RFC 6749,
/// RFC 7009, RFC 9207).
///
/// Use them when adding parameters to an authorization request or reading
/// a redirect, instead of writing the strings.
///
/// Spring (Java): `OAuth2ParameterNames`.
abstract final class OAuth2ParameterNames {
  /// `grant_type`.
  static const grantType = 'grant_type';

  /// `response_type`.
  static const responseType = 'response_type';

  /// `client_id`.
  static const clientId = 'client_id';

  /// `client_secret`.
  static const clientSecret = 'client_secret';

  /// `redirect_uri`.
  static const redirectUri = 'redirect_uri';

  /// `scope`.
  static const scope = 'scope';

  /// `state`.
  static const state = 'state';

  /// `code`.
  static const code = 'code';

  /// `access_token`.
  static const accessToken = 'access_token';

  /// `token_type`.
  static const tokenType = 'token_type';

  /// `expires_in`.
  static const expiresIn = 'expires_in';

  /// `refresh_token`.
  static const refreshToken = 'refresh_token';

  /// `error`.
  static const error = 'error';

  /// `error_description`.
  static const errorDescription = 'error_description';

  /// `error_uri`.
  static const errorUri = 'error_uri';

  /// `token` (RFC 7009 revocation).
  static const token = 'token';

  /// `token_type_hint` (RFC 7009 revocation).
  static const tokenTypeHint = 'token_type_hint';

  /// `iss` (RFC 9207: the issuer that sent the authorization response).
  static const issuer = 'iss';

  /// `response_mode`: how the authorization response comes back
  /// (`query`, `form_post`). Not in Spring's `OAuth2ParameterNames`.
  static const responseMode = 'response_mode';

  /// `registration_id`, the attribute of an authorization request that
  /// names its registration.
  static const registrationId = 'registration_id';
}

/// The parameter names of PKCE (RFC 7636).
///
/// Spring (Java): `PkceParameterNames`.
abstract final class PkceParameterNames {
  /// `code_challenge`.
  static const codeChallenge = 'code_challenge';

  /// `code_challenge_method`.
  static const codeChallengeMethod = 'code_challenge_method';

  /// `code_verifier`.
  static const codeVerifier = 'code_verifier';
}

/// The parameter names OpenID Connect adds.
///
/// Spring (Java): `OidcParameterNames`.
abstract final class OidcParameterNames {
  /// `id_token`.
  static const idToken = 'id_token';

  /// `nonce`.
  static const nonce = 'nonce';

  /// `id_token_hint` (RP-initiated logout).
  static const idTokenHint = 'id_token_hint';

  /// `post_logout_redirect_uri` (RP-initiated logout).
  static const postLogoutRedirectUri = 'post_logout_redirect_uri';
}

final Random _random = Random.secure();

/// [length] random bytes of `Random.secure()` in base64url without
/// padding: the `state`, the `nonce` and the PKCE code verifier.
///
/// At least 32 bytes (256 bits) are asked for, so the values cannot be
/// guessed.
///
/// ```dart
/// final state = generateSecureKey(); // 43 characters
/// ```
String generateSecureKey([int length = 32]) {
  if (length < 32) {
    throw ArgumentError.value(length, 'length', 'at least 32 bytes');
  }
  final bytes = [for (var i = 0; i < length; i++) _random.nextInt(256)];
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// [value] encoded as in an HTML form (`application/x-www-form-urlencoded`,
/// UTF-8): letters, digits and `.-*_` stay, a space becomes `+`, the rest
/// `%XX`. The same as Java's `URLEncoder.encode(value, UTF_8)`, which
/// Spring uses for the client id and secret of HTTP Basic (RFC 6749
/// §2.3.1).
String formUrlEncode(String value) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final unreserved =
        (byte >= 0x30 && byte <= 0x39) || // 0-9
        (byte >= 0x41 && byte <= 0x5a) || // A-Z
        (byte >= 0x61 && byte <= 0x7a) || // a-z
        byte == 0x2e || // .
        byte == 0x2d || // -
        byte == 0x2a || // *
        byte == 0x5f; // _
    if (unreserved) {
      buffer.writeCharCode(byte);
    } else if (byte == 0x20) {
      buffer.write('+');
    } else {
      buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buffer.toString();
}

/// [parameters] as a form body: `name=value&...`, each encoded with
/// [formUrlEncode].
String formUrlEncodeAll(Map<String, String> parameters) => [
  for (final MapEntry(:key, :value) in parameters.entries)
    '${formUrlEncode(key)}=${formUrlEncode(value)}',
].join('&');
