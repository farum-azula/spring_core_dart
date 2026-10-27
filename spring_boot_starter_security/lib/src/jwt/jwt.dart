/// A verified JWT, like Spring's `Jwt`: the token, its headers and claims.
///
/// ```dart
/// @GetMapping('/me')
/// String me(@AuthenticationPrincipal() Jwt jwt) => jwt.subject ?? '';
/// ```
final class Jwt {
  /// A token [tokenValue] with [headers] and [claims].
  Jwt(
    this.tokenValue, {
    required Map<String, Object?> headers,
    required Map<String, Object?> claims,
  }) : headers = Map.unmodifiable(headers),
       claims = Map.unmodifiable(claims);

  /// The compact token.
  final String tokenValue;

  /// The JOSE header (`alg`, `kid`, ...).
  final Map<String, Object?> headers;

  /// The claims.
  final Map<String, Object?> claims;

  /// `sub`.
  String? get subject => getClaimAsString('sub');

  /// `iss`.
  String? get issuer => getClaimAsString('iss');

  /// `aud`: a string or a list of strings.
  List<String> get audience => getClaimAsStringList('aud') ?? const [];

  /// `jti`.
  String? get id => getClaimAsString('jti');

  /// `exp`.
  DateTime? get expiresAt => getClaimAsInstant('exp');

  /// `nbf`.
  DateTime? get notBefore => getClaimAsInstant('nbf');

  /// `iat`.
  DateTime? get issuedAt => getClaimAsInstant('iat');

  /// Whether the claim [name] is present.
  bool hasClaim(String name) => claims.containsKey(name);

  /// The claim [name] as text.
  String? getClaimAsString(String name) => switch (claims[name]) {
    null => null,
    final String text => text,
    final other => '$other',
  };

  /// The claim [name] as a list of text (a single string is one element).
  List<String>? getClaimAsStringList(String name) => switch (claims[name]) {
    null => null,
    final String text => [text],
    final List<Object?> list => [for (final e in list) '$e'],
    final other => ['$other'],
  };

  /// The claim [name] (seconds since the epoch, RFC 7519 `NumericDate`) as
  /// a UTC time; `null` when absent; a malformed one throws.
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

  /// Never the token itself: it is a bearer credential.
  @override
  String toString() =>
      'Jwt [subject=$subject, issuer=$issuer, '
      'expiresAt=$expiresAt, tokenValue=[PROTECTED]]';
}

/// An error of an OAuth 2.0 check, like Spring's `OAuth2Error`.
final class OAuth2Error {
  /// An error [errorCode] (`invalid_token`).
  const OAuth2Error(this.errorCode, [this.description, this.uri]);

  /// The code.
  final String errorCode;

  /// For people.
  final String? description;

  /// More about it.
  final String? uri;

  @override
  String toString() => '[$errorCode] ${description ?? ''}';
}

/// The result of an [OAuth2TokenValidator], like Spring's
/// `OAuth2TokenValidatorResult`.
final class OAuth2TokenValidatorResult {
  /// A result with [errors] (none: valid).
  const OAuth2TokenValidatorResult([this.errors = const []]);

  /// Invalid with [error].
  factory OAuth2TokenValidatorResult.failure(OAuth2Error error) =>
      OAuth2TokenValidatorResult([error]);

  /// Valid.
  static const success = OAuth2TokenValidatorResult();

  /// What is wrong.
  final List<OAuth2Error> errors;

  /// Whether there are errors.
  bool get hasErrors => errors.isNotEmpty;
}

/// Checks a decoded token, like Spring's `OAuth2TokenValidator`.
abstract interface class OAuth2TokenValidator<T> {
  /// The result for [token].
  OAuth2TokenValidatorResult validate(T token);
}

const _invalidToken = 'invalid_token';
const _rfc6750 = 'https://tools.ietf.org/html/rfc6750#section-3.1';

/// `exp` and `nbf` with [clockSkew] (60 s), like Spring's
/// `JwtTimestampValidator`.
final class JwtTimestampValidator implements OAuth2TokenValidator<Jwt> {
  /// A validator allowing [clockSkew].
  JwtTimestampValidator({
    this.clockSkew = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Tolerated clock difference.
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

/// A claim must satisfy [test], like Spring's `JwtClaimValidator`.
final class JwtClaimValidator implements OAuth2TokenValidator<Jwt> {
  /// The claim [claim] must satisfy [test].
  const JwtClaimValidator(this.claim, this.test);

  /// The claim.
  final String claim;

  /// The condition.
  final bool Function(Object? value) test;

  @override
  OAuth2TokenValidatorResult validate(Jwt token) => test(token.claims[claim])
      ? OAuth2TokenValidatorResult.success
      : OAuth2TokenValidatorResult.failure(
          OAuth2Error(_invalidToken, 'The $claim claim is not valid', _rfc6750),
        );
}

/// `iss` must be [issuer], like Spring's `JwtIssuerValidator`.
final class JwtIssuerValidator implements OAuth2TokenValidator<Jwt> {
  /// The expected issuer.
  const JwtIssuerValidator(this.issuer);

  /// The issuer.
  final String issuer;

  @override
  OAuth2TokenValidatorResult validate(Jwt token) =>
      token.claims['iss'] == issuer
      ? OAuth2TokenValidatorResult.success
      : const OAuth2TokenValidatorResult([
          OAuth2Error(_invalidToken, 'The iss claim is not valid', _rfc6750),
        ]);
}

/// `aud` must contain one of [audiences], like Spring's
/// `JwtAudienceValidator`
/// (`spring.security.oauth2.resourceserver.jwt.audiences`).
final class JwtAudienceValidator implements OAuth2TokenValidator<Jwt> {
  /// One of [audiences] must be in `aud`.
  JwtAudienceValidator(List<String> audiences)
    : audiences = List.unmodifiable(audiences);

  /// The accepted audiences.
  final List<String> audiences;

  @override
  OAuth2TokenValidatorResult validate(Jwt token) =>
      token.audience.any(audiences.contains)
      ? OAuth2TokenValidatorResult.success
      : const OAuth2TokenValidatorResult([
          OAuth2Error(_invalidToken, 'The aud claim is not valid', _rfc6750),
        ]);
}

/// All of [validators], like Spring's `DelegatingOAuth2TokenValidator`.
final class DelegatingOAuth2TokenValidator<T>
    implements OAuth2TokenValidator<T> {
  /// Over [validators].
  DelegatingOAuth2TokenValidator(List<OAuth2TokenValidator<T>> validators)
    : validators = List.unmodifiable(validators);

  /// The validators.
  final List<OAuth2TokenValidator<T>> validators;

  @override
  OAuth2TokenValidatorResult validate(T token) => OAuth2TokenValidatorResult([
    for (final validator in validators) ...validator.validate(token).errors,
  ]);
}

/// The usual validators, like Spring's `JwtValidators`.
abstract final class JwtValidators {
  /// `exp` / `nbf` with 60 s of skew.
  static OAuth2TokenValidator<Jwt> createDefault() =>
      DelegatingOAuth2TokenValidator([JwtTimestampValidator()]);

  /// The default ones and `iss` == [issuer].
  static OAuth2TokenValidator<Jwt> createDefaultWithIssuer(String issuer) =>
      DelegatingOAuth2TokenValidator([
        JwtTimestampValidator(),
        JwtIssuerValidator(issuer),
      ]);
}
