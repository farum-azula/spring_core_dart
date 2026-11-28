// The documentation has properties lines, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client.dart';
import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client_manager.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_key.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/jwt_client_secret.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/token_response_clients.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token_decoder.dart';
import 'package:spring_boot_starter_oauth2_client/src/properties/oauth2_client_properties.dart';
import 'package:spring_boot_starter_oauth2_client/src/properties/oauth2_rest_client_properties.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration_repository.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/oauth2_client_properties.dart';
import 'package:spring_boot_starter_oauth2_client/src/user/oauth2_user.dart';
import 'package:spring_boot_starter_oauth2_client/src/user/user_services.dart';
import 'package:spring_boot_starter_oauth2_client/src/web/oauth2_client_http_request_interceptor.dart';
import 'package:spring_boot_starter_oauth2_client/src/web/oauth2_provider_addresses.dart';
import 'package:spring_boot_starter_oauth2_client/src/web/oauth2_rest_client_http_service_group_configurer.dart';
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart'
    show
        AllowedAddresses,
        AllowedAddressesContributor,
        HttpTransport,
        RestClientCustomizer;

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

// A registration with client-secret-jwt.* properties.
final class _OnClientSecretJwt implements Condition {
  const _OnClientSecretJwt();

  @override
  bool matches(ConditionContext context) =>
      JwtClientSecretResolver.registrationIds(context.environment).isNotEmpty;
}

const _clients = ConditionalOnBean(ClientRegistrationRepository);
const _restClient = ConditionalOnBooleanProperty(
  'spring.security.oauth2.client.restclient.enabled',
  matchIfMissing: true,
);

