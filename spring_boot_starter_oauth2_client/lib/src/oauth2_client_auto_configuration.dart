import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_oauth2_client/src/authorization_browser.dart';
import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client.dart';
import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client_manager.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/token_response_clients.dart';
import 'package:spring_boot_starter_oauth2_client/src/feign/oauth2_access_token_interceptor.dart';
import 'package:spring_boot_starter_oauth2_client/src/login/oauth2_login_service.dart';
import 'package:spring_boot_starter_oauth2_client/src/loopback_authorization_browser.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token_decoder.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration_repository.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/oauth2_client_properties.dart';
import 'package:spring_boot_starter_oauth2_client/src/token_store.dart';
import 'package:spring_boot_starter_oauth2_client/src/user/oauth2_user.dart';
import 'package:spring_boot_starter_oauth2_client/src/user/user_services.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _source =
    'package:spring_boot_starter_oauth2_client#OAuth2ClientAutoConfiguration';
const _log = SpringLog('spring.security.oauth2.client');

// At least one spring.security.oauth2.client.registration.* property:
// Spring Boot's ClientsConfiguredCondition.
final class _OnClientsConfigured implements Condition {
  const _OnClientsConfigured();

  @override
  bool matches(ConditionContext context) =>
      OAuth2ClientProperties.hasRegistrations(context.environment);
}

// The loopback browser needs dart:io (not in a web page).
final class _OnLoopbackSupported implements Condition {
  const _OnLoopbackSupported();

  @override
  bool matches(ConditionContext context) =>
      loopbackAuthorizationBrowserSupported;
}

const _clients = ConditionalOnBean(ClientRegistrationRepository);
const _feign = ConditionalOnBooleanProperty(
  'spring.cloud.openfeign.oauth2.enabled',
);

