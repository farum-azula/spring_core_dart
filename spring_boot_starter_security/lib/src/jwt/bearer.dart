import 'dart:async';

import 'package:spring_boot_starter_security/src/jwt/jwt.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt_decoder.dart';
import 'package:spring_boot_starter_security/src/web/authentication.dart';
import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/filter_chain.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _rfc6750 = 'https://tools.ietf.org/html/rfc6750#section-3.1';

/// A failed OAuth 2.0 authentication carrying its [error], like Spring's
/// `OAuth2AuthenticationException`.
class OAuth2AuthenticationException extends AuthenticationException {
  /// Failed with [error].
  OAuth2AuthenticationException(this.error, [String? message, Object? cause])
    : super(message ?? error.description ?? error.errorCode, cause);

  /// The OAuth 2.0 error.
  final OAuth2Error error;
}

/// The bearer token is malformed, expired or wrongly signed, like Spring's
/// `InvalidBearerTokenException`.
class InvalidBearerTokenException extends OAuth2AuthenticationException {
  /// Invalid for [description].
  InvalidBearerTokenException(String description, [Object? cause])
    : super(
        OAuth2Error('invalid_token', description, _rfc6750),
        description,
        cause,
      );
}

/// A bearer token not yet authenticated, like Spring's
/// `BearerTokenAuthenticationToken`.
final class BearerTokenAuthenticationToken extends AbstractAuthenticationToken {
  /// The request for [token].
  BearerTokenAuthenticationToken(this.token);

  /// The token.
  final String token;

  @override
  Object get principal => token;

  @override
  Object get credentials => token;

  /// The token is never shown.
  @override
  String get name => '';
}

/// An authenticated JWT, like Spring's `JwtAuthenticationToken`: the
/// principal is the [Jwt], the name its `sub` (or another claim).
final class JwtAuthenticationToken extends AbstractAuthenticationToken {
  /// [jwt] with [authorities], named by [name].
  JwtAuthenticationToken(
    this.jwt,
    Iterable<GrantedAuthority> authorities, {
    String? name,
  }) : _name = name ?? jwt.subject ?? '',
       super(authorities) {
    super.isAuthenticated = true;
  }

  /// The token.
  final Jwt jwt;

  final String _name;

  @override
  Object get principal => jwt;

  @override
  Object get credentials => jwt;

  @override
  String get name => _name;

  /// The claims (Spring's `getTokenAttributes`).
  Map<String, Object?> get tokenAttributes => jwt.claims;
}

/// The authorities of a JWT: its scopes as `SCOPE_x`, like Spring's
/// `JwtGrantedAuthoritiesConverter` — `scope` (space-separated) or `scp`
/// (a list or a string) unless [authoritiesClaimName] names another claim.
final class JwtGrantedAuthoritiesConverter {
  /// A converter.
  const JwtGrantedAuthoritiesConverter({
    this.authorityPrefix = 'SCOPE_',
    this.authoritiesClaimName,
    this.authoritiesClaimDelimiter = ' ',
  });

  /// Put before each value.
  final String authorityPrefix;

  /// The claim (default: `scope`, else `scp`).
  final String? authoritiesClaimName;

  /// Splits a string claim.
  final String authoritiesClaimDelimiter;

  /// The authorities of [jwt].
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

/// Turns a verified [Jwt] into an authentication, like Spring's
/// `JwtAuthenticationConverter`.
final class JwtAuthenticationConverter {
  /// A converter naming the principal by [principalClaimName] (`sub`).
  const JwtAuthenticationConverter({
    this.authoritiesConverter = const JwtGrantedAuthoritiesConverter(),
    this.principalClaimName = 'sub',
  });

  /// The authorities.
  final JwtGrantedAuthoritiesConverter authoritiesConverter;

  /// The claim naming the user.
  final String principalClaimName;