/// The bean definitions the OAuth2 client starter adds to every
/// application that depends on it. Applications do not use the list
/// directly; the generator adds it through
/// `springBootStarterOauth2ClientAutoConfiguration`.
///
/// Each is left out when the application (or an auto-configuration
/// registered before this one) declares a bean of its type. When a
/// `spring.security.oauth2.client.registration.*` property is set (Spring
/// Boot's `OAuth2ClientAutoConfiguration`):
///
/// - `clientRegistrationRepository`, an
///   [InMemoryClientRegistrationRepository] of the properties
///   ([OAuth2ClientPropertiesMapper]; providers with an `issuer-uri` are
///   discovered at their first use, through the `httpTransport` bean, and
///   the hosts of the token, JWK Set, user-info and revocation endpoints
///   their discovery documents name join its allow list,
///   `httpClientAllowedAddresses`);
/// - `authorizedClientService`, an
///   [InMemoryOAuth2AuthorizedClientService];
///
/// with a `ClientRegistrationRepository` (Spring Security's
/// `OAuth2AuthorizedClientManagerRegistrar` and the defaults of its
/// login):
///
/// - `dPoPKey`, a [SoftwareDPoPKey] made for this run (in memory) that
///   signs the DPoP proofs of the registrations that use DPoP (not in
///   Spring). Tokens bound to it die with the process, the refresh token
///   too, so an app that keeps its login across restarts must keep the
///   key: `spring_boot_starter_flutter_security` registers its own;
/// - `clientSecretResolver`, a [JwtClientSecretResolver], when a
///   registration has `client-secret-jwt.*` properties (a client secret
///   that is a JWT signed with the client's key, as Sign in with Apple
///   wants; not in Spring);
/// - `authorizationCodeTokenResponseClient`,
///   `refreshTokenTokenResponseClient` and
///   `clientCredentialsTokenResponseClient`, `RestClient` instances on the
///   `httpTransport` bean (the RestClient starter's), with the `dPoPKey`
///   and the `clientSecretResolver`;
/// - `oidcIdTokenDecoder`, a [TokenEndpointOidcIdTokenDecoder], for the
///   ID tokens the token endpoint returns (the security starter replaces
///   it with one that checks signatures);
/// - `oauth2UserService` ([DefaultOAuth2UserService]) and
///   `oidcUserService` ([OidcUserService]), on the `httpTransport` bean
///   too, with the `dPoPKey`;
/// - `authorizedClientManager`, an
///   [AuthorizedClientServiceOAuth2AuthorizedClientManager] for the
///   `authorization_code`, `refresh_token` and `client_credentials`
///   grants;
///
/// for `RestClient` calls and HTTP service interfaces (with the RestClient
/// starter, which this one depends on):
///
/// - `oauth2ProviderAllowedAddresses`, an [OAuth2ProviderAllowedAddresses]:
///   the hosts of the providers' endpoints the properties name join the
///   allow list of the RestClient starter's transport, which every token,
///   discovery and user-info call goes through;
/// - `oauth2ClientHttpRequestInterceptor`, the
///   [OAuth2ClientHttpRequestInterceptor] (Spring Security 7's), with the
///   `dPoPKey` and `spring.security.oauth2.client.restclient.client-registration-id`;
/// - `oauth2RestClientCustomizer`, a `RestClientCustomizer` that adds it to
///   every `RestClientBuilder` the RestClient starter makes (the injected
///   ones and the HTTP service groups'), unless
///   `spring.security.oauth2.client.restclient.enabled=false`; it sends a
///   token only on the calls that name a registration
///   (`@ClientRegistrationId`, `ClientAttributes.clientRegistrationId`).
///
/// ```properties
/// spring.security.oauth2.client.registration.partner.client-id=shop
/// spring.security.oauth2.client.registration.partner.client-secret=${PARTNER_SECRET}
/// spring.security.oauth2.client.registration.partner.authorization-grant-type=client_credentials
/// spring.security.oauth2.client.provider.partner.token-uri=https://id.partner.example/oauth2/token
/// spring.http.serviceclient.orders.base-url=https://api.partner.example
/// ```
final oauth2ClientAutoConfiguration = <BeanDefinition<Object>>[
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
          r.dependency<OAuth2ClientProperties>(),
          transport: r.optionalDependency<HttpTransport>(),
          allowedAddresses: r.optionalDependency<AllowedAddresses>(),
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
      InMemoryOAuth2AuthorizedClientService,
    ],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.authorizedClientService', [
        _clients,
        ConditionalOnMissingBean(OAuth2AuthorizedClientService),
      ]),
    ],
    create: (r) => InMemoryOAuth2AuthorizedClientService(
      r.dependency<ClientRegistrationRepository>(),
    ),
  ),
  BeanDefinition<DPoPKey>(
    name: 'dPoPKey',
    factoryMethodName: 'dPoPKey',
    types: const [DPoPKey],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.dPoPKey', [
        _clients,
        ConditionalOnMissingBean(DPoPKey),
      ]),
    ],
    create: (_) => SoftwareDPoPKey.generate(),
  ),
  BeanDefinition<OAuth2ClientSecretResolver>(
    name: 'clientSecretResolver',
    factoryMethodName: 'clientSecretResolver',
    types: const [OAuth2ClientSecretResolver, JwtClientSecretResolver],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.clientSecretResolver', [
        _clients,
        _OnClientSecretJwt(),
        ConditionalOnMissingBean(OAuth2ClientSecretResolver),
      ]),
    ],
    create: (r) => JwtClientSecretResolver.fromProperties(
      r.dependency<OAuth2ClientProperties>(),
      resourceLoader: r.optionalDependency<ResourceLoader>(),
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
      dPoPKey: r.optionalDependency<DPoPKey>(),
      clientSecretResolver: r.optionalDependency<OAuth2ClientSecretResolver>(),
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
    create: (r) => DefaultRefreshTokenTokenResponseClient(
      r.dependency<HttpTransport>(),
      dPoPKey: r.optionalDependency<DPoPKey>(),
      clientSecretResolver: r.optionalDependency<OAuth2ClientSecretResolver>(),
    ),
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
      dPoPKey: r.optionalDependency<DPoPKey>(),
      clientSecretResolver: r.optionalDependency<OAuth2ClientSecretResolver>(),
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
    create: (r) => DefaultOAuth2UserService(
      r.dependency<HttpTransport>(),
      dPoPKey: r.optionalDependency<DPoPKey>(),
    ),
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
    create: (r) => OidcUserService(
      r.dependency<HttpTransport>(),
      dPoPKey: r.optionalDependency<DPoPKey>(),
    ),
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
  BeanDefinition<OAuth2ProviderAllowedAddresses>(
    name: 'oauth2ProviderAllowedAddresses',
    factoryMethodName: 'oauth2ProviderAllowedAddresses',
    types: const [OAuth2ProviderAllowedAddresses, AllowedAddressesContributor],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.oauth2ProviderAllowedAddresses', [
        _OnClientsConfigured(),
      ]),
    ],
    create: (r) =>
        OAuth2ProviderAllowedAddresses(r.dependency<OAuth2ClientProperties>()),
  ),
  BeanDefinition<OAuth2ClientHttpRequestInterceptor>(
    name: 'oauth2ClientHttpRequestInterceptor',
    factoryMethodName: 'oauth2ClientHttpRequestInterceptor',
    types: const [OAuth2ClientHttpRequestInterceptor],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.oauth2ClientHttpRequestInterceptor', [
        ConditionalOnBean(OAuth2AuthorizedClientManager),
        ConditionalOnMissingBean(OAuth2ClientHttpRequestInterceptor),
      ]),
    ],
    create: (r) => OAuth2ClientHttpRequestInterceptor(
      r.dependency<OAuth2AuthorizedClientManager>(),
      defaultClientRegistrationId: r
          .dependency<OAuth2RestClientProperties>()
          .clientRegistrationId,
      authorizedClientService: r
          .optionalDependency<OAuth2AuthorizedClientService>(),
      dPoPKey: r.optionalDependency<DPoPKey>(),
    ),
  ),
  BeanDefinition<RestClientCustomizer>(
    name: 'oauth2RestClientCustomizer',
    factoryMethodName: 'oauth2RestClientCustomizer',
    types: const [RestClientCustomizer],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.oauth2RestClientCustomizer', [
        _restClient,
        ConditionalOnBean(OAuth2ClientHttpRequestInterceptor),
      ]),
    ],
    create: (r) {
      final interceptor = r.dependency<OAuth2ClientHttpRequestInterceptor>();
      return RestClientCustomizer.of(
        (builder) => OAuth2RestClientHttpServiceGroupConfigurer.addInterceptor(
          builder,
          interceptor,
        ),
      );
    },
  ),
];
