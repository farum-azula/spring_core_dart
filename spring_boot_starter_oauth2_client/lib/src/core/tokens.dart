/// What every OAuth 2.0 token has: its value and, when known, when it was
/// issued and when it expires.
///
/// The access, refresh and ID tokens extend it. The value is a
/// credential: whoever has it acts as the user. [toString] never shows
/// it, and nothing in this package logs it.
///
/// Spring (Java): `AbstractOAuth2Token`.
abstract class AbstractOAuth2Token {
  /// A token with [tokenValue], issued at [issuedAt] and expiring at
  /// [expiresAt] (both in UTC, when known).
  ///
  /// Throws an [ArgumentError] when [tokenValue] is empty or [expiresAt]
  /// is not after [issuedAt].
  AbstractOAuth2Token(this.tokenValue, {this.issuedAt, this.expiresAt})
    : _checked = _check(tokenValue, issuedAt, expiresAt);

  // The checks run on the parameters: a subclass (the ID token) may read
  // issuedAt and expiresAt from its claims instead.
  // ignore: unused_field
  final bool _checked;

  static bool _check(
    String tokenValue,
    DateTime? issuedAt,
    DateTime? expiresAt,
  ) {
    if (tokenValue.isEmpty) {
      throw ArgumentError('tokenValue cannot be empty');
    }
    if (issuedAt != null && expiresAt != null && !expiresAt.isAfter(issuedAt)) {
      throw ArgumentError('expiresAt must be after issuedAt');
    }
    return true;
  }

  /// The token itself, as the provider issued it; a credential, never log
  /// it.
  final String tokenValue;

  /// When the token was issued (UTC), or `null` when unknown.
  final DateTime? issuedAt;

  /// When the token stops being accepted (UTC), or `null` when unknown.
  final DateTime? expiresAt;

  @override
  String toString() =>
      '$runtimeType [tokenValue=[PROTECTED], issuedAt=$issuedAt, '
      'expiresAt=$expiresAt]';
}

/// The kind of an access token: how it is sent.
///
/// A `Bearer` token (RFC 6750) works for whoever holds it, sent as
/// `Authorization: Bearer <token>`. A `DPoP` token (RFC 9449) is bound to
/// a key of the client, sent as `Authorization: DPoP <token>` with a
/// proof signed by that key; the resource server accepts both. The
/// client gets `DPoP` tokens for the registrations that use DPoP
/// (`ClientRegistration.dpop`), `Bearer` ones otherwise.
///
/// Spring (Java): `OAuth2AccessToken.TokenType`.
// A class, as Spring's, not an enum: the token response may name types
// added later, and the public API stays the same when they are.
// ignore: use_enums
final class TokenType {
  const TokenType._(this.value);

  /// `Bearer`, the type of almost every access token.
  static const bearer = TokenType._('Bearer');

  /// `DPoP`, a token bound to the client's key (RFC 9449): useless
  /// without a proof signed by that key.
  static const dpop = TokenType._('DPoP');

  /// The name as sent in the `Authorization` header and the token
  /// response.
  final String value;

  @override
  String toString() => value;
}

/// The token a client sends with each call to an API on the user's (or
/// its own) behalf: `Authorization: Bearer <token>`.
///
/// It comes from the provider's token endpoint after a login or a client
/// credentials request, lives a few minutes, and is renewed with the
/// refresh token. Applications rarely build one: the authorized client
/// manager hands out a fresh one, and the Feign interceptor adds it to
/// calls.
///
/// ```dart
/// // The token of the logged-in user, refreshed when it expires soon.
/// final client = await manager.authorize(
///   OAuth2AuthorizeRequest.withClientRegistrationId('keycloak')
///       .principal(login.authentication!)
///       .build(),
/// );
/// final token = client!.accessToken; // OAuth2AccessToken
/// headers.set('Authorization', 'Bearer ${token.tokenValue}');
/// ```
///
/// Spring (Java): `OAuth2AccessToken`.
class OAuth2AccessToken extends AbstractOAuth2Token {
  /// A [tokenType] token with [tokenValue], valid for [scopes].
  OAuth2AccessToken(
    this.tokenType,
    super.tokenValue, {
    super.issuedAt,
    super.expiresAt,
    Set<String> scopes = const {},
  }) : scopes = Set.unmodifiable(scopes);

  /// How the token is sent: [TokenType.bearer], or [TokenType.dpop] for
  /// a token bound to the client's `DPoPKey`.
  final TokenType tokenType;

  /// What the token allows, such as `openid` or `orders.read`; cannot be
  /// modified.
  final Set<String> scopes;
}

/// The long-lived token that gets new access tokens without asking the
/// user to log in again.
///
/// The provider returns it with the access token (when the client may
/// have one); the authorized client manager sends it to the token
/// endpoint when the access token is about to expire. Revoking it (on
/// logout) ends the login for good.
///
/// Spring (Java): `OAuth2RefreshToken`.
class OAuth2RefreshToken extends AbstractOAuth2Token {
  /// A refresh token with [tokenValue].
  OAuth2RefreshToken(super.tokenValue, {super.issuedAt, super.expiresAt});
}
