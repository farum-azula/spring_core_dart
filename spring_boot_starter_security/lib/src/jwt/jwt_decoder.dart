import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show
        ClientRegistrations,
        DelegatingOAuth2TokenValidator,
        OAuth2Error,
        OAuth2TokenValidator;
import 'package:spring_boot_starter_security/src/jwt/jose.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt.dart';
import 'package:spring_boot_starter_security/src/jwt/since.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

const _log = SpringLog('spring.security.oauth2.jwt');

/// A token could not be decoded or verified.
///
/// This base class, thrown as is, means the decoder itself could not work,
/// for example because the key server cannot be reached: the request gets
/// a 401 without details. A token at fault throws [BadJwtException].
///
/// Spring (Java): `JwtException`.
class JwtException implements Exception {
  /// A failure described by [message], caused by [cause].
  JwtException(this.message, [this.cause]);

  /// What went wrong; for a [BadJwtException] it is sent to the client as
  /// the error description.
  final String message;

  /// The lower-level error, or `null`.
  final Object? cause;

  @override
  // The text names the actual class, subclasses included, like Java's
  // getClass().getName().
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType: $message';
}

/// The token itself is bad: malformed, wrongly signed, of a refused
/// algorithm, or expired.
///
/// The client is at fault, so it gets a 401 with
/// `WWW-Authenticate: Bearer error="invalid_token"` and the [message] as
/// the description.
///
/// Spring (Java): `BadJwtException`.
class BadJwtException extends JwtException {
  /// A bad token described by [message], caused by [cause].
  BadJwtException(super.message, [super.cause]);
}

/// The token is well signed but failed a validator: expired, wrong issuer,
/// wrong audience, or a rule of your own.
///
/// Spring (Java): `JwtValidationException`.
class JwtValidationException extends BadJwtException {
  /// A failure described by [message], with the validators' [errors].
  JwtValidationException(super.message, this.errors);

  /// The errors the validators reported.
  final List<OAuth2Error> errors;
}

/// Verifies a bearer token and decodes it into a [Jwt]: the signature,
/// the algorithm and the claims are checked before anything is trusted.
///
/// A resource server needs exactly one. The auto-configuration builds a
/// [NimbusJwtDecoder] from
/// `spring.security.oauth2.resourceserver.jwt.issuer-uri` or `jwk-set-uri`;
/// declare a bean to choose the keys or validators yourself.
///
/// ```dart
/// // Tokens signed by the identity provider's keys, for this API only.
/// @Bean()
/// JwtDecoder jwtDecoder() => JwtDecoders.fromIssuerLocation(
///   'https://login.example.com/realms/shop',
///   audiences: ['orders-api'],
/// );
/// ```
///
/// Spring (Java): `JwtDecoder`.
abstract interface class JwtDecoder {
  /// The verified token.
  ///
  /// Throws a [BadJwtException] when the token is at fault, and a
  /// [JwtException] when it could not be checked.
  Future<Jwt> decode(String token);
}

/// Where a [NimbusJwtDecoder] gets the public keys that verify
/// signatures.
///
/// [RemoteJwkSource] fetches them from the identity provider's JWK Set
/// URL; [StaticJwkSource] holds fixed keys. Implement it to load keys from
/// somewhere else, such as a secrets store.
abstract interface class JwkSource {
  /// The keys that may have signed a token whose header names [keyId]
  /// (`null` when it names none).
  ///
  /// [refresh] is `true` when no cached key had that id, asking for fresh
  /// keys in case the provider rotated them. The decoder filters the
  /// result by id and algorithm.
  Future<List<VerificationKey>> keys({String? keyId, bool refresh = false});
}

/// A [JwkSource] with a fixed list of keys, for keys known in advance and
/// tests.
final class StaticJwkSource implements JwkSource {
  /// A source always giving [keys] (copied).
  StaticJwkSource(List<VerificationKey> keys) : _keys = List.unmodifiable(keys);

  final List<VerificationKey> _keys;

  @override
  Future<List<VerificationKey>> keys({
    String? keyId,
    bool refresh = false,
  }) async => _keys;
}

/// The signature keys of a JWK Set document (`{"keys": [...]}`), the
/// format identity providers publish their public keys in.
///
/// RSA and EC public keys meant for signatures are read. Keys for
/// encryption (`use: enc`), symmetric keys, EC keys not on their curve,
/// and keys that cannot be read are skipped. Throws a [JwtException] when
/// the text is not JSON or has no `keys` list.
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
      // The type only: the message may quote the key.
      _log.debug('Skipping an unreadable JWK: ${e.runtimeType}');
    }
  }
  return result;
}

/// One JWK as a verification key; `null` for keys that do not verify
/// signatures here (`use: enc`, symmetric keys, EC points off their
/// curve).
///
/// Throws when a required member (`n`, `e`, `crv`, `x`, `y`) is missing or
/// malformed.
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

