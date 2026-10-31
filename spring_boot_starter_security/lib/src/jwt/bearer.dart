import 'dart:async';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show OAuth2AuthenticationException, OAuth2Error;
import 'package:spring_boot_starter_security/src/jwt/jwt.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt_decoder.dart';
import 'package:spring_boot_starter_security/src/web/authentication.dart';
import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/filter_chain.dart';
import 'package:spring_boot_starter_security/src/web/log_support.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog(
  'spring.security.oauth2.server.resource.web.BearerTokenAuthenticationFilter',
);

const _rfc6750 = 'https://tools.ietf.org/html/rfc6750#section-3.1';

/// A request was refused because its bearer token is malformed, expired,
/// wrongly signed or otherwise not acceptable.
///
/// The client gets a 401 with
/// `WWW-Authenticate: Bearer error="invalid_token"` and the description.
///
/// Spring (Java): `InvalidBearerTokenException`.
class InvalidBearerTokenException extends OAuth2AuthenticationException {
  /// An `invalid_token` error with [description], which is sent to the
  /// client in the `WWW-Authenticate` header.
  InvalidBearerTokenException(String description, [Object? cause])
    : super(
        OAuth2Error('invalid_token', description, _rfc6750),
        description,
        cause,
      );
}

/// The login request of a bearer token: the raw token as the request
/// sent it, not checked yet.
///
/// The bearer-token filter passes it to the `AuthenticationManager`,
/// whose [JwtAuthenticationProvider] returns a [JwtAuthenticationToken].
/// Write an `AuthenticationProvider` for it to accept opaque tokens.
///
/// Spring (Java): `BearerTokenAuthenticationToken`.
final class BearerTokenAuthenticationToken extends AbstractAuthenticationToken {
  /// A login request for [token].
  BearerTokenAuthenticationToken(this.token);

  /// The raw token, as sent after `Bearer `.
  final String token;

  @override
  Object get principal => token;

  @override
  Object get credentials => token;

  /// Always `''`, so the token never appears where a name is shown or
  /// logged.
  @override
  String get name => '';
}

/// The `Authentication` of a request with a valid JWT bearer token.
///
/// The principal is the decoded [Jwt], the name its `sub` claim (or the
/// claim set by `principal-claim-name`), and the authorities come from
/// its scopes (`SCOPE_read`). A controller gets it as an `Authentication`
/// parameter, or the token itself with `@AuthenticationPrincipal() Jwt`.
///
/// ```dart
/// @GetMapping('/me')
/// String me(Authentication authentication) =>
///     (authentication as JwtAuthenticationToken).tokenAttributes['email']
///         as String;
/// ```
///
/// Spring (Java): `JwtAuthenticationToken`.
final class JwtAuthenticationToken extends AbstractAuthenticationToken {
  /// An authenticated token for [jwt] with [authorities]; [name] defaults
  /// to the `sub` claim, else `''`.
  JwtAuthenticationToken(
    this.jwt,
    Iterable<GrantedAuthority> authorities, {
    String? name,
  }) : _name = name ?? jwt.subject ?? '',
       super(authorities) {
    super.isAuthenticated = true;
  }

  /// The decoded, verified token.
  final Jwt jwt;

  final String _name;

  @override
  Object get principal => jwt;

  @override
  Object get credentials => jwt;

  @override
  String get name => _name;

  /// The token's claims; Spring's `getTokenAttributes`.
  Map<String, Object?> get tokenAttributes => jwt.claims;
}

/// Reads the authorities of a JWT from one claim: by default its scopes,
/// each as `SCOPE_x`.
///
/// The claim is [authoritiesClaimName], else `scope`, else `scp`. A string
/// claim is split at [authoritiesClaimDelimiter] (a space); a list claim
/// gives its string elements. Each value gets [authorityPrefix]. A token
/// without the claim has no authorities. Configure it with the
/// `authority-prefix`, `authorities-claim-name` and
/// `authorities-claim-delimiter` properties under
/// `spring.security.oauth2.resourceserver.jwt`, or build one.
///
/// ```dart
/// // Keycloak-style `roles` claim: ["admin"] becomes ROLE_admin.
/// @Bean()
/// JwtAuthenticationConverter jwtAuthenticationConverter() =>
///     const JwtAuthenticationConverter(
///       authoritiesConverter: JwtGrantedAuthoritiesConverter(
///         authoritiesClaimName: 'roles',
///         authorityPrefix: 'ROLE_',
///       ),
///     );
/// ```
///
/// Spring (Java): `JwtGrantedAuthoritiesConverter`.
final class JwtGrantedAuthoritiesConverter {
  /// A converter with the given claim, prefix and delimiter.
  const JwtGrantedAuthoritiesConverter({
    this.authorityPrefix = 'SCOPE_',
    this.authoritiesClaimName,
    this.authoritiesClaimDelimiter = ' ',
  });

