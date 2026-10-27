// The documentation has Markdown table rows, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:math';

import 'package:spring_boot_starter_security/src/config/http_security.dart';
import 'package:spring_boot_starter_security/src/jwt/bearer.dart';
import 'package:spring_boot_starter_security/src/jwt/jose.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt_decoder.dart';
import 'package:spring_boot_starter_security/src/web/arguments.dart';
import 'package:spring_boot_starter_security/src/web/filter_chain.dart';
import 'package:spring_boot_starter_security/src/web/firewall.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _source =
    'package:spring_boot_starter_security#SecurityAutoConfiguration';
const _log = SpringLog('spring.security.autoconfigure');

/// `spring.security.*`, like Spring Boot's `SecurityProperties` and
/// `OAuth2ResourceServerProperties`.
///
/// | Property | Default |
/// |---|---|
/// | `spring.security.user.name` | `user` |
/// | `spring.security.user.password` | a random one, logged at startup |
/// | `spring.security.user.roles` | — |
/// | `spring.security.filter.order` | `-100` |
/// | `spring.security.oauth2.resourceserver.jwt.issuer-uri` | — |
/// | `spring.security.oauth2.resourceserver.jwt.jwk-set-uri` | — |
/// | `spring.security.oauth2.resourceserver.jwt.jws-algorithms` | `RS256` |
/// | `spring.security.oauth2.resourceserver.jwt.audiences` | — |
/// | `spring.security.oauth2.resourceserver.jwt.authority-prefix` | `SCOPE_` |
/// | `spring.security.oauth2.resourceserver.jwt.authorities-claim-name` | `scope`, else `scp` |
/// | `spring.security.oauth2.resourceserver.jwt.authorities-claim-delimiter` | a space |
/// | `spring.security.oauth2.resourceserver.jwt.principal-claim-name` | `sub` |
final class SecurityProperties {
  SecurityProperties._(this._environment);

  /// The properties of [environment].
  factory SecurityProperties.of(Environment environment) =>
      SecurityProperties._(environment);

  final Environment _environment;

  String? _text(String key) {
    final value = _environment.getProperty(key)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  List<String> _list(String key) {
    final binder = Binder.get(_environment as ConfigurableEnvironment);
    return binder
        .bind(key, const ListType<String>(ClassType<String>()))
        .map<List<String>>(
          (values) => [
            for (final v in values)
              if (v.trim().isNotEmpty) v.trim(),
          ],
        )
        .orElse(const []);
  }

  static const _jwt = 'spring.security.oauth2.resourceserver.jwt';

  /// The default user's name.
  String get userName => _text('spring.security.user.name') ?? 'user';

  /// The default user's password, when set.
  String? get userPassword => _text('spring.security.user.password');

  /// The default user's roles.
  List<String> get userRoles => _list('spring.security.user.roles');

  /// The order of the security filter among the web filters.
  int get filterOrder =>
      int.tryParse(_text('spring.security.filter.order') ?? '') ??
      FilterChainProxy.defaultFilterOrder;

  /// `issuer-uri`.
  String? get issuerUri => _text('$_jwt.issuer-uri');

  /// `jwk-set-uri`.
  String? get jwkSetUri => _text('$_jwt.jwk-set-uri');

  /// `jws-algorithms` (`RS256`).
  Set<JwsAlgorithm> get jwsAlgorithms {
    final names = _list('$_jwt.jws-algorithms');
    if (names.isEmpty) {
      return const {JwsAlgorithm.rs256};
    }
    return {
      for (final name in names)
        JwsAlgorithm.from(name) ??
            (throw ArgumentError('$_jwt.jws-algorithms: unknown $name')),
    };
  }

  /// `audiences`.
  List<String> get audiences => _list('$_jwt.audiences');

  /// Whether a resource server is configured by properties.
  bool get hasResourceServer => issuerUri != null || jwkSetUri != null;

  /// The authorities converter of the properties.
  JwtAuthenticationConverter get jwtAuthenticationConverter =>
      JwtAuthenticationConverter(
        authoritiesConverter: JwtGrantedAuthoritiesConverter(
          authorityPrefix:
              _environment.getProperty('$_jwt.authority-prefix') ?? 'SCOPE_',
          authoritiesClaimName: _text('$_jwt.authorities-claim-name'),
          authoritiesClaimDelimiter:
              _environment.getProperty('$_jwt.authorities-claim-delimiter') ??
              ' ',
        ),
        principalClaimName: _text('$_jwt.principal-claim-name') ?? 'sub',
      );
}

// spring.security.oauth2.resourceserver.jwt.issuer-uri or jwk-set-uri.
final class _OnResourceServerProperties implements Condition {
  const _OnResourceServerProperties();