/// Fetches the text at a URL: the JWK Set and the issuer's metadata.
///
/// Pass your own to go through a proxy, or to serve fixed documents in
/// tests.
typedef JwkFetcher = Future<String> Function(Uri uri);

/// The default [JwkFetcher]: a `GET` of [uri] with the platform's HTTP
/// client, with 10-second timeouts.
///
/// Throws a [JwtException] for an answer other than 200 or a body over
/// 1 MiB.
Future<String> defaultJwkFetcher(Uri uri) => transportJwkFetcher(
  platformHttpTransport(connectTimeout: const Duration(seconds: 10)),
)(uri);

/// A [JwkFetcher] sending its `GET` through [transport], with 10-second
/// timeouts.
///
/// The OpenID Connect login uses it with the application's
/// `HttpTransport` bean, so the provider's keys come through the same
/// client (proxy, TLS settings) as its tokens, and tests can answer with
/// a `MockHttpTransport`.
///
/// ```dart
/// final decoder = NimbusJwtDecoder.withJwkSetUri(
///   Uri.parse('https://login.example.com/jwks'),
///   fetcher: transportJwkFetcher(transport),
/// );
/// ```
///
/// The fetcher throws a [JwtException] for an answer other than 200 or a
/// body over 1 MiB.
JwkFetcher transportJwkFetcher(HttpTransport transport) => (uri) async {
  final response = await transport.send(
    HttpRequest(
      method: HttpMethod.get,
      url: uri,
      headers: HttpHeaders()..set(HttpHeaders.acceptHeader, 'application/json'),
      timeout: const Duration(seconds: 10),
      readTimeout: const Duration(seconds: 10),
    ),
  );
  _log.debug(
    () =>
        'The JWK Set endpoint ${_endpoint(uri)} answered '
        '${response.statusCode.value}',
  );
  if (response.statusCode.value != 200) {
    throw JwtException('$uri answered ${response.statusCode.value}');
  }
  if (response.bodyBytes.length > 1 << 20) {
    throw JwtException('$uri answered more than 1 MiB');
  }
  return response.bodyText;
};

