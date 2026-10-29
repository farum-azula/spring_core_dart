import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show
        DPoPProofClaims,
        DelegatingOAuth2TokenValidator,
        JwkThumbprint,
        OAuth2AuthenticationException,
        OAuth2Error,
        OAuth2ErrorCodes,
        OAuth2TokenValidator,
        OAuth2TokenValidatorResult,
        sha256Base64Url;
import 'package:spring_boot_starter_security/src/jwt/bearer.dart';
import 'package:spring_boot_starter_security/src/jwt/jose.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt_decoder.dart';
import 'package:spring_boot_starter_security/src/web/authentication.dart';
import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/filter_chain.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// The OAuth 2.0 error of a refused DPoP proof (RFC 9449 §7.1).
///
/// Spring (Java): `OAuth2ErrorCodes.INVALID_DPOP_PROOF`.
const String invalidDPoPProof = 'invalid_dpop_proof';

/// The name of the request header that carries a DPoP proof.
const String dPoPHeaderName = 'DPoP';

/// The longest DPoP proof accepted, in characters: 8 KiB.
///
/// A proof is a few hundred characters (an RSA 4096 one about 2 000), so
/// anything longer is refused before any decoding work.
const int maxDPoPProofLength = 8 * 1024;

/// The algorithms DPoP proofs may be signed with, by default: every
/// public-key algorithm, never `none` or a shared secret (HS*).
///
/// Spring (Java): the `algs` of `DPoPAuthenticationConfigurer`.
const Set<JwsAlgorithm> defaultDPoPAlgorithms = {
  JwsAlgorithm.rs256,
  JwsAlgorithm.rs384,
  JwsAlgorithm.rs512,
  JwsAlgorithm.ps256,
  JwsAlgorithm.ps384,
  JwsAlgorithm.ps512,
  JwsAlgorithm.es256,
  JwsAlgorithm.es384,
  JwsAlgorithm.es512,
};

/// What a DPoP proof is checked against: the proof itself and the request
/// it came with.
///
/// A proof is valid for one request only: its `htm` and `htu` claims must
/// name the request's method and URL, and on a call with an access token
/// its `ath` claim must be the hash of that token. The
/// [DPoPAuthenticationProvider] builds one per request and hands it to
/// the [DPoPProofJwtDecoderFactory]; applications only meet it when they
/// write their own proof validators.
///
/// ```dart
/// // Proofs must also carry the nonce this server handed out.
/// DPoPProofJwtDecoderFactory(
///   jwtValidatorFactory: (context) => DelegatingOAuth2TokenValidator([
///     DPoPProofJwtDecoderFactory.defaultValidator(context),
///     JwtClaimValidator('nonce', nonces.isCurrent),
///   ]),
/// );
/// ```
///
/// Spring (Java): `DPoPProofContext`, built with
/// `DPoPProofContext.withDPoPProof(proof).method(...).targetUri(...)`.
final class DPoPProofContext {
  /// The context of [dPoPProof] sent with a [method] request to
  /// [targetUri], with [accessToken] when the request carried one.
  const DPoPProofContext(
    this.dPoPProof, {
    required this.method,
    required this.targetUri,
    this.accessToken,
  });

  /// The proof, as sent in the `DPoP` header; never log it.
  final String dPoPProof;

  /// The HTTP method of the request, such as `GET`.
  final String method;

  /// The URL the client called: scheme, host and port as the request
  /// reached the server (its `Host` header), and the path.
  final Uri targetUri;

  /// The access token the request carried, or `null` (a proof sent to a
  /// token endpoint); a credential, never log it.
  final String? accessToken;

  /// A description for logs, without the proof and the token.
  @override
  String toString() =>
      'DPoPProofContext [method=$method, targetUri=$targetUri]';
}

