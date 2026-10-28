import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_security/src/jwt/jose.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt_decoder.dart';

/// The [OidcIdTokenDecoder] of servers: it checks the ID token's
/// signature with the provider's public keys (its JWK Set), then its
/// claims.
///
/// The ID token says who logged in. A server trusts it only once the
/// signature proves the provider issued it, so a token forged or changed
/// on the way, signed with another key, or not signed at all (`alg:
/// none`) never logs anyone in. Then [OidcIdTokenValidator] checks the
/// issuer, the audience (this client), `azp`, the expiry and the issue
/// time. The keys come from the registration's `jwk-set-uri` (discovered
/// from its `issuer-uri`), cached, and fetched again when a token names a
/// key id not seen yet (the provider rotated its keys).
///
/// `oauth2Login()` uses it by default, and the starter declares it as the
/// `oidcIdTokenDecoder` bean when OAuth2 clients are configured, so the
/// ID tokens of refreshed authorized clients are checked the same way.
/// Declare your own `OidcIdTokenDecoder` bean to replace it.
///
/// ```dart
/// // Keycloak realms that sign with ES256 instead of RS256.
/// @Bean()
/// OidcIdTokenDecoder oidcIdTokenDecoder(HttpTransport transport) =>
///     OidcIdTokenDecoderFactory(
///       fetcher: transportJwkFetcher(transport),
///       jwsAlgorithmResolver: (registration) => JwsAlgorithm.es256,
///     );
/// ```
///
/// Spring (Java): `OidcIdTokenDecoderFactory`, the
/// `JwtDecoderFactory<ClientRegistration>` of `oauth2Login()`: RS256 by
/// default, an HS* algorithm uses the client secret as the key, and the
/// default validator is the timestamps plus `OidcIdTokenValidator`.
final class OidcIdTokenDecoderFactory implements OidcIdTokenDecoder {
  /// A decoder fetching the keys with [fetcher] ([defaultJwkFetcher] by
  /// default) and accepting the algorithm [jwsAlgorithmResolver] picks
  /// for each registration (RS256 by default).
  ///
  /// [validatorFactory] makes the claim checks of a registration
  /// ([OidcIdTokenValidator] by default, with [clockSkew] and [clock]).
  OidcIdTokenDecoderFactory({
    JwkFetcher? fetcher,
    JwsAlgorithm Function(ClientRegistration registration)?
    jwsAlgorithmResolver,
    OAuth2TokenValidator<OidcIdToken> Function(ClientRegistration)?
    validatorFactory,
    this.clockSkew = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _fetcher = fetcher ?? defaultJwkFetcher,
       _algorithm = jwsAlgorithmResolver ?? ((_) => JwsAlgorithm.rs256),
       _clock = clock,
       _validatorFactory =
           validatorFactory ??
           ((registration) => OidcIdTokenValidator(
             registration,
             clockSkew: clockSkew,
             clock: clock,
           ));

  /// The tolerance of the time checks, 60 seconds by default.
  final Duration clockSkew;

  final JwkFetcher _fetcher;
  final JwsAlgorithm Function(ClientRegistration) _algorithm;
  final DateTime Function()? _clock;
  final OAuth2TokenValidator<OidcIdToken> Function(ClientRegistration)
  _validatorFactory;
  final Map<String, (String, JwtDecoder)> _decoders = {};

  /// The error code of a registration without a way to check signatures:
  /// no `jwk-set-uri` for an RS*, PS* or ES* algorithm, no client secret
  /// for HS*.
  static const missingSignatureVerifierErrorCode = 'missing_signature_verifier';

  /// The [JwtDecoder] of [registration]'s ID tokens: the signature with
  /// its keys, `exp` and `nbf` with [clockSkew]. Made once per
  /// registration (again when its keys' address or algorithm changes).
  ///
  /// Throws an [OAuth2AuthenticationException]
  /// ([missingSignatureVerifierErrorCode]) when the registration has no
  /// JWK Set URI (or no client secret for an HS* algorithm).
  JwtDecoder createDecoder(ClientRegistration registration) {
    final algorithm = _algorithm(registration);
    final jwkSetUri = registration.providerDetails.jwkSetUri;
    final secret = registration.clientSecret;
    // The client secret is part of the key of the cache, never logged.
    final key = algorithm.isMac
        ? '${algorithm.name} ${secret.hashCode}'
        : '${algorithm.name} $jwkSetUri';
    final cached = _decoders[registration.registrationId];
    if (cached != null && cached.$1 == key) {
      return cached.$2;
    }
    final validator = JwtTimestampValidator(
      clockSkew: clockSkew,
      clock: _clock,
    );
    final JwtDecoder decoder;
    if (algorithm.isMac) {
      if (secret.isEmpty) {
        throw _missingVerifier(
          registration,
          'Check to ensure you have configured the client-secret.',
        );
      }
      try {
        decoder = NimbusJwtDecoder.withSecretKey(
          utf8.encode(secret),
          macAlgorithm: algorithm,
          validator: validator,
        );
      } on ArgumentError {
        throw _missingVerifier(
          registration,
          'The client-secret is too short for ${algorithm.name}.',
        );
      }
    } else {
      if (jwkSetUri == null || jwkSetUri.isEmpty) {
        throw _missingVerifier(
          registration,
          'Check to ensure you have configured the JwkSet URI.',
        );
      }
      decoder = NimbusJwtDecoder.withJwkSetUri(
        Uri.parse(jwkSetUri),
        jwsAlgorithms: {algorithm},
        fetcher: _fetcher,
        validator: validator,
      );
    }
    _decoders[registration.registrationId] = (key, decoder);
    return decoder;
  }

  @override
  Future<OidcIdToken> decode(
    ClientRegistration registration,
    String tokenValue,
  ) async {
    final decoder = createDecoder(registration);
    final OidcIdToken idToken;
    try {
      await decoder.decode(tokenValue);
      // Verified, so it parses; any failure still refuses the token.
      idToken = OidcIdToken.parse(tokenValue);
    } on Exception catch (e) {
      final message = e is JwtException ? e.message : '$e';
      throw OAuth2AuthenticationException(
        OAuth2Error(OAuth2ErrorCodes.invalidIdToken, message),
        message,
        e,
      );
    }
    final result = _validatorFactory(registration).validate(idToken);
    if (result.hasErrors) {
      throw OAuth2AuthenticationException(result.errors.first);
    }
    return idToken;
  }

  static OAuth2AuthenticationException _missingVerifier(
    ClientRegistration registration,
    String hint,
  ) {
    final error = OAuth2Error(
      missingSignatureVerifierErrorCode,
      'Failed to find a Signature Verifier for Client Registration: '
      "'${registration.registrationId}'. $hint",
    );
    return OAuth2AuthenticationException(error, error.toString());
  }
}