  /// The authentication of [jwt].
  Authentication convert(Jwt jwt) => JwtAuthenticationToken(
    jwt,
    authoritiesConverter.convert(jwt),
    name: jwt.getClaimAsString(principalClaimName),
  );
}

/// Authenticates bearer tokens as JWTs, like Spring's
/// `JwtAuthenticationProvider`: a bad token is a 401 `invalid_token`; a
/// decoder that cannot work (the issuer is down) a 401 too, without
/// details.
final class JwtAuthenticationProvider implements AuthenticationProvider {
  /// Decodes with [jwtDecoder].
  const JwtAuthenticationProvider(
    this.jwtDecoder, {
    this.converter = const JwtAuthenticationConverter(),
  });

  /// The decoder.
  final JwtDecoder jwtDecoder;

  /// Makes the authentication.
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

/// Finds the bearer token of a request, like Spring's
/// `DefaultBearerTokenResolver`: `Authorization: Bearer <token>` (RFC 6750
/// syntax); `access_token` in the query or a form only when allowed (off by
/// default: URLs end up in logs). A malformed header, or a token in two
/// places, is a 401.
final class DefaultBearerTokenResolver {
  /// A resolver.
  const DefaultBearerTokenResolver({
    this.allowUriQueryParameter = false,
    this.bearerTokenHeaderName = HttpHeaders.authorizationHeader,
  });

  /// Whether `?access_token=` counts.
  final bool allowUriQueryParameter;

  /// The header.
  final String bearerTokenHeaderName;

  static final _token = RegExp(
    r'^Bearer (?<token>[a-zA-Z0-9\-._~+/]+=*)$',
    caseSensitive: false,
  );

  /// The token of [request], or `null`.
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
    final fromQuery = allowUriQueryParameter
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

/// `401` with `WWW-Authenticate: Bearer` (and the error when a token was
/// sent), like Spring's `BearerTokenAuthenticationEntryPoint`.
final class BearerTokenAuthenticationEntryPoint
    implements AuthenticationEntryPoint {
  /// An entry point (with [realmName] when set).
  const BearerTokenAuthenticationEntryPoint({this.realmName});

  /// The realm.
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

/// `403` with `WWW-Authenticate: Bearer error="insufficient_scope"`, like
/// Spring's `BearerTokenAccessDeniedHandler`.
final class BearerTokenAccessDeniedHandler implements AccessDeniedHandler {
  /// A handler (with [realmName] when set).
  const BearerTokenAccessDeniedHandler({this.realmName});

  /// The realm.
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

/// Authenticates `Authorization: Bearer` tokens, like Spring's
/// `BearerTokenAuthenticationFilter`: a valid token makes the request the
/// token's user (this request only); an invalid one gets the
/// [authenticationEntryPoint]'s 401 `invalid_token`; a request without one
/// goes on unauthenticated.
final class BearerTokenAuthenticationFilter implements WebFilter {
  /// A filter authenticating with [authenticationManager].
  const BearerTokenAuthenticationFilter(
    this.authenticationManager, {
    this.bearerTokenResolver = const DefaultBearerTokenResolver(),
    this.authenticationEntryPoint = const BearerTokenAuthenticationEntryPoint(),
    this.securityContextRepository =
        const RequestAttributeSecurityContextRepository(),
  });

  /// Checks tokens.
  final AuthenticationManager authenticationManager;

  /// Finds tokens.
  final DefaultBearerTokenResolver bearerTokenResolver;

  /// Answers failures.
  final AuthenticationEntryPoint authenticationEntryPoint;

  /// Where the context is kept (the request only).
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
      await authenticationEntryPoint.commence(request, response, e);
      return;
    }
    if (token == null) {
      return await chain.doFilter(request, response);
    }
    final Authentication result;
    try {
      result = await authenticationManager.authenticate(
        BearerTokenAuthenticationToken(token)
          ..details = WebAuthenticationDetails.of(request),
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
