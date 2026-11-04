// The source names below are single strings that cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:math';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show
        ClientRegistrationRepository,
        DelegatingOAuth2TokenValidator,
        OAuth2AuthorizedClientService,
        OAuth2ClientProperties,
        OidcIdTokenDecoder;
import 'package:spring_boot_starter_security/src/config/http_security.dart';
import 'package:spring_boot_starter_security/src/jwt/bearer.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt_decoder.dart';
import 'package:spring_boot_starter_security/src/oauth2/authorized_client_repository.dart';
import 'package:spring_boot_starter_security/src/oauth2/oidc_id_token_decoder_factory.dart';
import 'package:spring_boot_starter_security/src/properties/security_properties.dart';
import 'package:spring_boot_starter_security/src/web/arguments.dart';
import 'package:spring_boot_starter_security/src/web/cookie_signer.dart';
import 'package:spring_boot_starter_security/src/web/filter_chain.dart';
import 'package:spring_boot_starter_security/src/web/firewall.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _source =
    'package:spring_boot_starter_security#SecurityAutoConfiguration';
const _log = SpringLog('spring.security.autoconfigure');

// Whether issuer-uri or jwk-set-uri is set (SecurityProperties describes
// the keys); a condition runs before any bean exists.
bool _hasResourceServer(Environment environment) {
  bool set(String key) =>
      (environment
                  .getProperty(
                    'spring.security.oauth2.resourceserver.jwt.$key',
                  )
                  ?.trim() ??
              '')
          .isNotEmpty;
  return set('issuer-uri') || set('jwk-set-uri');
}

// spring.security.oauth2.resourceserver.jwt.issuer-uri or jwk-set-uri.
final class _OnResourceServerProperties implements Condition {
  const _OnResourceServerProperties();

  @override
  bool matches(ConditionContext context) =>
      _hasResourceServer(context.environment);
}

// No resource server properties (the default user backs off with them).
final class _OnNoResourceServerProperties implements Condition {
  const _OnNoResourceServerProperties();

  @override
  bool matches(ConditionContext context) =>
      !_hasResourceServer(context.environment);
}

// OAuth2 clients: a ClientRegistrationRepository bean registered before
// (the application's, or the OAuth2 client starter's from the properties)
// or, for the modules registered before that starter, the properties.
final class _OnClientRegistrations implements Condition {
  const _OnClientRegistrations();

  @override
  bool matches(ConditionContext context) =>
      OAuth2ClientProperties.hasRegistrations(context.environment) ||
      context.beanFactory
          .getBeanNamesForType(ClientRegistrationRepository)
          .isNotEmpty;
}

// No OAuth2 clients, or a default user asked for with
// spring.security.user.name or .password: Spring Boot's
// MissingAlternativeOrUserPropertiesConfigured.
final class _OnNoClientRegistrationsOrUserProperties implements Condition {
  const _OnNoClientRegistrationsOrUserProperties();

  @override
  bool matches(ConditionContext context) {
    final environment = context.environment;
    bool set(String key) =>
        (environment.getProperty(key)?.trim() ?? '').isNotEmpty;
    return context.beanFactory
            .getBeanNamesForType(ClientRegistrationRepository)
            .isEmpty ||
        set('spring.security.user.name') ||
        set('spring.security.user.password');
  }
}

