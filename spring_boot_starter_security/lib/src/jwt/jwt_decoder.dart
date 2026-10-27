import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_security/src/jwt/jose.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

const _log = SpringLog('spring.security.oauth2.jwt');

/// A token could not be decoded or verified, like Spring's
/// `JwtException`.
class JwtException implements Exception {
  /// Described by [message].
  JwtException(this.message, [this.cause]);

  /// What went wrong.
  final String message;

  /// The cause.
  final Object? cause;

  @override
  // The text names the actual class, subclasses included, like Java's
  // getClass().getName().
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType: $message';
}

/// The token itself is bad (malformed, wrong signature, expired), like
/// Spring's `BadJwtException`: the client's fault, a 401 `invalid_token`.
class BadJwtException extends JwtException {
  /// Described by [message].
  BadJwtException(super.message, [super.cause]);
}

/// The token failed a validator, like Spring's `JwtValidationException`.
class JwtValidationException extends BadJwtException {
  /// Failed with [errors].
  JwtValidationException(super.message, this.errors);

  /// What failed.
  final List<OAuth2Error> errors;
}

/// Turns a bearer token into a verified [Jwt], like Spring's `JwtDecoder`.
abstract interface class JwtDecoder {
  /// The verified token; throws [JwtException].
  Future<Jwt> decode(String token);
}

/// Where verification keys come from.
abstract interface class JwkSource {
  /// The keys that may have signed a token with [keyId] (`null`: no
  /// `kid` in the token); [refresh] asks for fresh keys (an unknown `kid`).
  Future<List<VerificationKey>> keys({String? keyId, bool refresh = false});
}

/// Fixed keys.
final class StaticJwkSource implements JwkSource {
  /// [keys].
  StaticJwkSource(List<VerificationKey> keys) : _keys = List.unmodifiable(keys);

  final List<VerificationKey> _keys;

  @override
  Future<List<VerificationKey>> keys({
    String? keyId,
    bool refresh = false,
  }) async => _keys;
}

/// Parses a JWK Set (`{"keys": [...]}`): RSA and EC public keys; other
/// keys (encryption keys, private parts, symmetric keys) are skipped.
List<VerificationKey> parseJwkSet(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (e) {
    throw JwtException('The JWK Set is not valid JSON', e);
  }
  final keys = switch (decoded) {
    {'keys': final List<Object?> keys} => keys,
    _ => throw JwtException('The JWK Set has no "keys" list'),
  };
  final result = <VerificationKey>[];
  for (final key in keys) {
    if (key is! Map<String, Object?>) {
      continue;
    }
    try {
      final parsed = parseJwk(key);
      if (parsed != null) {
        result.add(parsed);
      }
    } on Object catch (e) {
      _log.debug('Skipping an unreadable JWK: $e');
    }
  }
  return result;
}

/// One JWK as a verification key, `null` for keys that do not verify
/// signatures (`use: enc`, symmetric keys from a remote set).
VerificationKey? parseJwk(Map<String, Object?> jwk) {
  final use = jwk['use'] as String?;
  if (use != null && use != 'sig') {
    return null;
  }
  final kid = jwk['kid'] as String?;
  final alg = jwk['alg'] as String?;
  switch (jwk['kty']) {
    case 'RSA':
      return RsaVerificationKey(
        base64UrlToBigInt(jwk['n']! as String),
        base64UrlToBigInt(jwk['e']! as String),
        keyId: kid,
        algorithm: alg,
        use: use,
      );
    case 'EC':
      final key = EcVerificationKey(
        jwk['crv']! as String,
        base64UrlToBigInt(jwk['x']! as String),
        base64UrlToBigInt(jwk['y']! as String),
        keyId: kid,
        algorithm: alg,
        use: use,
      );
      return key.isOnCurve ? key : null;
    default:
      return null;
  }
}

/// Fetches text from a URL (the JWK Set, discovery documents).
typedef JwkFetcher = Future<String> Function(Uri uri);

