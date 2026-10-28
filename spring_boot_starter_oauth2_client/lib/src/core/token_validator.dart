import 'package:spring_boot_starter_oauth2_client/src/core/oauth2_error.dart';

/// What an [OAuth2TokenValidator] found: no errors means the token is
/// accepted.
///
/// ```dart
/// final result = OidcIdTokenValidator(registration).validate(idToken);
/// if (result.hasErrors) {
///   throw OAuth2AuthenticationException(result.errors.first);
/// }
/// ```
///
/// Spring (Java): `OAuth2TokenValidatorResult`.
final class OAuth2TokenValidatorResult {
  /// A result with [errors]; with none, the token is valid.
  const OAuth2TokenValidatorResult([this.errors = const []]);

  /// A result rejecting the token for [error].
  factory OAuth2TokenValidatorResult.failure(OAuth2Error error) =>
      OAuth2TokenValidatorResult([error]);

  /// The shared result of a valid token.
  static const success = OAuth2TokenValidatorResult();

  /// Everything wrong with the token; empty when it is valid.
  final List<OAuth2Error> errors;

  /// Whether the token is rejected.
  bool get hasErrors => errors.isNotEmpty;
}

/// A check of a token's claims: who issued it, for whom, until when.
///
/// The login runs the checks of `OidcIdTokenValidator` on every ID token
/// before it trusts the user in it. Write one for a rule of your own,
/// such as a required tenant claim, and combine it with the default one in
/// a [DelegatingOAuth2TokenValidator].
///
/// ```dart
/// // Only users of the "shop" tenant may log in.
/// final class TenantValidator implements OAuth2TokenValidator<OidcIdToken> {
///   @override
///   OAuth2TokenValidatorResult validate(OidcIdToken token) =>
///       token.claims['tenant'] == 'shop'
///       ? OAuth2TokenValidatorResult.success
///       : OAuth2TokenValidatorResult.failure(
///           const OAuth2Error('invalid_id_token', 'Wrong tenant'),
///         );
/// }
/// ```
///
/// Spring (Java): `OAuth2TokenValidator`.
abstract interface class OAuth2TokenValidator<T> {
  /// What is wrong with [token]; a result without errors accepts it.
  OAuth2TokenValidatorResult validate(T token);
}

/// An [OAuth2TokenValidator] made of several: it runs all of them and
/// collects every error, so a token must pass all.
///
/// ```dart
/// final validator = DelegatingOAuth2TokenValidator<OidcIdToken>([
///   OidcIdTokenValidator(registration),
///   TenantValidator(),
/// ]);
/// ```
///
/// Spring (Java): `DelegatingOAuth2TokenValidator`.
final class DelegatingOAuth2TokenValidator<T>
    implements OAuth2TokenValidator<T> {
  /// A validator running [validators] in order.
  DelegatingOAuth2TokenValidator(List<OAuth2TokenValidator<T>> validators)
    : validators = List.unmodifiable(validators);

  /// The validators, in order; cannot be modified.
  final List<OAuth2TokenValidator<T>> validators;

  @override
  OAuth2TokenValidatorResult validate(T token) => OAuth2TokenValidatorResult([
    for (final validator in validators) ...validator.validate(token).errors,
  ]);
}
