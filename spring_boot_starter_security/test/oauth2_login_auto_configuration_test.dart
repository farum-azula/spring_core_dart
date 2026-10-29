// What the starter does with spring.security.oauth2.client.* properties: the
// default chain logs browsers in with oauth2Login() (bearer tokens beside it
// with a JwtDecoder), there is no default user, the ID tokens of every user
// of the oidcIdTokenDecoder bean are checked with the provider's keys, and
// nothing changes without registrations. Through MockMvc, as an
// application runs.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';
import 'app/web/web.dart';
import 'chain_support.dart';
import 'oauth2_support.dart';
import 'support.dart';

const _r = 'spring.security.oauth2.client.registration.keycloak';
const _issuer = 'https://sso.test/realms/neon';
const _registration = [
  '$_r.client-id=$clientId',
  '$_r.client-secret=$clientSecret',
  '$_r.scope=openid,profile,email',
  'spring.security.oauth2.client.provider.keycloak.issuer-uri=$_issuer',
];

/// The application of test/app/web with every auto-configuration as the
/// generator passes them (with their `before` / `after`).
ApplicationContextRunner _runner(
  FakeOidcProvider provider, [
  List<String> properties = const [],
]) => const ApplicationContextRunner()
    .withUserConfiguration(securityWebBeans)
    .withAutoConfiguration(springBootAutoConfiguration)
    .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
    .withAutoConfiguration(springBootStarterWebAutoConfiguration)
    .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
    .withAutoConfiguration(springSecurityCoreAutoConfiguration)
    .withAutoConfiguration(springBootStarterOauth2ClientAutoConfiguration)
    .withAutoConfiguration(
      springBootStarterSecurityAutoConfiguration,
      const AutoConfigurationModule(
        after: ['springBootStarterOauth2ClientAutoConfiguration'],
      ),
    )
    .withAutoConfiguration(
      springBootStarterSecurityOAuth2ClientAutoConfiguration,
      const AutoConfigurationModule(
        before: ['springBootStarterOauth2ClientAutoConfiguration'],
      ),
    )
    .withBean<HttpTransport>(() => provider.transport)
    .withPropertyValues([
      'spring.test.web-environment=mock',
      'logging.level.root=warn',
      ...properties,
    ]);

Future<void> _withApp(
  ApplicationContextRunner runner,
  Future<void> Function(MockMvc mvc, ApplicationContext context) body,
) => runner.runAsync((started) async {
  final failure = started.startupFailure;
  if (failure != null) {
    fail('The application failed to start: $failure');
  }
  await body(MockMvc.of(started.context), started.context);
});

/// The browser's login: the protected page, the provider, the callback.
Future<MvcResult> _login(Browser browser, FakeOidcProvider provider) async {
  final protected = await browser.get('/api/me');
  expect(protected.status, 302);
  final start = await browser.get(protected.header('location')!);
  expect(start.status, 302);
  final callback = provider.approve(Uri.parse(start.header('location')!));
  return await browser.get('${callback.path}?${callback.query}');
}

