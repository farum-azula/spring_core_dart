// The starter's beans: what comes with a registration, what backs off for
// an application's bean, and how another auto-configuration registered
// before this one replaces a default.
import 'package:spring_boot_starter_oauth2_client/spring_auto_configuration.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

const _r = 'spring.security.oauth2.client.registration';
const _registration = [
  '$_r.github.client-id=gh',
  '$_r.partner.client-id=shop',
  '$_r.partner.client-secret=s',
  '$_r.partner.authorization-grant-type=client_credentials',
  'spring.security.oauth2.client.provider.partner.token-uri=https://p.test/t',
];

// What another auto-configuration that replaces a default looks like (the
// Flutter security package's authorized client service, for one).
final class _OwnClients implements OAuth2AuthorizedClientService {
  _OwnClients(ClientRegistrationRepository repository)
    : _delegate = InMemoryOAuth2AuthorizedClientService(repository);

  final OAuth2AuthorizedClientService _delegate;

  @override
  Future<OAuth2AuthorizedClient?> loadAuthorizedClient(
    String clientRegistrationId,
    String principalName,
  ) => _delegate.loadAuthorizedClient(clientRegistrationId, principalName);

  @override
  Future<void> saveAuthorizedClient(
    OAuth2AuthorizedClient authorizedClient,
    Authentication principal,
  ) => _delegate.saveAuthorizedClient(authorizedClient, principal);

  @override
  Future<void> removeAuthorizedClient(
    String clientRegistrationId,
    String principalName,
  ) => _delegate.removeAuthorizedClient(clientRegistrationId, principalName);
}

final _replacing = BeanModule('zzzReplacingAutoConfiguration', [
  BeanDefinition<OAuth2AuthorizedClientService>(
    name: 'ownAuthorizedClientService',
    factoryMethodName: 'ownAuthorizedClientService',
    types: const [OAuth2AuthorizedClientService],
    source: 'package:replacing#AutoConfiguration.ownAuthorizedClientService',
    conditions: const [
      ConditionGroup('replacing.ownAuthorizedClientService', [
        ConditionalOnMissingBean(OAuth2AuthorizedClientService),
      ]),
    ],
    create: (r) => _OwnClients(r.dependency<ClientRegistrationRepository>()),
  ),
]);