/// Remembers the ids (`jti`) of the DPoP proofs already used, so that a
/// proof caught on the way cannot be sent again.
///
/// Each id is kept until its proof's time window ends (`iat` plus the
/// clock skew); after that the proof is too old to be accepted anyway.
/// The default, [InMemoryDPoPProofJtiCache], keeps them in this process:
/// enough for one server. Behind a load balancer with several instances
/// (or isolates), a replayed proof could reach another one; implement
/// this with a shared store (Redis, a database) for that, as you would
/// for sessions, and pass it to the [DPoPProofJwtDecoderFactory].
///
/// Spring (Java): the `Cache` given to `DPoPProofReplayValidator`
/// (Spring Security 7), whose default is its `InMemoryCache`.
abstract interface class DPoPProofJtiCache {
  /// Records [jti] of a proof signed by the key [jwkThumbprint] as used
  /// until [expiresAt]; `true` when it was not used before, `false` for a
  /// replay.
  ///
  /// [jti] is already hashed (base64url SHA-256), so its length is fixed.
  /// Return `false` as well when the id cannot be recorded (a full store,
  /// too many ids of one key): the proof is then refused, never let
  /// through. A store that cannot be reached may throw; the proof is
  /// refused too.
  FutureOr<bool> markUsed(
    String jti,
    DateTime expiresAt, {
    required String jwkThumbprint,
  });
}

/// The default [DPoPProofJtiCache]: the ids in a map of this process, at
/// most [maximumSize] of them and [maximumPerKey] per client key.
///
/// Expired ids are dropped every 10 seconds, and at once when the map is
/// full. When it is still full of ids in their window, new proofs are
/// refused (a 401) until room frees up, rather than forgetting ids early,
/// which would let their proofs be replayed. The limit per key keeps one
/// client from filling the map for everyone. Size it for the proofs one
/// instance gets in a time window (twice the clock skew).
///
/// Spring (Java): `DPoPProofReplayValidator.InMemoryCache`, with the same
/// limits (100 000 entries, 1 000 per key).
final class InMemoryDPoPProofJtiCache implements DPoPProofJtiCache {
  /// A cache of at most [maximumSize] ids (100 000 by default) and
  /// [maximumPerKey] per key (1 000); [clock] gives the current time
  /// (`DateTime.now` by default), so tests can move it.
  InMemoryDPoPProofJtiCache({
    this.maximumSize = 100000,
    this.maximumPerKey = 1000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maximumSize < 1) {
      throw ArgumentError.value(maximumSize, 'maximumSize', 'must be > 0');
    }
    if (maximumPerKey < 1) {
      throw ArgumentError.value(maximumPerKey, 'maximumPerKey', 'must be > 0');
    }
  }

  /// How many ids the cache holds at most.
  final int maximumSize;

  /// How many ids of one client key the cache holds at most.
  final int maximumPerKey;

  final DateTime Function() _clock;
  final _entries = <String, (DateTime, String)>{};
  final _perKey = <String, int>{};
  DateTime? _purgedAt;

  /// How many ids are held now, expired ones not yet dropped included.
  int get size => _entries.length;

  @override
  bool markUsed(
    String jti,
    DateTime expiresAt, {
    required String jwkThumbprint,
  }) {
    final now = _clock().toUtc();
    final seen = _entries[jti];
    if (seen != null && seen.$1.isAfter(now)) {
      return false;
    }
    final purgedAt = _purgedAt;
    final full =
        _entries.length >= maximumSize ||
        (_perKey[jwkThumbprint] ?? 0) >= maximumPerKey;
    if (purgedAt == null ||
        now.difference(purgedAt) >= const Duration(seconds: 10) ||
        (full &&
            now.difference(purgedAt) >= const Duration(milliseconds: 50))) {
      _purge(now);
    }
    if (_entries.length >= maximumSize ||
        (_perKey[jwkThumbprint] ?? 0) >= maximumPerKey) {
      return false;
    }
    _remove(jti);
    _entries[jti] = (expiresAt.toUtc(), jwkThumbprint);
    _perKey.update(jwkThumbprint, (n) => n + 1, ifAbsent: () => 1);
    return true;
  }

