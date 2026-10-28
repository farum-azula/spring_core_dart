// Registrations: the builder's checks, the common providers, discovery,
// the properties of Spring Boot and the lazy repository.
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/fake_provider.dart';

Environment environment(Map<String, Object> properties) {
  final environment = StandardEnvironment();
  environment.propertySources.addFirst(MapPropertySource('test', properties));
  ConfigurationPropertySources.attach(environment);
  return environment;
}

Future<Map<String, ClientRegistration>> mapped(
  Map<String, Object> properties, {
  HttpTransport? transport,
}) async {
  final suppliers = OAuth2ClientPropertiesMapper(
    OAuth2ClientProperties.of(environment(properties)),
    transport: transport ?? MockHttpTransport(),
  ).asClientRegistrations();
  return {
    for (final MapEntry(:key, :value) in suppliers.entries) key: await value(),
  };
}

const _r = 'spring.security.oauth2.client.registration';
const _p = 'spring.security.oauth2.client.provider';

void main() {
  group('ClientRegistration.builder', () {
    test('an authorization_code registration needs its URIs', () {
      final builder = ClientRegistration.withRegistrationId('x')
          .clientId('c')
          .authorizationGrantType(AuthorizationGrantType.authorizationCode)
          .redirectUri('app:/cb')
          .authorizationUri('https://p/auth');
      expect(builder.build, throwsArgumentError); // no token URI
      expect(builder.tokenUri('https://p/token').build().clientName, 'x');
    });

    test('client_credentials needs a token URI only', () {
      final registration = ClientRegistration.withRegistrationId('x')
          .clientId('c')
          .clientSecret('s')
          .authorizationGrantType(AuthorizationGrantType.clientCredentials)
          .tokenUri('https://p/token')
          .build();
      expect(
        registration.clientAuthenticationMethod,
        ClientAuthenticationMethod.clientSecretBasic,
      );
    });

    test('without a secret, authorization_code is a public client', () {
      final registration = CommonOAuth2Provider.github
          .getBuilder('github')
          .clientId('c')
          .clientAuthenticationMethod(null)
          .build();
      expect(
        registration.clientAuthenticationMethod,
        ClientAuthenticationMethod.none,
      );
    });

    test('invalid scope characters are refused', () {
      expect(
        () => CommonOAuth2Provider.github.getBuilder('g').clientId('c').scope([
          'read user',
        ]).build(),
        throwsArgumentError,
      );
    });

    test('toString hides the secret', () {
      final registration = CommonOAuth2Provider.google
          .getBuilder('google')
          .clientId('c')
          .clientSecret('very-secret')
          .build();
      expect('$registration', isNot(contains('very-secret')));
    });
  });

  test("CommonOAuth2Provider has Spring's URIs", () {
    final google = CommonOAuth2Provider.google
        .getBuilder('google')
        .clientId('c')
        .build();
    expect(
      google.providerDetails.authorizationUri,
      'https://accounts.google.com/o/oauth2/v2/auth',
    );
    expect(
      google.providerDetails.tokenUri,
      'https://www.googleapis.com/oauth2/v4/token',
    );
    expect(google.providerDetails.issuerUri, 'https://accounts.google.com');
    expect(google.scopes, {'openid', 'profile', 'email'});
    expect(
      google.redirectUri,
      '{baseUrl}/{action}/oauth2/code/{registrationId}',
    );
    final github = CommonOAuth2Provider.github
        .getBuilder('github')
        .clientId('c')
        .build();
    expect(
      github.providerDetails.userInfoEndpoint.userNameAttributeName,
      'id',
    );
    expect(github.scopes, {'read:user'});
    final facebook = CommonOAuth2Provider.facebook
        .getBuilder('fb')
        .clientId('c')
        .clientSecret('s')
        .build();
    expect(
      facebook.clientAuthenticationMethod,
      ClientAuthenticationMethod.clientSecretPost,
    );
    expect(
      facebook.providerDetails.userInfoEndpoint.uri,
      'https://graph.facebook.com/me?fields=id,name,email',
    );
    expect(CommonOAuth2Provider.of('GitHub'), CommonOAuth2Provider.github);
    expect(CommonOAuth2Provider.of('keycloak'), isNull);
  });

  group('expandRedirectUri', () {
    final registration = CommonOAuth2Provider.google
        .getBuilder('google')
        .clientId('c')
        .build();

    test("Spring's template with a server's base URL", () {
      expect(
        expandRedirectUri(
          registration,
          baseUrl: Uri.parse('https://shop.example.com:8443/app/'),
        ),
        'https://shop.example.com:8443/app/login/oauth2/code/google',
      );
    });

    test('an app keeps 127.0.0.1 (a loopback redirect)', () {
      expect(
        expandRedirectUri(registration),
        'http://127.0.0.1/login/oauth2/code/google',
      );
    });

    test('the parts of the base URL', () {
      final custom = ClientRegistration.withClientRegistration(registration)
          .redirectUri('{baseScheme}://{baseHost}{basePort}{basePath}/{action}')
          .build();
      expect(
        expandRedirectUri(
          custom,
          baseUrl: Uri.parse('http://h:81/p'),
          action: 'authorize',
        ),
        'http://h:81/p/authorize',
      );
    });
  });

  group('discovery', () {
    test('OpenID Connect metadata fills the registration', () async {
      final provider = FakeProvider();
      final builder = await ClientRegistrations.fromIssuerLocation(
        issuer,
        transport: provider.transport,
      );
      final registration = builder.clientId('c').build();
      final details = registration.providerDetails;
      expect(registration.registrationId, 'sso.test');
      expect(details.issuerUri, issuer);
      expect(details.tokenUri, 'https://sso.test/token');
      expect(details.jwkSetUri, 'https://sso.test/certs');
      expect(details.userInfoEndpoint.uri, 'https://sso.test/userinfo');
      expect(details.userInfoEndpoint.userNameAttributeName, 'sub');
      expect(details.revocationEndpoint, 'https://sso.test/revoke');
      expect(details.endSessionEndpoint, 'https://sso.test/logout');
      expect(
        registration.clientAuthenticationMethod,
        ClientAuthenticationMethod.clientSecretBasic,
      );
    });

    test('falls back to the OAuth 2.0 metadata after a 404', () async {
      final transport = MockHttpTransport()
        ..when(
          HttpMethod.get,
          'https://as.test/tenant/.well-known/openid-configuration',
        ).respond(404)
        ..when(
          HttpMethod.get,
          'https://as.test/.well-known/openid-configuration/tenant',
        ).respond(404)
        ..when(
          HttpMethod.get,
          'https://as.test/.well-known/oauth-authorization-server/tenant',
        ).respond(
          200,
          json: {
            'issuer': 'https://as.test/tenant',
            'authorization_endpoint': 'https://as.test/a',
            'token_endpoint': 'https://as.test/t',
            'token_endpoint_auth_methods_supported': ['client_secret_post'],
          },
        );
      final registration = (await ClientRegistrations.fromIssuerLocation(
        'https://as.test/tenant',
        transport: transport,
      )).clientId('c').build();
      expect(registration.providerDetails.tokenUri, 'https://as.test/t');
      expect(
        registration.clientAuthenticationMethod,
        ClientAuthenticationMethod.clientSecretPost,
      );
      expect(transport.requests, hasLength(3));
    });

    test('an issuer that differs from the requested one is refused', () {
      final transport = MockHttpTransport()
        ..when(
          HttpMethod.get,
          'https://sso.test/realms/neon/.well-known/openid-configuration',
        ).respond(
          200,
          json: {
            'issuer': 'https://evil.test',
            'authorization_endpoint': 'https://evil.test/a',
            'token_endpoint': 'https://evil.test/t',
            'jwks_uri': 'https://evil.test/k',
          },
        );
      expect(
        ClientRegistrations.fromIssuerLocation(issuer, transport: transport),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('did not match the requested issuer'),
          ),
        ),
      );
    });

    test('a server error stops the search', () {
      final transport = MockHttpTransport()
        ..when(
          HttpMethod.get,
          'https://sso.test/realms/neon/.well-known/openid-configuration',
        ).respond(500);
      expect(
        ClientRegistrations.fromIssuerLocation(issuer, transport: transport),
        throwsArgumentError,
      );
      expect(transport.requests, hasLength(1));
    });

    test('metadata without a token endpoint is refused', () {
      final transport = MockHttpTransport()
        ..when(
          HttpMethod.get,
          'https://sso.test/realms/neon/.well-known/openid-configuration',
        ).respond(
          200,
          json: {
            'issuer': issuer,
            'authorization_endpoint': 'https://sso.test/a',
            'jwks_uri': 'https://sso.test/k',
          },
        );
      expect(
        ClientRegistrations.fromOidcIssuerLocation(
          issuer,
          transport: transport,
        ),
        throwsArgumentError,
      );
    });
  });

  group("Spring Boot's properties", () {
    test('a common provider needs only the client', () async {
      final registrations = await mapped({
        '$_r.google.client-id': 'g-id',
        '$_r.google.client-secret': 'g-secret',
        '$_r.my-github.provider': 'github',
        '$_r.my-github.client-id': 'gh-id',
      });
      final google = registrations['google']!;
      expect(google.clientId, 'g-id');
      expect(google.clientSecret, 'g-secret');
      expect(
        google.clientAuthenticationMethod,
        ClientAuthenticationMethod.clientSecretBasic,
      );
      expect(google.clientName, 'Google');
      final github = registrations['my-github']!;
      expect(github.registrationId, 'my-github');
      expect(
        github.providerDetails.tokenUri,
        'https://github.com/login/oauth/access_token',
      );
      // No secret: a public client (this starter's choice for apps).
      expect(
        github.clientAuthenticationMethod,
        ClientAuthenticationMethod.none,
      );
    });

    test('a custom provider from its properties', () async {
      final registrations = await mapped({
        '$_r.partner.client-id': 'shop',
        '$_r.partner.client-secret': 's',
        '$_r.partner.authorization-grant-type': 'client_credentials',
        '$_r.partner.scope': 'orders.read, orders.write',
        '$_p.partner.token-uri': 'https://partner.test/token',
      });
      final partner = registrations['partner']!;
      expect(
        partner.authorizationGrantType,
        AuthorizationGrantType.clientCredentials,
      );
      expect(partner.scopes, {'orders.read', 'orders.write'});
    });

    test('scopes as a YAML list', () async {
      final registrations = await mapped({
        '$_r.google.client-id': 'c',
        '$_r.google.scope[0]': 'openid',
        '$_r.google.scope[1]': 'email',
      });
      expect(registrations['google']!.scopes, {'openid', 'email'});
    });

    test('provider properties override the common provider', () async {
      final registrations = await mapped({
        '$_r.okta.client-id': 'c',
        '$_p.okta.authorization-uri': 'https://okta.test/a',
        '$_p.okta.token-uri': 'https://okta.test/t',
        '$_p.okta.user-name-attribute': 'email',
      });
      final okta = registrations['okta']!;
      expect(okta.providerDetails.tokenUri, 'https://okta.test/t');
      expect(
        okta.providerDetails.userInfoEndpoint.userNameAttributeName,
        'email',
      );
    });

    test('an issuer is discovered at first use, not at startup', () async {
      final provider = FakeProvider();
      final suppliers = OAuth2ClientPropertiesMapper(
        OAuth2ClientProperties.of(
          environment({
            '$_r.keycloak.client-id': clientId,
            '$_r.keycloak.scope': 'openid,profile',
            '$_r.keycloak.redirect-uri': 'neonbooks:/oauth2/callback',
            '$_p.keycloak.issuer-uri': issuer,
          }),
        ),
        transport: provider.transport,
      ).asClientRegistrations();
      expect(provider.transport.requests, isEmpty);
      final keycloak = await suppliers['keycloak']!();
      expect(keycloak.registrationId, 'keycloak');
      expect(keycloak.providerDetails.issuerUri, issuer);
      expect(keycloak.redirectUri, 'neonbooks:/oauth2/callback');
      expect(
        keycloak.clientAuthenticationMethod,
        ClientAuthenticationMethod.none,
      );
    });

    test('a missing client id fails the start', () {
      expect(
        () => mapped({'$_r.google.client-secret': 's'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            "Client id of registration 'google' must not be empty.",
          ),
        ),
      );
    });

    test('an unknown provider fails the start', () {
      expect(
        () => mapped({'$_r.x.client-id': 'c', '$_r.x.provider': 'nowhere'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            "Unknown provider ID 'nowhere'",
          ),
        ),
      );
      expect(
        () => mapped({'$_r.x.client-id': 'c'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Provider ID must be specified'),
          ),
        ),
      );
    });

    test('hasRegistrations', () {
      expect(OAuth2ClientProperties.hasRegistrations(environment({})), isFalse);
      expect(
        OAuth2ClientProperties.hasRegistrations(
          environment({'$_r.google.client-id': 'c'}),
        ),
        isTrue,
      );
    });
  });

  group('InMemoryClientRegistrationRepository', () {
    test('a failed supplier is tried again; a success is kept', () async {
      var calls = 0;
      final registration = CommonOAuth2Provider.github
          .getBuilder('github')
          .clientId('c')
          .build();
      final repository = InMemoryClientRegistrationRepository.lazy({
        'github': () async {
          calls++;
          if (calls == 1) {
            throw HttpTransportException('offline');
          }
          return registration;
        },
      });
      await expectLater(
        repository.findByRegistrationId('github'),
        throwsA(isA<HttpTransportException>()),
      );
      expect(
        await repository.findByRegistrationId('github'),
        same(registration),
      );
      expect(
        await repository.findByRegistrationId('github'),
        same(registration),
      );
      expect(calls, 2);
      expect(await repository.findByRegistrationId('nope'), isNull);
      expect(repository.registrationIds, ['github']);
    });

    test('duplicate ids are refused', () {
      final registration = CommonOAuth2Provider.github
          .getBuilder('github')
          .clientId('c')
          .build();
      expect(
        () =>
            InMemoryClientRegistrationRepository([registration, registration]),
        throwsArgumentError,
      );
    });
  });
}
