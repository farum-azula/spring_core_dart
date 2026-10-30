// The package's beans per platform, the app login when a registration is
// configured, the order before the OAuth2 client's module (its
// authorized client service replaces the client's in-memory one), and
// the application's own beans winning.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show
        ApplicationContextRunner,
        MockHttpTransport,
        doesNotHaveBean,
        hasSingleBean;

const _registration = [
  'spring.security.oauth2.client.registration.keycloak.client-id=neon-app',
  'spring.security.oauth2.client.registration.keycloak.authorization-grant-type=authorization_code',
  'spring.security.oauth2.client.registration.keycloak.redirect-uri=neonbooks:/oauth2/callback',
  'spring.security.oauth2.client.provider.keycloak.authorization-uri=https://sso.test/auth',
  'spring.security.oauth2.client.provider.keycloak.token-uri=https://sso.test/token',
];

void main() {
  // The modules in the wrong order on purpose: `before` puts this
  // package's first.
  final modules = const ApplicationContextRunner()
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
      .withAutoConfiguration(springSecurityCoreAutoConfiguration)
      .withAutoConfiguration(springBootStarterOauth2ClientAutoConfiguration)
      .withAutoConfiguration(
        springBootStarterFlutterSecurityAutoConfiguration,
        const AutoConfigurationModule(
          before: [
            'springBootStarterOauth2ClientAutoConfiguration',
            'springBootStarterFeignAutoConfiguration',
          ],
        ),
      );
  final runner = modules.withBean<HttpTransport>(MockHttpTransport.new);

  void on(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  test('on a phone: the secure store, the template, the login window', () {
    on(TargetPlatform.iOS);
    runner.run((context) {
      expect(context.startupFailure, isNull);
      expect(context.getBeanNamesForType<SecretStore>(), [
        'platformSecretStore',
      ]);
      expect(
        context.getBean<SecretTemplate>().secretStore,
        same(context.getBean<SecretStore>()),
      );
      expect(context.getBeanNamesForType<AuthorizationWindow>(), [
        'platformAuthorizationWindow',
      ]);
      expect(context, hasSingleBean<PrincipalNotifier>());
      // No registration, no login.
      expect(context, doesNotHaveBean<OAuth2LoginService>());
      expect(context, doesNotHaveBean<OAuth2AuthorizedClientService>());
    });
  });

  test('spring.flutter.security.ephemeral-session picks a private window', () {
    on(TargetPlatform.iOS);
    runner.run((context) {
      expect(
        context.getBean<PlatformAuthorizationWindow>().preferEphemeralSession,
        isFalse,
      );
    });
    runner
        .withPropertyValues([
          'spring.flutter.security.ephemeral-session=true',
        ])
        .run((context) {
          expect(
            context
                .getBean<PlatformAuthorizationWindow>()
                .preferEphemeralSession,
            isTrue,
          );
        });
  });

  test('on Windows and Linux: the secure store, the loopback window', () {
    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      on(platform);
      runner.run((context) {
        expect(context.getBeanNamesForType<SecretStore>(), [
          'platformSecretStore',
        ]);
        expect(context.getBeanNamesForType<AuthorizationWindow>(), [
          'loopbackAuthorizationWindow',
        ]);
      });
    }
  });

  test('without a secure storage: in memory, and no window', () {
    on(TargetPlatform.fuchsia);
    runner.run((context) {
      expect(context.getBeanNamesForType<SecretStore>(), [
        'inMemorySecretStore',
      ]);
      expect(context, hasSingleBean<SecretTemplate>());
      expect(context.getBeanNamesForType<AuthorizationWindow>(), isEmpty);
    });
  });

  test('with a registration: the app login on the secure store', () {
    on(TargetPlatform.android);
    runner.withPropertyValues(_registration).run((context) {
      expect(context.startupFailure, isNull);
      // The client's in-memory service yields to this package's.
      expect(context.getBeanNamesForType<OAuth2AuthorizedClientService>(), [
        'authorizedClientService',
      ]);
      final clients =
          context.getBean<OAuth2AuthorizedClientService>()
              as SecretStoreOAuth2AuthorizedClientService;
      expect(clients.secretStore, isA<PlatformSecretStore>());
      final login = context.getBean<NativeOAuth2LoginService>();
      expect(login.authorizedClientService, same(clients));
      expect(login.authorizationWindow, isA<PlatformAuthorizationWindow>());
      expect(login.revocationClient, isNotNull);
      expect(
        login.authorizedClientManager,
        same(context.getBean<OAuth2AuthorizedClientManager>()),
      );
      expect(login.idTokenDecoder, same(context.getBean<OidcIdTokenDecoder>()));
    });
  });

  test('Sign in with Apple: the sheet on iOS and macOS only', () {
    const apple = [
      'spring.security.oauth2.client.registration.apple.client-id=books.neon.app',
      'spring.security.oauth2.client.provider.apple.token-uri=https://api.neon.test/oauth2/apple/token',
    ];
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      on(platform);
      runner.withPropertyValues(apple).run((context) {
        expect(context.startupFailure, isNull);
        final login = context.getBean<NativeOAuth2LoginService>();
        expect(login.appleIdSignIn, isA<PlatformAppleIdSignIn>());
        expect(login.nativeSignIn, {'apple': NativeSignIn.apple});
        expect(login.nativeIdTokenDecoder, isA<JwkSetOidcIdTokenDecoder>());
      });
    }
    on(TargetPlatform.android);
    runner.withPropertyValues(apple).run((context) {
      expect(context, doesNotHaveBean<AppleIdSignIn>());
      expect(context.getBean<NativeOAuth2LoginService>().appleIdSignIn, isNull);
    });
  });

  test("with an application's ClientRegistrationRepository too", () {
    runner
        .withBean<ClientRegistrationRepository>(
          () => InMemoryClientRegistrationRepository([
            ClientRegistration.withRegistrationId('own')
                .clientId('own')
                .authorizationGrantType(
                  AuthorizationGrantType.authorizationCode,
                )
                .redirectUri('neonbooks:/oauth2/callback')
                .authorizationUri('https://sso.test/auth')
                .tokenUri('https://sso.test/token')
                .build(),
          ]),
        )
        .run((context) {
          expect(context.startupFailure, isNull);
          expect(context, hasSingleBean<OAuth2LoginService>());
          expect(
            context.getBean<OAuth2AuthorizedClientService>(),
            isA<SecretStoreOAuth2AuthorizedClientService>(),
          );
        });
  });

  test("the application's own beans win", () {
    final store = InMemorySecretStore();
    final window = _FakeWindow();
    runner
        .withPropertyValues(_registration)
        .withBean<SecretStore>(() => store)
        .withBean<AuthorizationWindow>(() => window)
        .run((context) {
          expect(context, hasSingleBean<SecretStore>());
          expect(context.getBean<SecretStore>(), same(store));
          expect(context, hasSingleBean<AuthorizationWindow>());
          expect(
            context.getBean<NativeOAuth2LoginService>().authorizationWindow,
            same(window),
          );
          expect(
            context.getBean<SecretTemplate>().secretStore,
            same(store),
          );
        });
  });

  group('in a browser (the web profile)', () {
    final web = modules
        .withPropertyValues(['spring.profiles.active=web'])
        .withBean<BrowserPage>(_FakePage.new);

    test('the server logs in: its login service, the CSRF transport', () {
      web.withPropertyValues(_registration).run((context) {
        expect(context.startupFailure, isNull);
        expect(context.getBeanNamesForType<OAuth2LoginService>(), [
          'serverOAuth2LoginService',
        ]);
        expect(context, doesNotHaveBean<NativeOAuth2LoginService>());
        // Feign's transport backs off: one, with the CSRF token.
        expect(context.getBeanNamesForType<HttpTransport>(), [
          'httpTransport',
        ]);
        final transport = context.getBean<HttpTransport>();
        expect(transport, isA<CsrfCookieHttpTransport>());
        expect(
          (transport as CsrfCookieHttpTransport).server.toString(),
          'http://localhost:5050',
        );
        final login = context.getBean<ServerOAuth2LoginService>();
        expect(login.transport, same(transport));
        expect(login.properties.userEndpoint, '/user');
        expect(context.getBeanNamesForType<SecretStore>(), [
          'inMemorySecretStore',
        ]);
      });
    });

    test('the profile decides for every bean: no platform bean next to the '
        "web's", () {
      // The VM of a test (any platform) with the web profile is a browser
      // for every bean of the module, as a real browser is.
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        on(platform);
        web.withPropertyValues(_registration).run((context) {
          expect(context.startupFailure, isNull);
          expect(context.getBeanNamesForType<SecretStore>(), [
            'inMemorySecretStore',
          ]);
          expect(context.getBeanNamesForType<AuthorizationWindow>(), isEmpty);
          expect(context, doesNotHaveBean<AppleIdSignIn>());
          expect(context, doesNotHaveBean<PlatformDPoPKey>());
          expect(context.getBeanNamesForType<OAuth2LoginService>(), [
            'serverOAuth2LoginService',
          ]);
        });
      }
    });

    test('without any registration too: they are the server\'s', () {
      web
          .withPropertyValues([
            'spring.flutter.security.web.server-url=http://localhost:8080',
          ])
          .run((context) {
            expect(context.startupFailure, isNull);
            expect(context, hasSingleBean<ServerOAuth2LoginService>());
            expect(
              context.getBean<CsrfCookieHttpTransport>().server.toString(),
              'http://localhost:8080',
            );
          });
    });

    test('a server on another origin gets the cookies, nothing else does', () {
      web
          .withPropertyValues([
            'spring.flutter.security.web.server-url=http://localhost:8080',
          ])
          .run((context) {
            final delegate = context
                .getBean<CsrfCookieHttpTransport>()
                .delegate;
            expect(delegate, isA<ServerCredentialsHttpTransport>());
            final routing = delegate as ServerCredentialsHttpTransport;
            expect(routing.server.toString(), 'http://localhost:8080');
            expect(
              routing.transportFor(
                HttpRequest(
                  method: HttpMethod.get,
                  url: Uri.parse('https://api.open-meteo.com/v1/forecast'),
                ),
              ),
              same(routing.otherTransport),
            );
            expect(
              routing.transportFor(
                HttpRequest(
                  method: HttpMethod.post,
                  url: Uri.parse('http://localhost:8080/api/orders'),
                ),
              ),
              same(routing.serverTransport),
            );
          });
      // The page's own origin: one transport, the browser's default.
      web.run((context) {
        expect(
          context.getBean<CsrfCookieHttpTransport>().delegate,
          isNot(isA<ServerCredentialsHttpTransport>()),
        );
      });
    });

    test("the application's own transport wins; the login wraps it", () {
      final own = MockHttpTransport();
      web.withBean<HttpTransport>(() => own).run((context) {
        expect(context.getBean<HttpTransport>(), same(own));
        final login = context.getBean<ServerOAuth2LoginService>();
        expect(login.transport, isA<CsrfCookieHttpTransport>());
        expect(
          (login.transport as CsrfCookieHttpTransport).delegate,
          same(own),
        );
      });
    });

    test('mode=spa without a registration or page stops the start', () {
      // The spa beans and messages: test/spa_auto_configuration_test.dart.
      web.withPropertyValues(['spring.flutter.security.web.mode=spa']).run((
        context,
      ) {
        expect(context.startupFailure, isNotNull);
      });
    });
  });

  test('outside a browser nothing of the web', () {
    on(TargetPlatform.android);
    runner
        .withPropertyValues([
          'spring.flutter.security.web.mode=spa', // read on the web only
        ])
        .run((context) {
          expect(context.startupFailure, isNull);
          expect(context, doesNotHaveBean<FlutterWebSecurityProperties>());
          expect(context, doesNotHaveBean<BrowserPage>());
          expect(context, doesNotHaveBean<CsrfCookieHttpTransport>());
          expect(context, doesNotHaveBean<OAuth2LoginService>());
        });
  });
}

class _FakeWindow implements AuthorizationWindow {
  @override
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  }) async => redirectUri;
}

class _FakePage implements BrowserPage {
  @override
  Uri get location => Uri.parse('http://localhost:5050/#/home');

  @override
  String? cookie(String name) => null;

  @override
  void navigate(Uri url) {}
}