  void _purge(DateTime now) {
    [
      for (final MapEntry(:key, :value) in _entries.entries)
        if (!value.$1.isAfter(now)) key,
    ].forEach(_remove);
    _purgedAt = now;
  }

  void _remove(String jti) {
    final removed = _entries.remove(jti);
    if (removed == null) {
      return;
    }
    final left = (_perKey[removed.$2] ?? 1) - 1;
    if (left <= 0) {
      _perKey.remove(removed.$2);
    } else {
      _perKey[removed.$2] = left;
    }
  }
}

/// Builds, for each request, the [JwtDecoder] that checks its DPoP
/// proof.
///
/// A proof is a JWT the client signs with its own key for one request. It
/// is checked like this, and refused (a [BadJwtException]) at the first
/// failure:
///
/// 1. At most [maxDPoPProofLength] characters, parsed strictly (no
///    `crit`, no nested or encrypted tokens).
/// 2. The header: `typ` exactly `dpop+jwt`; `alg` one of [jwsAlgorithms]
///    (never `none` or HS*); `jwk` the public key, EC (P-256, P-384,
///    P-521, on its curve) or RSA (2 048 to 8 192 bits). A `jwk` with a
///    private member (`d`, `p`, `q`, ...) or a symmetric key is refused.
/// 3. The signature, with that `jwk` and nothing else.
/// 4. The claims, read strictly ([DPoPProofClaims.fromJson]), then the
///    validators of the `jwtValidatorFactory` (by default
///    [defaultValidator]:
///    `htm`, `htu`, `iat` within [clockSkew], and `ath` when the request
///    has an access token).
/// 5. The `jti` was not used before ([jtiCache]); it is recorded only now,
///    for a proof that passed everything else.
///
/// Whether the key is the one the access token is bound to (`cnf.jkt`)
/// is checked by the [DPoPAuthenticationProvider].
///
/// The resource server makes one by itself; declare a bean of this type
/// to change the clock skew, the algorithms or the `jti` store.
///
/// ```dart
/// // Two instances behind a load balancer share the used proof ids.
/// @Bean()
/// DPoPProofJwtDecoderFactory dPoPProofs(RedisJtiCache cache) =>
///     DPoPProofJwtDecoderFactory(jtiCache: cache);
/// ```
///
/// Spring (Java): `DPoPProofJwtDecoderFactory`, a
/// `JwtDecoderFactory<DPoPProofContext>`.
final class DPoPProofJwtDecoderFactory {
  /// A factory accepting proofs signed with [jwsAlgorithms] and made
  /// within [clockSkew] (30 seconds, as in Spring Security 7) of [clock]'s
  /// time,
  /// remembering their ids in [jtiCache] (a new
  /// [InMemoryDPoPProofJtiCache] by default).
  ///
  /// Throws an [ArgumentError] for an empty set of algorithms or an HMAC
  /// one.
  DPoPProofJwtDecoderFactory({
    Set<JwsAlgorithm> jwsAlgorithms = defaultDPoPAlgorithms,
    this.clockSkew = const Duration(seconds: 30),
    DPoPProofJtiCache? jtiCache,
    DateTime Function()? clock,
    OAuth2TokenValidator<Jwt> Function(DPoPProofContext context)?
    jwtValidatorFactory,
  }) : jwsAlgorithms = Set.unmodifiable(jwsAlgorithms),
       _clock = clock ?? DateTime.now,
       jtiCache = jtiCache ?? InMemoryDPoPProofJtiCache(clock: clock),
       _validatorFactory = jwtValidatorFactory {
    if (jwsAlgorithms.isEmpty || jwsAlgorithms.any((a) => a.isMac)) {
      throw ArgumentError('DPoP proofs use RS*, PS* and ES* algorithms only');
    }
  }