/// Makes a JWT readable in method security expressions:
/// `principal.subject`, `principal.claims['tenant']`, and
/// `authentication.token` or `authentication.tokenAttributes`.
///
/// The auto-configuration registers it, so `@PreAuthorize` works on APIs
/// with bearer tokens as on form logins:
///
/// ```dart
/// @PreAuthorize("principal.claims['tenant'] == #order.tenant")
/// Future<void> cancel(Order order) async { ... }
/// ```
///
/// A [Jwt] exposes `claims`, `headers`, `subject`, `issuer`, `audience`,
/// `id`, `expiresAt`, `issuedAt` and `notBefore`; a
/// [JwtAuthenticationToken] exposes `tokenAttributes` and `token`.
final class JwtExpressionCustomizer
    implements SecurityExpressionContextCustomizer {
  /// The stateless customizer.
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

/// The beans the starter adds to every application; they make the
/// application secure by default and let it change one part at a time.
///
/// - `httpSecurity`: a new [HttpSecurity] for every `SecurityFilterChain`
///   bean method (a prototype).
/// - `defaultSecurityFilterChain`, unless the application declares a
///   `SecurityFilterChain`: every request needs a login, with
///   `oauth2Login()` when OAuth2 clients are configured (a
///   `ClientRegistrationRepository`; with a `JwtDecoder` too, bearer
///   tokens are accepted beside it), else with bearer tokens when there
///   is a `JwtDecoder`, else with form login and HTTP Basic.
/// - `authorizedClientRepository`, when OAuth2 clients are configured: an
///   [AuthenticatedPrincipalOAuth2AuthorizedClientRepository] on the
///   `OAuth2AuthorizedClientService`, unless the application declares an
///   `OAuth2AuthorizedClientRepository`.
/// - `securityFilterChain`: the [FilterChainProxy] web filter over all
///   chains, at `spring.security.filter.order`, behind the `HttpFirewall`
///   bean or a [StrictHttpFirewall]. Startup fails when a chain that
///   matches every request is not the last one.
/// - `inMemoryUserDetailsManager`: the default user from
///   `spring.security.user.*`, unless the application has a
///   `UserDetailsService`, an `AuthenticationProvider`, an
///   `AuthenticationManager` or a `JwtDecoder`, or sets the resource server
///   properties, or has OAuth2 clients (unless `spring.security.user.name`
///   or `.password` is set). Without a password property, a random one is
///   generated and logged at startup, for development only. Without a
///   `PasswordEncoder` bean the password is stored as `{noop}` unless it
///   already starts with an `{id}`; with one, it is stored as given, so it
///   must already be encoded (and a generated password cannot log in).
/// - `cookieSigner`, when `spring.security.cookie.secret` is set (at
///   least 32 characters; the same on every instance behind a proxy): it
///   signs the cookies kept instead of a session before a login (the
///   page to come back to, the OAuth 2.0 authorization request). Without
///   it, a random key of the process signs them.
/// - `jwtDecoder`, when `issuer-uri` or `jwk-set-uri` is set and the
///   application declares none.
/// - `jwtAuthenticationConverter`: the authorities and the name of JWT
///   users, from the properties.
/// - The resolver of `@AuthenticationPrincipal`, `@CurrentSecurityContext`
///   and `Authentication` controller parameters, and [JwtExpressionCustomizer]
///   for JWTs in method security expressions.
///
/// Spring (Java): Spring Boot's `SecurityAutoConfiguration`,
/// `SpringBootWebSecurityConfiguration`,
/// `UserDetailsServiceAutoConfiguration`,
/// `OAuth2ResourceServerAutoConfiguration` and
/// `OAuth2ClientWebSecurityAutoConfiguration`. With both OAuth2 clients
/// and a `JwtDecoder`, Spring Boot's default chain has `oauth2Login()`
/// only; here it accepts bearer tokens too (browsers log in, native apps
/// send their tokens).
final securityAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<HttpSecurity>(
    name: 'httpSecurity',
    scope: ScopeType.prototype,
    source: _source,
    create: (r) {
      final environment = r.dependency<Environment>();
      final properties = r.dependency<SecurityProperties>();
      return HttpSecurity(
        r.dependency<BeanFactory>(),
        contextPath: ServerProperties.of(environment).contextPath,
        maximumSessions: properties.maximumSessions,
        maxSessionsPreventsLogin: properties.maxSessionsPreventsLogin,
      );
    },
  ),
  BeanDefinition<CookieSigner>(
    name: 'cookieSigner',
    factoryMethodName: 'cookieSigner',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.cookieSigner', [
        ConditionalOnProperty('spring.security.cookie.secret'),
        ConditionalOnMissingBean(CookieSigner),
      ]),
    ],
    create: (r) => CookieSigner.fromSecret(
      r.dependency<SecurityProperties>().cookie.secret!,
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
      final properties = r.dependency<SecurityProperties>();
      final jwkSetUri = properties.jwkSetUri;
      final issuer = properties.issuerUri;
      final audiences = properties.audiences;
      if (jwkSetUri != null) {
        return NimbusJwtDecoder.withJwkSetUri(
          Uri.parse(jwkSetUri),
          jwsAlgorithms: properties.jwsAlgorithms,
          validator: DelegatingOAuth2TokenValidator([
            JwtTypeValidator.jwt(),
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
        r.dependency<SecurityProperties>().jwtAuthenticationConverter,
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
        _OnNoClientRegistrationsOrUserProperties(),
      ]),
    ],
    create: (r) {
      final properties = r.dependency<SecurityProperties>();
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
      final jwt = r.optionalDependency<JwtDecoder>() != null;
      if (r.optionalDependency<ClientRegistrationRepository>() != null) {
        http.oauth2Login();
        if (jwt) {
          http.oauth2ResourceServer((server) => server.jwt());
        }
        return http.build();
      }
      if (jwt) {
        return http.oauth2ResourceServer((server) => server.jwt()).build();
      }
      return http.formLogin().httpBasic().build();
    },
  ),
  BeanDefinition<OAuth2AuthorizedClientRepository>(
    name: 'authorizedClientRepository',
    factoryMethodName: 'authorizedClientRepository',
    types: const [
      OAuth2AuthorizedClientRepository,
      AuthenticatedPrincipalOAuth2AuthorizedClientRepository,
    ],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.authorizedClientRepository', [
        ConditionalOnBean(OAuth2AuthorizedClientService),
        ConditionalOnMissingBean(OAuth2AuthorizedClientRepository),
      ]),
    ],
    create: (r) => AuthenticatedPrincipalOAuth2AuthorizedClientRepository(
      r.dependency<OAuth2AuthorizedClientService>(),
    ),
  ),
  BeanDefinition<FilterChainProxy>(
    name: 'securityFilterChain',
    types: const [FilterChainProxy, WebFilter, Ordered],
    source: _source,
    create: (r) {
      final chains =
          r.optionalDependencyList<SecurityFilterChain>() ?? const [];
      final properties = r.dependency<SecurityProperties>();
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

const _oauth2Source =
    'package:spring_boot_starter_security#SecurityOAuth2ClientAutoConfiguration';

/// The bean definitions the security starter adds before the OAuth2
/// client starter's, so the latter's defaults step aside:
///
/// - `oidcIdTokenDecoder`, when OAuth2 clients are configured (a
///   `spring.security.oauth2.client.registration.*` property or a
///   `ClientRegistrationRepository` bean of the application): an
///   [OidcIdTokenDecoderFactory] on the `HttpTransport` bean, which checks
///   the signature of every ID token with the provider's JWK Set. The
///   OAuth2 client starter's default trusts the token endpoint's TLS
///   instead; on a server, the logins of `oauth2Login()` and the
///   refreshed ID tokens of the authorized client manager both use this
///   one. An `OidcIdTokenDecoder` bean of the application replaces it.
///
/// Spring (Java): the `OidcIdTokenDecoderFactory` Spring Security's
/// `OAuth2LoginConfigurer` creates when there is no
/// `JwtDecoderFactory<ClientRegistration>` bean.
final securityOAuth2ClientAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<OidcIdTokenDecoder>(
    name: 'oidcIdTokenDecoder',
    factoryMethodName: 'oidcIdTokenDecoder',
    types: const [OidcIdTokenDecoder, OidcIdTokenDecoderFactory],
    source: _oauth2Source,
    conditions: const [
      ConditionGroup('$_oauth2Source.oidcIdTokenDecoder', [
        _OnClientRegistrations(),
        ConditionalOnMissingBean(OidcIdTokenDecoder),
      ]),
    ],
    create: (r) => OidcIdTokenDecoderFactory(
      fetcher: transportJwkFetcher(
        r.optionalDependency<HttpTransport>() ?? platformHttpTransport(),
      ),
    ),
  ),
];