/// A [JwkSource] that fetches the keys from the identity provider's JWK
/// Set URL and caches them.
///
/// - Keys are kept for [cacheLifespan] (5 minutes), then fetched again.
/// - A token with an unknown `kid` fetches the set again, at most once
///   per [refreshInterval] (30 seconds), so tokens with made-up ids cannot
///   flood the provider with requests.
/// - A failed fetch counts too: the next one is made [refreshInterval]
///   later at the earliest, whatever the tokens, so a provider that is
///   down gets no request per token.
/// - When the provider cannot be reached, the keys fetched last keep
///   working (with a warning in the log, once per attempt). Before the
///   first successful fetch, every token fails with a [JwtException] (a
///   401).
/// - Concurrent requests share one fetch.
///
/// Spring (Java): Nimbus' `RemoteJWKSet`, behind Spring's
/// `NimbusJwtDecoder`.
final class RemoteJwkSource implements JwkSource {
  /// A source for the JWK Set at [uri], fetched with [fetcher]
  /// ([defaultJwkFetcher] when omitted). [cacheLifespan] and
  /// [refreshInterval] are measured on a monotonic stopwatch, so a wall
  /// clock set back stretches neither; [clock] lets tests move time (a
  /// clock that goes back past a fetch ends them too).
  RemoteJwkSource(
    this.uri, {
    JwkFetcher? fetcher,
    this.cacheLifespan = const Duration(minutes: 5),
    this.refreshInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _fetch = fetcher ?? defaultJwkFetcher,
       _clock = clock ?? DateTime.now;

  /// The URL of the JWK Set.
  final Uri uri;

  /// How long fetched keys are used before fetching again; 5 minutes by
  /// default.
  final Duration cacheLifespan;

  /// The shortest time between two fetches, successful or not; 30
  /// seconds by default.
  final Duration refreshInterval;

  final JwkFetcher _fetch;
  final DateTime Function() _clock;
  List<VerificationKey>? _cached;
  // Measured on a monotonic stopwatch too: a wall clock set back would
  // keep the keys "fresh" and hold off the next fetch as long (a rotated
  // key refused for hours).
  Since? _fetched;
  // The last fetch, successful or not, and why it failed.
  Since? _attempted;
  Object? _failure;
  Future<List<VerificationKey>>? _inFlight;

  @override
  Future<List<VerificationKey>> keys({
    String? keyId,
    bool refresh = false,
  }) async {
    final now = _clock();
    final cached = _cached;
    final fetched = _fetched;
    final fresh =
        cached != null &&
        fetched != null &&
        !fetched.passed(cacheLifespan, now);
    final attempted = _attempted;
    final mayRefetch =
        attempted == null || attempted.passed(refreshInterval, now);
    if (fresh && !(refresh && mayRefetch)) {
      return cached;
    }
    if (!mayRefetch && _inFlight == null) {
      if (cached != null) {
        return cached;
      }
      // The last fetch failed a moment ago: not again before the interval.
      throw JwtException(
        "Couldn't retrieve remote JWK set: $_failure",
        _failure,
      );
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
    _attempted = Since(_clock());
    final List<VerificationKey> keys;
    try {
      keys = parseJwkSet(await _fetch(uri));
    } on Object catch (e) {
      _failure = e;
      rethrow;
    }
    _log.debug(
      () => 'Loaded ${keys.length} verification keys from ${_endpoint(uri)}',
    );
    _cached = keys;
    _fetched = Since(_clock());
    _failure = null;
    return keys;
  }
}

/// The standard [JwtDecoder]: it checks a signed JWT (a JWS) step by step
/// and returns it only when every step passes.
///
/// 1. The token is parsed strictly: never `alg: none`, no `crit`, no
///    nested or encrypted tokens, at most 64 KiB.
/// 2. Its `alg` must be one of [jwsAlgorithms] (by default those the keys
///    allow: RS* and PS* for RSA keys, the ES* of their curve for EC keys,
///    never HMAC) and must fit the key, so an RSA public key is never used
///    as an HMAC secret.
/// 3. The signature is checked with the key of its `kid`, or with every
///    fitting key when there is none. Keys named in the token (`jku`,
///    `jwk`, `x5u`) are ignored: a token cannot bring its own key.
/// 4. The token passes the [validator]: by default its type (`typ` is
///    `JWT` or absent, so a logout token or a DPoP proof signed with the
///    same key is no access token) and `exp` and `nbf` with 60 seconds of
///    skew.
///
/// A failure of steps 1 to 4 throws a [BadJwtException] (401
/// `invalid_token`). Build one with a factory: from the provider's JWK Set
/// URL, one public key, or a shared secret.
///
/// ```dart
/// @Bean()
/// JwtDecoder jwtDecoder() => NimbusJwtDecoder.withJwkSetUri(
///   Uri.parse('https://login.example.com/jwks'),
///   jwsAlgorithms: {JwsAlgorithm.rs256, JwsAlgorithm.es256},
///   validator: JwtValidators.createDefaultWithIssuer(
///     'https://login.example.com',
///   ),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// NimbusJwtDecoder decoder = NimbusJwtDecoder
///     .withJwkSetUri("https://login.example.com/jwks")
///     .jwsAlgorithm(SignatureAlgorithm.RS256)
///     .build();
/// decoder.setJwtValidator(
///     JwtValidators.createDefaultWithIssuer("https://login.example.com"));
/// ```
final class NimbusJwtDecoder implements JwtDecoder {
  NimbusJwtDecoder._(
    this._source, {
    Set<JwsAlgorithm>? jwsAlgorithms,
    OAuth2TokenValidator<Jwt>? validator,
  }) : jwsAlgorithms = jwsAlgorithms == null
           ? null
           : Set.unmodifiable(jwsAlgorithms),
       validator = validator ?? JwtValidators.createDefault();

  /// A decoder with the keys of the JWK Set at [jwkSetUri], fetched with
  /// [fetcher] and cached.
  ///
  /// [jwsAlgorithms] defaults to RS256 alone, Spring Boot's
  /// `jws-algorithms` default. Without a [validator] only the type and the
  /// lifetime are checked ([JwtValidators.createDefault]): add the issuer
  /// and audience checks yourself. Throws an
  /// [ArgumentError] for an empty set or an HMAC algorithm.
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

  /// A decoder for tokens signed with the private half of [key].
  ///
  /// [jwsAlgorithms] defaults to RS256. Throws an [ArgumentError] for an
  /// empty set or an HMAC algorithm.
  factory NimbusJwtDecoder.withPublicKey(
    RsaVerificationKey key, {
    Set<JwsAlgorithm> jwsAlgorithms = const {JwsAlgorithm.rs256},
    OAuth2TokenValidator<Jwt>? validator,
  }) => NimbusJwtDecoder._(
    StaticJwkSource([key]),
    jwsAlgorithms: _asymmetric(jwsAlgorithms),
    validator: validator,
  );

  /// A decoder for tokens signed with the shared [secret], for systems
  /// where the issuer and this server share one key.
  ///
  /// [macAlgorithm] defaults to HS256. Throws an [ArgumentError] when it is
  /// not an HMAC algorithm, or when [secret] has fewer bits than its hash
  /// (256 for HS256).
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

  /// A decoder with the keys of [source]; without [jwsAlgorithms], the
  /// algorithms the keys allow (never HMAC).
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

  /// The algorithms accepted in a token's `alg`; `null` accepts those the
  /// keys allow, never HMAC.
  final Set<JwsAlgorithm>? jwsAlgorithms;

  /// Checks the claims of a correctly signed token.
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

/// Builds a [JwtDecoder] from the address of an identity provider alone.
///
/// Spring (Java): `JwtDecoders`.
abstract final class JwtDecoders {
  /// A decoder for the tokens of [issuer], such as
  /// `https://login.example.com/realms/shop`.
  ///
  /// The issuer's OpenID Connect (or OAuth 2.0 authorization server)
  /// metadata gives the JWK Set URL; the `issuer` named there must equal
  /// [issuer]. Tokens must carry `iss` equal to [issuer], pass the type
  /// and lifetime checks ([JwtValidators.createDefault]), and, when
  /// [audiences] is not empty, name one of them in `aud`. The algorithms
  /// are those the keys allow.
  ///
  /// The metadata is looked up where the OAuth2 client's
  /// `ClientRegistrations.fromIssuerLocation` looks (the same code):
  /// `<issuer>/.well-known/openid-configuration`, then
  /// `/.well-known/openid-configuration<issuer path>` and
  /// `/.well-known/oauth-authorization-server<issuer path>`; a location
  /// [fetcher] cannot read moves to the next.
  ///
  /// The metadata is fetched at the first token, not at startup, so the
  /// provider may start later. While it cannot be fetched, tokens fail
  /// with a [JwtException] (a 401); a failed lookup is made again
  /// [retryInterval] (30 seconds) later at the earliest, so a provider
  /// that is down gets no requests per token. The pause is measured on a
  /// monotonic stopwatch, so a wall clock set back never stretches it;
  /// [clock] lets tests move time.
  static JwtDecoder fromIssuerLocation(
    String issuer, {
    JwkFetcher? fetcher,
    List<String> audiences = const [],
    Duration retryInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) => _IssuerJwtDecoder(
    issuer,
    fetcher ?? defaultJwkFetcher,
    audiences,
    retryInterval,
    clock ?? DateTime.now,
  );
}

final class _IssuerJwtDecoder implements JwtDecoder {
  _IssuerJwtDecoder(
    this.issuer,
    this.fetcher,
    this.audiences,
    this.retryInterval,
    this.clock,
  );

  final String issuer;
  final JwkFetcher fetcher;
  final List<String> audiences;
  final Duration retryInterval;
  final DateTime Function() clock;
  Future<JwtDecoder>? _delegate;
  // The last failed lookup: when (on a monotonic stopwatch too, so a
  // wall clock set back does not stretch the pause), and why.
  (Since, Object)? _failure;

  @override
  Future<Jwt> decode(String token) async {
    final failure = _failure;
    if (_delegate == null &&
        failure != null &&
        !failure.$1.passed(retryInterval, clock())) {
      throw JwtException(
        'Unable to resolve the issuer $issuer: ${failure.$2}',
        failure.$2,
      );
    }
    final pending = _delegate ??= _discover();
    final JwtDecoder delegate;
    try {
      delegate = await pending;
    } on Object catch (e) {
      if (identical(_delegate, pending)) {
        _delegate = null; // tried again after the retry interval
        _failure = (Since(clock()), e);
      }
      throw JwtException('Unable to resolve the issuer $issuer: $e', e);
    }
    _failure = null;
    return await delegate.decode(token);
  }

  // The client's discovery (ClientRegistrations), so the resource server
  // and the login look for the metadata in the same places and check the
  // issuer the same way. A location the fetcher cannot read (an error
  // answer, a 404 included, or no JSON object) moves to the next.
  Future<JwtDecoder> _discover() async {
    Object? lastError;
    final configuration =
        await ClientRegistrations.configurationForIssuerLocation(
          issuer,
          fetch: (uri) async {
            try {
              final metadata = jsonDecode(await fetcher(uri));
              return metadata is Map<String, Object?> ? metadata : null;
            } on Object catch (e) {
              lastError = e;
              return null;
            }
          },
        );
    if (configuration == null) {
      throw JwtException('No metadata for issuer $issuer: $lastError');
    }
    final jwksUri = configuration.metadata['jwks_uri'];
    if (jwksUri is! String) {
      throw JwtException('The issuer metadata has no jwks_uri');
    }
    return NimbusJwtDecoder.withJwkSource(
      RemoteJwkSource(Uri.parse(jwksUri), fetcher: fetcher, clock: clock),
      validator: DelegatingOAuth2TokenValidator([
        JwtTypeValidator.jwt(),
        JwtTimestampValidator(),
        JwtIssuerValidator(issuer),
        if (audiences.isNotEmpty) JwtAudienceValidator(audiences),
      ]),
    );
  }
}

// The host and the path: a query can hold a key or a token.
String _endpoint(Uri uri) => '${uri.host}${uri.path}';