  /// The algorithms a proof may be signed with.
  final Set<JwsAlgorithm> jwsAlgorithms;

  /// How far a proof's `iat` may be from this server's clock, either way;
  /// also how long its `jti` is remembered after `iat`.
  final Duration clockSkew;

  /// Where the ids of used proofs are kept.
  final DPoPProofJtiCache jtiCache;

  final DateTime Function() _clock;
  final OAuth2TokenValidator<Jwt> Function(DPoPProofContext)? _validatorFactory;

  /// The decoder of the proof of [context]: it returns the proof as a
  /// [Jwt] (its header holds the client's `jwk`) or throws a
  /// [BadJwtException].
  JwtDecoder createDecoder(DPoPProofContext context) => _DPoPProofJwtDecoder(
    this,
    context,
    _validatorFactory?.call(context) ??
        defaultValidator(context, clockSkew: clockSkew, clock: _clock),
  );

  /// The claim checks of a proof for [context]: `htm` equal to the
  /// request's method; `htu` equal to its URL (scheme, host, port and
  /// path, compared after RFC 3986 normalization, query and fragment
  /// ignored as RFC 9449 §4.3 says); `iat` within [clockSkew] of now; and
  /// when [DPoPProofContext.accessToken] is set, `ath` equal to its
  /// base64url SHA-256.
  ///
  /// Start from it when adding checks of your own.
  static OAuth2TokenValidator<Jwt> defaultValidator(
    DPoPProofContext context, {
    Duration clockSkew = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) => DelegatingOAuth2TokenValidator([
    _DPoPProofClaimsValidator(context, clockSkew, clock ?? DateTime.now),
  ]);
}

OAuth2TokenValidatorResult _proofFailure(String description) =>
    OAuth2TokenValidatorResult.failure(
      OAuth2Error(invalidDPoPProof, description),
    );

final class _DPoPProofClaimsValidator implements OAuth2TokenValidator<Jwt> {
  _DPoPProofClaimsValidator(this.context, this.clockSkew, this.clock);

  final DPoPProofContext context;
  final Duration clockSkew;
  final DateTime Function() clock;

  @override
  OAuth2TokenValidatorResult validate(Jwt token) {
    final DPoPProofClaims claims;
    try {
      claims = DPoPProofClaims.fromJson(token.claims);
    } on FormatException catch (e) {
      return _proofFailure(e.message);
    }
    if (claims.htm != context.method) {
      return _proofFailure('The htm claim is not valid');
    }
    final target = normalizedDPoPTarget(context.targetUri);
    if (target == null || normalizedDPoPTarget(claims.htu) != target) {
      return _proofFailure('The htu claim is not valid');
    }
    final now = clock().toUtc();
    if (claims.iat.isBefore(now.subtract(clockSkew)) ||
        claims.iat.isAfter(now.add(clockSkew))) {
      return _proofFailure('The iat claim is not valid');
    }
    final accessToken = context.accessToken;
    if (accessToken != null) {
      final ath = claims.ath;
      if (ath == null) {
        return _proofFailure('The ath claim is required');
      }
      if (!constantTimeEquals(
        utf8.encode(ath),
        utf8.encode(sha256Base64Url(accessToken)),
      )) {
        return _proofFailure('The ath claim is not valid');
      }
    }
    return OAuth2TokenValidatorResult.success;
  }
}

/// [uri] as the `htu` of a DPoP proof is compared (RFC 9449 §4.3):
/// `scheme://host[:port]/path`, scheme and host in lower case, the
/// default port left out, percent-encoding and dot segments normalized
/// (RFC 3986 §6.2.2 and §6.2.3), an empty path as `/`, query and fragment
/// dropped.
///
/// `null` for a URL that is not absolute `http` or `https`, or carries
/// user information: such a target never matches.
String? normalizedDPoPTarget(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  // Uri.parse already normalizes percent-encoding and dot segments; this
  // parses again so a Uri built by hand is normalized too.
  final Uri parsed;
  try {
    parsed = Uri.parse(uri.toString());
  } on FormatException {
    return null;
  }
  final defaultPort = scheme == 'https' ? 443 : 80;
  final port = parsed.hasPort && parsed.port != defaultPort
      ? ':${parsed.port}'
      : '';
  final path = parsed.path.isEmpty ? '/' : parsed.path;
  return '$scheme://${parsed.host.toLowerCase()}$port$path';
}

const _privateJwkMembers = ['d', 'p', 'q', 'dp', 'dq', 'qi', 'oth', 'k'];

final class _DPoPProofJwtDecoder implements JwtDecoder {
  _DPoPProofJwtDecoder(this.factory, this.context, this.validator);