  @override
  bool matches(ConditionContext context) =>
      SecurityProperties.of(context.environment).hasResourceServer;
}

// No resource server properties (the default user backs off with them).
final class _OnNoResourceServerProperties implements Condition {
  const _OnNoResourceServerProperties();

  @override
  bool matches(ConditionContext context) =>
      !SecurityProperties.of(context.environment).hasResourceServer;
}

/// Reads `principal.claims['sub']`, `principal.subject`, ... of a JWT in
/// method security expressions.
final class JwtExpressionCustomizer
    implements SecurityExpressionContextCustomizer {
  /// The customizer.
  const JwtExpressionCustomizer();

  @override
  void customize(StandardEvaluationContext context) => context
    ..addPropertyAccessor(
      FunctionPropertyAccessor<Jwt>(
        getters: {
          'claims': (jwt) => jwt.claims,
          'headers': (jwt) => jwt.headers,
          'subject': (jwt) => jwt.subject,
          'issuer': (jwt) => jwt.issuer,
          'audience': (jwt) => jwt.audience,
          'id': (jwt) => jwt.id,
          'expiresAt': (jwt) => jwt.expiresAt,
          'issuedAt': (jwt) => jwt.issuedAt,
          'notBefore': (jwt) => jwt.notBefore,
        },
      ),
    )
    ..addPropertyAccessor(
      FunctionPropertyAccessor<JwtAuthenticationToken>(
        getters: {
          'tokenAttributes': (token) => token.tokenAttributes,
          'token': (token) => token.jwt,
        },
      ),
    );
}

String _generatedPassword() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}

