// oauth2Login() against a fake OpenID Connect provider: the whole login (the
// redirect to the provider, the callback, the code exchange with PKCE, the ID
// token checked with the provider's JWK Set, the user, the session), the
// login page and entry point, the logout at the provider, and the attacks of
// docs/security.md's catalog as tests.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';
import 'chain_support.dart';
import 'oauth2_support.dart';

/// Records the failures (their OAuth 2.0 error codes) and redirects as
/// the default handler does.
final class _Failures implements AuthenticationFailureHandler {
  final List<AuthenticationException> errors = [];

  String? get lastCode => switch (errors.lastOrNull) {
    final OAuth2AuthenticationException e => e.error.errorCode,
    final Object e => '${e.runtimeType}',
    null => null,
  };

  @override
  Future<void> onAuthenticationFailure(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException exception,
  ) async {
    errors.add(exception);
    await sendRedirect(response, '/login?error');
  }
}

final class _AddUserRole implements GrantedAuthoritiesMapper {
  const _AddUserRole();

  @override
  List<GrantedAuthority> mapAuthorities(
    Iterable<GrantedAuthority> authorities,
  ) => [...authorities, SimpleGrantedAuthority('ROLE_USER')];
}

final class _Fixture {
  _Fixture(this.provider, this.registrations, this.client, this.failures);

  final FakeOidcProvider provider;
  final InMemoryClientRegistrationRepository registrations;
  final ChainClient client;
  final _Failures failures;

  /// The authentication the application saw at [path].
  Future<Authentication?> who([String path = '/private']) async {
    final reply = await client.get(path);
    return reply.reached ? reply.authentication : null;
  }
}

Future<_Fixture> _fixture({
  FakeOidcProvider? provider,
  List<ClientRegistration>? registrations,
  Customizer<OAuth2LoginConfigurer>? customizer,
  void Function(HttpSecurity http)? configure,
  String contextPath = '',
}) async {
  final fake = provider ?? FakeOidcProvider();
  final repository = InMemoryClientRegistrationRepository(
    registrations ?? [await fake.registration()],
  );
  final failures = _Failures();
  final http = oauth2Http(
    fake,
    repository,
    contextPath: contextPath,
    customizer: (login) {
      login.failureHandler(failures);
      customizer?.call(login);
    },
  );
  configure?.call(http);
  return _Fixture(
    fake,
    repository,
    ChainClient(http.build(), contextPath: contextPath),
    failures,
  );
}