  /// Put before each value: `SCOPE_` by default, `''` for none.
  final String authorityPrefix;

  /// The claim holding the authorities; `null` looks for `scope`, else
  /// `scp`.
  final String? authoritiesClaimName;

  /// Separates the values of a string claim; a space by default.
  final String authoritiesClaimDelimiter;

  /// The authorities of [jwt]; blank values are skipped and the rest
  /// trimmed.
  List<GrantedAuthority> convert(Jwt jwt) {
    final name =
        authoritiesClaimName ??
        (jwt.hasClaim('scope')
            ? 'scope'
            : jwt.hasClaim('scp')
            ? 'scp'
            : null);
    if (name == null) {
      return const [];
    }
    final values = switch (jwt.claims[name]) {
      final String text => text.split(authoritiesClaimDelimiter),
      final List<Object?> list => [
        for (final e in list)
          if (e is String) e,
      ],
      _ => const <String>[],
    };
    return [
      for (final value in values)
        if (value.trim().isNotEmpty)
          SimpleGrantedAuthority('$authorityPrefix${value.trim()}'),
    ];
  }
}

/// Turns a verified [Jwt] into the `Authentication` of the request: which
/// claim names the user and which give the authorities.
///
/// The auto-configuration builds one from the
/// `spring.security.oauth2.resourceserver.jwt.*` properties. Declare a
/// bean of this type to change it (see [JwtGrantedAuthoritiesConverter]
/// for an example).
///
/// Spring (Java): `JwtAuthenticationConverter`.
final class JwtAuthenticationConverter {
  /// A converter naming the user by [principalClaimName] (`sub` by
  /// default) and reading authorities with [authoritiesConverter].
  const JwtAuthenticationConverter({
    this.authoritiesConverter = const JwtGrantedAuthoritiesConverter(),
    this.principalClaimName = 'sub',
  });

  /// Reads the authorities from the token.
  final JwtGrantedAuthoritiesConverter authoritiesConverter;

  /// The claim whose value becomes `Authentication.name`.
  final String principalClaimName;

  /// A [JwtAuthenticationToken] for [jwt]; when the principal claim is
  /// missing, the name falls back to `sub`, else `''`.
  Authentication convert(Jwt jwt) => JwtAuthenticationToken(
    jwt,
    authoritiesConverter.convert(jwt),
    name: jwt.getClaimAsString(principalClaimName),
  );
}

/// The [AuthenticationProvider] of JWT bearer tokens: it verifies the
/// token with a [JwtDecoder] and converts it into a
/// [JwtAuthenticationToken].
///
/// A token the decoder rejects (bad signature, expired, wrong issuer or
/// audience) fails with an [InvalidBearerTokenException], a 401
/// `invalid_token`. A decoder that cannot work, for example because the
/// key server is down, fails with an `AuthenticationServiceException`, a
/// 401 without details. `oauth2ResourceServer((s) => s.jwt())` sets it
/// up.
///
/// Spring (Java): `JwtAuthenticationProvider`.
final class JwtAuthenticationProvider implements AuthenticationProvider {
  /// A provider verifying tokens with [jwtDecoder] and converting them
  /// with [converter].
  const JwtAuthenticationProvider(
    this.jwtDecoder, {
    this.converter = const JwtAuthenticationConverter(),
  });

  /// Verifies and decodes the tokens.
  final JwtDecoder jwtDecoder;

  /// Turns a verified token into the authentication.
  final JwtAuthenticationConverter converter;

  @override
  bool supports(Authentication authentication) =>
      authentication is BearerTokenAuthenticationToken;