/// The bean definitions the OAuth2 client starter adds to every
/// application that depends on it. Applications do not use the list
/// directly; the generator adds it through
/// `springBootStarterOauth2ClientAutoConfiguration`.
///
/// Each is left out when the application (or an auto-configuration
/// registered before this one, such as the Flutter starter's) declares a
/// bean of its type:
///
/// - `tokenStore`, an [InMemoryTokenStore] (the Flutter starter declares
///   the platform's secure storage instead);
/// - `authorizationBrowser`, a [LoopbackAuthorizationBrowser], where
///   `dart:io` exists;
///
/// and when a `spring.security.oauth2.client.registration.*` property is
/// set (Spring Boot's `OAuth2ClientAutoConfiguration`):
///
/// - `clientRegistrationRepository`, an
///   [InMemoryClientRegistrationRepository] of the properties
///   ([OAuth2ClientPropertiesMapper]; providers with an `issuer-uri` are
///   discovered at their first use);
/// - `authorizedClientService`, a
///   [TokenStoreOAuth2AuthorizedClientService] on the `tokenStore`;
/// - `authorizationCodeTokenResponseClient`,
///   `refreshTokenTokenResponseClient` and
///   `clientCredentialsTokenResponseClient`, on the `httpTransport` bean
///   (the Feign starter's);
/// - `oidcIdTokenDecoder`, a [TokenEndpointOidcIdTokenDecoder];
/// - `oauth2UserService` ([DefaultOAuth2UserService]) and
///   `oidcUserService` ([OidcUserService]);
/// - `authorizedClientManager`, an
///   [AuthorizedClientServiceOAuth2AuthorizedClientManager] for the
///   `authorization_code`, `refresh_token` and `client_credentials`
///   grants;
/// - `oauth2LoginService`, the [OAuth2LoginService] of apps, with the
///   `GrantedAuthoritiesMapper` bean when there is one;
///
/// and with `spring.cloud.openfeign.oauth2.enabled=true` (Spring Cloud
/// OpenFeign's `FeignAutoConfiguration.Oauth2FeignConfiguration`):
///
/// - `oauth2AccessTokenInterceptor`, the [OAuth2AccessTokenInterceptor]
///   of every Feign client, for the registration
///   `spring.cloud.openfeign.oauth2.client-registration-id` (else the
///   Feign client's name);
/// - `oauth2AccessTokenErrorDecoder`, the [OAuth2AccessTokenErrorDecoder]
///   that renews a token rejected with 401, unless the application has an
///   `ErrorDecoder`.
///
/// ```properties
/// spring.security.oauth2.client.registration.keycloak.client-id=neon-app
/// spring.security.oauth2.client.registration.keycloak.scope=openid,profile
/// spring.security.oauth2.client.registration.keycloak.redirect-uri=http://127.0.0.1/callback
/// spring.security.oauth2.client.provider.keycloak.issuer-uri=http://localhost:8180/realms/neon
/// spring.cloud.openfeign.oauth2.enabled=true
/// spring.cloud.openfeign.oauth2.client-registration-id=keycloak
/// ```
final oauth2ClientAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<TokenStore>(
    name: 'tokenStore',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'tokenStore',
    types: const [TokenStore, InMemoryTokenStore],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.tokenStore', [
        ConditionalOnMissingBean(TokenStore),
      ]),
    ],
    create: (_) {
      _log.debug(
        'No TokenStore bean: the tokens of OAuth2 logins are kept in '
        'memory and forgotten when the application stops',
      );
      return InMemoryTokenStore();
    },
  ),
  BeanDefinition<AuthorizationBrowser>(
    name: 'authorizationBrowser',
    factoryMethodName: 'authorizationBrowser',
    types: const [AuthorizationBrowser, LoopbackAuthorizationBrowser],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.authorizationBrowser', [
        _OnLoopbackSupported(),
        ConditionalOnMissingBean(AuthorizationBrowser),
      ]),
    ],
    create: (_) => LoopbackAuthorizationBrowser(),
  ),
  BeanDefinition<ClientRegistrationRepository>(
    name: 'clientRegistrationRepository',
    factoryMethodName: 'clientRegistrationRepository',
    types: const [
      ClientRegistrationRepository,
      InMemoryClientRegistrationRepository,
    ],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.clientRegistrationRepository', [
        _OnClientsConfigured(),
        ConditionalOnMissingBean(ClientRegistrationRepository),
      ]),
    ],
    create: (r) {
      final repository = InMemoryClientRegistrationRepository.lazy(
        OAuth2ClientPropertiesMapper(
          OAuth2ClientProperties.of(r.dependency<Environment>()),
          transport: r.optionalDependency<HttpTransport>(),
        ).asClientRegistrations(),
      );
      _log.debug(
        'OAuth2 client registrations: '
        '${repository.registrationIds.join(', ')}',
      );
      return repository;
    },
  ),
  BeanDefinition<OAuth2AuthorizedClientService>(
    name: 'authorizedClientService',
    factoryMethodName: 'authorizedClientService',
    types: const [
      OAuth2AuthorizedClientService,
      TokenStoreOAuth2AuthorizedClientService,
    ],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.authorizedClientService', [
        _clients,
        ConditionalOnMissingBean(OAuth2AuthorizedClientService),
      ]),
    ],
    create: (r) => TokenStoreOAuth2AuthorizedClientService(
      r.dependency<TokenStore>(),
      r.dependency<ClientRegistrationRepository>(),
    ),
  ),
  BeanDefinition<
    OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest>
  >(
    name: 'authorizationCodeTokenResponseClient',
    factoryMethodName: 'authorizationCodeTokenResponseClient',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.authorizationCodeTokenResponseClient', [
        _clients,
        ConditionalOnMissingBean(
          OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest>,
        ),
      ]),
    ],
    create: (r) => DefaultAuthorizationCodeTokenResponseClient(
      r.dependency<HttpTransport>(),
    ),
  ),
  BeanDefinition<
    OAuth2AccessTokenResponseClient<OAuth2RefreshTokenGrantRequest>
  >(
    name: 'refreshTokenTokenResponseClient',
    factoryMethodName: 'refreshTokenTokenResponseClient',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.refreshTokenTokenResponseClient', [
        _clients,
        ConditionalOnMissingBean(
          OAuth2AccessTokenResponseClient<OAuth2RefreshTokenGrantRequest>,
        ),
      ]),
    ],
    create: (r) =>
        DefaultRefreshTokenTokenResponseClient(r.dependency<HttpTransport>()),
  ),
  BeanDefinition<
    OAuth2AccessTokenResponseClient<OAuth2ClientCredentialsGrantRequest>
  >(
    name: 'clientCredentialsTokenResponseClient',
    factoryMethodName: 'clientCredentialsTokenResponseClient',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.clientCredentialsTokenResponseClient', [
        _clients,
        ConditionalOnMissingBean(
          OAuth2AccessTokenResponseClient<OAuth2ClientCredentialsGrantRequest>,
        ),
      ]),
    ],
    create: (r) => DefaultClientCredentialsTokenResponseClient(
      r.dependency<HttpTransport>(),
    ),
  ),
  BeanDefinition<OidcIdTokenDecoder>(
    name: 'oidcIdTokenDecoder',
    factoryMethodName: 'oidcIdTokenDecoder',
    types: const [OidcIdTokenDecoder, TokenEndpointOidcIdTokenDecoder],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.oidcIdTokenDecoder', [
        _clients,
        ConditionalOnMissingBean(OidcIdTokenDecoder),
      ]),
    ],
    create: (_) => TokenEndpointOidcIdTokenDecoder(),
  ),
  BeanDefinition<OAuth2UserService<OAuth2UserRequest, OAuth2User>>(
    name: 'oauth2UserService',
    factoryMethodName: 'oauth2UserService',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.oauth2UserService', [
        _clients,
        ConditionalOnMissingBean(
          OAuth2UserService<OAuth2UserRequest, OAuth2User>,
        ),
      ]),
    ],
    create: (r) => DefaultOAuth2UserService(r.dependency<HttpTransport>()),
  ),
  BeanDefinition<OAuth2UserService<OidcUserRequest, OidcUser>>(
    name: 'oidcUserService',
    factoryMethodName: 'oidcUserService',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.oidcUserService', [
        _clients,
        ConditionalOnMissingBean(OAuth2UserService<OidcUserRequest, OidcUser>),
      ]),
    ],
    create: (r) => OidcUserService(r.dependency<HttpTransport>()),
  ),
  BeanDefinition<OAuth2AuthorizedClientManager>(
    name: 'authorizedClientManager',
    factoryMethodName: 'authorizedClientManager',
    types: const [
      OAuth2AuthorizedClientManager,
      AuthorizedClientServiceOAuth2AuthorizedClientManager,
    ],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.authorizedClientManager', [
        _clients,
        ConditionalOnMissingBean(OAuth2AuthorizedClientManager),
      ]),
    ],
    create: (r) => AuthorizedClientServiceOAuth2AuthorizedClientManager(
      r.dependency<ClientRegistrationRepository>(),
      r.dependency<OAuth2AuthorizedClientService>(),
      authorizedClientProvider: OAuth2AuthorizedClientProviderBuilder.builder()
          .authorizationCode()
          .refreshToken(
            accessTokenResponseClient: r
                .dependency<
                  OAuth2AccessTokenResponseClient<
                    OAuth2RefreshTokenGrantRequest
                  >
                >(),
            idTokenDecoder: r.dependency<OidcIdTokenDecoder>(),
          )
          .clientCredentials(
            accessTokenResponseClient: r
                .dependency<
                  OAuth2AccessTokenResponseClient<
                    OAuth2ClientCredentialsGrantRequest
                  >
                >(),
          )
          .build(),
    ),
  ),
  BeanDefinition<OAuth2LoginService>(
    name: 'oauth2LoginService',
    factoryMethodName: 'oauth2LoginService',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.oauth2LoginService', [
        _clients,
        ConditionalOnMissingBean(OAuth2LoginService),
      ]),
    ],
    create: (r) => OAuth2LoginService(
      clientRegistrationRepository: r
          .dependency<ClientRegistrationRepository>(),
      authorizedClientService: r.dependency<OAuth2AuthorizedClientService>(),
      tokenStore: r.dependency<TokenStore>(),
      accessTokenResponseClient: r
          .dependency<
            OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest>
          >(),
      userService: r
          .dependency<OAuth2UserService<OAuth2UserRequest, OAuth2User>>(),
      oidcUserService: r
          .dependency<OAuth2UserService<OidcUserRequest, OidcUser>>(),
      browser: r.optionalDependency<AuthorizationBrowser>(),
      authorizedClientManager: r
          .optionalDependency<OAuth2AuthorizedClientManager>(),
      revocationClient: OAuth2TokenRevocationClient(
        r.dependency<HttpTransport>(),
      ),
      idTokenDecoder: r.dependency<OidcIdTokenDecoder>(),
      authoritiesMapper:
          r.optionalDependency<GrantedAuthoritiesMapper>() ??
          const NullAuthoritiesMapper(),
      eventPublisher: r.dependency<ApplicationEventPublisher>(),
    ),
  ),
  BeanDefinition<OAuth2AccessTokenInterceptor>(
    name: 'oauth2AccessTokenInterceptor',
    factoryMethodName: 'oauth2AccessTokenInterceptor',
    types: const [OAuth2AccessTokenInterceptor, RequestInterceptor],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.oauth2AccessTokenInterceptor', [
        _feign,
        ConditionalOnBean(OAuth2AuthorizedClientManager),
        ConditionalOnMissingBean(OAuth2AccessTokenInterceptor),
      ]),
    ],
    create: (r) => OAuth2AccessTokenInterceptor(
      r.dependency<OAuth2AuthorizedClientManager>(),
      clientRegistrationId: r.dependency<Environment>().getProperty(
        'spring.cloud.openfeign.oauth2.client-registration-id',
      ),
      authorizedClientService: r
          .optionalDependency<OAuth2AuthorizedClientService>(),
    ),
  ),
  BeanDefinition<OAuth2AccessTokenErrorDecoder>(
    name: 'oauth2AccessTokenErrorDecoder',
    factoryMethodName: 'oauth2AccessTokenErrorDecoder',
    types: const [OAuth2AccessTokenErrorDecoder, ErrorDecoder],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.oauth2AccessTokenErrorDecoder', [
        _feign,
        ConditionalOnBean(OAuth2AccessTokenInterceptor),
        ConditionalOnMissingBean(ErrorDecoder),
      ]),
    ],
    create: (r) => OAuth2AccessTokenErrorDecoder(
      const DefaultErrorDecoder(),
      r.dependency<OAuth2AccessTokenInterceptor>(),
    ),
  ),
];