  final DPoPProofJwtDecoderFactory factory;
  final DPoPProofContext context;
  final OAuth2TokenValidator<Jwt> validator;

  @override
  Future<Jwt> decode(String token) async {
    if (token.length > maxDPoPProofLength) {
      throw BadJwtException('The DPoP proof is too long');
    }
    final ParsedJws jws;
    try {
      jws = parseJws(token);
    } on JoseException catch (e) {
      throw BadJwtException(e.message, e);
    }
    if (jws.header['typ'] != 'dpop+jwt') {
      throw BadJwtException('The DPoP proof typ header is not dpop+jwt');
    }
    final algorithm = JwsAlgorithm.from(jws.algorithmName!);
    if (algorithm == null || !factory.jwsAlgorithms.contains(algorithm)) {
      throw BadJwtException('The DPoP proof alg is not supported');
    }
    final jwk = jws.header['jwk'];
    if (jwk is! Map<String, Object?>) {
      throw BadJwtException('The DPoP proof has no jwk header');
    }
    final key = _publicKey(jwk);
    if (!verifySignature(jws, algorithm, key)) {
      throw BadJwtException('The DPoP proof signature is not valid');
    }
    final jwt = Jwt(token, headers: jws.header, claims: jws.claims);
    final DPoPProofClaims claims;
    try {
      claims = DPoPProofClaims.fromJson(jws.claims);
    } on FormatException catch (e) {
      throw BadJwtException(e.message, e);
    }
    final result = validator.validate(jwt);
    if (result.hasErrors) {
      throw JwtValidationException(
        result.errors.map((e) => e.description ?? e.errorCode).join(', '),
        result.errors,
      );
    }
    final bool fresh;
    try {
      fresh = await factory.jtiCache.markUsed(
        sha256Base64Url(claims.jti),
        claims.iat.add(factory.clockSkew),
        jwkThumbprint: JwkThumbprint.of(jwk),
      );
    } on Object catch (e) {
      throw JwtException('The DPoP proof id could not be recorded', e);
    }
    if (!fresh) {
      throw BadJwtException('The jti claim is not valid');
    }
    return jwt;
  }