/// The beans of the security starter, like Spring Boot's
/// `SecurityAutoConfiguration`, `SpringBootWebSecurityConfiguration`,
/// `UserDetailsServiceAutoConfiguration` and
/// `OAuth2ResourceServerAutoConfiguration`:
///
/// - `httpSecurity` — a new [HttpSecurity] for every `SecurityFilterChain`
///   bean method (a prototype);
/// - `defaultSecurityFilterChain` — without a `SecurityFilterChain` bean:
///   every request needs a login, with form login and HTTP Basic (with a
///   JWT decoder: bearer tokens instead), like Spring Boot;
/// - `securityFilterChain` — the [FilterChainProxy] web filter over the
///   chains (`spring.security.filter.order`), behind the `HttpFirewall`
///   bean or the strict one;
/// - `inMemoryUserDetailsManager` — the default user
///   (`spring.security.user.*`; a generated password, logged at startup),
///   unless the application has users, providers, a manager or a JWT
///   decoder;
/// - `jwtDecoder` — from `spring.security.oauth2.resourceserver.jwt.*`;
/// - `jwtAuthenticationConverter` — the authorities and the principal
///   claim of JWTs;
/// - argument resolvers for `@AuthenticationPrincipal`,
///   `@CurrentSecurityContext` and `Authentication` parameters, and JWT
///   properties in method security expressions.
final securityAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<HttpSecurity>(
    name: 'httpSecurity',
    scope: ScopeType.prototype,
    source: _source,
    create: (r) => HttpSecurity(
      r.dependency<BeanFactory>(),
      contextPath: ServerProperties.of(r.dependency<Environment>()).contextPath,
    ),
  ),
  BeanDefinition<JwtDecoder>(
    name: 'jwtDecoder',
    factoryMethodName: 'jwtDecoder',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.jwtDecoder', [
        ConditionalOnMissingBean(JwtDecoder),
        _OnResourceServerProperties(),
      ]),
    ],
    create: (r) {
      final properties = SecurityProperties.of(r.dependency<Environment>());
      final jwkSetUri = properties.jwkSetUri;
      final issuer = properties.issuerUri;
      final audiences = properties.audiences;
      if (jwkSetUri != null) {
        return NimbusJwtDecoder.withJwkSetUri(
          Uri.parse(jwkSetUri),
          jwsAlgorithms: properties.jwsAlgorithms,
          validator: DelegatingOAuth2TokenValidator([
            JwtTimestampValidator(),
            if (issuer != null) JwtIssuerValidator(issuer),
            if (audiences.isNotEmpty) JwtAudienceValidator(audiences),
          ]),
        );
      }
      return JwtDecoders.fromIssuerLocation(issuer!, audiences: audiences);
    },
  ),
  BeanDefinition<JwtAuthenticationConverter>(
    name: 'jwtAuthenticationConverter',
    factoryMethodName: 'jwtAuthenticationConverter',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.jwtAuthenticationConverter', [
        ConditionalOnMissingBean(JwtAuthenticationConverter),
      ]),
    ],
    create: (r) =>
        SecurityProperties.of(r.dependency<Environment>())
            .jwtAuthenticationConverter,
  ),
  BeanDefinition<InMemoryUserDetailsManager>(
    name: 'inMemoryUserDetailsManager',
    factoryMethodName: 'inMemoryUserDetailsManager',
    types: const [
      InMemoryUserDetailsManager,
      UserDetailsManager,
      UserDetailsService,
      UserDetailsPasswordService,
    ],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.inMemoryUserDetailsManager', [
        ConditionalOnMissingBean.where(
          types: [
            AuthenticationManager,
            AuthenticationProvider,
            UserDetailsService,
            JwtDecoder,
          ],
        ),
        _OnNoResourceServerProperties(),
      ]),
    ],
    create: (r) {
      final properties = SecurityProperties.of(r.dependency<Environment>());
      var password = properties.userPassword;
      if (password == null) {
        password = _generatedPassword();
        // Like Spring Boot: the developer needs it to log in at all.
        _log.warning(
          '\n\nUsing generated security password: $password\n\n'
          'This generated password is for development use only. Your '
          'security configuration must be updated before running your '
          'application in production.\n',
        );
      }
      final encoder = r.optionalDependency<PasswordEncoder>();
      final stored = encoder != null || RegExp(r'^\{.+\}.*$').hasMatch(password)
          ? password
          : '{noop}$password';
      return InMemoryUserDetailsManager([
        User.withUsername(properties.userName)
            .password(stored)
            .roles(properties.userRoles)
            .build(),
      ]);
    },
  ),
  BeanDefinition<SecurityFilterChain>(
    name: 'defaultSecurityFilterChain',
    factoryMethodName: 'defaultSecurityFilterChain',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.defaultSecurityFilterChain', [
        ConditionalOnMissingBean(SecurityFilterChain),
      ]),
    ],
    create: (r) {
      final http = r.dependency<HttpSecurity>().authorizeHttpRequests(
        (auth) => auth.anyRequest().authenticated(),
      );
      if (r.optionalDependency<JwtDecoder>() != null) {
        return http.oauth2ResourceServer((server) => server.jwt()).build();
      }
      return http.formLogin().httpBasic().build();
    },
  ),
  BeanDefinition<FilterChainProxy>(
    name: 'securityFilterChain',
    types: const [FilterChainProxy, WebFilter, Ordered],
    source: _source,
    create: (r) {
      final chains =
          r.optionalDependencyList<SecurityFilterChain>() ?? const [];
      final properties = SecurityProperties.of(r.dependency<Environment>());
      _check(chains);
      return FilterChainProxy(
        chains,
        firewall: r.optionalDependency<HttpFirewall>(),
        order: properties.filterOrder,
      );
    },
  ),
  BeanDefinition<WebMvcConfigurer>(
    name: 'securityWebMvcConfigurer',
    types: const [WebMvcConfigurer],
    source: _source,
    create: (r) => const _SecurityWebMvcConfigurer(),
  ),
  BeanDefinition<JwtExpressionCustomizer>(
    name: 'jwtExpressionCustomizer',
    types: const [JwtExpressionCustomizer, SecurityExpressionContextCustomizer],
    source: _source,
    create: (r) => const JwtExpressionCustomizer(),
  ),
];

// Like Spring: a chain matching every request must be the last one.
void _check(List<SecurityFilterChain> chains) {
  for (var i = 0; i < chains.length - 1; i++) {
    final chain = chains[i];
    if (chain is DefaultSecurityFilterChain &&
        identical(chain.requestMatcher, _anyRequest)) {
      throw StateError(
        'A filter chain that matches any request has already been '
        'configured, which means that this filter chain '
        '(${chains[i + 1]}) will never get invoked. Please use '
        'HttpSecurity.securityMatcher to restrict the chains, and @Order '
        'to put the one matching every request last.',
      );
    }
  }
}

const AnyRequestMatcher _anyRequest = AnyRequestMatcher.instance;

final class _SecurityWebMvcConfigurer with WebMvcConfigurer {
  const _SecurityWebMvcConfigurer();

  @override
  void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) =>
      resolvers.add(const SecurityArgumentResolver());
}
