// The starter's beans: what comes with a registration, what backs off for
// an application's bean, and how another starter's auto-configuration (the
// Flutter starter's TokenStore and AuthorizationBrowser) replaces the
// defaults.
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

final class _PlatformStore extends InMemoryTokenStore {}

final class _PlatformBrowser implements AuthorizationBrowser {
  @override
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  }) async => redirectUri;
}

// What the Flutter starter's module looks like: its own TokenStore and
// AuthorizationBrowser, each only when the application has none.
final _flutter = BeanModule('springBootStarterFlutterAutoConfiguration', [
  BeanDefinition<TokenStore>(
    name: 'platformTokenStore',
    factoryMethodName: 'platformTokenStore',
    types: const [TokenStore],
    source: 'package:flutter#FlutterAutoConfiguration.platformTokenStore',
    conditions: const [
      ConditionGroup('flutter.platformTokenStore', [
        ConditionalOnMissingBean(TokenStore),
      ]),
    ],
    create: (_) => _PlatformStore(),
  ),
  BeanDefinition<AuthorizationBrowser>(
    name: 'platformAuthorizationBrowser',
    factoryMethodName: 'platformAuthorizationBrowser',
    types: const [AuthorizationBrowser],
    source: 'package:flutter#FlutterAutoConfiguration.browser',
    conditions: const [
      ConditionGroup('flutter.browser', [
        ConditionalOnMissingBean(AuthorizationBrowser),
      ]),
    ],
    create: (_) => _PlatformBrowser(),
  ),
]);

void main() {
  // As the generator passes the starter's module: with its `after`.
  final runner = const ApplicationContextRunner()
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
      .withAutoConfiguration(springSecurityCoreAutoConfiguration)
      .withAutoConfiguration(
        springBootStarterOauth2ClientAutoConfiguration,
        const AutoConfigurationModule(
          after: ['springBootStarterFlutterAutoConfiguration'],
        ),
      )
      .withBean<HttpTransport>(MockHttpTransport.new);

  test('without registrations: only the token store and the browser', () {
    runner.run((context) {
      expect(context.startupFailure, isNull);
      expect(context, hasSingleBean<TokenStore>());
      expect(context.getBean<TokenStore>(), isA<InMemoryTokenStore>());
      expect(
        context.getBean<AuthorizationBrowser>(),
        isA<LoopbackAuthorizationBrowser>(),
      );
      expect(context, doesNotHaveBean<ClientRegistrationRepository>());
      expect(context, doesNotHaveBean<OAuth2LoginService>());
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
        isA<TokenStoreOAuth2AuthorizedClientService>(),
      );
      expect(
        context.getBean<OAuth2AuthorizedClientManager>(),
        isA<AuthorizedClientServiceOAuth2AuthorizedClientManager>(),
      );
      expect(context, hasSingleBean<OAuth2LoginService>());
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
    final store = InMemoryTokenStore();
    runner
        .withPropertyValues(_registration)
        .withBean<TokenStore>(() => store)
        .withBean<AuthorizationBrowser>(_PlatformBrowser.new)
        .run((context) {
          expect(context, hasSingleBean<TokenStore>());
          expect(context.getBean<TokenStore>(), same(store));
          expect(
            context.getBean<AuthorizationBrowser>(),
            isA<_PlatformBrowser>(),
          );
        });
  });

  test("another auto-configuration's TokenStore and browser win", () {
    // Added last on purpose: the order comes from `after`.
    runner
        .withPropertyValues(_registration)
        .withAutoConfiguration(_flutter)
        .run((context) {
          expect(context.startupFailure, isNull);
          expect(context, hasSingleBean<TokenStore>());
          expect(context.getBean<TokenStore>(), isA<_PlatformStore>());
          expect(context, hasSingleBean<AuthorizationBrowser>());
          expect(
            context.getBean<AuthorizationBrowser>(),
            isA<_PlatformBrowser>(),
          );
          final service =
              context.getBean<OAuth2AuthorizedClientService>()
                  as TokenStoreOAuth2AuthorizedClientService;
          expect(service.tokenStore, isA<_PlatformStore>());
        });
  });

  test('any module with `before` wins too; without it, it comes too late', () {
    final platform = BeanModule('zzzPlatformAutoConfiguration', [
      ..._flutter.definitions,
    ]);
    runner
        .withPropertyValues(_registration)
        .withAutoConfiguration(
          platform,
          const AutoConfigurationModule(
            before: ['springBootStarterOauth2ClientAutoConfiguration'],
          ),
        )
        .run((context) {
          expect(context.getBean<TokenStore>(), isA<_PlatformStore>());
        });
    runner
        .withPropertyValues(_registration)
        .withAutoConfiguration(platform)
        .run(
          (context) {
            // Registered after the starter: the starter's default is taken.
            expect(context.getBean<TokenStore>(), isNot(isA<_PlatformStore>()));
          },
        );
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
