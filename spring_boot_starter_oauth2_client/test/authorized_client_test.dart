// The authorized clients: the TokenStore service, the manager (refresh
// within the clock skew, single-flight, client credentials, removal on
// invalid_grant) and the Feign interceptor.
import 'dart:async';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:test/test.dart';

import 'support/fake_provider.dart';

void main() {
  late LoginFixture fixture;

  setUp(() async {
    fixture = await LoginFixture.create();
  });

  OAuth2AuthorizeRequest request([String principal = 'user-1']) =>
      OAuth2AuthorizeRequest.withClientRegistrationId(
        'keycloak',
      ).principalName(principal).build();

  group('TokenStoreOAuth2AuthorizedClientService', () {
    test('a JSON entry per registration and principal', () async {
      await fixture.service().login('keycloak');
      final key = TokenStoreOAuth2AuthorizedClientService.keyOf(
        'keycloak',
        'user-1',
      );
      expect(key, 'oauth2.authorized-client.keycloak.user-1');
      expect(await fixture.store.read(key), contains('"version":1'));
      expect(
        TokenStoreOAuth2AuthorizedClientService.keyOf('a.b', 'x y/z'),
        'oauth2.authorized-client.a.b.x%20y%2Fz',
      );
      final client = await fixture.clients.loadAuthorizedClient(
        'keycloak',
        'user-1',
      );
      expect(client!.idToken!.subject, 'user-1');
      expect(
        await fixture.clients.loadAuthorizedClient('keycloak', 'user-2'),
        isNull,
      );
    });

    test('an entry under another key is not taken', () async {
      await fixture.service().login('keycloak');
      final stored = await fixture.store.read(
        TokenStoreOAuth2AuthorizedClientService.keyOf('keycloak', 'user-1'),
      );
      final other = TokenStoreOAuth2AuthorizedClientService.keyOf(
        'keycloak',
        'mallory',
      );
      await fixture.store.write(other, stored!);
      expect(
        await fixture.clients.loadAuthorizedClient('keycloak', 'mallory'),
        isNull,
      );
      expect(await fixture.store.read(other), isNull, reason: 'removed');
    });

    test('a damaged entry is removed', () async {
      final key = TokenStoreOAuth2AuthorizedClientService.keyOf(
        'keycloak',
        'user-1',
      );
      await fixture.store.write(key, '{"version":1}');
      expect(
        await fixture.clients.loadAuthorizedClient('keycloak', 'user-1'),
        isNull,
      );
      expect(await fixture.store.read(key), isNull);
    });
  });

  group('the manager', () {
    test('without a login an authorization_code client needs one', () {
      expect(
        fixture.manager.authorize(request()),
        throwsA(isA<ClientAuthorizationRequiredException>()),
      );
    });

    test('a fresh token is returned as it is', () async {
      await fixture.service().login('keycloak');
      final before = fixture.provider.tokenRequests.length;
      final client = await fixture.manager.authorize(request());
      expect(client!.accessToken.tokenValue, startsWith('access-'));
      expect(fixture.provider.tokenRequests, hasLength(before));
    });

    test('a token expiring within 60 seconds is refreshed', () async {
      await fixture.service().login('keycloak');
      final first = await fixture.manager.authorize(request());
      fixture.provider.now = fixture.provider.now.add(
        const Duration(minutes: 4, seconds: 1),
      );
      final second = await fixture.manager.authorize(request());
      expect(
        second!.accessToken.tokenValue,
        isNot(first!.accessToken.tokenValue),
      );
      expect(
        fixture.provider.tokenRequests.last['grant_type'],
        'refresh_token',
      );
      final stored = await fixture.clients.loadAuthorizedClient(
        'keycloak',
        'user-1',
      );
      expect(stored!.accessToken.tokenValue, second.accessToken.tokenValue);
    });

    test('concurrent callers share one refresh (single-flight)', () async {
      await fixture.service().login('keycloak');
      fixture.provider
        ..now = fixture.provider.now.add(const Duration(hours: 1))
        ..tokenDelay = const Duration(milliseconds: 20);
      final before = fixture.provider.tokenRequests.length;
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) fixture.manager.authorize(request()),
      ]);
      expect(fixture.provider.tokenRequests.length - before, 1);
      expect(
        results.map((client) => client!.accessToken.tokenValue).toSet(),
        hasLength(1),
      );
      // Once settled, the next expiry refreshes again.
      fixture.provider.now = fixture.provider.now.add(const Duration(hours: 1));
      await fixture.manager.authorize(request());
      expect(fixture.provider.tokenRequests.length - before, 2);
    });

    test('a refused refresh (invalid_grant) removes the client', () async {
      await fixture.service().login('keycloak');
      fixture.provider
        ..now = fixture.provider.now.add(const Duration(hours: 1))
        ..revokeEverything();
      await expectLater(
        fixture.manager.authorize(request()),
        throwsA(
          isA<ClientAuthorizationException>()
              .having((e) => e.error.errorCode, 'code', 'invalid_grant')
              .having((e) => e.clientRegistrationId, 'id', 'keycloak'),
        ),
      );
      expect(
        await fixture.clients.loadAuthorizedClient('keycloak', 'user-1'),
        isNull,
      );
    });

    test('an unreachable provider keeps the client', () async {
      await fixture.service().login('keycloak');
      fixture.provider
        ..now = fixture.provider.now.add(const Duration(hours: 1))
        ..tokenUnreachable = true;
      await expectLater(
        fixture.manager.authorize(request()),
        throwsA(isA<OAuth2AuthorizationException>()),
      );
      expect(
        await fixture.clients.loadAuthorizedClient('keycloak', 'user-1'),
        isNotNull,
      );
    });

    test('client credentials: a token for the client, renewed', () async {
      final provider = FakeProvider();
      final registration = ClientRegistration.withRegistrationId('partner')
          .clientId('shop')
          .clientSecret('s')
          .authorizationGrantType(AuthorizationGrantType.clientCredentials)
          .tokenUri('https://sso.test/token')
          .scope(['orders.read'])
          .build();
      final repository = InMemoryClientRegistrationRepository([registration]);
      final manager = AuthorizedClientServiceOAuth2AuthorizedClientManager(
        repository,
        InMemoryOAuth2AuthorizedClientService(repository),
        authorizedClientProvider: OAuth2AuthorizedClientProviderBuilder.builder(
          transport: provider.transport,
        ).clientCredentials(clock: () => provider.now).build(),
      );
      final principal = OAuth2AuthorizeRequest.withClientRegistrationId(
        'partner',
      ).principal(anonymousAuthentication).build();
      final first = await manager.authorize(principal);
      expect(first!.principalName, 'anonymousUser');
      expect(first.accessToken.scopes, {'orders.read'});
      expect(await manager.authorize(principal), isNotNull);
      expect(provider.tokenRequests, hasLength(1));
      provider.now = provider.now.add(const Duration(minutes: 5));
      final renewed = await manager.authorize(principal);
      expect(provider.tokenRequests, hasLength(2));
      expect(
        renewed!.accessToken.tokenValue,
        isNot(first.accessToken.tokenValue),
      );
    });

    test('an unknown registration is an error', () {
      expect(
        fixture.manager.authorize(
          OAuth2AuthorizeRequest.withClientRegistrationId(
            'nope',
          ).principalName('x').build(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('the Feign interceptor', () {
    late OAuth2AccessTokenInterceptor interceptor;

    setUp(() {
      interceptor = OAuth2AccessTokenInterceptor(
        fixture.manager,
        clientRegistrationId: 'keycloak',
        authorizedClientService: fixture.clients,
        securityContextHolderStrategy: fixture.strategy,
      );
    });

    RequestTemplate template([String client = 'orders']) => RequestTemplate(
      method: HttpMethod.get,
      url: Uri.parse('https://api.test/me'),
      methodKey: 'Api#me()',
      clientName: client,
      headers: HttpHeaders({'Authorization': 'Basic old'}),
    );

    test("adds the current user's token, replacing any", () async {
      await fixture.service().login('keycloak');
      final call = template();
      await interceptor.apply(call);
      final client = await fixture.clients.loadAuthorizedClient(
        'keycloak',
        'user-1',
      );
      expect(call.headers.getAll('Authorization'), [
        'Bearer ${client!.accessToken.tokenValue}',
      ]);
    });

    test('nobody logged in: the call fails', () {
      expect(
        interceptor.apply(template()),
        throwsA(isA<ClientAuthorizationRequiredException>()),
      );
    });

    test("without a registration id, the Feign client's name", () async {
      final byName = OAuth2AccessTokenInterceptor(
        fixture.manager,
        clientRegistrationId: ' ',
        securityContextHolderStrategy: fixture.strategy,
      );
      await fixture.service().login('keycloak');
      await byName.apply(template('keycloak'));
      expect(
        byName.apply(template()),
        throwsArgumentError, // no registration "orders"
      );
    });

    test('a 401 marks the token expired: the next call refreshes', () async {
      await fixture.service().login('keycloak');
      final first = template();
      await interceptor.apply(first);
      final sent = first.headers['Authorization']!.substring(7);

      // The API refuses the token although it has not expired.
      fixture.provider.rejectedAccessTokens.add(sent);
      final response = await fixture.provider.transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: first.url,
          headers: first.headers,
        ),
      );
      expect(response.statusCode, 401);
      final decoder = OAuth2AccessTokenErrorDecoder(
        const DefaultErrorDecoder(),
        interceptor,
      );
      expect(decoder.decode('Api#me()', response), isA<FeignUnauthorized>());

      final second = template();
      await interceptor.apply(second);
      expect(second.headers['Authorization'], isNot('Bearer $sent'));
      expect(
        fixture.provider.tokenRequests.last['grant_type'],
        'refresh_token',
      );
    });

    test('a 401 for a token it did not send changes nothing', () async {
      await fixture.service().login('keycloak');
      await interceptor.invalidate('someone-elses-token');
      final before = fixture.provider.tokenRequests.length;
      await interceptor.apply(template());
      expect(fixture.provider.tokenRequests, hasLength(before));
    });
  });

  test('two registrations of one principal do not share a flight', () async {
    // A guard against a key made of the principal alone.
    final gate = Completer<void>();
    var calls = 0;
    ClientRegistration registration(String id) =>
        ClientRegistration.withRegistrationId(id)
            .clientId('c')
            .clientSecret('s')
            .authorizationGrantType(AuthorizationGrantType.clientCredentials)
            .tokenUri('https://t.test/token')
            .build();
    final repository = InMemoryClientRegistrationRepository([
      registration('a'),
      registration('b'),
    ]);
    final manager = AuthorizedClientServiceOAuth2AuthorizedClientManager(
      repository,
      InMemoryOAuth2AuthorizedClientService(repository),
      authorizedClientProvider: _GatedProvider(gate, () => calls++),
    );
    final a = manager.authorize(
      OAuth2AuthorizeRequest.withClientRegistrationId('a')
          .principal(anonymousAuthentication)
          .build(),
    );
    final b = manager.authorize(
      OAuth2AuthorizeRequest.withClientRegistrationId('b')
          .principal(anonymousAuthentication)
          .build(),
    );
    gate.complete();
    final results = await Future.wait([a, b]);
    expect(calls, 2);
    expect(results.map((c) => c!.clientRegistration.registrationId), [
      'a',
      'b',
    ]);
  });
}

final class _GatedProvider implements OAuth2AuthorizedClientProvider {
  _GatedProvider(this.gate, this.called);
  final Completer<void> gate;
  final void Function() called;

  @override
  Future<OAuth2AuthorizedClient?> authorize(
    OAuth2AuthorizationContext context,
  ) async {
    called();
    await gate.future;
    return OAuth2AuthorizedClient(
      context.clientRegistration,
      context.principal.name,
      OAuth2AccessToken(TokenType.bearer, 't'),
    );
  }
}