void main() {
  final runner = const ApplicationContextRunner()
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
      .withAutoConfiguration(springSecurityCoreAutoConfiguration)
      .withAutoConfiguration(springBootStarterOauth2ClientAutoConfiguration)
      .withBean<HttpTransport>(MockHttpTransport.new);

  test('without registrations: nothing', () {
    runner.run((context) {
      expect(context.startupFailure, isNull);
      expect(context, doesNotHaveBean<ClientRegistrationRepository>());
      expect(context, doesNotHaveBean<OAuth2AuthorizedClientService>());
      expect(context, doesNotHaveBean<OAuth2AuthorizedClientManager>());
      expect(context, doesNotHaveBean<OAuth2AccessTokenInterceptor>());
    });
  });

  test('with registrations: the whole client', () async {
    await runner.withPropertyValues(_registration).runAsync((context) async {
      expect(context.startupFailure, isNull);
      final repository = context.getBean<ClientRegistrationRepository>();
      expect(
        (await repository.findByRegistrationId('github'))?.clientId,
        'gh',
      );
      expect(
        context.getBean<OAuth2AuthorizedClientService>(),
        isA<InMemoryOAuth2AuthorizedClientService>(),
      );
      expect(
        context.getBean<OAuth2AuthorizedClientManager>(),
        isA<AuthorizedClientServiceOAuth2AuthorizedClientManager>(),
      );
      expect(
        context.getBean<OidcIdTokenDecoder>(),
        isA<TokenEndpointOidcIdTokenDecoder>(),
      );
      expect(
        context.getBean<OAuth2UserService<OidcUserRequest, OidcUser>>(),
        isA<OidcUserService>(),
      );
      expect(
        context
            .getBean<
              OAuth2AccessTokenResponseClient<OAuth2RefreshTokenGrantRequest>
            >(),
        isA<DefaultRefreshTokenTokenResponseClient>(),
      );

      // Client credentials end to end, through the Feign starter's
      // transport bean.
      final transport = context.getBean<HttpTransport>() as MockHttpTransport;
      transport
          .when(HttpMethod.post, 'https://p.test/t')
          .respond(
            200,
            json: {'access_token': 'cc', 'token_type': 'Bearer'},
          );
      final client = await context
          .getBean<OAuth2AuthorizedClientManager>()
          .authorize(
            OAuth2AuthorizeRequest.withClientRegistrationId(
              'partner',
            ).principal(anonymousAuthentication).build(),
          );
      expect(client!.accessToken.tokenValue, 'cc');
    });
  });

  test('a bad registration fails the start', () {
    runner
        .withPropertyValues([
          'spring.security.oauth2.client.registration.github.client-secret=s',
        ])
        .run((context) {
          expect(context.startupFailure, isNotNull);
          expect(
            '${context.startupFailure}',
            contains("Client id of registration 'github' must not be empty"),
          );
        });
  });

  test("the application's beans win", () {
    final clients = _OwnClients(
      InMemoryClientRegistrationRepository([
        ClientRegistration.withRegistrationId('own')
            .clientId('own')
            .authorizationGrantType(AuthorizationGrantType.clientCredentials)
            .tokenUri('https://own.test/token')
            .build(),
      ]),
    );
    runner
        .withPropertyValues(_registration)
        .withBean<OAuth2AuthorizedClientService>(() => clients)
        .run((context) {
          expect(context, hasSingleBean<OAuth2AuthorizedClientService>());
          expect(
            context.getBean<OAuth2AuthorizedClientService>(),
            same(clients),
          );
        });
  });

  test('a module with `before` replaces a default; without it, too late', () {
    runner
        .withPropertyValues(_registration)
        .withAutoConfiguration(
          _replacing,
          const AutoConfigurationModule(
            before: ['springBootStarterOauth2ClientAutoConfiguration'],
          ),
        )
        .run((context) {
          expect(context.startupFailure, isNull);
          expect(context, hasSingleBean<OAuth2AuthorizedClientService>());
          expect(
            context.getBean<OAuth2AuthorizedClientService>(),
            isA<_OwnClients>(),
          );
        });
    runner
        .withPropertyValues(_registration)
        .withAutoConfiguration(_replacing)
        .run((
          context,
        ) {
          // Registered after the starter: the starter's default is taken.
          expect(
            context.getBean<OAuth2AuthorizedClientService>(),
            isNot(isA<_OwnClients>()),
          );
        });
  });

  group('Feign', () {
    test('spring.cloud.openfeign.oauth2.enabled adds the interceptor', () {
      runner
          .withPropertyValues([
            ..._registration,
            'spring.cloud.openfeign.oauth2.enabled=true',
            'spring.cloud.openfeign.oauth2.client-registration-id=partner',
          ])
          .run((context) {
            final interceptor = context.getBean<OAuth2AccessTokenInterceptor>();
            expect(interceptor.clientRegistrationId, 'partner');
            expect(
              context.getBeanNamesForType<RequestInterceptor>(),
              ['oauth2AccessTokenInterceptor'],
            );
            expect(
              context.getBean<ErrorDecoder>(),
              isA<OAuth2AccessTokenErrorDecoder>(),
            );
          });
    });

    test('off by default', () {
      runner.withPropertyValues(_registration).run((context) {
        expect(context, doesNotHaveBean<OAuth2AccessTokenInterceptor>());
        expect(context, doesNotHaveBean<ErrorDecoder>());
      });
    });

    test("an application's ErrorDecoder is kept", () {
      runner
          .withPropertyValues([
            ..._registration,
            'spring.cloud.openfeign.oauth2.enabled=true',
          ])
          .withBean<ErrorDecoder>(() => const DefaultErrorDecoder())
          .run((context) {
            expect(context, hasSingleBean<ErrorDecoder>());
            expect(context.getBean<ErrorDecoder>(), isA<DefaultErrorDecoder>());
            expect(context, hasSingleBean<OAuth2AccessTokenInterceptor>());
          });
    });
  });
}
