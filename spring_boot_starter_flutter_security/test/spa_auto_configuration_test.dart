// The beans of the web login in spa mode: the browser's login service,
// the tokens in the tab's memory, the WebCrypto DPoP key before the
// OAuth2 client's, no CSRF transport; the start fails without a
// registration.
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
  'spring.security.oauth2.client.registration.keycloak.client-id=neon-web',
  'spring.security.oauth2.client.registration.keycloak.authorization-grant-type=authorization_code',
  'spring.security.oauth2.client.registration.keycloak.redirect-uri={baseUrl}/',
  'spring.security.oauth2.client.provider.keycloak.authorization-uri=https://sso.test/auth',
  'spring.security.oauth2.client.provider.keycloak.token-uri=https://sso.test/token',
];

void main() {
  final spa = const ApplicationContextRunner()
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
      )
      .withBean<HttpTransport>(MockHttpTransport.new)
      .withBean<SpaBrowserPage>(_FakePage.new)
      .withPropertyValues([
        'spring.profiles.active=web',
        'spring.flutter.security.web.mode=spa',
      ]);

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  });

  test('the browser logs in: its service, the tab, the WebCrypto key', () {
    spa.withPropertyValues(_registration).run((context) {
      expect(context.startupFailure, isNull);
      expect(context.getBeanNamesForType<OAuth2LoginService>(), [
        'spaOAuth2LoginService',
      ]);
      expect(context.getBeanNamesForType<OAuth2AuthorizedClientService>(), [
        'tabAuthorizedClientService',
      ]);
      expect(context.getBeanNamesForType<DPoPKey>(), ['webCryptoDPoPKey']);
      final key = context.getBean<DPoPKey>() as WebCryptoDPoPKey;
      expect(key.isLoaded, isFalse); // nothing asked of the browser yet
      final login = context.getBean<SpaOAuth2LoginService>();
      expect(login.dPoPKey, same(key));
      expect(login.properties.mode, WebLoginMode.spa);
      expect(login.page, same(context.getBean<SpaBrowserPage>()));
      expect(context, doesNotHaveBean<ServerOAuth2LoginService>());
      expect(context, doesNotHaveBean<CsrfCookieHttpTransport>());
      expect(context, doesNotHaveBean<NativeOAuth2LoginService>());
      expect(
        context,
        doesNotHaveBean<SecretStoreOAuth2AuthorizedClientService>(),
      );
      // Feign's transport (the application's here), no cookies, no CSRF.
      expect(context.getBean<HttpTransport>(), isA<MockHttpTransport>());
      // The page is the spa page; no second one.
      expect(context.getBeanNamesForType<BrowserPage>(), isEmpty);
    });
  });

  test('without a registration the start fails, saying what is missing', () {
    spa.run((context) {
      expect(context.startupFailure, isNotNull);
      expect(
        '${context.startupFailure}',
        allOf(
          contains('mode=spa'),
          contains('spring.security.oauth2.client.registration'),
        ),
      );
    });
  });

  test("the application's own DPoP key and login win", () {
    final key = SoftwareDPoPKey.generate();
    spa.withPropertyValues(_registration).withBean<DPoPKey>(() => key).run((
      context,
    ) {
      expect(context.getBean<DPoPKey>(), same(key));
      expect(context.getBean<SpaOAuth2LoginService>().dPoPKey, same(key));
    });
  });

  test('server mode has none of it', () {
    spa
        .withPropertyValues(_registration)
        .withPropertyValues(['spring.flutter.security.web.mode=server'])
        .withBean<BrowserPage>(_FakePage.new)
        .run((context) {
          expect(context.startupFailure, isNull);
          expect(context, doesNotHaveBean<SpaOAuth2LoginService>());
          expect(context, doesNotHaveBean<WebCryptoDPoPKey>());
          expect(context, doesNotHaveBean<TabOAuth2AuthorizedClientService>());
          expect(context, hasSingleBean<ServerOAuth2LoginService>());
        });
  });
}

class _FakePage implements SpaBrowserPage {
  @override
  Uri get location => Uri.parse('http://localhost:5050/');

  @override
  Uri get baseUri => Uri.parse('http://localhost:5050/');

  @override
  String? cookie(String name) => null;

  @override
  void navigate(Uri url) {}

  @override
  void replaceLocation(Uri url) {}

  @override
  final BrowserStorage sessionStorage = InMemoryBrowserStorage();

  @override
  final BrowserStorage localStorage = InMemoryBrowserStorage();
}
