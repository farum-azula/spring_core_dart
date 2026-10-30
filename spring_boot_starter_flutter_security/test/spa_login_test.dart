// The web login in spa mode (the browser logs in by itself), on the VM:
// the page (address, history, storages, navigation) is a fake, the
// provider the fake OpenID Connect provider. The redirect round trip and
// each attack it must refuse, the token exchange, the address cleanup,
// the silent re-authentication, the logout, DPoP with the WebCrypto key
// (a fake vault), the refresh token rotation warning.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_flutter_security/src/web/web_crypto_dpop_key.dart'
    show StoredKeyPair, storedKeyPairUsable;
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show captureLogs;

import 'support/fake_provider.dart';
import 'support/spa_fakes.dart';

final class _Events implements ApplicationEventPublisher {
  final events = <Object>[];

  @override
  void publishEvent<T extends Object>(T event) => events.add(event);
}

Matcher failsWith(String code) => throwsA(
  isA<OAuth2AuthenticationException>().having(
    (e) => e.error.errorCode,
    'errorCode',
    code,
  ),
);

Map<String, Object?> _jwtPart(String token, int index) => jsonDecode(
  utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[index]))),
) as Map<String, Object?>;

/// One "browser": the tab and the provider; [service] is the app of one
/// page load (a new one after each navigation, as the page starts again).
final class SpaFixture {
  SpaFixture._(this.provider, this.repository, this.page);

  static Future<SpaFixture> create({
    FakeProvider? provider,
    DPoPMode dpop = DPoPMode.disabled,
    String redirectUri = '{baseUrl}/',
  }) async {
    final fake = provider ?? FakeProvider();
    final base = await registration(fake, redirectUri: redirectUri);
    final reg = ClientRegistration.withClientRegistration(base)
        .dpop(dpop)
        .build();
    return SpaFixture._(
      fake,
      InMemoryClientRegistrationRepository([reg]),
      FakeSpaPage(),
    );
  }

  final FakeProvider provider;
  final InMemoryClientRegistrationRepository repository;
  final FakeSpaPage page;
  final events = _Events();
  final SecurityContextHolderStrategy strategy =
      GlobalSecurityContextHolderStrategy();
  late TabOAuth2AuthorizedClientService clients;
  DPoPKey? dPoPKey;

  SpaOAuth2LoginService service({
    FlutterWebSecurityProperties properties =
        const FlutterWebSecurityProperties(mode: WebLoginMode.spa),
  }) {
    // A page load: the memory (the tokens) starts empty.
    clients = TabOAuth2AuthorizedClientService(repository);
    return SpaOAuth2LoginService(
      clientRegistrationRepository: repository,
      authorizedClientService: clients,
      accessTokenResponseClient: DefaultAuthorizationCodeTokenResponseClient(
        provider.transport,
        clock: () => provider.now,
        dPoPKey: dPoPKey,
      ),
      userService: DefaultOAuth2UserService(provider.transport),
      oidcUserService: OidcUserService(provider.transport),
      page: page,
      properties: properties,
      revocationClient: OAuth2TokenRevocationClient(provider.transport),
      idTokenDecoder: TokenEndpointOidcIdTokenDecoder(
        clock: () => provider.now,
      ),
      dPoPKey: dPoPKey,
      eventPublisher: events,
      securityContextHolderStrategy: strategy,
      clock: () => provider.now,
    );
  }

  /// The provider's page, where the tab was sent last: it approves (or
  /// [answer]s) and sends the tab back to the redirect URI.
  void comeBack([Uri Function(Uri authorizationUri)? answer]) {
    page.location = (answer ?? provider.approve)(page.visited.last);
  }

  /// Logs in: the page leaves, comes back approved, the app starts again.
  Future<OAuth2AuthenticationToken?> logIn() async {
    await service().login('keycloak');
    comeBack();
    return service().restore();
  }
}

