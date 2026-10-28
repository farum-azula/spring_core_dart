import 'package:spring_boot_starter_oauth2_client/src/core/oauth2_error.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/token_validator.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token_validator.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';

/// Turns the raw ID token of a token response into a checked
/// [OidcIdToken]: the hook where the signature is (or is not) verified.
///
/// The login calls it with the `id_token` the token endpoint returned.
/// The default, [TokenEndpointOidcIdTokenDecoder], trusts the token
/// because it came straight from the provider's token endpoint over TLS
/// (OpenID Connect Core §3.1.3.7 allows it) and checks its claims; an app
/// needs nothing else. A server that wants the signature checked too
/// (the security starter's `oauth2Login()` does) implements it with the
/// provider's JWK Set, then runs the same claim checks:
///
/// ```dart
/// // A decoder that verifies the signature with the provider's keys.
/// final class JwkOidcIdTokenDecoder implements OidcIdTokenDecoder {
///   @override
///   Future<OidcIdToken> decode(
///     ClientRegistration registration,
///     String tokenValue,
///   ) async {
///     final jwt = await decoderFor(registration).decode(tokenValue);
///     final idToken = OidcIdToken(
///       tokenValue,
///       claims: jwt.claims,
///       issuedAt: jwt.issuedAt,
///       expiresAt: jwt.expiresAt,
///     );
///     final result = OidcIdTokenValidator(registration).validate(idToken);
///     if (result.hasErrors) {
///       throw OAuth2AuthenticationException(result.errors.first);
///     }
///     return idToken;
///   }
/// }
/// ```
///
/// Declare a bean of this type to replace the default in the app login.
///
/// Spring (Java): the `JwtDecoderFactory<ClientRegistration>` of
/// `OidcIdTokenDecoderFactory`, which always verifies the signature.
abstract interface class OidcIdTokenDecoder {
  /// The checked ID token of [registration] in [tokenValue].
  ///
  /// Throws an [OAuth2AuthenticationException] (`invalid_id_token`) when
  /// the token is malformed or fails a check.
  Future<OidcIdToken> decode(
    ClientRegistration registration,
    String tokenValue,
  );
}

/// The [OidcIdTokenDecoder] of apps: it reads the ID token without
/// checking its signature, then checks its claims with
/// [OidcIdTokenValidator].
///
/// Skipping the signature is safe only for a token received directly from
/// the token endpoint over TLS (OpenID Connect Core §3.1.3.7): TLS proves
/// it comes from the provider. Never use it for an ID token that came
/// through the browser or from another party. Tokens with `alg: none` are
/// refused all the same.
///
/// ```dart
/// final decoder = TokenEndpointOidcIdTokenDecoder(
///   // An extra rule: the e-mail must be verified.
///   validatorFactory: (registration) => DelegatingOAuth2TokenValidator([
///     OidcIdTokenValidator(registration),
///     EmailVerifiedValidator(),
///   ]),
/// );
/// ```
///
/// Spring Security has no such decoder: its `oauth2Login()` runs on
/// servers, which verify the signature.
final class TokenEndpointOidcIdTokenDecoder implements OidcIdTokenDecoder {
  /// A decoder checking the claims with the validator [validatorFactory]
  /// makes per registration ([OidcIdTokenValidator] by default, with
  /// [clockSkew] and [clock]).
  TokenEndpointOidcIdTokenDecoder({
    OAuth2TokenValidator<OidcIdToken> Function(ClientRegistration)?
    validatorFactory,
    Duration clockSkew = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _validatorFactory =
           validatorFactory ??
           ((registration) => OidcIdTokenValidator(
             registration,
             clockSkew: clockSkew,
             clock: clock,
           ));

  final OAuth2TokenValidator<OidcIdToken> Function(ClientRegistration)
  _validatorFactory;

  @override
  Future<OidcIdToken> decode(
    ClientRegistration registration,
    String tokenValue,
  ) async {
    final OidcIdToken idToken;
    try {
      idToken = OidcIdToken.parse(tokenValue);
    } on FormatException catch (e) {
      throw OAuth2AuthenticationException(
        OAuth2Error(
          OAuth2ErrorCodes.invalidIdToken,
          'An error occurred while attempting to decode the Jwt: '
          '${e.message}',
        ),
      );
    }
    final result = _validatorFactory(registration).validate(idToken);
    if (result.hasErrors) {
      throw OAuth2AuthenticationException(result.errors.first);
    }
    return idToken;
  }
}