void main() {
  group('the login', () {
    test('an OpenID Connect login from a protected page and back', () async {
      final f = await _fixture();
      final client = f.client;

      final protected = await client.get('/private?tab=1');
      expect(protected.status, 302);
      expect(
        protected.header('location'),
        '/oauth2/authorization/keycloak',
        reason: 'one registration, no form login: straight to it',
      );

      final authorization = await client.startLogin('keycloak');
      final query = authorization.queryParameters;
      expect(authorization.origin, 'https://sso.test');
      expect(
        query['redirect_uri'],
        'http://localhost/login/oauth2/code/keycloak',
      );
      expect(query['scope']!.split(' '), containsAll(['openid', 'profile']));
      expect(query['state'], hasLength(greaterThanOrEqualTo(43)));
      expect(query['nonce'], isNotEmpty);
      expect(query['code_challenge'], isNotEmpty);

      final callback = await client.callback(f.provider.approve(authorization));
      expect(callback.status, 302);
      expect(callback.header('location'), '/private?tab=1&continue');

      final token = f.provider.tokenRequests.single;
      expect(token['grant_type'], 'authorization_code');
      expect(token['redirect_uri'], query['redirect_uri']);
      expect(token['code_verifier'], isNotEmpty);
      expect(token.containsKey('client_secret'), isFalse, reason: 'basic');

      final user = await f.who();
      expect(user, isA<OAuth2AuthenticationToken>());
      final authentication = user! as OAuth2AuthenticationToken;
      expect(authentication.name, 'user-1');
      expect(authentication.authorizedClientRegistrationId, 'keycloak');
      expect(authentication.principal, isA<OidcUser>());
      final oidc = authentication.principal as OidcUser;
      expect(oidc.idToken.tokenValue, f.provider.lastIdToken);
      expect(oidc.userInfo?.email, 'ada@example.com');
      expect(
        [for (final a in authentication.authorities) a.authority],
        containsAll(['OIDC_USER', 'SCOPE_openid', 'SCOPE_profile']),
      );
      expect(authentication.details, isA<WebAuthenticationDetails>());
      expect(f.provider.jwkFetches, 1, reason: 'the signature was checked');
    });

    test('the tokens go to the authorized client service', () async {
      final provider = FakeOidcProvider();
      final registrations = InMemoryClientRegistrationRepository([
        await provider.registration(),
      ]);
      final service = InMemoryOAuth2AuthorizedClientService(registrations);
      final f = await _fixture(
        provider: provider,
        registrations: [await provider.registration()],
        customizer: (login) => login
            .clientRegistrationRepository(registrations)
            .authorizedClientService(service),
      );
      await f.client.loginWith(provider, 'keycloak');
      final stored = await service.loadAuthorizedClient('keycloak', 'user-1');
      expect(stored, isNotNull);
      expect(stored!.accessToken.tokenValue, startsWith('access-'));
      expect(stored.refreshToken?.tokenValue, startsWith('refresh-'));
      expect(stored.idToken?.tokenValue, provider.lastIdToken);
      expect(stored.toString(), isNot(contains('access-')));
    });

    test('an OAuth 2.0 login without OpenID Connect uses user info', () async {
      final provider = FakeOidcProvider();
      final f = await _fixture(
        provider: provider,
        registrations: [provider.oauth2Registration()],
      );
      final reply = await f.client.loginWith(provider, 'github');
      expect(reply.header('location'), '/');
      final user = await f.who() as OAuth2AuthenticationToken?;
      expect(user?.name, 'ada-gh');
      expect(user?.principal, isNot(isA<OidcUser>()));
      expect(
        [for (final a in user!.authorities) a.authority],
        containsAll(['OAUTH2_USER', 'SCOPE_read:user']),
      );
      expect(provider.jwkFetches, 0);
    });

    test('the authorities go through the mapper', () async {
      final f = await _fixture(
        customizer: (login) => login.userInfoEndpoint(
          (userInfo) => userInfo.userAuthoritiesMapper(
            const _AddUserRole(),
          ),
        ),
      );
      await f.client.loginWith(f.provider, 'keycloak');
      final user = await f.who();
      expect(
        [for (final a in user!.authorities) a.authority],
        contains('ROLE_USER'),
      );
    });

    test('the session gets a new id at login (fixation)', () async {
      final f = await _fixture();
      final authorization = await f.client.startLogin('keycloak');
      final before = f.client.cookies['JSESSIONID'];
      expect(before, isNotNull, reason: 'the request is kept in the session');
      await f.client.callback(f.provider.approve(authorization));
      final after = f.client.cookies['JSESSIONID'];
      expect(after, isNot(before));
      expect(await f.client.sessions.repository.findById(before!), isNull);

      // The planted id is worthless.
      final attacker = ChainClient(
        oauth2Http(f.provider, f.registrations).build(),
        sessions: f.client.sessions,
      )..cookies['JSESSIONID'] = before;
      expect((await attacker.get('/private')).reached, isFalse);
    });

    test('the default success URL, absolute for a Flutter web app', () async {
      final f = await _fixture(
        customizer: (login) =>
            login.defaultSuccessUrl('http://localhost:5050/', alwaysUse: true),
      );
      await f.client.get('/private');
      final reply = await f.client.loginWith(f.provider, 'keycloak');
      expect(reply.header('location'), 'http://localhost:5050/');
    });

    test('a login under the context path', () async {
      final f = await _fixture(contextPath: '/shop');
      final protected = await f.client.get('/shop/private');
      expect(
        protected.header('location'),
        '/shop/oauth2/authorization/keycloak',
      );
      final authorization = await f.client.startLogin('keycloak');
      expect(
        authorization.queryParameters['redirect_uri'],
        'http://localhost/shop/login/oauth2/code/keycloak',
      );
      final reply = await f.client.callback(f.provider.approve(authorization));
      expect(reply.header('location'), '/shop/private?continue');
      expect(await f.who('/shop/private'), isNotNull);
    });

    test('the redirect URI follows the host and port of the request', () async {
      final f = await _fixture();
      final reply = await f.client.get(
        'https://shop.test:8443/oauth2/authorization/keycloak',
      );
      expect(
        Uri.parse(reply.header('location')!).queryParameters['redirect_uri'],
        'https://shop.test:8443/login/oauth2/code/keycloak',
      );
    });

    test('a second login replaces the first one of the session', () async {
      final f = await _fixture();
      final first = await f.client.startLogin('keycloak');
      final second = await f.client.startLogin('keycloak');
      expect(
        first.queryParameters['state'],
        isNot(second.queryParameters['state']),
      );
      await f.client.callback(f.provider.approve(first));
      expect(f.failures.lastCode, 'authorization_request_not_found');
      final reply = await f.client.callback(f.provider.approve(second));
      expect(reply.header('location'), '/');
      expect(await f.who(), isNotNull);
    });
  });

  group('starting a login', () {
    test('an unknown registration is a 400, nothing saved', () async {
      final f = await _fixture();
      final reply = await f.client.get('/oauth2/authorization/nope');
      expect(reply.status, 400);
      expect(reply.reached, isFalse);
      expect(f.client.cookies, isEmpty);
    });

    test('a registration that cannot be discovered is a 500', () async {
      final f = await _fixture();
      final broken = InMemoryClientRegistrationRepository.lazy({
        'keycloak': () async => throw StateError('the provider is down'),
      });
      final client = ChainClient(
        oauth2Http(f.provider, broken).build(),
      );
      expect((await client.get('/oauth2/authorization/keycloak')).status, 500);
    });

    test('a client-credentials registration cannot start a login', () async {
      final registration = ClientRegistration.withRegistrationId('partner')
          .clientId('shop')
          .clientSecret('s')
          .authorizationGrantType(AuthorizationGrantType.clientCredentials)
          .tokenUri('https://sso.test/token')
          .build();
      final provider = FakeOidcProvider();
      final f = await _fixture(
        provider: provider,
        registrations: [await provider.registration(), registration],
      );
      expect((await f.client.get('/oauth2/authorization/partner')).status, 400);
      // And it is not a login choice: still one, so straight to it.
      expect(
        (await f.client.get('/private')).header('location'),
        '/oauth2/authorization/keycloak',
      );
    });
  });

  group('the login page and the entry point', () {
    Future<_Fixture> two({String otherName = 'Other'}) async {
      final provider = FakeOidcProvider();
      final other = FakeOidcProvider(
        transport: provider.transport,
        base: 'https://other.test',
      );
      return await _fixture(
        provider: provider,
        registrations: [
          await provider.registration(clientName: 'Keycloak'),
          await other.registration(id: 'other', clientName: otherName),
        ],
      );
    }

    test('several registrations: the login page lists them', () async {
      final f = await two();
      expect((await f.client.get('/private')).header('location'), '/login');
      final page = await f.client.get('/login');
      expect(page.status, 200);
      final body = page.body.replaceAll('&#47;', '/');
      expect(body, contains('Login with OAuth 2.0'));
      expect(
        body,
        contains('<a href="/oauth2/authorization/keycloak">Keycloak</a>'),
      );
      expect(body, contains('<a href="/oauth2/authorization/other">Other</a>'));
      expect(body, isNot(contains('password')), reason: 'no form');
    });

    test('the client names are escaped', () async {
      final f = await two(otherName: '<script>alert(1)</script>');
      final page = await f.client.get('/login');
      expect(page.body, isNot(contains('<script>')));
      expect(
        page.body,
        contains('&lt;script&gt;alert(1)&lt;&#47;script&gt;'),
      );
    });

    test('a failed login is reported without its reason', () async {
      final f = await two();
      final page = await f.client.get('/login?error');
      expect(page.body, contains('Bad credentials'));
    });

    test('scripts are sent to the login page, not the provider', () async {
      final f = await _fixture();
      final reply = await f.client.get(
        '/private',
        headers: {'X-Requested-With': 'XMLHttpRequest'},
      );
      expect(reply.header('location'), '/login');
    });

    test('with form login too: the page has both, no auto-redirect', () async {
      final f = await _fixture(
        configure: (http) => http
          ..userDetailsService(testUsers())
          ..formLogin(),
      );
      expect((await f.client.get('/private')).header('location'), '/login');
      final page = await f.client.get('/login');
      expect(page.body, contains('name="password"'));
      expect(
        page.body.replaceAll('&#47;', '/'),
        contains('/oauth2/authorization/keycloak'),
      );
      final login = await f.client.login('ada', 'ada-pw');
      expect(login.header('location'), '/private?continue');
    });

    test('a login page of its own: no generated page', () async {
      final f = await _fixture(
        customizer: (login) => login.loginPage('/sign-in'),
      );
      expect((await f.client.get('/private')).header('location'), '/sign-in');
      final login = await f.client.get('/login');
      expect(login.status, 302, reason: 'no generated page: a rule decides');
      expect(login.header('location'), '/sign-in');
    });
  });

  group('attacks on the callback', () {
    test('no state: invalid request', () async {
      final f = await _fixture();
      final authorization = await f.client.startLogin('keycloak');
      final callback = f.provider.approve(authorization);
      final reply = await f.client.get(
        '/login/oauth2/code/keycloak?code=${callback.queryParameters['code']}',
      );
      expect(reply.header('location'), '/login?error');
      expect(f.failures.lastCode, 'invalid_request');
      expect(f.provider.tokenRequests, isEmpty);
    });

    test('a wrong state is refused and the real login goes on', () async {
      final f = await _fixture();
      final authorization = await f.client.startLogin('keycloak');
      final callback = f.provider.approve(authorization);
      final forged = callback.replace(
        queryParameters: {...callback.queryParameters, 'state': 'forged'},
      );
      await f.client.callback(forged);
      expect(f.failures.lastCode, 'authorization_request_not_found');
      expect(await f.who(), isNull);
      expect(f.provider.tokenRequests, isEmpty);

      await f.client.callback(callback);
      expect(await f.who(), isNotNull);
    });

    test('a state given twice counts as none', () async {
      final f = await _fixture();
      final authorization = await f.client.startLogin('keycloak');
      final callback = f.provider.approve(authorization);
      final state = callback.queryParameters['state'];
      await f.client.get('${callback.path}?${callback.query}&state=$state');
      expect(f.failures.lastCode, 'invalid_request');
    });

    test('a replayed callback finds no saved request', () async {
      final f = await _fixture();
      final callback = f.provider.approve(
        await f.client.startLogin('keycloak'),
      );
      await f.client.callback(callback);
      expect(await f.who(), isNotNull);
      await f.client.callback(callback);
      expect(f.failures.lastCode, 'authorization_request_not_found');
      expect(f.provider.tokenRequests, hasLength(1));
    });

    test('a callback in another browser (login CSRF) fails', () async {
      final f = await _fixture();
      // The attacker starts a login and stops before the callback...
      final callback = f.provider.approve(
        await f.client.startLogin('keycloak'),
      );
      // ...and makes the victim's browser follow it.
      final victim = ChainClient(
        oauth2Http(
          f.provider,
          f.registrations,
          customizer: (login) => login.failureHandler(f.failures),
        ).build(),
        sessions: f.client.sessions,
      );
      await victim.callback(callback);
      expect(f.failures.lastCode, 'authorization_request_not_found');
      expect((await victim.get('/private')).reached, isFalse);
    });

    test('a replayed code is refused by the provider', () async {
      final f = await _fixture();
      final first = f.provider.approve(await f.client.startLogin('keycloak'));
      await f.client.callback(first);
      // A new login, answered with the first code and the new state.
      final second = await f.client.startLogin('keycloak');
      await f.client.callback(
        first.replace(
          queryParameters: {
            ...first.queryParameters,
            'state': second.queryParameters['state'],
          },
        ),
      );
      expect(f.failures.lastCode, 'invalid_grant');
    });

    test("a callback for registration B with A's state (mix-up)", () async {
      final provider = FakeOidcProvider();
      final other = FakeOidcProvider(
        transport: provider.transport,
        base: 'https://other.test',
      );
      final f = await _fixture(
        provider: provider,
        registrations: [
          await provider.registration(),
          await other.registration(id: 'other'),
        ],
      );
      final callback = provider.approve(await f.client.startLogin('keycloak'));
      await f.client.get(
        '/login/oauth2/code/other?${callback.query}',
      );
      expect(f.failures.lastCode, 'invalid_redirect_uri_parameter');
      expect(provider.tokenRequests, isEmpty);
      // The saved request is used up.
      await f.client.callback(callback);
      expect(f.failures.lastCode, 'authorization_request_not_found');
    });

    test('an error from the provider fails the login', () async {
      final f = await _fixture();
      final authorization = await f.client.startLogin('keycloak');
      await f.client.get(
        '/login/oauth2/code/keycloak?error=access_denied'
        '&state=${authorization.queryParameters['state']}',
      );
      expect(f.failures.lastCode, 'access_denied');
      expect(f.provider.tokenRequests, isEmpty);
    });

    test('an iss parameter of another issuer (RFC 9207)', () async {
      final f = await _fixture();
      f.provider.issParameter = 'https://evil.test';
      await f.client.loginWith(f.provider, 'keycloak');
      expect(f.failures.lastCode, 'invalid_issuer');
      expect(f.provider.tokenRequests, isEmpty);
    });

    test('no iss parameter from a provider that announces it', () async {
      final provider = FakeOidcProvider()
        ..advertiseIss = true
        ..includeIss = false;
      final f = await _fixture(provider: provider);
      await f.client.loginWith(provider, 'keycloak');
      expect(f.failures.lastCode, 'invalid_issuer');
    });

    test('the token endpoint refuses the code', () async {
      final f = await _fixture();
      f.provider.tokenError = 'invalid_grant';
      await f.client.loginWith(f.provider, 'keycloak');
      expect(f.failures.lastCode, 'invalid_grant');
      expect(await f.who(), isNull);
    });

    test('a token response without an ID token', () async {
      final f = await _fixture();
      f.provider.sendIdToken = false;
      await f.client.loginWith(f.provider, 'keycloak');
      expect(f.failures.lastCode, 'invalid_id_token');
    });
  });

  group('attacks with the ID token', () {
    Future<String?> loginWith(void Function(FakeOidcProvider p) change) async {
      final f = await _fixture();
      change(f.provider);
      final reply = await f.client.loginWith(f.provider, 'keycloak');
      expect(reply.header('location'), '/login?error');
      expect(await f.who(), isNull);
      return f.failures.lastCode;
    }

    test('a wrong nonce (a replayed ID token)', () async {
      expect(
        await loginWith((p) => p.forcedNonce = 'replayed'),
        'invalid_nonce',
      );
    });

    test('no nonce', () async {
      expect(await loginWith((p) => p.omitNonce = true), 'invalid_nonce');
    });

    test('another issuer', () async {
      expect(
        await loginWith((p) => p.issuedIssuer = 'https://evil.test'),
        'invalid_id_token',
      );
    });

    test('another audience', () async {
      expect(
        await loginWith((p) => p.audience = 'another-client'),
        'invalid_id_token',
      );
    });

    test('several audiences and azp of another client', () async {
      expect(
        await loginWith(
          (p) => p
            ..audience = [clientId, 'another-client']
            ..authorizedParty = 'another-client',
        ),
        'invalid_id_token',
      );
    });

    test('expired', () async {
      expect(
        await loginWith(
          (p) => p
            ..idTokenAge = const Duration(hours: 2)
            ..idTokenLifetime = const Duration(hours: 1),
        ),
        'invalid_id_token',
      );
    });

    test('alg: none', () async {
      expect(await loginWith((p) => p.unsigned = true), 'invalid_id_token');
    });

    test('signed by another key with the same kid', () async {
      expect(await loginWith((p) => p.signer = otherKeys), 'invalid_id_token');
    });

    test('an unknown kid fails, without flooding the provider', () async {
      final f = await _fixture();
      f.provider
        ..signer = otherKeys
        ..kid = 'rsa-unknown';
      await f.client.loginWith(f.provider, 'keycloak');
      expect(f.failures.lastCode, 'invalid_id_token');
      await f.client.loginWith(f.provider, 'keycloak');
      expect(f.failures.lastCode, 'invalid_id_token');
      expect(
        f.provider.jwkFetches,
        1,
        reason: 'unknown kids refetch at most every 30 seconds',
      );
    });

    test('HS256 signed with a guessable key (RS/HS confusion)', () async {
      expect(await loginWith((p) => p.alg = 'HS256'), 'invalid_id_token');
    });

    test('the user info of another user', () async {
      expect(
        await loginWith((p) => p.userInfoSubject = 'user-2'),
        'invalid_user_info_response',
      );
    });
  });

  group('after the login', () {
    test(
      'no open redirect: only the saved page or the configured URL',
      () async {
        const evil = 'https://evil.test';
        Future<Reply> login(_Fixture f) async {
          final callback = f.provider.approve(
            await f.client.startLogin('keycloak'),
          );
          return await f.client.get(
            '${callback.path}?${callback.query}'
            '&redirect_uri=$evil&continue=$evil&target=$evil&url=$evil',
          );
        }

        expect((await login(await _fixture())).header('location'), '/');
        final saved = await _fixture();
        await saved.client.get('/private?next=$evil');
        expect(
          (await login(saved)).header('location'),
          '/private?next=https://evil.test&continue',
          reason: 'the saved page of this site, its query as it was',
        );
      },
    );

    test('defaultSuccessUrl takes paths and http(s) URLs only', () async {
      final f = await _fixture();
      final http = oauth2Http(f.provider, f.registrations);
      for (final bad in [
        '//evil.test/',
        'javascript:alert(1)',
        'evil.test',
        r'https:\\evil.test',
      ]) {
        expect(
          () => http.oauth2Login((l) => l.defaultSuccessUrl(bad)),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('logout still needs the CSRF token', () async {
      final f = await _fixture();
      await f.client.loginWith(f.provider, 'keycloak');
      final forged = await f.client.post('/logout', {});
      expect(forged.status, 403);
      expect(await f.who(), isNotNull);
    });
  });

  group('OidcClientInitiatedLogoutSuccessHandler', () {
    Future<(_Fixture, Reply)> logout({
      String? postLogoutRedirectUri,
      FakeOidcProvider? provider,
    }) async {
      final fake = provider ?? FakeOidcProvider();
      final registrations = InMemoryClientRegistrationRepository([
        await fake.registration(),
      ]);
      final f = await _fixture(
        provider: fake,
        configure: (http) => http
          ..logout(
            (logout) => logout.logoutSuccessHandler(
              OidcClientInitiatedLogoutSuccessHandler(
                registrations,
                postLogoutRedirectUri: postLogoutRedirectUri,
              ),
            ),
          )
          // A page with the CSRF token, as an application has.
          ..formLogin()
          ..userDetailsService(testUsers()),
      );
      await f.client.loginWith(fake, 'keycloak');
      final token = (await f.client.get('/login')).csrfField;
      return (f, await f.client.post('/logout', {'_csrf': token}));
    }

    test('ends the provider session with the ID token as hint', () async {
      final (f, reply) = await logout(postLogoutRedirectUri: '{baseUrl}/bye');
      final location = Uri.parse(reply.header('location')!);
      expect(location.origin, 'https://sso.test');
      expect(location.path, '/logout');
      expect(location.queryParameters['id_token_hint'], f.provider.lastIdToken);
      expect(
        location.queryParameters['post_logout_redirect_uri'],
        'http://localhost/bye',
      );
      expect(await f.who(), isNull, reason: 'logged out locally first');
    });

    test('the templates include the context path', () async {
      final provider = FakeOidcProvider();
      final registrations = InMemoryClientRegistrationRepository([
        await provider.registration(),
      ]);
      final idToken = OidcIdToken.parse(provider.idToken(nonce: 'n'));
      final user = DefaultOidcUser([
        OidcUserAuthority(idToken),
      ], idToken);
      final response = MockServerHttpResponse();
      await OidcClientInitiatedLogoutSuccessHandler(
        registrations,
        postLogoutRedirectUri:
            '{baseScheme}://{baseHost}{basePort}'
            '{basePath}/{registrationId}',
      ).onLogoutSuccess(
        ContextPathRequest(
          MockServerHttpRequest(
            HttpMethod.post,
            'https://shop.test:8443/shop/logout',
          ),
          '/shop',
        ),
        response,
        OAuth2AuthenticationToken(user, user.authorities, 'keycloak'),
      );
      final location = Uri.parse(response.headers['location']!);
      expect(
        location.queryParameters['post_logout_redirect_uri'],
        'https://shop.test:8443/shop/keycloak',
      );
      expect(location.queryParameters['id_token_hint'], idToken.tokenValue);
    });

    test('without a post logout URI the provider shows its page', () async {
      final (_, reply) = await logout();
      final location = Uri.parse(reply.header('location')!);
      expect(location.queryParameters.keys, ['id_token_hint']);
    });

    test('a provider without the endpoint: the plain redirect', () async {
      final (_, reply) = await logout(
        provider: FakeOidcProvider()..endSession = false,
      );
      expect(reply.header('location'), '/');
    });

    test('a user who did not log in with OpenID Connect', () async {
      final provider = FakeOidcProvider();
      final handler = OidcClientInitiatedLogoutSuccessHandler(
        InMemoryClientRegistrationRepository([await provider.registration()]),
        logoutSuccessUrl: '/signed-out',
      );
      final response = MockServerHttpResponse();
      await handler.onLogoutSuccess(
        MockServerHttpRequest(HttpMethod.post, '/logout'),
        response,
        UsernamePasswordAuthenticationToken.authenticated(
          'ada',
          null,
          const [],
        ),
      );
      expect(response.headers['location'], '/signed-out');
    });
  });

  group('repositories', () {
    test('one authorization request per session, by its state, once', () async {
      final sessions = newSessions();
      const repository = HttpSessionOAuth2AuthorizationRequestRepository();
      final registration = await FakeOidcProvider().registration();
      OAuth2AuthorizationRequest request() =>
          OAuth2AuthorizationRequest.forRegistration(
            registration,
            redirectUri: 'http://localhost/login/oauth2/code/keycloak',
          );
      final (setup, setupResponse) = await exchange(sessions);
      final first = request();
      final second = request();
      await repository.saveAuthorizationRequest(first, setup, setupResponse);
      await repository.saveAuthorizationRequest(second, setup, setupResponse);
      final id = setup.getSession(create: false)!.id;

      Future<MockServerHttpRequest> callback(String? state) async {
        final (r, _) = await exchange(
          sessions,
          path: state == null ? '/cb' : '/cb?state=$state',
          cookies: {'JSESSIONID': id},
        );
        return r;
      }

      expect(repository.loadAuthorizationRequest(await callback(null)), isNull);
      expect(
        repository.loadAuthorizationRequest(await callback(first.state)),
        isNull,
        reason: 'replaced by the second',
      );
      final (r, response) = await exchange(
        sessions,
        path: '/cb?state=${second.state}',
        cookies: {'JSESSIONID': id},
      );
      expect(repository.removeAuthorizationRequest(r, response), second);
      expect(
        repository.loadAuthorizationRequest(await callback(second.state)),
        isNull,
        reason: 'removed when used',
      );
    });

    test('anonymous users keep their clients in the session', () async {
      final provider = FakeOidcProvider();
      final registration = await provider.registration();
      final service = InMemoryOAuth2AuthorizedClientService(
        InMemoryClientRegistrationRepository([registration]),
      );
      final repository = AuthenticatedPrincipalOAuth2AuthorizedClientRepository(
        service,
      );
      final sessions = newSessions();
      final (request, response) = await exchange(sessions);
      final client = OAuth2AuthorizedClient(
        registration,
        'anonymousUser',
        OAuth2AccessToken(TokenType.bearer, 'a'),
      );
      final anonymous = AnonymousAuthenticationToken(
        'key',
        'anonymousUser',
        [SimpleGrantedAuthority('ROLE_ANONYMOUS')],
      );
      await repository.saveAuthorizedClient(
        client,
        anonymous,
        request,
        response,
      );
      expect(
        await service.loadAuthorizedClient('keycloak', 'anonymousUser'),
        isNull,
      );
      expect(
        await repository.loadAuthorizedClient('keycloak', anonymous, request),
        client,
      );
      await repository.removeAuthorizedClient(
        'keycloak',
        anonymous,
        request,
        response,
      );
      expect(
        await repository.loadAuthorizedClient('keycloak', anonymous, request),
        isNull,
      );
    });
  });

  group('OidcIdTokenDecoderFactory', () {
    test('a registration without a JWK Set URI cannot be checked', () async {
      final registration = ClientRegistration.withRegistrationId('manual')
          .clientId(clientId)
          .clientSecret(clientSecret)
          .authorizationGrantType(AuthorizationGrantType.authorizationCode)
          .redirectUri('{baseUrl}/login/oauth2/code/{registrationId}')
          .scope({'openid'})
          .authorizationUri('https://sso.test/auth')
          .tokenUri('https://sso.test/token')
          .build();
      await expectLater(
        OidcIdTokenDecoderFactory().decode(registration, testKeys.token()),
        throwsA(
          isA<OAuth2AuthenticationException>().having(
            (e) => e.error.errorCode,
            'errorCode',
            'missing_signature_verifier',
          ),
        ),
      );
    });

    test('HS256 with the client secret when the resolver says so', () async {
      final provider = FakeOidcProvider();
      final registration = await provider.registration();
      final secret = utf8.encode(clientSecret.padRight(32, '!'));
      final macRegistration = ClientRegistration.withClientRegistration(
        registration,
      ).clientSecret(utf8.decode(secret)).build();
      final now = seconds(DateTime.now());
      final token = TokenFactory(testKeys.rsa, testKeys.ec, secret).token(
        alg: 'HS256',
        claims: {
          'iss': provider.issuer,
          'aud': clientId,
          'iat': now,
          'exp': now + 60,
        },
      );
      final decoder = OidcIdTokenDecoderFactory(
        jwsAlgorithmResolver: (_) => JwsAlgorithm.hs256,
      );
      expect(
        (await decoder.decode(macRegistration, token)).issuer,
        provider.issuer,
      );
      await expectLater(
        decoder.decode(registration, token),
        throwsA(isA<OAuth2AuthenticationException>()),
        reason: 'the client secret is too short for HS256',
      );
    });

    test('the decoder of a registration is made once', () async {
      final provider = FakeOidcProvider();
      final registration = await provider.registration();
      final decoder = OidcIdTokenDecoderFactory(
        fetcher: transportJwkFetcher(provider.transport),
      );
      expect(
        identical(
          decoder.createDecoder(registration),
          decoder.createDecoder(registration),
        ),
        isTrue,
      );
    });
  });
}
