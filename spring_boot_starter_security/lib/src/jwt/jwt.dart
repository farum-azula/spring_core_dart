// OAuth2Error, OAuth2TokenValidator, OAuth2TokenValidatorResult and
// DelegatingOAuth2TokenValidator are the OAuth2 client's (one type for the
// resource server and the login, as in Spring's spring-security-oauth2-core).
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show
        DelegatingOAuth2TokenValidator,
        OAuth2Error,
        OAuth2TokenValidator,
        OAuth2TokenValidatorResult;

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

  /// The `cnf` claim (RFC 7800): the key the token is bound to, so that
  /// only its holder can use it; `null` when absent or not a JSON object.
  ///
  /// A DPoP-bound token (RFC 9449) carries `{"jkt": "<thumbprint>"}`
  /// here; see [jwkThumbprint].
  Map<String, Object?>? get confirmation => switch (claims['cnf']) {
    final Map<String, Object?> cnf => cnf,
    _ => null,
  };

  /// The `jkt` member of the `cnf` claim: the RFC 7638 thumbprint of the
  /// key a DPoP-bound token is bound to; `null` for a token that is not
  /// DPoP-bound.
  ///
  /// The resource server accepts such a token only with the `DPoP`
  /// scheme and a proof signed by that key, never as a `Bearer` token.
  /// A `jkt` that is not a string gives `''`, which matches no key.
  String? get jwkThumbprint {
    final cnf = confirmation;
    if (cnf == null || !cnf.containsKey('jkt')) {
      return null;
    }
    return switch (cnf['jkt']) {
      final String jkt => jkt,
      _ => '',
    };
  }

  /// The `x5t#S256` member of the `cnf` claim (RFC 8705): the SHA-256
  /// thumbprint of the client certificate the token is bound to, so that
  /// it is valid only over a TLS connection made with that certificate;
  /// `null` for a token not bound to a certificate.
  ///
  /// The web starter does not hand the client's certificate to the
  /// security filters, so the resource server cannot check the binding
  /// and refuses such tokens, with either scheme (Spring Security refuses
  /// them too when the request has no client certificate). A value that
  /// is not a string gives `''`.
  String? get x509Thumbprint {
    final cnf = confirmation;
    if (cnf == null || !cnf.containsKey('x5t#S256')) {
      return null;
    }
    return switch (cnf['x5t#S256']) {
      final String thumbprint => thumbprint,
      _ => '',
    };
  }

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

/// The [OAuth2TokenValidator] of the token's kind: the `typ` header must
/// be one of [validTypes], compared without regard to case.
///
/// An identity provider signs other JWTs with the same keys as its access
/// tokens: logout tokens (`logout+jwt`), security event tokens
/// (`secevent+jwt`), and clients sign DPoP proofs (`dpop+jwt`). Their
/// `typ` keeps them from being taken for an access token (RFC 8725
/// §3.11). [JwtTypeValidator.jwt], in every default decoder, accepts
/// `JWT` or no `typ` at all, which is what most providers put on access
/// tokens.
///
/// ```dart
/// // A provider that types its access tokens as RFC 9068 says.
/// @Bean()
/// JwtDecoder jwtDecoder() => NimbusJwtDecoder.withJwkSetUri(
///   Uri.parse('https://login.example.com/jwks'),
///   validator: DelegatingOAuth2TokenValidator([
///     JwtTypeValidator(['at+jwt', 'JWT'], allowEmpty: true),
///     JwtTimestampValidator(),
///     const JwtIssuerValidator('https://login.example.com'),
///   ]),
/// );
/// ```
///
/// Spring (Java): `JwtTypeValidator`.
final class JwtTypeValidator implements OAuth2TokenValidator<Jwt> {
  /// A validator accepting the `typ` values [validTypes] and, with
  /// [allowEmpty], a token without `typ` (or with an empty one).
  ///
  /// Throws an [ArgumentError] when [validTypes] is empty.
  JwtTypeValidator(List<String> validTypes, {this.allowEmpty = false})
    : validTypes = List.unmodifiable(validTypes) {
    if (validTypes.isEmpty) {
      throw ArgumentError('validTypes cannot be empty');
    }
  }

  /// The default of the decoders: `JWT` (in any case) or no `typ`, as
  /// Spring Security 7's `JwtTypeValidator.jwt()`. `at+jwt` is not
  /// accepted by it, as in Spring.
  factory JwtTypeValidator.jwt() => JwtTypeValidator(['JWT'], allowEmpty: true);

  /// The accepted `typ` values; cannot be modified.
  final List<String> validTypes;

  /// Whether a token without `typ`, or with a blank one, passes.
  final bool allowEmpty;

  @override
  OAuth2TokenValidatorResult validate(Jwt token) {
    final type = token.headers['typ'];
    if (allowEmpty && (type == null || (type is String && type.trim() == ''))) {
      return OAuth2TokenValidatorResult.success;
    }
    if (type is String) {
      final lower = type.toLowerCase();
      if (validTypes.any((valid) => valid.toLowerCase() == lower)) {
        return OAuth2TokenValidatorResult.success;
      }
    }
    return OAuth2TokenValidatorResult.failure(
      OAuth2Error(
        _invalidToken,
        'the given typ value needs to be one of $validTypes',
        'https://datatracker.ietf.org/doc/html/rfc7515#section-4.1.9',
      ),
    );
  }
}

/// Ready-made sets of validators, to start from when adding your own.
///
/// Spring (Java): `JwtValidators`.
abstract final class JwtValidators {
  /// The checks every token gets: its type ([JwtTypeValidator.jwt]:
  /// `JWT` or no `typ`) and its lifetime (`exp` and `nbf` with 60 seconds
  /// of skew).
  static OAuth2TokenValidator<Jwt> createDefault() =>
      DelegatingOAuth2TokenValidator([
        JwtTypeValidator.jwt(),
        JwtTimestampValidator(),
      ]);

  /// The checks of [createDefault], and the `iss` claim must equal
  /// [issuer].
  static OAuth2TokenValidator<Jwt> createDefaultWithIssuer(String issuer) =>
      DelegatingOAuth2TokenValidator([
        JwtTypeValidator.jwt(),
        JwtTimestampValidator(),
        JwtIssuerValidator(issuer),
      ]);
}