void main() {
  final logs = captureLogs(level: SpringLogLevel.debug);
  late SpaFixture fixture;

  setUp(() async => fixture = await SpaFixture.create());

  group('the round trip', () {
    test('login leaves for the provider with PKCE, state and nonce', () async {
      final login = fixture.service();
      expect(await login.login('keycloak'), isNull);

      final sent = fixture.page.visited.single;
      expect(sent.path, '/auth');
      final query = sent.queryParameters;
      expect(query['redirect_uri'], 'http://localhost:5050/');
      expect(query['code_challenge_method'], 'S256');
      expect(query['code_challenge']!.length, 43);
      expect(query['state']!.length, greaterThanOrEqualTo(43));
      expect(query['nonce']!.length, 43);
      expect(query.containsKey('code_verifier'), isFalse);
      expect(query.containsKey('prompt'), isFalse);

      // The request waits in the tab's sessionStorage: the verifier and
      // the raw nonce, nothing in localStorage.
      final stored = jsonDecode(
        fixture.page.sessionStorage.getItem(
          SpaOAuth2LoginService.authorizationRequestKey,
        )!,
      ) as Map<String, Object?>;
      expect(stored['state'], query['state']);
      expect(stored['codeVerifier'], isA<String>());
      expect(
        sha256Base64Url(stored['codeVerifier']! as String),
        query['code_challenge'],
      );
      expect(fixture.page.localStorage.items, isEmpty);
    });

    test('restore exchanges the code and logs the user in', () async {
      final authentication = await fixture.logIn();

      expect(authentication!.name, 'user-1');
      expect(authentication.authorizedClientRegistrationId, 'keycloak');
      expect((authentication.principal as OidcUser).email, 'ada@example.com');
      expect(
        fixture.strategy.getContext().authentication,
        same(authentication),
      );
      expect(fixture.events.events.single, isA<AuthenticationSuccessEvent>());

      // A public client: the verifier, no secret.
      final form = fixture.provider.tokenRequests.single;
      expect(form['grant_type'], 'authorization_code');
      expect(form['redirect_uri'], 'http://localhost:5050/');
      expect(form['code_verifier'], isNotNull);
      expect(form['client_id'], clientId);
      expect(form.containsKey('client_secret'), isFalse);

      // The tokens in the tab's memory only.
      final client = await fixture.clients.loadAuthorizedClient(
        'keycloak',
        'user-1',
      );
      expect(client!.accessToken.tokenValue, startsWith('access-'));
      expect(client.refreshToken, isNotNull);
      expect(fixture.page.stored, isNot(contains('access-')));
      expect(fixture.page.stored, isNot(contains('refresh-')));
      expect(
        fixture.page.stored,
        isNot(contains(fixture.provider.lastIdToken)),
      );

      // The answer left the address bar, the request the sessionStorage;
      // the hint is the registration id.
      expect(fixture.page.replaced.single.toString(), 'http://localhost:5050/');
      expect(fixture.page.sessionStorage.items, isEmpty);
      expect(fixture.page.localStorage.items, {
        SpaOAuth2LoginService.loginHintKey: 'keycloak',
      });
    });

    test('the cleanup keeps the app\'s parameters and route', () async {
      await fixture.service().login('keycloak');
      fixture.comeBack((uri) {
        final answer = fixture.provider.approve(uri);
        return answer.replace(
          queryParameters: {'ref': 'mail', ...answer.queryParameters},
          fragment: '/books/42',
        );
      });
      expect(await fixture.service().restore(), isNotNull);
      expect(
        fixture.page.replaced.single.toString(),
        'http://localhost:5050/?ref=mail#/books/42',
      );
    });

    test('nothing secret is logged', () async {
      await fixture.logIn();
      final everything = logs.messages.join('\n');
      final form = fixture.provider.tokenRequests.single;
      expect(everything, isNot(contains(form['code']!)));
      expect(everything, isNot(contains(form['code_verifier']!)));
      expect(everything, isNot(contains('access-')));
      expect(everything, isNot(contains('refresh-')));
    });
  });

  group('the attacks on the answer', () {
    test('another state is refused, without a token request', () async {
      await fixture.service().login('keycloak');
      fixture.comeBack(
        (uri) => fixture.provider.approve(
          uri.replace(
            queryParameters: {...uri.queryParameters, 'state': 'forged'},
          ),
        ),
      );
      await expectLater(
        fixture.service().restore(),
        failsWith(OAuth2ErrorCodes.invalidStateParameter),
      );
      expect(fixture.provider.tokenRequests, isEmpty);
      expect(fixture.strategy.getContext().authentication, isNull);
      // The answer left the address bar anyway, the request is used up.
      expect(fixture.page.replaced, hasLength(1));
      expect(fixture.page.sessionStorage.items, isEmpty);
      expect(fixture.page.localStorage.items, isEmpty);
    });

    test("the provider's error is the login's error", () async {
      await fixture.service().login('keycloak');
      fixture.comeBack(
        (uri) => Uri.parse(uri.queryParameters['redirect_uri']!).replace(
          queryParameters: {
            'error': 'access_denied',
            'error_description': 'The user said no',
            'state': uri.queryParameters['state'],
            'iss': issuer,
          },
        ),
      );
      await expectLater(
        fixture.service().restore(),
        failsWith(OAuth2ErrorCodes.accessDenied),
      );
      expect(fixture.provider.tokenRequests, isEmpty);
      expect(fixture.page.location.hasQuery, isFalse);
    });

    test('another iss is refused (RFC 9207)', () async {
      await fixture.service().login('keycloak');
      fixture.comeBack((uri) {
        final answer = fixture.provider.approve(uri);
        return answer.replace(
          queryParameters: {
            ...answer.queryParameters,
            'iss': 'https://evil.test',
          },
        );
      });
      await expectLater(
        fixture.service().restore(),
        failsWith(OAuth2ErrorCodes.invalidIssuer),
      );
      expect(fixture.provider.tokenRequests, isEmpty);
    });

    test('a missing iss is refused when the provider announces it', () async {
      final provider = FakeProvider()
        ..advertiseIssParameter = true
        ..includeIssParameter = false;
      fixture = await SpaFixture.create(provider: provider);
      await fixture.service().login('keycloak');
      fixture.comeBack();
      await expectLater(
        fixture.service().restore(),
        failsWith(OAuth2ErrorCodes.invalidIssuer),
      );
    });

    test('a reload of the answer (a replay) logs nobody in', () async {
      await fixture.logIn();
      final answer = Uri.parse(
        'http://localhost:5050/?code=code-1&state=x&iss=$issuer',
      );
      fixture.page.location = answer;
      expect(await fixture.service().restore(), isNull);
      expect(fixture.provider.tokenRequests, hasLength(1));
      expect(fixture.page.location.toString(), 'http://localhost:5050/');
      expect(
        logs.messages,
        contains(contains('this tab did not ask for')),
      );
    });

    test('an answer in another tab (no request here) logs nobody in', () async {
      await fixture.service().login('keycloak');
      fixture.comeBack();
      fixture.page.sessionStorage.items.clear(); // another tab
      expect(await fixture.service().restore(), isNull);
      expect(fixture.provider.tokenRequests, isEmpty);
    });

    test('a request without its verifier logs nobody in', () async {
      await fixture.service().login('keycloak');
      const key = SpaOAuth2LoginService.authorizationRequestKey;
      final stored = jsonDecode(
        fixture.page.sessionStorage.getItem(key)!,
      ) as Map<String, Object?>..remove('codeVerifier');
      fixture.page.sessionStorage.setItem(key, jsonEncode(stored));
      fixture.comeBack();
      expect(await fixture.service().restore(), isNull);
      expect(fixture.provider.tokenRequests, isEmpty);
      expect(fixture.page.sessionStorage.items, isEmpty);
      expect(logs.messages, contains(contains('unreadable')));
    });

    test('an answer after the request lifetime logs nobody in', () async {
      await fixture.service().login('keycloak');
      fixture.comeBack();
      fixture.provider.now = fixture.provider.now.add(
        const Duration(minutes: 11),
      );
      expect(await fixture.service().restore(), isNull);
      expect(fixture.provider.tokenRequests, isEmpty);
    });

    test('a wrong nonce in the ID token is refused', () async {
      fixture.provider.corruptNonce = true;
      await fixture.service().login('keycloak');
      fixture.comeBack();
      await expectLater(
        fixture.service().restore(),
        failsWith(OAuth2ErrorCodes.invalidNonce),
      );
      expect(fixture.strategy.getContext().authentication, isNull);
    });

    test("the app's own ?code= on another page is left alone", () async {
      fixture.page.location = Uri.parse(
        'http://localhost:5050/promo?code=SUMMER&state=open',
      );
      expect(await fixture.service().restore(), isNull);
      expect(fixture.page.replaced, isEmpty);
    });

    test('the token endpoint refusing the code fails the login', () async {
      await fixture.service().login('keycloak');
      fixture.comeBack();
      fixture.provider.tokenError = 'invalid_grant';
      await expectLater(
        fixture.service().restore(),
        failsWith(OAuth2ErrorCodes.invalidGrant),
      );
    });

    test('an unreachable token endpoint names CORS', () async {
      await fixture.service().login('keycloak');
      fixture.comeBack();
      fixture.provider.tokenUnreachable = true;
      await expectLater(
        fixture.service().restore(),
        throwsA(
          isA<OAuth2AuthenticationException>().having(
            (e) => e.message,
            'message',
            allOf(contains('CORS'), contains('mode=server')),
          ),
        ),
      );
    });
  });

  group('registrations a browser cannot use', () {
    test('a client secret is refused before leaving', () async {
      final reg = await registration(
        fixture.provider,
        redirectUri: '{baseUrl}/',
      );
      final confidential = ClientRegistration.withClientRegistration(reg)
          .clientSecret('secret')
          .clientAuthenticationMethod(
            ClientAuthenticationMethod.clientSecretBasic,
          )
          .build();
      final login = SpaOAuth2LoginService(
        clientRegistrationRepository: InMemoryClientRegistrationRepository([
          confidential,
        ]),
        authorizedClientService: TabOAuth2AuthorizedClientService(
          fixture.repository,
        ),
        accessTokenResponseClient: DefaultAuthorizationCodeTokenResponseClient(
          fixture.provider.transport,
        ),
        userService: DefaultOAuth2UserService(fixture.provider.transport),
        oidcUserService: OidcUserService(fixture.provider.transport),
        page: fixture.page,
      );
      await expectLater(
        login.login('keycloak'),
        failsWith(OAuth2ErrorCodes.invalidClient),
      );
      expect(fixture.page.visited, isEmpty);
    });

    test('an unknown registration is refused', () {
      expect(
        fixture.service().login('nope'),
        failsWith(OAuth2ErrorCodes.clientRegistrationNotFound),
      );
    });
  });

  group('after a reload: the silent login', () {
    test('goes to the provider with prompt=none and comes back in', () async {
      await fixture.logIn();
      // A reload: no tokens, the hint is there.
      fixture.page
        ..location = Uri.parse('http://localhost:5050/#/books')
        ..visited.clear();
      expect(await fixture.service().restore(), isNull);
      final sent = fixture.page.visited.single;
      expect(sent.queryParameters['prompt'], 'none');

      fixture.comeBack();
      final authentication = await fixture.service().restore();
      expect(authentication?.name, 'user-1');
      expect(fixture.provider.tokenRequests, hasLength(2));
      expect(
        fixture.page.localStorage.getItem(SpaOAuth2LoginService.loginHintKey),
        'keycloak',
      );
    });

    test('login_required: nobody logged in, no error, no second try', () async {
      await fixture.logIn();
      fixture.page.visited.clear();
      fixture.page.location = Uri.parse('http://localhost:5050/');
      await fixture.service().restore();
      fixture.comeBack(
        (uri) => Uri.parse(uri.queryParameters['redirect_uri']!).replace(
          queryParameters: {
            'error': 'login_required',
            'state': uri.queryParameters['state'],
            'iss': issuer,
          },
        ),
      );
      expect(await fixture.service().restore(), isNull);
      expect(fixture.page.localStorage.items, isEmpty);
      expect(fixture.page.location.toString(), 'http://localhost:5050/');
      // The next load: no hint, no trip to the provider.
      fixture.page.visited.clear();
      expect(await fixture.service().restore(), isNull);
      expect(fixture.page.visited, isEmpty);
    });

    test('back without an answer: no second try', () async {
      await fixture.logIn();
      fixture.page
        ..visited.clear()
        ..location = Uri.parse('http://localhost:5050/');
      await fixture.service().restore();
      expect(fixture.page.visited, hasLength(1));
      // The back button: the page loads again without an answer.
      expect(await fixture.service().restore(), isNull);
      expect(fixture.page.visited, hasLength(1));
      expect(fixture.page.localStorage.items, isEmpty);
    });

    test('nobody logged in before: no trip to the provider', () async {
      expect(await fixture.service().restore(), isNull);
      expect(fixture.page.visited, isEmpty);
    });

    test('silent-restore=false: no trip to the provider', () async {
      await fixture.logIn();
      fixture.page
        ..visited.clear()
        ..location = Uri.parse('http://localhost:5050/');
      final login = fixture.service(
        properties: const FlutterWebSecurityProperties(
          mode: WebLoginMode.spa,
          silentRestore: false,
        ),
      );
      expect(await login.restore(), isNull);
      expect(fixture.page.visited, isEmpty);
    });
  });

  group('logout', () {
    test('forgets, revokes, ends the provider session', () async {
      final login = fixture.service();
      await login.login('keycloak');
      fixture.comeBack();
      final app = fixture.service();
      final authentication = await app.restore();
      final client = await fixture.clients.loadAuthorizedClient(
        'keycloak',
        'user-1',
      );
      fixture.page.visited.clear();

      await app.logout();

      expect(app.isLoggedIn, isFalse);
      expect(fixture.strategy.getContext().authentication, isNull);
      expect(fixture.events.events.last, isA<LogoutSuccessEvent>());
      expect(
        (fixture.events.events.last as LogoutSuccessEvent).authentication,
        same(authentication),
      );
      expect(
        await fixture.clients.loadAuthorizedClient('keycloak', 'user-1'),
        isNull,
      );
      expect(fixture.page.localStorage.items, isEmpty);
      // Refresh token first, then the access token.
      expect(fixture.provider.revoked.map((form) => form['token']), [
        client!.refreshToken!.tokenValue,
        client.accessToken.tokenValue,
      ]);
      final logout = fixture.page.visited.single;
      expect(logout.path, '/logout');
      expect(logout.queryParameters, {
        'id_token_hint': client.idToken!.tokenValue,
        'client_id': clientId,
        'post_logout_redirect_uri': 'http://localhost:5050/',
      });
    });

    test('a failed revocation still logs out', () async {
      final app = fixture.service();
      await app.login('keycloak');
      fixture.comeBack();
      final reloaded = fixture.service();
      await reloaded.restore();
      fixture.provider.transport
          .when(
            HttpMethod.post,
            'https://sso.test/revoke',
          )
          .respondWith((request) async => HttpResponse(503));
      fixture.page.visited.clear();
      await reloaded.logout(
        postLogoutRedirectUri: Uri.parse('http://localhost:5050/bye'),
      );
      expect(reloaded.isLoggedIn, isFalse);
      expect(
        fixture.page.visited.single.queryParameters['post_logout_redirect_uri'],
        'http://localhost:5050/bye',
      );
    });

    test('nobody logged in: only the hint goes', () async {
      fixture.page.localStorage.setItem(
        SpaOAuth2LoginService.loginHintKey,
        'keycloak',
      );
      await fixture.service().logout();
      expect(fixture.page.localStorage.items, isEmpty);
      expect(fixture.page.visited, isEmpty);
      expect(fixture.provider.revoked, isEmpty);
    });
  });

  group('a stored WebCrypto key is checked before use', () {
    // What the browser vault reads of a key pair from IndexedDB.
    const p256 = {'name': 'ECDSA', 'namedCurve': 'P-256'};
    StoredKeyPair pair({
      bool privateExtractable = false,
      String? privateType = 'private',
      String? publicType = 'public',
      Object? privateAlgorithm = p256,
      Object? publicAlgorithm = p256,
      List<String> privateUsages = const ['sign'],
    }) => (
      privateExtractable: privateExtractable,
      privateType: privateType,
      publicType: publicType,
      privateAlgorithm: privateAlgorithm,
      publicAlgorithm: publicAlgorithm,
      privateUsages: privateUsages,
    );

    test('the vault\'s own key is used', () {
      expect(storedKeyPairUsable(pair()), isTrue);
    });

    test('anything else is replaced', () {
      for (final (reason, bad) in [
        ('extractable', pair(privateExtractable: true)),
        ('a public key as the private one', pair(privateType: 'public')),
        ('a secret key', pair(privateType: 'secret')),
        ('no public key', pair(publicType: null)),
        (
          'P-384',
          pair(privateAlgorithm: {'name': 'ECDSA', 'namedCurve': 'P-384'}),
        ),
        (
          'ECDH',
          pair(privateAlgorithm: {'name': 'ECDH', 'namedCurve': 'P-256'}),
        ),
        ('RSA', pair(publicAlgorithm: {'name': 'RSASSA-PKCS1-v1_5'})),
        ('no algorithm', pair(privateAlgorithm: null)),
        ('cannot sign', pair(privateUsages: const ['deriveBits'])),
      ]) {
        expect(storedKeyPairUsable(bad), isFalse, reason: reason);
      }
    });
  });

  group('DPoP with the WebCrypto key', () {
    test('the key loads at the first use, then signs the proofs', () async {
      fixture = await SpaFixture.create(dpop: DPoPMode.enabled);
      final vault = FakeVault();
      final key = WebCryptoDPoPKey(vault: vault);
      fixture.dPoPKey = key;
      expect(() => key.publicJwk, throwsStateError);
      expect(vault.loads, 0);

      await fixture.service().login('keycloak');
      expect(vault.loads, 1);
      // The code is bound to the key (RFC 9449 §10).
      expect(
        fixture.page.visited.single.queryParameters['dpop_jkt'],
        vault.key.thumbprint,
      );

      fixture.comeBack();
      expect(await fixture.service().restore(), isNotNull);
      final tokenRequest = fixture.provider.transport.requests.firstWhere(
        (request) => request.url.path == '/token',
      );
      final proof = tokenRequest.headers['DPoP']!;
      final header = _jwtPart(proof, 0);
      expect(header['typ'], 'dpop+jwt');
      expect(header['alg'], 'ES256');
      expect(header['jwk'], vault.key.publicJwk);
      final claims = _jwtPart(proof, 1);
      expect(claims['htm'], 'POST');
      expect(claims['htu'], 'https://sso.test/token');
      expect(
        base64Url.decode(base64Url.normalize(proof.split('.')[2])),
        hasLength(64),
      );
      expect(vault.loads, 1); // loaded once
      expect(key.toString(), contains(vault.key.thumbprint));
    });

    test(
      'every login binds a new key, never one found in the storage',
      () async {
        // A key already in the origin's IndexedDB: a script could have
        // planted it, knowing its private key.
        fixture = await SpaFixture.create(dpop: DPoPMode.enabled);
        final vault = FakeVault();
        final planted = vault.key.thumbprint;
        fixture.dPoPKey = WebCryptoDPoPKey(vault: vault);

        await fixture.service().login('keycloak');
        final first = fixture.page.visited.last.queryParameters['dpop_jkt'];
        expect(first, isNot(planted));
        expect(first, vault.key.thumbprint);

        await fixture.service().login('keycloak');
        final second = fixture.page.visited.last.queryParameters['dpop_jkt'];
        expect(second, isNot(first));
        expect(vault.deletes, 2);
      },
    );

    test('a DER signature becomes raw R || S', () async {
      final vault = FakeVault(der: true);
      final key = WebCryptoDPoPKey(vault: vault);
      final signature = await key.sign(Uint8List.fromList([1, 2, 3]));
      expect(signature, hasLength(64));
      expect(key.isLoaded, isTrue);
      expect(key.publicJwk, vault.key.publicJwk);
      expect(key.publicJwk.containsKey('d'), isFalse);
    });

    test('a key that cannot load fails the login before leaving', () async {
      fixture = await SpaFixture.create(dpop: DPoPMode.enabled);
      fixture.dPoPKey = WebCryptoDPoPKey(vault: _NoWebCrypto());
      await expectLater(
        fixture.service().login('keycloak'),
        throwsUnsupportedError,
      );
      expect(fixture.page.visited, isEmpty);
    });

    test('DPoP off: the key is never loaded', () async {
      final vault = FakeVault();
      fixture.dPoPKey = WebCryptoDPoPKey(vault: vault);
      await fixture.logIn();
      expect(vault.loads, 0);
      expect(
        fixture.provider.transport.requests.every(
          (request) => request.headers['DPoP'] == null,
        ),
        isTrue,
      );
    });
  });

  group('refresh tokens in the tab', () {
    test('a refresh without a new refresh token is warned about', () async {
      final service = TabOAuth2AuthorizedClientService(fixture.repository);
      final reg = (await fixture.repository.findByRegistrationId('keycloak'))!;
      final user = TestingAuthenticationToken('user-1', null);
      OAuth2AuthorizedClient client(String access, String refresh) =>
          OAuth2AuthorizedClient(
            reg,
            'user-1',
            OAuth2AccessToken(TokenType.bearer, access),
            refreshToken: OAuth2RefreshToken(refresh),
          );
      await service.saveAuthorizedClient(client('a1', 'r1'), user);
      await service.saveAuthorizedClient(client('a2', 'r2'), user); // rotated
      expect(logs.atLevel(SpringLogLevel.warning), isEmpty);
      await service.saveAuthorizedClient(client('a3', 'r2'), user); // not
      await service.saveAuthorizedClient(client('a4', 'r2'), user);
      final warnings = logs.atLevel(SpringLogLevel.warning);
      expect(warnings, hasLength(1)); // once per registration
      expect(warnings.single.message, contains('did not rotate'));
      expect(warnings.single.message, isNot(contains('r2')));
      expect(
        (await service.loadAuthorizedClient(
          'keycloak',
          'user-1',
        ))!.accessToken.tokenValue,
        'a4',
      );
    });
  });

  group('properties', () {
    FlutterWebSecurityProperties bind(Map<String, String> values) =>
        FlutterWebSecurityProperties.bind(
          StandardEnvironment()
            ..propertySources.addFirst(MapPropertySource('test', values)),
        );

    test('mode=spa, silent restore on by default', () {
      final properties = bind({'spring.flutter.security.web.mode': 'spa'});
      expect(properties.mode, WebLoginMode.spa);
      expect(properties.silentRestore, isTrue);
      expect(
        bind({
          'spring.flutter.security.web.mode': 'SPA',
          'spring.flutter.security.web.silent-restore': 'false',
        }).silentRestore,
        isFalse,
      );
      expect(
        () => bind({'spring.flutter.security.web.silent-restore': 'maybe'}),
        throwsArgumentError,
      );
    });
  });
}

final class _NoWebCrypto implements BrowserKeyVault {
  @override
  Future<BrowserKeyPair> loadOrCreate(String name) async =>
      throw UnsupportedError('WebCrypto is not available');

  @override
  Future<void> delete(String name) async {}
}