  @override
  Future<Authentication?> authenticate(Authentication authentication) async {
    final token = (authentication as BearerTokenAuthenticationToken).token;
    final Jwt jwt;
    try {
      jwt = await jwtDecoder.decode(token);
    } on BadJwtException catch (e) {
      throw InvalidBearerTokenException(e.message, e);
    } on JwtException catch (e) {
      throw AuthenticationServiceException(e.message, e);
    }
    final result = converter.convert(jwt);
    if (result is AbstractAuthenticationToken) {
      result.details = authentication.details;
    }
    return result;
  }
}

/// The [AuthenticationProvider] of `Bearer` tokens in the resource
/// server's chain: [tokenAuthenticationManager] checks the token, and a
/// token bound to a key or a certificate is refused.
///
/// A DPoP-bound token (a `cnf.jkt` claim) is worthless without a proof of
/// its key (RFC 9449 §7.2), so it is accepted only with the `DPoP` scheme
/// (`DPoPAuthenticationProvider`). A token bound to a client certificate
/// (`cnf.x5t#S256`, RFC 8705) is valid only over a TLS connection made
/// with that certificate, which the web starter does not hand to the
/// security filters, so it is always refused (fail closed). The refusal
/// is an [InvalidBearerTokenException] (401 `invalid_token`) thrown
/// inside the provider, so the [ProviderManager] around it publishes one
/// event per request, a failure, never a success for a token then
/// refused. `oauth2ResourceServer((s) => s.jwt())` sets it up.
///
/// Spring (Java): none; Spring's `BearerTokenAuthenticationFilter`
/// refuses a DPoP-bound token itself, after its manager has published a
/// success, and its decoders' `X509CertificateThumbprintValidator`
/// refuses a certificate-bound token sent without the certificate.
final class UnboundBearerTokenAuthenticationProvider
    implements AuthenticationProvider {
  /// A provider checking tokens with [tokenAuthenticationManager], usually
  /// a [ProviderManager] over a [JwtAuthenticationProvider] that publishes
  /// no events.
  const UnboundBearerTokenAuthenticationProvider(
    this.tokenAuthenticationManager,
  );

  /// Checks the token: signature, issuer, audience, lifetime.
  final AuthenticationManager tokenAuthenticationManager;

  @override
  bool supports(Authentication authentication) =>
      authentication is BearerTokenAuthenticationToken;

  @override
  Future<Authentication?> authenticate(Authentication authentication) async {
    final result = await tokenAuthenticationManager.authenticate(
      authentication,
    );
    if (result.principal case final Jwt jwt) {
      if (jwt.jwkThumbprint != null) {
        throw InvalidBearerTokenException(_boundTokenAsBearer);
      }
      if (jwt.x509Thumbprint != null) {
        throw InvalidBearerTokenException(_certificateBound);
      }
    }
    return result;
  }
}

const _boundTokenAsBearer =
    'The access token is DPoP-bound; send it with the DPoP scheme and a proof';

// RFC 8705: the web starter does not hand the client's certificate to the
// filters, so the binding cannot be checked (the same text in dpop.dart).
const _certificateBound =
    'The access token is bound to a client certificate (RFC 8705), which '
    'this server cannot check';

/// Finds the bearer token of a request: the header
/// `Authorization: Bearer <token>`, in the syntax of RFC 6750.
///
/// The `access_token` query parameter counts only with
/// [allowUriQueryParameter], off by default because URLs end up in logs
/// and browser histories, and then only in a `GET` request, as in Spring:
/// any page can send a form or a link with that parameter, so it must
/// never make a request that changes something look like a token request.
/// A form field is never read. A header of another scheme gives no token.
/// A malformed `Bearer` header, more than one header, a token both in the
/// header and the query, or an empty query value fails with an
/// [InvalidBearerTokenException] (401).
///
/// ```dart
/// // Server-sent events from a browser cannot set headers.
/// http.oauth2ResourceServer((s) => s
///     .jwt()
///     .bearerTokenResolver(
///         const DefaultBearerTokenResolver(allowUriQueryParameter: true)));
/// ```
///
/// Spring (Java): `DefaultBearerTokenResolver`.
final class DefaultBearerTokenResolver {
  /// A resolver reading [bearerTokenHeaderName] (`Authorization`) and,
  /// with [allowUriQueryParameter], the `access_token` query parameter.
  const DefaultBearerTokenResolver({
    this.allowUriQueryParameter = false,
    this.bearerTokenHeaderName = HttpHeaders.authorizationHeader,
  });

