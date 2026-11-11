/// What every OAuth 2.0 token has, whoever issued it and however it is
/// encoded: its value and, when known, when it was issued and when it
/// expires.
///
/// An access token, a refresh token, an OpenID Connect ID token and a
/// decoded JWT are all one: code that only needs to send a token, or to
/// know whether it is about to expire, takes this type and works with
/// any of them. [tokenValue] is a credential: whoever has it acts as the
/// user, so an implementation never shows it in `toString` and nothing
/// logs it.
///
/// ```dart
/// // True when the token must be refreshed before it is sent again.
/// bool expiresSoon(OAuth2Token token, {Duration within = Duration.zero}) {
///   final expiresAt = token.expiresAt;
///   return expiresAt != null &&
///       !DateTime.now().toUtc().add(within).isBefore(expiresAt);
/// }
/// ```
///
/// Implemented by `AbstractOAuth2Token` of
/// `spring_boot_starter_oauth2_client` (the access, refresh and ID tokens)
/// and by `Jwt` of `spring_boot_starter_security`.
///
/// Spring (Java): `org.springframework.security.oauth2.core.OAuth2Token`.
abstract interface class OAuth2Token {
  /// The token itself, as it was issued; a credential, never log it.
  String get tokenValue;

  /// When the token was issued (UTC), or `null` when unknown.
  DateTime? get issuedAt;

  /// When the token stops being accepted (UTC), or `null` when unknown.
  DateTime? get expiresAt;
}