void main() {
  group('with registrations', () {
    test('the beans: the decoder of servers, no default user', () async {
      final provider = FakeOidcProvider();
      await _withApp(_runner(provider, _registration), (_, context) async {
        expect(context, hasSingleBean<ClientRegistrationRepository>());
        expect(context, hasSingleBean<OidcIdTokenDecoder>());
        expect(
          context.getBean<OidcIdTokenDecoder>(),
          isA<OidcIdTokenDecoderFactory>(),
        );
        expect(
          context.getBean<OAuth2AuthorizedClientRepository>(),
          isA<AuthenticatedPrincipalOAuth2AuthorizedClientRepository>(),
        );
        expect(context, doesNotHaveBean<UserDetailsService>());
        final chain = context.getBean<SecurityFilterChain>();
        expect(
          filterTypes(chain),
          containsAllInOrder([
            LogoutFilter,
            OAuth2AuthorizationRequestRedirectFilter,
            OAuth2LoginAuthenticationFilter,
            DefaultLoginPageGeneratingFilter,
            AuthorizationFilter,
          ]),
        );
        expect(filterTypes(chain), isNot(contains(BasicAuthenticationFilter)));
      });
    });

    test('a browser logs in through the provider', () async {
      final provider = FakeOidcProvider();
      await _withApp(_runner(provider, _registration), (mvc, _) async {
        final browser = Browser(mvc);
        final callback = await _login(browser, provider);
        expect(callback.status, 302);
        expect(callback.header('location'), '/api/me?continue');
        final me = await browser.get('/api/me', accept: 'application/json');
        expect(me.status, 200);
        final json = jsonDecode(me.response.bodyText) as Map<String, Object?>;
        expect(json['name'], 'user-1');
        expect(json['authorities'], contains('OIDC_USER'));
        expect(provider.jwkFetches, 1, reason: 'the signature was checked');
      });
    });

    test('an ID token signed by another key is refused', () async {
      final provider = FakeOidcProvider()..signer = otherKeys;
      await _withApp(_runner(provider, _registration), (mvc, _) async {
        final browser = Browser(mvc);
        final callback = await _login(browser, provider);
        expect(callback.header('location'), '/login?error');
        expect((await browser.get('/api/me')).status, 302);
      });
    });

    test('the GrantedAuthoritiesMapper bean maps the users', () async {
      final provider = FakeOidcProvider();
      await _withApp(
        _runner(provider, _registration).withBean<GrantedAuthoritiesMapper>(
          () => const _Roles(),
        ),
        (mvc, _) async {
          final browser = Browser(mvc);
          await _login(browser, provider);
          final me = await browser.get('/api/me', accept: 'application/json');
          expect(me.response.bodyText, contains('ROLE_USER'));
        },
      );
    });

    test('a default user only when asked for by its properties', () async {
      final provider = FakeOidcProvider();
      await _withApp(
        _runner(provider, [
          ..._registration,
          'spring.security.user.password=pw',
        ]),
        (_, context) async {
          expect(context, hasSingleBean<UserDetailsService>());
        },
      );
    });

    test('with a JwtDecoder: sessions for browsers, tokens for apps', () async {
      final provider = FakeOidcProvider();
      final runner = _runner(provider, _registration).withBean<JwtDecoder>(
        () => NimbusJwtDecoder.withJwkSource(
          StaticJwkSource([testKeys.rsa.verificationKey]),
        ),
      );
      await _withApp(runner, (mvc, context) async {
        expect(
          filterTypes(context.getBean<SecurityFilterChain>()),
          containsAll([
            OAuth2LoginAuthenticationFilter,
            BearerTokenAuthenticationFilter,
          ]),
        );
        // A native app with its access token.
        final api = await mvc.perform(
          request(
            HttpMethod.get,
            '/api/me',
            headers: {
              'authorization': 'Bearer ${testKeys.token()}',
              'accept': 'application/json',
            },
          ),
        );
        expect(api.status, 200);
        expect(api.response.bodyText, contains('"name":"ada"'));
        // A program without a token: a 401, not a login page.
        final anonymous = await mvc.perform(
          request(
            HttpMethod.get,
            '/api/me',
            headers: {'accept': 'application/json'},
          ),
        );
        expect(anonymous.status, 401);
        expect(anonymous.header('www-authenticate'), startsWith('Bearer'));
        // A forged token.
        final forged = await mvc.perform(
          request(
            HttpMethod.get,
            '/api/me',
            headers: {'authorization': 'Bearer ${otherKeys.token()}'},
          ),
        );
        expect(forged.status, 401);
        // A browser logs in with the session.
        final browser = Browser(mvc);
        await _login(browser, provider);
        final me = await browser.get('/api/me', accept: 'application/json');
        expect(me.status, 200);
        expect(me.response.bodyText, contains('user-1'));
        expect(browser.cookies, contains('JSESSIONID'));
      });
    });
  });

  group('without registrations', () {
    test('nothing changes: form login, Basic, the default user', () async {
      final provider = FakeOidcProvider();
      await _withApp(_runner(provider), (_, context) async {
        expect(context, doesNotHaveBean<ClientRegistrationRepository>());
        expect(context, doesNotHaveBean<OidcIdTokenDecoder>());
        expect(context, doesNotHaveBean<OAuth2AuthorizedClientRepository>());
        expect(context, hasSingleBean<UserDetailsService>());
        final types = filterTypes(context.getBean<SecurityFilterChain>());
        expect(types, contains(UsernamePasswordAuthenticationFilter));
        expect(types, contains(BasicAuthenticationFilter));
        expect(types, isNot(contains(OAuth2LoginAuthenticationFilter)));
      });
    });
  });

  group('the oidcIdTokenDecoder bean', () {
    test("the application's own decoder is kept", () async {
      final provider = FakeOidcProvider();
      final own = TokenEndpointOidcIdTokenDecoder();
      await _withApp(
        _runner(provider, _registration).withBean<OidcIdTokenDecoder>(
          () => own,
        ),
        (mvc, context) async {
          expect(context.getBean<OidcIdTokenDecoder>(), same(own));
          // oauth2Login() never takes the app decoder, which trusts TLS:
          // a forged signature still fails.
          provider.signer = otherKeys;
          final browser = Browser(mvc);
          final callback = await _login(browser, provider);
          expect(callback.header('location'), '/login?error');
        },
      );
    });
  });
}

final class _Roles implements GrantedAuthoritiesMapper {
  const _Roles();

  @override
  List<GrantedAuthority> mapAuthorities(
    Iterable<GrantedAuthority> authorities,
  ) => [...authorities, SimpleGrantedAuthority('ROLE_USER')];
}
