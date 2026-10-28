// The ID token, its validator and the user services.
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/fake_provider.dart';

final _now = DateTime.utc(2026, 10, 28, 12);

ClientRegistration _registration({String? issuerUri = issuer}) =>
    ClientRegistration.withRegistrationId('keycloak')
        .clientId(clientId)
        .authorizationGrantType(AuthorizationGrantType.authorizationCode)
        .redirectUri('http://127.0.0.1/callback')
        .authorizationUri('https://sso.test/auth')
        .tokenUri('https://sso.test/token')
        .userInfoUri('https://sso.test/userinfo')
        .userNameAttributeName('sub')
        .issuerUri(issuerUri)
        .scope(['openid', 'profile'])
        .build();

OidcIdToken _token(Map<String, Object?> changes) => OidcIdToken.parse(
  jwt(
    {
      'iss': issuer,
      'sub': 'user-1',
      'aud': clientId,
      'iat': seconds(_now),
      'exp': seconds(_now) + 300,
      ...changes,
    }..removeWhere((_, value) => value == null),
  ),
);

List<String> _invalid(
  OidcIdToken token, {
  ClientRegistration? registration,
  String? nonce,
}) => [
  for (final error in OidcIdTokenValidator(
    registration ?? _registration(),
    nonce: nonce,
    clock: () => _now,
  ).validate(token).errors)
    error.errorCode,
];