  /// Whether the `access_token` query parameter of a `GET` request counts;
  /// `false` by default. Other methods never read it.
  final bool allowUriQueryParameter;

  /// The header carrying the token, `Authorization` by default.
  final String bearerTokenHeaderName;

  static final _token = RegExp(
    r'^Bearer (?<token>[a-zA-Z0-9\-._~+/]+=*)$',
    caseSensitive: false,
  );

  /// The token of [request], or `null` when it sent none.
  ///
  /// Throws an [InvalidBearerTokenException] for a malformed or repeated
  /// token.
  String? resolve(ServerHttpRequest request) {
    final values = request.headers.getAll(bearerTokenHeaderName);
    if (values.length > 1) {
      throw InvalidBearerTokenException(
        'Found multiple bearer tokens in the request',
      );
    }
    String? fromHeader;
    final header = values.singleOrNull;
    if (header != null && header.toLowerCase().startsWith('bearer')) {
      final match = _token.firstMatch(header);
      if (match == null) {
        throw InvalidBearerTokenException('Bearer token is malformed');
      }
      fromHeader = match.namedGroup('token');
    }
    // GET only (Spring's DefaultBearerTokenResolver too): a page of any
    // origin can post a form to a URL with ?access_token=.
    final fromQuery = allowUriQueryParameter && request.method == HttpMethod.get
        ? request.uri.queryParametersAll['access_token']
        : null;
    if (fromQuery != null && fromQuery.length > 1) {
      throw InvalidBearerTokenException(
        'Found multiple bearer tokens in the request',
      );
    }
    if (fromHeader != null && fromQuery != null) {
      throw InvalidBearerTokenException(
        'Found multiple bearer tokens in the request',
      );
    }
    final query = fromQuery?.singleOrNull;
    if (query != null && query.isEmpty) {
      throw InvalidBearerTokenException(
        'The requested token parameter is an empty string',
      );
    }
    return fromHeader ?? query;
  }
}

String _challenge(String? realm, OAuth2Error? error) {
  final parameters = <String>[
    if (realm != null) 'realm="$realm"',
    if (error != null) ...[
      'error="${error.errorCode}"',
      if (error.description != null)
        'error_description="${error.description!.replaceAll('"', "'")}"',
      if (error.uri != null) 'error_uri="${error.uri}"',
    ],
  ];
  return parameters.isEmpty ? 'Bearer' : 'Bearer ${parameters.join(', ')}';
}

/// The [AuthenticationEntryPoint] of bearer tokens: a `401` with a
/// `WWW-Authenticate: Bearer` challenge.
///
/// When a token was sent and refused, the challenge also carries the
/// OAuth 2.0 error, its description and its URI, so the client knows to
/// get a new token: `Bearer error="invalid_token", error_description=...`.
/// The body is the usual `ProblemDetail`.
///
/// Spring (Java): `BearerTokenAuthenticationEntryPoint`.
final class BearerTokenAuthenticationEntryPoint
    implements AuthenticationEntryPoint {
  /// An entry point naming [realmName] in the challenge when it is
  /// set.
  const BearerTokenAuthenticationEntryPoint({this.realmName});

  /// The realm named in the challenge, or `null` for none.
  final String? realmName;

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
        HttpHeaders.wwwAuthenticateHeader: _challenge(realmName, error),
      },
    );
  }
}

/// The [AccessDeniedHandler] of bearer-token requests: a `403` with
/// `WWW-Authenticate: Bearer error="insufficient_scope"` when the user
/// logged in with a JWT.
///
/// The error tells the client its token is valid but lacks a scope. For
/// a user who did not log in with a JWT the challenge is a plain
/// `Bearer`.
///
/// Spring (Java): `BearerTokenAccessDeniedHandler`.
final class BearerTokenAccessDeniedHandler implements AccessDeniedHandler {
  /// A handler naming [realmName] in the challenge when it is set.
  const BearerTokenAccessDeniedHandler({this.realmName});

  /// The realm named in the challenge, or `null` for none.
  final String? realmName;

