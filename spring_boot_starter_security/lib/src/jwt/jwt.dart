/// A decoded JSON Web Token: the raw token, its header and its claims.
///
/// A `JwtDecoder` returns one only after checking the signature and the
/// validators, so its claims can be trusted. It is the principal of a
/// request authenticated with a bearer token: a controller gets it with
/// `@AuthenticationPrincipal() Jwt jwt`, and `@PreAuthorize` expressions
/// read `principal.subject` or `principal.claims['tenant']`. [toString]
/// never shows the raw token.
///
/// ```dart
/// // The user id of the identity provider is the token's subject.
/// @GetMapping('/me')
/// String me(@AuthenticationPrincipal() Jwt jwt) => jwt.subject ?? '';
/// ```
///
/// Spring (Java): `Jwt`, with the same getters.
final class Jwt {
  /// A token whose compact form is [tokenValue], with copies of [headers]
  /// and [claims] that cannot be modified.
  ///
  /// Nothing is checked here: build one by hand only in tests.
  Jwt(
    this.tokenValue, {
    required Map<String, Object?> headers,
    required Map<String, Object?> claims,
  }) : headers = Map.unmodifiable(headers),
       claims = Map.unmodifiable(claims);

  /// The token as it was sent (`xxxxx.yyyyy.zzzzz`); a credential, never
  /// log it.
  final String tokenValue;

  /// The token's header: `alg`, `kid` and so on.
  final Map<String, Object?> headers;

  /// The token's claims, by name.
  final Map<String, Object?> claims;

  /// The `sub` claim: who the token is about, usually the user id.
  String? get subject => getClaimAsString('sub');

  /// The `iss` claim: who issued the token.
  String? get issuer => getClaimAsString('iss');

  /// The `aud` claim: who the token is for. A single string gives a list
  /// of one; empty when absent.
  List<String> get audience => getClaimAsStringList('aud') ?? const [];

  /// The `jti` claim: the token's unique id.
  String? get id => getClaimAsString('jti');

  /// The `exp` claim: when the token expires, in UTC.
  ///
  /// Throws a [FormatException] when the claim is not a number.
  DateTime? get expiresAt => getClaimAsInstant('exp');

  /// The `nbf` claim: the time before which the token is not valid, in
  /// UTC.
  ///
  /// Throws a [FormatException] when the claim is not a number.
  DateTime? get notBefore => getClaimAsInstant('nbf');

  /// The `iat` claim: when the token was issued, in UTC.
  ///
  /// Throws a [FormatException] when the claim is not a number.
  DateTime? get issuedAt => getClaimAsInstant('iat');

  /// Whether the token has the claim [name], even with a `null` value.
  bool hasClaim(String name) => claims.containsKey(name);

  /// The claim [name] as text (`toString()` of a non-string value); `null`
  /// when absent.
  String? getClaimAsString(String name) => switch (claims[name]) {
    null => null,
    final String text => text,
    final other => '$other',
  };

  /// The claim [name] as a list of text: a single value gives a list of
  /// one, and list elements are turned into text; `null` when absent.
  List<String>? getClaimAsStringList(String name) => switch (claims[name]) {
    null => null,
    final String text => [text],
    final List<Object?> list => [for (final e in list) '$e'],
    final other => ['$other'],
  };

  /// The claim [name], seconds since the epoch (an RFC 7519
  /// `NumericDate`), as a UTC time; `null` when absent.
  ///
  /// Throws a [FormatException] when the value is not a finite number.
  DateTime? getClaimAsInstant(String name) {
    final value = claims[name];
    if (value == null) {
      return null;
    }
    if (value is! num || !value.isFinite) {
      throw FormatException('The $name claim is not a NumericDate');
    }
    return DateTime.fromMillisecondsSinceEpoch(
      (value * 1000).round(),
      isUtc: true,
    );
  }

  /// A description for logs: subject, issuer and expiry; the token itself
  /// shows as `[PROTECTED]`, since anyone holding it can use it.
  @override
  String toString() =>
      'Jwt [subject=$subject, issuer=$issuer, '
      'expiresAt=$expiresAt, tokenValue=[PROTECTED]]';
}