  // The client's public key from the proof's own header: EC or RSA,
  // public members only, a size and shape that verify cheaply.
  static VerificationKey _publicKey(Map<String, Object?> jwk) {
    for (final member in _privateJwkMembers) {
      if (jwk.containsKey(member)) {
        throw BadJwtException('The DPoP proof jwk is not a public key');
      }
    }
    final use = jwk['use'];
    final alg = jwk['alg'];
    if ((use != null && use != 'sig') || (alg != null && alg is! String)) {
      throw BadJwtException('The DPoP proof jwk is not a signature key');
    }
    try {
      switch (jwk) {
        case {
          'kty': 'EC',
          'crv': final String crv,
          'x': final String x,
          'y': final String y,
        }:
          final key = EcVerificationKey(
            crv,
            base64UrlToBigInt(x),
            base64UrlToBigInt(y),
            algorithm: alg as String?,
          );
          if (key.isOnCurve) {
            return key;
          }
        case {'kty': 'RSA', 'n': final String n, 'e': final String e}:
          final modulus = base64UrlToBigInt(n);
          final exponent = base64UrlToBigInt(e);
          if (modulus.bitLength >= 2048 &&
              modulus.bitLength <= 8192 &&
              exponent.isOdd &&
              exponent > BigInt.one &&
              exponent.bitLength <= 64) {
            return RsaVerificationKey(
              modulus,
              exponent,
              algorithm: alg as String?,
            );
          }
      }
    } on JoseException {
      // malformed base64url: refused below
    }
    throw BadJwtException('The DPoP proof jwk is not a supported public key');
  }
}

/// The login request of a DPoP-bound access token: the token, its proof
/// and the request they came with, none of it checked yet.
///
/// The DPoP filter builds one for each request with
/// `Authorization: DPoP <token>` and passes it to the
/// [DPoPAuthenticationProvider], which returns the same
/// [JwtAuthenticationToken] a `Bearer` token gives.
///
/// Spring (Java): `DPoPAuthenticationToken`.
final class DPoPAuthenticationToken extends AbstractAuthenticationToken {
  /// The login request of [accessToken] with [dPoPProof], sent with a
  /// [method] request to [resourceUri].
  DPoPAuthenticationToken(
    this.accessToken,
    this.dPoPProof, {
    required this.method,
    required this.resourceUri,
  });

  /// The access token, as sent after `DPoP `; never log it.
  final String accessToken;

  /// The proof of the `DPoP` header; never log it.
  final String dPoPProof;

  /// The HTTP method of the request, such as `GET`.
  final String method;

  /// The URL of the request, without query.
  final Uri resourceUri;

  @override
  Object get principal => accessToken;

  @override
  Object get credentials => dPoPProof;

  /// Always `''`, so the token never appears where a name is shown or
  /// logged.
  @override
  String get name => '';
}

/// The [AuthenticationProvider] of DPoP-bound access tokens (RFC 9449):
/// the token must be valid and the request's proof signed by the key the
/// token is bound to.
///
/// For a [DPoPAuthenticationToken] it:
///
/// 1. checks the access token with [tokenAuthenticationManager], the one
///    `Bearer` tokens go through (signature, `iss`, `aud`, `exp`); a
///    refused token fails as for `Bearer`, `invalid_token`;
/// 2. checks the proof with a decoder of [dPoPProofVerifierFactory]
///    (`typ`, algorithm, signature, `htm`, `htu`, `iat`, `ath`, `jti`);
/// 3. compares the RFC 7638 thumbprint of the proof's key with the
///    token's `cnf.jkt` claim; a token without it is not DPoP-bound and is
///    refused.
///
/// A failure of 2 or 3 is an [OAuth2AuthenticationException] with
/// `invalid_dpop_proof`. On success it returns what step 1 returned,
/// usually a [JwtAuthenticationToken], so controllers, `@PreAuthorize`
/// and `@AuthenticationPrincipal() Jwt` work as for `Bearer` tokens.
/// `oauth2ResourceServer((s) => s.jwt())` sets it up.
///
/// Spring (Java): `DPoPAuthenticationProvider`.
final class DPoPAuthenticationProvider implements AuthenticationProvider {
  /// A provider checking access tokens with [tokenAuthenticationManager]
  /// and proofs with [dPoPProofVerifierFactory] (a default
  /// [DPoPProofJwtDecoderFactory] when omitted).
  DPoPAuthenticationProvider(
    this.tokenAuthenticationManager, {
    DPoPProofJwtDecoderFactory? dPoPProofVerifierFactory,
  }) : dPoPProofVerifierFactory =
           dPoPProofVerifierFactory ?? DPoPProofJwtDecoderFactory();

  /// Checks the access token, as for `Bearer` tokens.
  final AuthenticationManager tokenAuthenticationManager;

  /// Makes the decoder of each request's proof.
  final DPoPProofJwtDecoderFactory dPoPProofVerifierFactory;