/// Fetches [uri] with the platform's HTTP client (10 s timeouts); a non-200
/// answer is an error.
Future<String> defaultJwkFetcher(Uri uri) async {
  final transport = platformHttpTransport(
    connectTimeout: const Duration(seconds: 10),
  );
  final response = await transport.send(
    HttpRequest(
      method: HttpMethod.get,
      url: uri,
      headers: HttpHeaders()..set(HttpHeaders.acceptHeader, 'application/json'),
      timeout: const Duration(seconds: 10),
      readTimeout: const Duration(seconds: 10),
    ),
  );
  if (response.statusCode.value != 200) {
    throw JwtException('$uri answered ${response.statusCode.value}');
  }
  if (response.bodyBytes.length > 1 << 20) {
    throw JwtException('$uri answered more than 1 MiB');
  }
  return response.bodyText;
}

/// The keys of a JWK Set URL, cached for [cacheLifespan] (5 minutes), like
/// Nimbus' `RemoteJWKSet` behind Spring's `NimbusJwtDecoder`: an unknown
/// `kid` fetches the set again (at most every [refreshInterval], 30 s, so
/// tokens with made-up ids cannot hammer the issuer); when the issuer is
/// down, the keys fetched last keep working.
final class RemoteJwkSource implements JwkSource {
  /// The keys at [uri].
  RemoteJwkSource(
    this.uri, {
    JwkFetcher? fetcher,
    this.cacheLifespan = const Duration(minutes: 5),
    this.refreshInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _fetch = fetcher ?? defaultJwkFetcher,
       _clock = clock ?? DateTime.now;

  /// The JWK Set URL.
  final Uri uri;

  /// How long keys are kept.
  final Duration cacheLifespan;

  /// The shortest time between two fetches.
  final Duration refreshInterval;

  final JwkFetcher _fetch;
  final DateTime Function() _clock;
  List<VerificationKey>? _cached;
  DateTime? _fetchedAt;
  Future<List<VerificationKey>>? _inFlight;

  @override
  Future<List<VerificationKey>> keys({
    String? keyId,
    bool refresh = false,
  }) async {
    final now = _clock();
    final cached = _cached;
    final fetchedAt = _fetchedAt;
    final fresh =
        cached != null &&
        fetchedAt != null &&
        now.difference(fetchedAt) < cacheLifespan;
    final mayRefetch =
        fetchedAt == null || now.difference(fetchedAt) >= refreshInterval;
    if (fresh && !(refresh && mayRefetch)) {
      return cached;
    }
    if (cached != null && !mayRefetch) {
      return cached;
    }
    try {
      return await (_inFlight ??= _load().whenComplete(() => _inFlight = null));
    } on Object catch (e) {
      if (cached != null) {
        _log.warning('Could not refresh the JWK Set $uri: $e');
        return cached;
      }
      throw JwtException("Couldn't retrieve remote JWK set: $e", e);
    }
  }

  Future<List<VerificationKey>> _load() async {
    final keys = parseJwkSet(await _fetch(uri));
    _cached = keys;
    _fetchedAt = _clock();
    return keys;
  }
}

/// Decodes and verifies JWS tokens, like Spring's `NimbusJwtDecoder`:
///
/// 1. the token is parsed strictly (see `parseJws`): never `alg: none`,
///    no `crit`, no nested or encrypted tokens, at most 64 KiB;
/// 2. its `alg` must be one of [jwsAlgorithms] (by default those the
///    keys allow: RSA keys RS*/PS*, EC keys the ES* of their curve) and
///    fit the key: an RSA public key is never used as an HMAC secret;
/// 3. the signature is checked with the key of its `kid` (or every key
///    fitting the algorithm when there is none); keys named in the token
///    (`jku`, `jwk`, `x5u`) are ignored;
/// 4. the claims pass the [validator] (`exp` / `nbf` with 60 s of skew by
///    default; the issuer when built from one).
final class NimbusJwtDecoder implements JwtDecoder {
  NimbusJwtDecoder._(
    this._source, {
    Set<JwsAlgorithm>? jwsAlgorithms,
    OAuth2TokenValidator<Jwt>? validator,
  }) : jwsAlgorithms = jwsAlgorithms == null
           ? null
           : Set.unmodifiable(jwsAlgorithms),
       validator = validator ?? JwtValidators.createDefault();

  /// Keys from the JWK Set at [jwkSetUri]; [jwsAlgorithms] default to
  /// RS256 (Spring Boot's `jws-algorithms` default).
  factory NimbusJwtDecoder.withJwkSetUri(
    Uri jwkSetUri, {
    Set<JwsAlgorithm> jwsAlgorithms = const {JwsAlgorithm.rs256},
    JwkFetcher? fetcher,
    OAuth2TokenValidator<Jwt>? validator,
  }) => NimbusJwtDecoder._(
    RemoteJwkSource(jwkSetUri, fetcher: fetcher),
    jwsAlgorithms: _asymmetric(jwsAlgorithms),
    validator: validator,
  );

  /// One RSA public key (RS256 by default).
  factory NimbusJwtDecoder.withPublicKey(
    RsaVerificationKey key, {
    Set<JwsAlgorithm> jwsAlgorithms = const {JwsAlgorithm.rs256},
    OAuth2TokenValidator<Jwt>? validator,
  }) => NimbusJwtDecoder._(
    StaticJwkSource([key]),
    jwsAlgorithms: _asymmetric(jwsAlgorithms),
    validator: validator,
  );

  /// One HMAC secret (HS256 by default, at least 256 bits).
  factory NimbusJwtDecoder.withSecretKey(
    List<int> secret, {
    JwsAlgorithm macAlgorithm = JwsAlgorithm.hs256,
    OAuth2TokenValidator<Jwt>? validator,
  }) {
    if (!macAlgorithm.isMac) {
      throw ArgumentError('$macAlgorithm is not an HMAC algorithm');
    }
    final key = SecretVerificationKey(secret);
    if (!key.fits(macAlgorithm)) {
      throw ArgumentError(
        'The secret must have at least as many bits as the hash of '
        '${macAlgorithm.name}',
      );
    }
    return NimbusJwtDecoder._(
      StaticJwkSource([key]),
      jwsAlgorithms: {macAlgorithm},
      validator: validator,
    );
  }

  /// Keys from any [source], algorithms derived from the keys unless
  /// given.
  factory NimbusJwtDecoder.withJwkSource(
    JwkSource source, {
    Set<JwsAlgorithm>? jwsAlgorithms,
    OAuth2TokenValidator<Jwt>? validator,
  }) => NimbusJwtDecoder._(
    source,
    jwsAlgorithms: jwsAlgorithms,
    validator: validator,
  );

  static Set<JwsAlgorithm> _asymmetric(Set<JwsAlgorithm> algorithms) {
    if (algorithms.isEmpty || algorithms.any((a) => a.isMac)) {
      throw ArgumentError(
        'Public keys verify RS*, PS* and ES* algorithms only',
      );
    }
    return algorithms;
  }

  final JwkSource _source;

  /// The accepted algorithms (`null`: those the keys allow).
  final Set<JwsAlgorithm>? jwsAlgorithms;

  /// Checks the claims.
  final OAuth2TokenValidator<Jwt> validator;

  static const _prefix =
      'An error occurred while attempting to decode the Jwt: ';

  @override
  Future<Jwt> decode(String token) async {
    final ParsedJws jws;
    try {
      jws = parseJws(token);
    } on JoseException catch (e) {
      throw BadJwtException('$_prefix${e.message}', e);
    }
    final algorithm = JwsAlgorithm.from(jws.algorithmName!);
    final allowed = jwsAlgorithms;
    if (algorithm == null ||
        (allowed != null && !allowed.contains(algorithm)) ||
        (allowed == null && algorithm.isMac)) {
      throw BadJwtException(
        '${_prefix}Signed JWT rejected: Another algorithm expected, or no '
        'matching key(s) found',
      );
    }
    final kid = jws.keyId;
    var candidates = _matching(await _source.keys(keyId: kid), kid, algorithm);
    if (candidates.isEmpty && kid != null) {
      // A key the cache does not know yet (rotation).
      candidates = _matching(
        await _source.keys(keyId: kid, refresh: true),
        kid,
        algorithm,
      );
    }
    if (candidates.isEmpty) {
      throw BadJwtException(
        '${_prefix}Signed JWT rejected: Another algorithm expected, or no '
        'matching key(s) found',
      );
    }
    if (!candidates.any((key) => verifySignature(jws, algorithm, key))) {
      throw BadJwtException('${_prefix}Signed JWT rejected: Invalid signature');
    }
    final jwt = Jwt(token, headers: jws.header, claims: jws.claims);
    final result = validator.validate(jwt);
    if (result.hasErrors) {
      final description = result.errors
          .map((e) => e.description ?? e.errorCode)
          .join(', ');
      throw JwtValidationException('$_prefix$description', result.errors);
    }
    return jwt;
  }

  static List<VerificationKey> _matching(
    List<VerificationKey> keys,
    String? kid,
    JwsAlgorithm algorithm,
  ) => [
    for (final key in keys)
      if ((kid == null || key.keyId == kid) &&
          key.fits(algorithm) &&
          (key.algorithm == null || key.algorithm == algorithm.name))
        key,
  ];
}

/// Decoders from an issuer, like Spring's `JwtDecoders`.
abstract final class JwtDecoders {
  /// A decoder for the tokens of [issuer]: its OpenID Connect (or OAuth 2.0
  /// authorization server) metadata gives the JWK Set; the `issuer` there
  /// must be [issuer]; tokens must carry `iss` == [issuer]. Fetched on the
  /// first token, not at startup (the issuer may start later).
  static JwtDecoder fromIssuerLocation(
    String issuer, {
    JwkFetcher? fetcher,
    List<String> audiences = const [],
  }) => _IssuerJwtDecoder(issuer, fetcher ?? defaultJwkFetcher, audiences);
}

final class _IssuerJwtDecoder implements JwtDecoder {
  _IssuerJwtDecoder(this.issuer, this.fetcher, this.audiences);

  final String issuer;
  final JwkFetcher fetcher;
  final List<String> audiences;
  Future<JwtDecoder>? _delegate;

  @override
  Future<Jwt> decode(String token) async {
    final pending = _delegate ??= _discover();
    final JwtDecoder delegate;
    try {
      delegate = await pending;
    } on Object catch (e) {
      _delegate = null; // try again with the next token
      throw JwtException('Unable to resolve the issuer $issuer: $e', e);
    }
    return await delegate.decode(token);
  }

  Future<JwtDecoder> _discover() async {
    final base = Uri.parse(issuer);
    final path = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final candidates = [
      base.replace(path: '$path/.well-known/openid-configuration'),
      base.replace(path: '/.well-known/openid-configuration$path'),
      base.replace(path: '/.well-known/oauth-authorization-server$path'),
    ];
    Object? lastError;
    for (final uri in candidates) {
      try {
        final metadata = jsonDecode(await fetcher(uri));
        if (metadata is! Map<String, Object?>) {
          continue;
        }
        if (metadata['issuer'] != issuer) {
          throw JwtException(
            'The issuer "${metadata['issuer']}" provided in the configuration '
            'did not match the requested issuer "$issuer"',
          );
        }
        final jwksUri = metadata['jwks_uri'];
        if (jwksUri is! String) {
          throw JwtException('The issuer metadata has no jwks_uri');
        }
        return NimbusJwtDecoder.withJwkSource(
          RemoteJwkSource(Uri.parse(jwksUri), fetcher: fetcher),
          validator: DelegatingOAuth2TokenValidator([
            JwtTimestampValidator(),
            JwtIssuerValidator(issuer),
            if (audiences.isNotEmpty) JwtAudienceValidator(audiences),
          ]),
        );
      } on JwtException {
        rethrow;
      } on Object catch (e) {
        lastError = e;
      }
    }
    throw JwtException('No metadata for issuer $issuer: $lastError');
  }
}
