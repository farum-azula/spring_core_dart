// The access token on RestClient calls: OAuth2ClientHttpRequestInterceptor
// (Bearer, DPoP with the nonce retry, the refresh after a 401, the
// registration from the request attribute or the default one, a missing
// registration), @ClientRegistrationId, the group configurer, and the
// auto-configuration on the RestClient starter's builders and allow list.
import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/spring_auto_configuration.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/fake_provider.dart';

const _json = MapType<String, Object?>(ClassType<String>(), DynamicType());

Map<String, Object?> _claims(String proof) {
  final payload = proof.split('.')[1];
  return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload))))
      as Map<String, Object?>;
}

final class _FixedManager implements OAuth2AuthorizedClientManager {
  _FixedManager(this.client);

  OAuth2AuthorizedClient? client;
  final List<String> registrations = [];

  @override
  Future<OAuth2AuthorizedClient?> authorize(
    OAuth2AuthorizeRequest authorizeRequest,
  ) async {
    registrations.add(authorizeRequest.clientRegistrationId);
    return client;
  }
}

void main() {
  group('Bearer tokens and the refresh', () {
    late ClientFixture fixture;
    late RestClient rest;

    setUp(() async {
      fixture = await ClientFixture.create();
      rest = RestClient.builder()
          .baseUrl('https://api.test')
          .transport(fixture.provider.transport)
          .requestInterceptor(
            OAuth2ClientHttpRequestInterceptor(
              fixture.manager,
              authorizedClientService: fixture.clients,
              securityContextHolderStrategy: fixture.strategy,
            ),
          )
          .build();
    });

    Future<Map<String, Object?>> me() => rest
        .get()
        .uri('/me')
        .attributes(ClientAttributes.clientRegistrationId('keycloak'))
        .retrieve()
        .body(_json);

    test("the attribute's registration: the current user's token", () async {
      await fixture.signIn();
      final client = await fixture.clients.loadAuthorizedClient(
        'keycloak',
        'user-1',
      );
      expect(await me(), {'token': client!.accessToken.tokenValue});
      expect(
        fixture.provider.transport.lastRequest.headers.getAll('Authorization'),
        ['Bearer ${client.accessToken.tokenValue}'],
      );
    });

    test('a call without the attribute is sent without a token', () async {
      await fixture.signIn();
      await expectLater(
        rest.get().uri('/me').retrieve().body(_json),
        throwsA(isA<HttpClientErrorException>()),
      );
      expect(
        fixture.provider.transport.lastRequest.headers['Authorization'],
        isNull,
      );
    });

    test('a 401 marks the token expired: the next call refreshes', () async {
      await fixture.signIn();
      final first = await me();
      fixture.provider.rejectedAccessTokens.add(first['token']! as String);
      await expectLater(me(), throwsA(isA<HttpClientErrorException>()));

      final second = await me();
      expect(second['token'], isNot(first['token']));
      expect(
        fixture.provider.tokenRequests.last['grant_type'],
        'refresh_token',
      );
    });

    test('a registration that does not exist fails before sending', () async {
      await fixture.signIn();
      final sent = fixture.provider.transport.requests.length;
      await expectLater(
        rest
            .get()
            .uri('/me')
            .attribute(ClientAttributes.clientRegistrationIdAttributeName, 'x')
            .retrieve()
            .body(_json),
        throwsArgumentError,
      );
      expect(fixture.provider.transport.requests, hasLength(sent));
    });

    test('nobody logged in: the call fails before sending', () async {
      final sent = fixture.provider.transport.requests.length;
      await expectLater(
        me(),
        throwsA(isA<ClientAuthorizationRequiredException>()),
      );
      expect(fixture.provider.transport.requests, hasLength(sent));
    });
  });

  group('the registration of a call', () {
    final registration = ClientRegistration.withRegistrationId('partner')
        .clientId('shop')
        .clientSecret('s')
        .authorizationGrantType(AuthorizationGrantType.clientCredentials)
        .tokenUri('https://sso.test/token')
        .build();
    late MockHttpTransport api;
    late _FixedManager manager;

    setUp(() {
      api = MockHttpTransport()
        ..when(HttpMethod.get, 'https://api.test/orders').respond(200);
      manager = _FixedManager(
        OAuth2AuthorizedClient(
          registration,
          'anonymousUser',
          OAuth2AccessToken(TokenType.bearer, 'partner-token'),
        ),
      );
    });

    RestClient client(OAuth2ClientHttpRequestInterceptor interceptor) =>
        RestClient.builder()
            .transport(api)
            .requestInterceptor(interceptor)
            .build();

    test('the attribute set by hand wins over the default', () async {
      final rest = client(
        OAuth2ClientHttpRequestInterceptor(
          manager,
          defaultClientRegistrationId: 'fallback',
        ),
      );
      await rest
          .get()
          .uri('https://api.test/orders')
          .attributes(ClientAttributes.clientRegistrationId('partner'))
          .retrieve()
          .toBodilessEntity();
      await rest
          .get()
          .uri('https://api.test/orders')
          .retrieve()
          .toBodilessEntity();
      expect(manager.registrations, ['partner', 'fallback']);
      expect(api.lastRequest.headers['Authorization'], 'Bearer partner-token');
    });

    test('@ClientRegistrationId is the request attribute', () async {
      const annotation = ClientRegistrationId('partner');
      expect(annotation, isA<HttpRequestAttribute>());
      expect(
        annotation.attributeName,
        ClientAttributes.clientRegistrationIdAttributeName,
      );
      final rest = client(OAuth2ClientHttpRequestInterceptor(manager));
      await rest
          .get()
          .uri('https://api.test/orders')
          .attribute(annotation.attributeName, annotation.attributeValue)
          .retrieve()
          .toBodilessEntity();
      expect(manager.registrations, ['partner']);
    });

    test('no authorized client: the call goes without a token', () async {
      manager.client = null;
      final rest = client(OAuth2ClientHttpRequestInterceptor(manager));
      await rest
          .get()
          .uri('https://api.test/orders')
          .attributes(ClientAttributes.clientRegistrationId('partner'))
          .header('Authorization', 'Basic stale')
          .retrieve()
          .toBodilessEntity();
      expect(api.lastRequest.headers['Authorization'], 'Basic stale');
    });

    test('the group configurer adds one interceptor per builder', () {
      final builders = {
        const HttpServiceGroup('orders'): RestClient.builder(),
      };
      final configurer =
          OAuth2RestClientHttpServiceGroupConfigurer.from(manager)
            ..configureGroups(HttpServiceGroupBuilders(builders))
            ..configureGroups(HttpServiceGroupBuilders(builders));
      final interceptors = <ClientHttpRequestInterceptor>[];
      builders.values.single.requestInterceptors(interceptors.addAll);
      expect(interceptors, [same(configurer.interceptor)]);
    });
  });

  group('DPoP', () {
    final key = SoftwareDPoPKey.generate();
    final registration = ClientRegistration.withRegistrationId('partner')
        .clientId('shop')
        .clientSecret('s')
        .authorizationGrantType(AuthorizationGrantType.clientCredentials)
        .tokenUri('https://sso.test/token')
        .dpop(DPoPMode.enabled)
        .build();
    final stored = OAuth2AuthorizedClient(
      registration,
      'anonymousUser',
      OAuth2AccessToken(TokenType.dpop, 'dpop-token'),
    );

    test('DPoP <token> and a proof of this request; a nonce asked for is '
        'sent once more, then kept for the server', () async {
      final api = MockHttpTransport()
        ..when(HttpMethod.post, 'https://api.test/orders').respond(
          401,
          headers: {
            'WWW-Authenticate': 'DPoP error="use_dpop_nonce"',
            'DPoP-Nonce': 'n-1',
          },
        )
        ..when(HttpMethod.post, 'https://api.test/orders').respond(201);
      final service = InMemoryOAuth2AuthorizedClientService(
        InMemoryClientRegistrationRepository([registration]),
      );
      await service.saveAuthorizedClient(stored, anonymousAuthentication);
      final rest = RestClient.builder()
          .baseUrl('https://api.test')
          .transport(api)
          .requestInterceptor(
            OAuth2ClientHttpRequestInterceptor(
              _FixedManager(stored),
              authorizedClientService: service,
              dPoPKey: key,
              defaultClientRegistrationId: 'partner',
            ),
          )
          .build();

      final entity = await rest
          .post()
          .uri('/orders?page=2')
          .body('{}')
          .retrieve()
          .toBodilessEntity();
      expect(entity.statusCode.value, 201);
      expect(api.requests, hasLength(2));
      final (first, second) = (api.requests[0], api.requests[1]);
      expect(first.headers.getAll('Authorization'), ['DPoP dpop-token']);
      final claims = _claims(first.headers['DPoP']!);
      expect(claims['htm'], 'POST');
      expect(claims['htu'], 'https://api.test/orders');
      expect(claims['ath'], sha256Base64Url('dpop-token'));
      expect(claims, isNot(contains('nonce')));
      expect(_claims(second.headers['DPoP']!)['nonce'], 'n-1');
      expect(
        _claims(second.headers['DPoP']!)['jti'],
        isNot(claims['jti']),
      );
      // Asking for a nonce leaves the token alone.
      expect(
        (await service.loadAuthorizedClient(
          'partner',
          'anonymousUser',
        ))!.accessToken.expiresAt,
        isNull,
      );
    });

    // What only the tests of the interceptor this one replaces checked.
    test('a Bearer token with a key: Bearer, no proof, the stale headers '
        'replaced', () async {
      final api = MockHttpTransport()
        ..when(HttpMethod.delete, 'https://api.test/orders').respond(204);
      final rest = RestClient.builder()
          .transport(api)
          .requestInterceptor(
            OAuth2ClientHttpRequestInterceptor(
              _FixedManager(
                OAuth2AuthorizedClient(
                  registration,
                  'anonymousUser',
                  OAuth2AccessToken(TokenType.bearer, 'bearer-token'),
                ),
              ),
              dPoPKey: key,
              defaultClientRegistrationId: 'partner',
            ),
          )
          .build();
      await rest
          .delete()
          .uri('https://api.test/orders')
          .header('Authorization', 'Basic old')
          .header('DPoP', 'stale')
          .retrieve()
          .toBodilessEntity();
      expect(api.lastRequest.headers.getAll('Authorization'), [
        'Bearer bearer-token',
      ]);
      expect(api.lastRequest.headers['DPoP'], isNull);
    });

    test('a nonce goes to its own server only, from a successful answer '
        'too', () async {
      final api = MockHttpTransport()
        ..when(HttpMethod.get, 'https://api.test/orders').respond(
          200,
          headers: {'DPoP-Nonce': 'api-nonce'},
        )
        ..when(HttpMethod.get, 'https://api.test/other').respond(200)
        ..when(HttpMethod.get, 'https://other.test/orders').respond(200);
      final rest = RestClient.builder()
          .transport(api)
          .requestInterceptor(
            OAuth2ClientHttpRequestInterceptor(
              _FixedManager(stored),
              dPoPKey: key,
              defaultClientRegistrationId: 'partner',
            ),
          )
          .build();
      Future<Map<String, Object?>> proofOf(String url) async {
        await rest.get().uri(url).retrieve().toBodilessEntity();
        return _claims(api.lastRequest.headers['DPoP']!);
      }

      expect(
        await proofOf('https://api.test/orders'),
        isNot(contains('nonce')),
      );
      expect((await proofOf('https://api.test/other'))['nonce'], 'api-nonce');
      expect(
        await proofOf('https://other.test/orders'),
        isNot(contains('nonce')),
      );
    });

    test('a 401 that is not about the nonce marks the DPoP token '
        'expired', () async {
      final api = MockHttpTransport()
        ..when(HttpMethod.get, 'https://api.test/orders').respond(
          401,
          headers: {'WWW-Authenticate': 'DPoP error="invalid_token"'},
        );
      final service = InMemoryOAuth2AuthorizedClientService(
        InMemoryClientRegistrationRepository([registration]),
      );
      await service.saveAuthorizedClient(stored, anonymousAuthentication);
      final rest = RestClient.builder()
          .transport(api)
          .requestInterceptor(
            OAuth2ClientHttpRequestInterceptor(
              _FixedManager(stored),
              authorizedClientService: service,
              dPoPKey: key,
              defaultClientRegistrationId: 'partner',
            ),
          )
          .build();
      await expectLater(
        rest.get().uri('https://api.test/orders').retrieve().toBodilessEntity(),
        throwsA(isA<HttpClientErrorException>()),
      );
      expect(api.requests, hasLength(1));
      expect(
        (await service.loadAuthorizedClient(
          'partner',
          'anonymousUser',
        ))!.accessToken.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('a 401 for a token replaced meanwhile changes nothing', () async {
      final api = MockHttpTransport()
        ..when(HttpMethod.get, 'https://api.test/orders').respond(401);
      final service = InMemoryOAuth2AuthorizedClientService(
        InMemoryClientRegistrationRepository([registration]),
      );
      final newer = OAuth2AuthorizedClient(
        registration,
        'anonymousUser',
        OAuth2AccessToken(TokenType.dpop, 'newer-token'),
      );
      await service.saveAuthorizedClient(newer, anonymousAuthentication);
      final rest = RestClient.builder()
          .transport(api)
          .requestInterceptor(
            OAuth2ClientHttpRequestInterceptor(
              _FixedManager(stored), // still hands out the old token
              authorizedClientService: service,
              dPoPKey: key,
              defaultClientRegistrationId: 'partner',
            ),
          )
          .build();
      await expectLater(
        rest.get().uri('https://api.test/orders').retrieve().toBodilessEntity(),
        throwsA(isA<HttpClientErrorException>()),
      );
      final kept = await service.loadAuthorizedClient(
        'partner',
        'anonymousUser',
      );
      expect(kept!.accessToken.tokenValue, 'newer-token');
      expect(kept.accessToken.expiresAt, isNull);
    });

    test('a DPoP token without a key fails the call', () {
      final api = MockHttpTransport();
      final rest = RestClient.builder()
          .transport(api)
          .requestInterceptor(
            OAuth2ClientHttpRequestInterceptor(
              _FixedManager(stored),
              defaultClientRegistrationId: 'partner',
            ),
          )
          .build();
      expect(
        rest.get().uri('https://api.test/orders').retrieve().toBodilessEntity(),
        throwsStateError,
      );
    });
  });

  group('the auto-configuration', () {
    const r = 'spring.security.oauth2.client.registration';
    final transport = MockHttpTransport()
      ..when(HttpMethod.post, 'https://p.test/t').respond(
        200,
        json: {
          'access_token': 'cc-token',
          'token_type': 'Bearer',
          'expires_in': 300,
        },
      )
      ..when(HttpMethod.get, 'https://api.partner.test/orders').respond(200);
    final runner = const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterRestclientAutoConfiguration)
        .withAutoConfiguration(springSecurityCoreAutoConfiguration)
        .withAutoConfiguration(springBootStarterOauth2ClientAutoConfiguration)
        .withPropertyValues([
          '$r.partner.client-id=shop',
          '$r.partner.client-secret=s',
          '$r.partner.authorization-grant-type=client_credentials',
          'spring.security.oauth2.client.provider.partner.token-uri=https://p.test/t',
          '$r.google.client-id=g',
        ]);

    test('every RestClientBuilder gets the interceptor; it sends the '
        "attribute's token", () async {
      await runner.withBean<HttpTransport>(() => transport).runAsync((
        context,
      ) async {
        expect(context.startupFailure, isNull);
        expect(context, hasSingleBean<OAuth2ClientHttpRequestInterceptor>());
        final rest = context
            .getBean<RestClientBuilder>()
            .baseUrl('https://api.partner.test')
            .build();
        await rest
            .get()
            .uri('/orders')
            .attributes(ClientAttributes.clientRegistrationId('partner'))
            .retrieve()
            .toBodilessEntity();
        expect(
          transport.lastRequest.headers['Authorization'],
          'Bearer cc-token',
        );
        await rest.get().uri('/orders').retrieve().toBodilessEntity();
        expect(transport.lastRequest.headers['Authorization'], isNull);
      });
    });

    test('the providers the properties name join the allow list', () {
      runner.run((context) {
        final allowed = context.getBean<AllowedAddresses>()
          ..checkUrl(Uri.parse('https://p.test/t'))
          ..checkUrl(Uri.parse('https://www.googleapis.com/oauth2/v4/token'))
          ..checkUrl(Uri.parse('https://accounts.google.com/'));
        expect(
          () => allowed.checkUrl(Uri.parse('https://api.partner.test/')),
          throwsA(isA<FilteredHostException>()),
        );
      });
    });

    test('spring.security.oauth2.client.restclient.enabled=false: the '
        'builders get none', () {
      runner
          .withPropertyValues([
            'spring.security.oauth2.client.restclient.enabled=false',
          ])
          .run((context) {
            expect(
              context.getBeanNamesForType<RestClientCustomizer>(),
              isEmpty,
            );
            final interceptors = <ClientHttpRequestInterceptor>[];
            context.getBean<RestClientBuilder>().requestInterceptors(
              interceptors.addAll,
            );
            expect(interceptors, isEmpty);
          });
    });

    test('without registrations: nothing of it', () {
      const ApplicationContextRunner()
          .withAutoConfiguration(springBootAutoConfiguration)
          .withAutoConfiguration(springBootStarterRestclientAutoConfiguration)
          .withAutoConfiguration(springSecurityCoreAutoConfiguration)
          .withAutoConfiguration(springBootStarterOauth2ClientAutoConfiguration)
          .run((context) {
            expect(context.startupFailure, isNull);
            expect(
              context,
              doesNotHaveBean<OAuth2ClientHttpRequestInterceptor>(),
            );
            expect(
              context.getBeanNamesForType<RestClientCustomizer>(),
              isEmpty,
            );
          });
    });
  });
}