void main() {
  group('OidcIdToken.parse', () {
    test('reads the claims', () {
      final token = _token({'name': 'Ada', 'auth_time': seconds(_now) - 60});
      expect(token.subject, 'user-1');
      expect(token.audience, [clientId]);
      expect(token.issuedAt, _now);
      expect(token.expiresAt, _now.add(const Duration(minutes: 5)));
      expect(token.fullName, 'Ada');
      expect(token.authenticatedAt, _now.subtract(const Duration(minutes: 1)));
      expect('$token', isNot(contains(token.tokenValue)));
    });

    test('refuses unsigned and malformed tokens', () {
      for (final raw in [
        jwt({'sub': 'x'}, alg: 'none'),
        jwt({'sub': 'x'}, alg: 'NONE'),
        'a.b',
        'not-a-jwt',
        '${jwt({'sub': 'x'})}.extra',
        jwt({'sub': 'x'}).replaceFirst(RegExp(r'\.[^.]*$'), '.'),
        'e30.W10.c2ln', // payload is a list
        'x' * 100001,
      ]) {
        expect(
          () => OidcIdToken.parse(raw),
          throwsFormatException,
          reason: raw,
        );
      }
    });
  });

  group('OidcIdTokenValidator', () {
    test('a good token passes', () {
      expect(_invalid(_token({})), isEmpty);
    });

    test('required claims', () {
      for (final claim in ['iss', 'sub', 'aud', 'exp', 'iat']) {
        expect(_invalid(_token({claim: null})), [
          'invalid_id_token',
        ], reason: claim);
      }
    });

    test('iss, aud and azp', () {
      expect(_invalid(_token({'iss': 'https://evil.test'})), [
        'invalid_id_token',
      ]);
      expect(_invalid(_token({'aud': 'other'})), ['invalid_id_token']);
      expect(
        _invalid(
          _token({
            'aud': [clientId, 'other'],
          }),
        ),
        ['invalid_id_token'],
      );
      expect(
        _invalid(
          _token({
            'aud': [clientId, 'other'],
            'azp': clientId,
          }),
        ),
        isEmpty,
      );
      expect(_invalid(_token({'azp': 'other'})), ['invalid_id_token']);
      // No issuer known (a registration without one): not compared.
      expect(
        _invalid(
          _token({'iss': 'https://anyone.test'}),
          registration: _registration(issuerUri: null),
        ),
        isEmpty,
      );
    });

    test('exp and iat with 60 seconds of skew', () {
      expect(_invalid(_token({'exp': seconds(_now) - 59})), isEmpty);
      expect(_invalid(_token({'exp': seconds(_now) - 61})), [
        'invalid_id_token',
      ]);
      expect(
        _invalid(
          _token({'iat': seconds(_now) + 59, 'exp': seconds(_now) + 600}),
        ),
        isEmpty,
      );
      expect(
        _invalid(
          _token({'iat': seconds(_now) + 61, 'exp': seconds(_now) + 600}),
        ),
        ['invalid_id_token'],
      );
    });

    test('the nonce is the hash of the one sent', () {
      final good = _token({'nonce': sha256Base64Url('raw-nonce')});
      expect(_invalid(good, nonce: 'raw-nonce'), isEmpty);
      expect(_invalid(good, nonce: 'other'), ['invalid_nonce']);
      expect(_invalid(_token({}), nonce: 'raw-nonce'), ['invalid_nonce']);
      // The raw nonce in the token (a client that would send it raw).
      expect(
        _invalid(_token({'nonce': 'raw-nonce'}), nonce: 'raw-nonce'),
        ['invalid_nonce'],
      );
    });

    test('the default decoder runs the validator', () async {
      final decoder = TokenEndpointOidcIdTokenDecoder(clock: () => _now);
      expect(
        (await decoder.decode(_registration(), _token({}).tokenValue)).subject,
        'user-1',
      );
      await expectLater(
        decoder.decode(_registration(), _token({'aud': 'x'}).tokenValue),
        throwsA(isA<OAuth2AuthenticationException>()),
      );
      await expectLater(
        decoder.decode(_registration(), 'garbage'),
        throwsA(
          isA<OAuth2AuthenticationException>().having(
            (e) => e.error.errorCode,
            'code',
            'invalid_id_token',
          ),
        ),
      );
    });
  });

  group('user services', () {
    MockHttpTransport userInfo(int status, Object? json) =>
        MockHttpTransport()
          ..when(HttpMethod.get, 'https://sso.test/userinfo').respond(
            status,
            json: json,
            headers: status == 401
                ? {'WWW-Authenticate': 'Bearer error="invalid_token"'}
                : const {},
          );
    final access = OAuth2AccessToken(
      TokenType.bearer,
      'at',
      scopes: {'openid', 'profile'},
    );

    test(
      'DefaultOAuth2UserService sends the token and names the user',
      () async {
        final transport = userInfo(200, {'sub': 'user-1', 'login': 'ada'});
        final user = await DefaultOAuth2UserService(transport).loadUser(
          OAuth2UserRequest(_registration(), access),
        );
        expect(transport.lastRequest.headers['Authorization'], 'Bearer at');
        expect(user.name, 'user-1');
        expect(user.getAttribute<String>('login'), 'ada');
        expect(AuthorityUtils.authorityListToSet(user.authorities), {
          'OAUTH2_USER',
          'SCOPE_openid',
          'SCOPE_profile',
        });
      },
    );

    test('the name attribute must be there', () {
      final transport = userInfo(200, {'login': 'ada'});
      expect(
        DefaultOAuth2UserService(transport).loadUser(
          OAuth2UserRequest(_registration(), access),
        ),
        throwsA(isA<OAuth2AuthenticationException>()),
      );
    });

    test('an error of the endpoint fails without the token', () async {
      try {
        await DefaultOAuth2UserService(userInfo(401, null)).loadUser(
          OAuth2UserRequest(_registration(), access),
        );
        fail('loaded');
      } on OAuth2AuthenticationException catch (e) {
        expect(e.error.errorCode, 'invalid_user_info_response');
        expect(e.message, contains('invalid_token'));
        expect('$e', isNot(contains('Bearer at')));
      }
    });

    test('OidcUserService checks the subject of the user info', () async {
      final idToken = _token({'name': 'Ada'});
      final good = await OidcUserService(
        userInfo(200, {'sub': 'user-1', 'email': 'ada@example.com'}),
      ).loadUser(OidcUserRequest(_registration(), access, idToken));
      expect(good.email, 'ada@example.com');
      expect(good.fullName, 'Ada');
      expect(good.name, 'user-1');
      expect(good.authorities.first, isA<OidcUserAuthority>());

      for (final answer in [
        {'sub': 'user-2'},
        {'email': 'no-sub@example.com'},
      ]) {
        await expectLater(
          OidcUserService(userInfo(200, answer)).loadUser(
            OidcUserRequest(_registration(), access, idToken),
          ),
          throwsA(
            isA<OAuth2AuthenticationException>().having(
              (e) => e.error.errorCode,
              'code',
              'invalid_user_info_response',
            ),
          ),
        );
      }
    });

    test('no user info without a profile scope', () async {
      final transport = MockHttpTransport();
      final user = await OidcUserService(transport).loadUser(
        OidcUserRequest(
          _registration(),
          OAuth2AccessToken(TokenType.bearer, 'at', scopes: {'openid'}),
          _token({}),
        ),
      );
      expect(transport.requests, isEmpty);
      expect(user.userInfo, isNull);
      expect(user.subject, 'user-1');
    });

    test('the ID token claims win over the user info', () async {
      final user =
          await OidcUserService(
            userInfo(200, {'sub': 'user-1', 'name': 'Mallory'}),
          ).loadUser(
            OidcUserRequest(_registration(), access, _token({'name': 'Ada'})),
          );
      expect(user.fullName, 'Ada');
    });
  });

  test('OAuth2AuthenticationToken', () {
    final user = DefaultOAuth2User(
      AuthorityUtils.createAuthorityList(['OAUTH2_USER']),
      {'id': 42, 'login': 'ada'},
      'id',
    );
    final token = OAuth2AuthenticationToken(
      user,
      user.authorities,
      'github',
    );
    expect(token.isAuthenticated, isTrue);
    expect(token.name, '42');
    expect(token.credentials, '');
    expect(
      () => DefaultOAuth2User(const [], {'login': 'ada'}, 'id'),
      throwsArgumentError,
    );
  });
}