/// An OAuth 2.0 error as the client sees it: a standard code, a
/// description and a link to the specification.
///
/// Validators return it, and the bearer-token entry point sends it in the
/// `WWW-Authenticate` header, so do not put secrets in the description.
///
/// Spring (Java): `OAuth2Error`.
final class OAuth2Error {
  /// An error with the code [errorCode] (such as `invalid_token`), an
  /// optional [description] and [uri].
  const OAuth2Error(this.errorCode, [this.description, this.uri]);

  /// The standard error code, such as `invalid_token` or
  /// `insufficient_scope`.
  final String errorCode;

  /// A sentence for developers explaining the error; sent to the
  /// client.
  final String? description;

  /// A link to a page about the error, or `null`.
  final String? uri;

  @override
  String toString() => '[$errorCode] ${description ?? ''}';
}

/// What an [OAuth2TokenValidator] found: no errors means the token is
/// accepted.
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

/// A check of a decoded token's claims, run by the decoder after the
/// signature check; any error rejects the token with a 401.
///
/// The decoder already checks the expiry, and the issuer and audience
/// when configured. Write one for a rule of your own, such as a required
/// tenant, and pass it to the decoder (combine it with the default ones
/// in a [DelegatingOAuth2TokenValidator]).
///
/// ```dart
/// // Only tokens of the "shop" tenant are accepted.
/// @Bean()
/// JwtDecoder jwtDecoder() => NimbusJwtDecoder.withJwkSetUri(
///   Uri.parse('https://login.example.com/jwks'),
///   validator: DelegatingOAuth2TokenValidator([
///     JwtValidators.createDefaultWithIssuer('https://login.example.com'),
///     JwtClaimValidator('tenant', (value) => value == 'shop'),
///   ]),
/// );
/// ```
///
/// Spring (Java): `OAuth2TokenValidator`.
abstract interface class OAuth2TokenValidator<T> {
  /// What is wrong with [token]; a result without errors accepts it.
  OAuth2TokenValidatorResult validate(T token);
}

const _invalidToken = 'invalid_token';
const _rfc6750 = 'https://tools.ietf.org/html/rfc6750#section-3.1';