  @override
  bool supports(Authentication authentication) =>
      authentication is DPoPAuthenticationToken;

  @override
  Future<Authentication?> authenticate(Authentication authentication) async {
    final request = authentication as DPoPAuthenticationToken;
    final result = await tokenAuthenticationManager.authenticate(
      BearerTokenAuthenticationToken(request.accessToken)
        ..details = request.details,
    );
    final principal = result.principal;
    if (principal is! Jwt) {
      throw OAuth2AuthenticationException(
        const OAuth2Error(
          OAuth2ErrorCodes.invalidToken,
          'Unable to authenticate the DPoP-bound access token.',
        ),
      );
    }
    final decoder = dPoPProofVerifierFactory.createDecoder(
      DPoPProofContext(
        request.dPoPProof,
        method: request.method,
        targetUri: request.resourceUri,
        accessToken: request.accessToken,
      ),
    );
    final Jwt proof;
    try {
      proof = await decoder.decode(request.dPoPProof);
    } on JwtException catch (e) {
      throw OAuth2AuthenticationException(
        OAuth2Error(invalidDPoPProof, e.message),
        e.message,
        e,
      );
    }
    final jkt = principal.jwkThumbprint;
    if (jkt == null) {
      throw OAuth2AuthenticationException(
        const OAuth2Error(invalidDPoPProof, 'The jkt claim is required'),
      );
    }
    final String thumbprint;
    try {
      thumbprint = JwkThumbprint.of(
        proof.headers['jwk']! as Map<String, Object?>,
      );
    } on FormatException catch (e) {
      throw OAuth2AuthenticationException(
        const OAuth2Error(invalidDPoPProof, 'The jkt claim is not valid'),
        null,
        e,
      );
    }
    if (!constantTimeEquals(utf8.encode(thumbprint), utf8.encode(jkt))) {
      throw OAuth2AuthenticationException(
        const OAuth2Error(invalidDPoPProof, 'The jkt claim is not valid'),
      );
    }
    return result;
  }
}

String _dPoPChallenge(OAuth2Error? error, String algorithms) {
  final parameters = <String>[
    if (error != null) ...[
      'error="${error.errorCode}"',
      if (error.description != null)
        'error_description="${error.description!.replaceAll('"', "'")}"',
      if (error.uri != null) 'error_uri="${error.uri}"',
    ],
    'algs="$algorithms"',
  ];
  return 'DPoP ${parameters.join(', ')}';
}

/// The [AuthenticationEntryPoint] of DPoP requests: a `401` with a
/// `WWW-Authenticate: DPoP` challenge naming the error and the accepted
/// algorithms.
///
/// `error="invalid_dpop_proof"` when the proof was refused,
/// `error="invalid_token"` when the access token was, and
/// `error="invalid_request"` when the request had no proof or two. The
/// body is the usual `ProblemDetail`.
///
/// ```text
/// WWW-Authenticate: DPoP error="invalid_dpop_proof",
///     error_description="The htu claim is not valid",
///     algs="RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512"
/// ```
///
/// Spring (Java): the `DPoPAuthenticationEntryPoint` of
/// `DPoPAuthenticationConfigurer`.
final class DPoPAuthenticationEntryPoint implements AuthenticationEntryPoint {
  /// An entry point announcing [algorithms] in the `algs` parameter.
  const DPoPAuthenticationEntryPoint({
    this.algorithms = defaultDPoPAlgorithms,
  });

  /// The algorithms named in the challenge.
  final Set<JwsAlgorithm> algorithms;

  @override
  Future<void> commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  ) {
    final error = authException is OAuth2AuthenticationException
        ? authException.error
        : null;
    return writeSecurityProblem(
      request,
      response,
      HttpStatus.unauthorized,
      'Full authentication is required to access this resource',
      headers: {
        HttpHeaders.wwwAuthenticateHeader: _dPoPChallenge(
          error,
          algorithms.map((a) => a.name).join(' '),
        ),
      },
    );
  }
}