  @override
  Future<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AccessDeniedException accessDeniedException,
  ) {
    final bearer =
        SecurityContextHolder.getContext().authentication
            is JwtAuthenticationToken;
    return writeSecurityProblem(
      request,
      response,
      HttpStatus.forbidden,
      'Access Denied',
      headers: {
        HttpHeaders.wwwAuthenticateHeader: _challenge(
          realmName,
          bearer
              ? const OAuth2Error(
                  'insufficient_scope',
                  'The request requires higher privileges than provided by '
                      'the access token.',
                  _rfc6750,
                )
              : null,
        ),
      },
    );
  }
}

/// The filter of bearer-token logins: it checks the token sent with every
/// request of an API.
///
/// `oauth2ResourceServer((s) => s.jwt())` adds it. For each request:
///
/// - no token: the request goes on without a login (the rules may then
///   ask for one);
/// - a valid token: the request goes on as the token's user, for this
///   request only (no session);
/// - a malformed or refused token: the [authenticationEntryPoint] answers,
///   a 401 with `error="invalid_token"` by default, and the request stops;
/// - a valid token bound to a DPoP key (a `cnf.jkt` claim): refused the
///   same way, since such a token is only valid with the `DPoP` scheme
///   and a proof (RFC 9449 §7.2; `DPoPAuthenticationFilter`);
/// - a valid token bound to a client certificate (`cnf.x5t#S256`, RFC
///   8705): refused the same way, since the binding cannot be checked
///   here.
///
/// Spring (Java): `BearerTokenAuthenticationFilter`.
final class BearerTokenAuthenticationFilter implements WebFilter {
  /// A filter checking tokens with [authenticationManager]; the context
  /// is kept for the current request only by default.
  const BearerTokenAuthenticationFilter(
    this.authenticationManager, {
    this.bearerTokenResolver = const DefaultBearerTokenResolver(),
    this.authenticationEntryPoint = const BearerTokenAuthenticationEntryPoint(),
    this.securityContextRepository =
        const RequestAttributeSecurityContextRepository(),
  });

  /// Checks the tokens, usually with a [JwtAuthenticationProvider].
  final AuthenticationManager authenticationManager;

  /// Finds the token in the request.
  final DefaultBearerTokenResolver bearerTokenResolver;

  /// Answers a malformed or refused token.
  final AuthenticationEntryPoint authenticationEntryPoint;

  /// Where the context of a valid token is saved; the request only, by
  /// default.
  final SecurityContextRepository securityContextRepository;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    final String? token;
    try {
      token = bearerTokenResolver.resolve(request);
    } on OAuth2AuthenticationException catch (e) {
      _log.debug(
        () => 'Failed to process authentication request: ${logText(e.message)}',
      );
      await authenticationEntryPoint.commence(request, response, e);
      return;
    }
    if (token == null) {
      _log.trace('Did not find a bearer token in the request');
      return await chain.doFilter(request, response);
    }
    _log.trace('Found a bearer token in the request');
    final Authentication result;
    try {
      result = await authenticationManager.authenticate(
        BearerTokenAuthenticationToken(token)
          ..details = WebAuthenticationDetails.of(request),
      );
    } on AuthenticationException catch (e) {
      SecurityContextHolder.clearContext();
      _log.debug(
        () => 'Failed to process authentication request: ${logText(e.message)}',
      );
      await authenticationEntryPoint.commence(request, response, e);
      return;
    }
    // RFC 9449 §7.2: a token bound to a DPoP key (cnf.jkt) is worthless
    // without a proof of that key, so it is never accepted as Bearer; a
    // token bound to a client certificate (cnf.x5t#S256, RFC 8705) cannot
    // be checked here. The chain's manager refuses both already
    // (UnboundBearerTokenAuthenticationProvider); this is for a filter
    // built with another manager.
    if (result.principal case final Jwt jwt
        when jwt.jwkThumbprint != null || jwt.x509Thumbprint != null) {
      SecurityContextHolder.clearContext();
      _log.debug(
        'Failed to process authentication request: the token is bound',
      );
      await authenticationEntryPoint.commence(
        request,
        response,
        InvalidBearerTokenException(
          jwt.jwkThumbprint != null ? _boundTokenAsBearer : _certificateBound,
        ),
      );
      return;
    }
    final context = SecurityContextHolder.createEmptyContext()
      ..authentication = result;
    SecurityContextHolder.setContext(context);
    _log.debug(() => 'Authenticated token: ${describeUser(result)}');
    await securityContextRepository.saveContext(context, request, response);
    await chain.doFilter(request, response);
  }
}