/// The [OAuth2TokenValidator] of the token's lifetime: the token must not
/// have expired (`exp`) and must already be valid (`nbf`).
///
/// [clockSkew], 60 seconds by default, is tolerated on both sides,
/// because the server's clock and the issuer's are never exactly in step.
/// A token without `exp` or `nbf` passes that part of the check, as in
/// Spring; a value that is not a number rejects the token. Every decoder
/// runs it by default.
///
/// Spring (Java): `JwtTimestampValidator`.
final class JwtTimestampValidator implements OAuth2TokenValidator<Jwt> {
  /// A validator tolerating [clockSkew]; [clock] gives the current time
  /// (`DateTime.now` by default), so tests can fix it.
  JwtTimestampValidator({
    this.clockSkew = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How far the clocks may differ; 60 seconds by default.
  final Duration clockSkew;

  final DateTime Function() _clock;

  @override
  OAuth2TokenValidatorResult validate(Jwt token) {
    final now = _clock().toUtc();
    final DateTime? expiresAt;
    final DateTime? notBefore;
    try {
      expiresAt = token.expiresAt;
      notBefore = token.notBefore;
    } on FormatException catch (e) {
      return OAuth2TokenValidatorResult.failure(
        OAuth2Error(_invalidToken, e.message, _rfc6750),
      );
    }
    if (expiresAt != null && now.subtract(clockSkew).isAfter(expiresAt)) {
      return OAuth2TokenValidatorResult.failure(
        OAuth2Error(
          _invalidToken,
          'Jwt expired at ${expiresAt.toIso8601String()}',
          _rfc6750,
        ),
      );
    }
    if (notBefore != null && now.add(clockSkew).isBefore(notBefore)) {
      return OAuth2TokenValidatorResult.failure(
        OAuth2Error(
          _invalidToken,
          'Jwt used before ${notBefore.toIso8601String()}',
          _rfc6750,
        ),
      );
    }
    return OAuth2TokenValidatorResult.success;
  }
}

/// An [OAuth2TokenValidator] that rejects a token unless one claim
/// satisfies a test.
///
/// The test also gets `null` when the claim is absent.
///
/// ```dart
/// JwtClaimValidator('email_verified', (value) => value == true)
/// ```
///
/// Spring (Java): `JwtClaimValidator`.
final class JwtClaimValidator implements OAuth2TokenValidator<Jwt> {
  /// A validator requiring the claim [claim] to satisfy [test].
  const JwtClaimValidator(this.claim, this.test);

  /// The name of the claim tested.
  final String claim;

  /// Returns `true` for an acceptable value (`null` when absent).
  final bool Function(Object? value) test;

  @override
  OAuth2TokenValidatorResult validate(Jwt token) => test(token.claims[claim])
      ? OAuth2TokenValidatorResult.success
      : OAuth2TokenValidatorResult.failure(
          OAuth2Error(_invalidToken, 'The $claim claim is not valid', _rfc6750),
        );
}

/// An [OAuth2TokenValidator] that accepts only tokens of one issuer: the
/// `iss` claim must equal [issuer] exactly.
///
/// Without it, a token signed by another tenant of the same identity
/// provider, with the same keys, would be accepted. The decoders built
/// from an issuer, or with `issuer-uri`, add it.
///
/// Spring (Java): `JwtIssuerValidator`.
final class JwtIssuerValidator implements OAuth2TokenValidator<Jwt> {
  /// A validator requiring the issuer [issuer].
  const JwtIssuerValidator(this.issuer);

  /// The exact value the `iss` claim must have.
  final String issuer;

  @override
  OAuth2TokenValidatorResult validate(Jwt token) =>
      token.claims['iss'] == issuer
      ? OAuth2TokenValidatorResult.success
      : const OAuth2TokenValidatorResult([
          OAuth2Error(_invalidToken, 'The iss claim is not valid', _rfc6750),
        ]);
}

/// An [OAuth2TokenValidator] that accepts only tokens meant for this
/// application: the `aud` claim must contain one of [audiences].
///
/// Without it, a token the identity provider issued for another
/// application would be accepted here. Set the audiences with
/// `spring.security.oauth2.resourceserver.jwt.audiences`. A token without
/// `aud` is rejected.
///
/// Spring (Java): `JwtAudienceValidator`.
final class JwtAudienceValidator implements OAuth2TokenValidator<Jwt> {
  /// A validator requiring one of [audiences] in the `aud` claim.
  JwtAudienceValidator(List<String> audiences)
    : audiences = List.unmodifiable(audiences);

  /// The audiences accepted; cannot be modified.
  final List<String> audiences;

  @override
  OAuth2TokenValidatorResult validate(Jwt token) =>
      token.audience.any(audiences.contains)
      ? OAuth2TokenValidatorResult.success
      : const OAuth2TokenValidatorResult([
          OAuth2Error(_invalidToken, 'The aud claim is not valid', _rfc6750),
        ]);
}

/// An [OAuth2TokenValidator] made of several: it runs all of them and
/// collects every error, so a token must pass all.
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

/// Ready-made sets of validators, to start from when adding your own.
///
/// Spring (Java): `JwtValidators`.
abstract final class JwtValidators {
  /// The lifetime check alone: `exp` and `nbf` with 60 seconds of
  /// skew.
  static OAuth2TokenValidator<Jwt> createDefault() =>
      DelegatingOAuth2TokenValidator([JwtTimestampValidator()]);

  /// The lifetime check, and the `iss` claim must equal [issuer].
  static OAuth2TokenValidator<Jwt> createDefaultWithIssuer(String issuer) =>
      DelegatingOAuth2TokenValidator([
        JwtTimestampValidator(),
        JwtIssuerValidator(issuer),
      ]);
}
