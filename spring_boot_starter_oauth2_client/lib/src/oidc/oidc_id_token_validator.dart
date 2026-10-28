import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/src/core/oauth2_error.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/sha256.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/token_validator.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/claims.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_security_core/spring_security_core.dart'
    show constantTimeEquals;

const _idTokenValidationUri =
    'https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation';

/// Checks that an ID token was issued by the registration's provider, for
/// this client, and is current (OpenID Connect Core §3.1.3.7).
///
/// Without these checks, a token the provider issued to another
/// application, an old one, or one from another provider could log a user
/// in. The checks:
///
/// - `iss`, `sub`, `aud`, `exp` and `iat` are present;
/// - `iss` equals the registration's issuer (when it has one);
/// - `aud` contains the client id;
/// - with several audiences, `azp` is present; when present, it is the
///   client id;
/// - `exp` has not passed and `iat` is not in the future, each with
///   [clockSkew] (60 seconds) of tolerance;
/// - with [nonce], the token's `nonce` is the SHA-256 hash of it (the
///   value the login sent), so a token cannot be replayed into another
///   login.
///
/// The login runs it on every ID token (the nonce separately, with
/// [validateNonce]); run it yourself when you decode ID tokens in your
/// own code.
///
/// ```dart
/// final result = OidcIdTokenValidator(registration).validate(idToken);
/// if (result.hasErrors) {
///   throw OAuth2AuthenticationException(result.errors.first);
/// }
/// ```
///
/// Spring (Java): `OidcIdTokenValidator`; the [nonce] check is in Spring's
/// `OidcAuthorizationCodeAuthenticationProvider`.
final class OidcIdTokenValidator implements OAuth2TokenValidator<OidcIdToken> {
  /// A validator for the ID tokens of [clientRegistration]; with [nonce]
  /// (the raw value of the authorization request) the nonce is checked
  /// too.
  OidcIdTokenValidator(
    this.clientRegistration, {
    this.nonce,
    this.clockSkew = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The registration whose tokens are checked.
  final ClientRegistration clientRegistration;

  /// The raw nonce of the authorization request, or `null` to skip the
  /// nonce check.
  final String? nonce;

  /// The tolerance of the time checks.
  final Duration clockSkew;

  final DateTime Function() _clock;

  @override
  OAuth2TokenValidatorResult validate(OidcIdToken token) {
    final invalid = <String, Object?>{};
    for (final name in const [
      IdTokenClaimNames.iss,
      IdTokenClaimNames.sub,
      IdTokenClaimNames.aud,
      IdTokenClaimNames.exp,
      IdTokenClaimNames.iat,
    ]) {
      if (token.claims[name] == null) {
        invalid[name] = null;
      }
    }
    if (token.expiresAt == null) {
      invalid[IdTokenClaimNames.exp] = token.claims[IdTokenClaimNames.exp];
    }
    if (token.issuedAt == null) {
      invalid[IdTokenClaimNames.iat] = token.claims[IdTokenClaimNames.iat];
    }
    if (invalid.isNotEmpty) {
      return OAuth2TokenValidatorResult.failure(_invalidIdToken(invalid));
    }
    final issuer = clientRegistration.providerDetails.issuerUri;
    if (issuer != null && issuer != token.issuer) {
      invalid[IdTokenClaimNames.iss] = token.issuer;
    }
    final clientId = clientRegistration.clientId;
    final audience = token.audience;
    if (!audience.contains(clientId)) {
      invalid[IdTokenClaimNames.aud] = audience;
    }
    final authorizedParty = token.authorizedParty;
    if (audience.length > 1 && authorizedParty == null) {
      invalid[IdTokenClaimNames.azp] = authorizedParty;
    }
    if (authorizedParty != null && authorizedParty != clientId) {
      invalid[IdTokenClaimNames.azp] = authorizedParty;
    }
    final now = _clock().toUtc();
    if (now.subtract(clockSkew).isAfter(token.expiresAt!)) {
      invalid[IdTokenClaimNames.exp] = token.expiresAt;
    }
    if (now.add(clockSkew).isBefore(token.issuedAt!)) {
      invalid[IdTokenClaimNames.iat] = token.issuedAt;
    }
    final errors = [
      if (invalid.isNotEmpty) _invalidIdToken(invalid),
      if (nonce case final raw?) ...validateNonce(token, raw).errors,
    ];
    return OAuth2TokenValidatorResult(errors);
  }

  /// Checks that the `nonce` of [token] is the SHA-256 hash of [nonce],
  /// the raw value the authorization request kept; fails with
  /// `invalid_nonce` otherwise (a missing nonce included).
  static OAuth2TokenValidatorResult validateNonce(
    OidcIdToken token,
    String nonce,
  ) {
    final claim = token.nonce;
    if (claim == null ||
        !constantTimeEquals(
          utf8.encode(claim),
          utf8.encode(sha256Base64Url(nonce)),
        )) {
      return OAuth2TokenValidatorResult.failure(
        const OAuth2Error(
          OAuth2ErrorCodes.invalidNonce,
          'The nonce of the ID token does not match the login',
          _idTokenValidationUri,
        ),
      );
    }
    return OAuth2TokenValidatorResult.success;
  }

  static OAuth2Error _invalidIdToken(Map<String, Object?> claims) =>
      OAuth2Error(
        OAuth2ErrorCodes.invalidIdToken,
        'The ID Token contains invalid claims: $claims',
        _idTokenValidationUri,
      );
}
