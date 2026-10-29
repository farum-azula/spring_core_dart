// The app login against a fake provider: the happy path, then each
// attack the login must refuse (docs/security.md: attacks as tests).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

import 'support/fake_provider.dart';

Matcher failsWith(String code) => throwsA(
  isA<OAuth2AuthenticationException>().having(
    (e) => e.error.errorCode,
    'errorCode',
    code,
  ),
);

void main() {
  late LoginFixture fixture;
  late NativeOAuth2LoginService login;

  setUp(() async {
    fixture = await LoginFixture.create();
    login = fixture.service();
  });

  group('login', () {
    test('logs in with PKCE, state and nonce, and keeps everything', () async {
      final authentication = await login.login('keycloak');

      final user = authentication.principal as OidcUser;
      expect(authentication.name, 'user-1');
      expect(authentication.authorizedClientRegistrationId, 'keycloak');
      expect(user.fullName, 'Ada Lovelace');
      expect(user.email, 'ada@example.com'); // from the user info
      expect(user.userInfo?.subject, 'user-1');
      expect(
        AuthorityUtils.authorityListToSet(authentication.authorities),
        {'OIDC_USER', 'SCOPE_openid', 'SCOPE_profile', 'SCOPE_email'},
      );
      expect(login.user, same(user));
      expect(
        fixture.strategy.getContext().authentication,
        same(authentication),
      );
      expect(fixture.events.single, isA<AuthenticationSuccessEvent>());

      // The authorization request: PKCE S256, a state, a nonce hash, the
      // redirect URI the browser chose.
      final opened = fixture.window.opened.single.queryParameters;
      expect(opened['redirect_uri'], 'http://127.0.0.1:49152/callback');
      expect(opened['state']!.length, greaterThanOrEqualTo(43));
      expect(opened['nonce']!.length, 43);
      expect(opened['code_challenge']!.length, 43);
      expect(opened.containsKey('code_verifier'), isFalse);

      // The token request: the same redirect URI and the verifier.
      final form = fixture.provider.tokenRequests.single;
      expect(form['redirect_uri'], 'http://127.0.0.1:49152/callback');
      expect(form['code_verifier'], isNotNull);
      expect(form.containsKey('client_secret'), isFalse);

      final client = await fixture.clients.loadAuthorizedClient(
        'keycloak',
        'user-1',
      );
      expect(client!.accessToken.tokenValue, startsWith('access-'));
      expect(client.refreshToken, isNotNull);
      expect(client.idToken?.subject, 'user-1');
    });

    test('a GrantedAuthoritiesMapper maps the authorities', () async {
      final mapped = await fixture
          .service(mapper: const _AdminMapper())
          .login('keycloak');
      expect(
        AuthorityUtils.authorityListToSet(mapped.authorities),
        contains('ROLE_ADMIN'),
      );
    });

    test('an OAuth 2.0 login (no openid) loads the user info', () async {
      final oauth = await LoginFixture.create(scopes: {'profile'});
      final reg = await oauth.repository.findByRegistrationId('keycloak');
      expect(
        reg!.providerDetails.userInfoEndpoint.userNameAttributeName,
        'sub',
      );
      final authentication = await oauth.service().login('keycloak');
      expect(authentication.principal, isNot(isA<OidcUser>()));
      expect(authentication.name, 'user-1');
      expect(
        AuthorityUtils.authorityListToSet(authentication.authorities),
        {'OAUTH2_USER', 'SCOPE_profile'},
      );
    });

    test('a cancelled page fails without a login', () async {
      fixture.window.cancel = true;
      await expectLater(
        login.login('keycloak'),
        throwsA(isA<AuthorizationCancelledException>()),
      );
      expect(login.isLoggedIn, isFalse);
    });

    test('an unknown registration fails', () {
      expect(
        login.login('nope'),
        failsWith(OAuth2ErrorCodes.clientRegistrationNotFound),
      );
    });

    test('without a login window (a web page) it refuses', () {
      expect(
        fixture.service(withWindow: false).login('keycloak'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('a second login while one runs is refused', () async {
      final first = login.login('keycloak');
      expect(login.login('keycloak'), throwsA(isA<StateError>()));
      await first;
    });
  });

  group('forged and broken redirects are refused', () {
    Uri approved(Uri uri) => fixture.provider.approve(uri);
    Uri withQuery(Uri uri, Map<String, String?> changes) {
      final query = {...uri.queryParameters};
      for (final MapEntry(:key, :value) in changes.entries) {
        if (value == null) {
          query.remove(key);
        } else {
          query[key] = value;
        }
      }
      return uri.replace(queryParameters: query);
    }

    Future<void> refused(
      Uri Function(Uri authorizationUri) respond,
      String code,
    ) async {
      fixture.window.respond = respond;
      await expectLater(login.login('keycloak'), failsWith(code));
      expect(login.isLoggedIn, isFalse);
      expect(fixture.strategy.getContext().authentication, isNull);
      expect(fixture.events, isEmpty);
      expect(fixture.provider.tokenRequests, isEmpty, reason: 'no exchange');
    }

    test('missing state', () async {
      await refused(
        (uri) => withQuery(approved(uri), {'state': null}),
        OAuth2ErrorCodes.invalidStateParameter,
      );
    });

    test('wrong state (a forged redirect, CSRF)', () async {
      await refused(
        (uri) => withQuery(approved(uri), {'state': 'attacker'}),
        OAuth2ErrorCodes.invalidStateParameter,
      );
    });

    test('state given twice', () async {
      await refused((uri) {
        final good = approved(uri);
        return good.replace(
          query: '${good.query}&state=attacker',
        );
      }, OAuth2ErrorCodes.invalidStateParameter);
    });

    test("an error parameter is the provider's error", () async {
      await refused(
        (uri) => Uri.parse(uri.queryParameters['redirect_uri']!).replace(
          queryParameters: {
            'error': 'access_denied',
            'error_description': 'The user said no',
            'state': ?uri.queryParameters['state'],
          },
        ),
        OAuth2ErrorCodes.accessDenied,
      );
    });

    test('an error with a wrong state is a forged redirect', () async {
      await refused(
        (uri) => Uri.parse(uri.queryParameters['redirect_uri']!).replace(
          queryParameters: {'error': 'access_denied', 'state': 'x'},
        ),
        OAuth2ErrorCodes.invalidStateParameter,
      );
    });

    test('a wrong iss parameter (mix-up attack, RFC 9207)', () async {
      await refused(
        (uri) => withQuery(approved(uri), {'iss': 'https://evil.test'}),
        OAuth2ErrorCodes.invalidIssuer,
      );
    });

    test('a missing iss although the provider advertises it', () async {
      final provider = FakeProvider()..advertiseIssParameter = true;
      fixture = await LoginFixture.create(provider: provider);
      login = fixture.service();
      await refused(
        (uri) => withQuery(approved(uri), {'iss': null}),
        OAuth2ErrorCodes.invalidIssuer,
      );
    });

    test('no code', () async {
      await refused(
        (uri) => withQuery(approved(uri), {'code': null}),
        OAuth2ErrorCodes.invalidRequest,
      );
    });

    test('a redirect to another URI', () async {
      await refused(
        (uri) => approved(uri).replace(path: '/elsewhere'),
        OAuth2ErrorCodes.invalidRedirectUri,
      );
      await refused(
        (uri) => approved(uri).replace(port: 1234),
        OAuth2ErrorCodes.invalidRedirectUri,
      );
    });

    test('a code of another login (no matching verifier)', () async {
      fixture.window.respond = (uri) {
        // The attacker's code, obtained with the attacker's own challenge.
        final stolen = fixture.provider.approve(
          uri.replace(
            queryParameters: {
              ...uri.queryParameters,
              'code_challenge': sha256Base64Url('attacker-verifier-' * 3),
            },
          ),
        );
        return stolen;
      };
      await expectLater(
        login.login('keycloak'),
        failsWith(OAuth2ErrorCodes.invalidGrant),
      );
      expect(login.isLoggedIn, isFalse);
    });
  });

  group('bad ID tokens are refused', () {
    Future<void> refused(
      void Function(FakeProvider) change,
      String code,
    ) async {
      change(fixture.provider);
      await expectLater(login.login('keycloak'), failsWith(code));
      expect(login.isLoggedIn, isFalse);
      expect(fixture.events, isEmpty);
      expect(
        await fixture.store.read(NativeOAuth2LoginService.sessionKey),
        isNull,
      );
      expect(
        await fixture.clients.loadAuthorizedClient('keycloak', 'user-1'),
        isNull,
      );
    }

    test('no ID token', () async {
      await refused((p) => p.sendIdToken = false, 'invalid_id_token');
    });

    test('another issuer', () async {
      await refused(
        (p) => p.issuedIssuer = 'https://evil.test',
        'invalid_id_token',
      );
    });

    test('another audience', () async {
      await refused((p) => p.audience = 'other-app', 'invalid_id_token');
    });

    test('several audiences without azp', () async {
      await refused(
        (p) => p.audience = [clientId, 'other-app'],
        'invalid_id_token',
      );
    });

    test('azp of another client', () async {
      await refused((p) => p.authorizedParty = 'other-app', 'invalid_id_token');
    });

    test('several audiences with azp of this client pass', () async {
      fixture.provider
        ..audience = [clientId, 'other-app']
        ..authorizedParty = clientId;
      expect((await login.login('keycloak')).name, 'user-1');
    });

    test('expired beyond the clock skew', () async {
      await refused(
        (p) => p
          ..idTokenAge = const Duration(minutes: 10)
          ..idTokenLifetime = const Duration(minutes: 5),
        'invalid_id_token',
      );
    });

    test('expired within the clock skew passes', () async {
      fixture.provider
        ..idTokenAge = const Duration(minutes: 5, seconds: 30)
        ..idTokenLifetime = const Duration(minutes: 5);
      expect((await login.login('keycloak')).name, 'user-1');
    });

    test('issued in the future', () async {
      await refused(
        (p) => p.idTokenAge = const Duration(minutes: -5),
        'invalid_id_token',
      );
    });

    test('a replayed token (wrong nonce)', () async {
      await refused((p) => p.corruptNonce = true, 'invalid_nonce');
    });

    test('alg none', () async {
      fixture.window.respond = fixture.provider.approve;
      // The provider answers an unsigned token.
      fixture.provider.transport.reset();
      final provider = fixture.provider;
      provider.transport
          .when(HttpMethod.post, 'https://sso.test/token')
          .respondWith(
            (request) => HttpResponse(
              200,
              headers: HttpHeaders({'Content-Type': 'application/json'}),
              body: utf8.encode(
                jsonEncode({
                  'access_token': 'a',
                  'token_type': 'Bearer',
                  'id_token': jwt({
                    'iss': issuer,
                    'sub': 'user-1',
                    'aud': clientId,
                    'iat': seconds(provider.now),
                    'exp': seconds(provider.now) + 300,
                  }, alg: 'none'),
                }),
              ),
            ),
          );
      await expectLater(login.login('keycloak'), failsWith('invalid_id_token'));
    });

    test('user info about someone else', () async {
      await refused(
        (p) => p.userInfoSubject = 'user-2',
        OAuth2ErrorCodes.invalidUserInfoResponse,
      );
    });

    test('a refused code exchange', () async {
      await refused(
        (p) => p.tokenError = 'invalid_grant',
        OAuth2ErrorCodes.invalidGrant,
      );
    });
  });

  group('restore', () {
    test('brings back the stored user, offline too', () async {
      await login.login('keycloak');
      // A restarted app: a new service and a fresh context.
      fixture.strategy.clearContext();
      fixture.events.clear();
      fixture.provider.tokenUnreachable = true; // the token is still fresh
      final again = fixture.service();
      final restored = await again.restore();
      expect(restored?.name, 'user-1');
      expect((restored!.principal as OidcUser).email, 'ada@example.com');
      expect(fixture.strategy.getContext().authentication, same(restored));
      expect(fixture.events.single, isA<AuthenticationSuccessEvent>());
    });

    test('refreshes an access token that expires soon', () async {
      await login.login('keycloak');
      final before = await fixture.clients.loadAuthorizedClient(
        'keycloak',
        'user-1',
      );
      fixture.provider.now = fixture.provider.now.add(
        const Duration(minutes: 4, seconds: 30), // 30 s left, skew is 60 s
      );
      final restored = await fixture.service().restore();
      expect(restored?.name, 'user-1');
      final after = await fixture.clients.loadAuthorizedClient(
        'keycloak',
        'user-1',
      );
      expect(
        after!.accessToken.tokenValue,
        isNot(before!.accessToken.tokenValue),
      );
      expect(
        after.refreshToken!.tokenValue,
        isNot(before.refreshToken!.tokenValue),
      );
      expect(
        fixture.provider.tokenRequests.last['grant_type'],
        'refresh_token',
      );
    });

    test('a revoked refresh token logs the user out', () async {
      await login.login('keycloak');
      fixture.provider
        ..now = fixture.provider.now.add(const Duration(hours: 1))
        ..revokeEverything();
      expect(await fixture.service().restore(), isNull);
      expect(
        await fixture.store.read(NativeOAuth2LoginService.sessionKey),
        isNull,
      );
      expect(
        await fixture.clients.loadAuthorizedClient('keycloak', 'user-1'),
        isNull,
      );
    });

    test('an unreachable provider keeps the user (offline start)', () async {
      await login.login('keycloak');
      fixture.provider
        ..now = fixture.provider.now.add(const Duration(hours: 1))
        ..tokenUnreachable = true;
      expect((await fixture.service().restore())?.name, 'user-1');
      expect(
        await fixture.clients.loadAuthorizedClient('keycloak', 'user-1'),
        isNotNull,
      );
    });

    test('a refreshed ID token about another user is refused', () async {
      await login.login('keycloak');
      fixture.provider
        ..now = fixture.provider.now.add(const Duration(hours: 1))
        ..subject = 'user-2';
      expect(await fixture.service().restore(), isNull);
    });

    test('a damaged record is removed', () async {
      await fixture.store.write(
        NativeOAuth2LoginService.sessionKey,
        '{not json',
      );
      expect(await login.restore(), isNull);
      expect(
        await fixture.store.read(NativeOAuth2LoginService.sessionKey),
        isNull,
      );
    });

    test('nothing stored, nobody restored', () async {
      expect(await login.restore(), isNull);
      expect(fixture.events, isEmpty);
    });
  });

  group('logout', () {
    test('revokes the tokens, forgets them and clears the context', () async {
      final authentication = await login.login('keycloak');
      final client = await fixture.clients.loadAuthorizedClient(
        'keycloak',
        'user-1',
      );
      fixture.events.clear();

      await login.logout();

      final revoked = fixture.provider.revoked;
      expect(revoked.map((form) => form['token_type_hint']), [
        'refresh_token',
        'access_token',
      ]);
      expect(revoked.first['token'], client!.refreshToken!.tokenValue);
      expect(revoked.last['token'], client.accessToken.tokenValue);
      expect(revoked.first['client_id'], clientId);
      expect(login.isLoggedIn, isFalse);
      expect(fixture.strategy.getContext().authentication, isNull);
      expect(
        await fixture.store.read(NativeOAuth2LoginService.sessionKey),
        isNull,
      );
      expect(
        await fixture.clients.loadAuthorizedClient('keycloak', 'user-1'),
        isNull,
      );
      final event = fixture.events.single as LogoutSuccessEvent;
      expect(event.authentication, same(authentication));
      expect(await fixture.service().restore(), isNull);
    });

    test('ends the provider session with the ID token as hint', () async {
      await login.login('keycloak');
      final idToken = fixture.provider.lastIdToken;
      await login.logout(endSession: true);
      final page = fixture.window.opened.last;
      expect(page.path, '/logout');
      expect(page.queryParameters['id_token_hint'], idToken);
      expect(page.queryParameters['client_id'], clientId);
      expect(
        page.queryParameters['post_logout_redirect_uri'],
        'http://127.0.0.1:49152/callback',
      );
    });

    test('logs out locally when revocation fails', () async {
      await login.login('keycloak');
      fixture.provider.transport.reset(); // the provider is gone
      await login.logout();
      expect(login.isLoggedIn, isFalse);
      expect(
        await fixture.store.read(NativeOAuth2LoginService.sessionKey),
        isNull,
      );
    });

    test('without a revocation endpoint nothing is revoked', () async {
      fixture = await LoginFixture.create(
        provider: FakeProvider()..revocation = false,
      );
      login = fixture.service();
      await login.login('keycloak');
      await login.logout();
      expect(fixture.provider.revoked, isEmpty);
      expect(login.isLoggedIn, isFalse);
    });
  });

  test('no token in what the login logs or prints', () async {
    final authentication = await login.login('keycloak');
    final client = await fixture.clients.loadAuthorizedClient(
      'keycloak',
      'user-1',
    );
    final texts = [
      '$authentication',
      '$client',
      '${client!.accessToken}',
      '${client.refreshToken}',
      '${client.clientRegistration}',
    ].join('\n');
    expect(texts, isNot(contains(client.accessToken.tokenValue)));
    expect(texts, isNot(contains(client.refreshToken!.tokenValue)));
  });
}

final class _AdminMapper implements GrantedAuthoritiesMapper {
  const _AdminMapper();

  @override
  List<GrantedAuthority> mapAuthorities(
    Iterable<GrantedAuthority> authorities,
  ) => [...authorities, SimpleGrantedAuthority('ROLE_ADMIN')];
}