/// The filter of DPoP-bound access tokens: requests with
/// `Authorization: DPoP <token>` and a `DPoP` proof header.
///
/// `oauth2ResourceServer((s) => s.jwt())` adds it, just before the
/// [BearerTokenAuthenticationFilter], so an API accepts both kinds of
/// tokens. For each request:
///
/// - no `Authorization` header, another scheme, or more than one header:
///   the filter does nothing (the bearer filter refuses the last);
/// - `Authorization: DPoP` with a malformed token: `invalid_token`;
///   without a `DPoP` header, or with two: `invalid_request`;
/// - otherwise the [authenticationManager] checks token and proof (a
///   [DPoPAuthenticationProvider]); a valid pair logs the request in for
///   this request only, a refused one is answered by the
///   [authenticationEntryPoint], a 401 with a `DPoP` challenge.
///
/// A `DPoP` header next to `Authorization: Bearer` is ignored here, as in
/// Spring: an unbound token stays a `Bearer` token, and a bound one is
/// refused by the bearer filter.
///
/// Spring (Java): the `AuthenticationFilter` that
/// `DPoPAuthenticationConfigurer` adds, with its
/// `DPoPAuthenticationConverter`.
final class DPoPAuthenticationFilter implements WebFilter {
  /// A filter checking DPoP requests with [authenticationManager]; the
  /// context is kept for the current request only by default.
  const DPoPAuthenticationFilter(
    this.authenticationManager, {
    this.authenticationEntryPoint = const DPoPAuthenticationEntryPoint(),
    this.securityContextRepository =
        const RequestAttributeSecurityContextRepository(),
  });

  /// Checks token and proof, usually with a [DPoPAuthenticationProvider].
  final AuthenticationManager authenticationManager;

  /// Answers a refused request.
  final AuthenticationEntryPoint authenticationEntryPoint;

  /// Where the context of a valid request is saved; the request only, by
  /// default.
  final SecurityContextRepository securityContextRepository;

  static final _token = RegExp(
    r'^DPoP (?<token>[a-zA-Z0-9\-._~+/]+=*)$',
    caseSensitive: false,
  );

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    final authorization = request.headers.getAll(
      HttpHeaders.authorizationHeader,
    );
    if (authorization.length != 1 ||
        !authorization.single.toLowerCase().startsWith('dpop')) {
      return await chain.doFilter(request, response);
    }
    final Authentication result;
    try {
      final match = _token.firstMatch(authorization.single);
      if (match == null) {
        throw OAuth2AuthenticationException(
          const OAuth2Error(
            OAuth2ErrorCodes.invalidToken,
            'DPoP access token is malformed.',
          ),
        );
      }
      final proofs = request.headers.getAll(dPoPHeaderName);
      if (proofs.length != 1 ||
          proofs.single.isEmpty ||
          proofs.single.length > maxDPoPProofLength) {
        throw OAuth2AuthenticationException(
          const OAuth2Error(
            OAuth2ErrorCodes.invalidRequest,
            'DPoP proof is missing or invalid.',
          ),
        );
      }
      final uri = request.uri;
      result = await authenticationManager.authenticate(
        DPoPAuthenticationToken(
          match.namedGroup('token')!,
          proofs.single,
          method: request.method.value,
          resourceUri: Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: uri.path,
          ),
        )..details = WebAuthenticationDetails.of(request),
      );
    } on AuthenticationException catch (e) {
      SecurityContextHolder.clearContext();
      await authenticationEntryPoint.commence(request, response, e);
      return;
    }
    final context = SecurityContextHolder.createEmptyContext()
      ..authentication = result;
    SecurityContextHolder.setContext(context);
    await securityContextRepository.saveContext(context, request, response);
    await chain.doFilter(request, response);
  }
}
