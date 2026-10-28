// PKCE and the authorization request, the token response clients (client
// authentication, the forms, RFC 6749 §5.1 / §5.2 answers) and revocation.
import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

ClientRegistration _registration({
  ClientAuthenticationMethod method = ClientAuthenticationMethod.none,
  String? secret,
  String clientId = 'neon-app',
  AuthorizationGrantType grant = AuthorizationGrantType.authorizationCode,
  Set<String> scopes = const {'openid', 'profile'},
}) =>
    ClientRegistration.withRegistrationId('keycloak')
        .clientId(clientId)
        .clientSecret(secret)
        .clientAuthenticationMethod(method)
        .authorizationGrantType(grant)
        .redirectUri('http://127.0.0.1/callback')
        .authorizationUri('https://sso.test/auth')
        .tokenUri('https://sso.test/token')
        .scope(scopes)
        .build();

Map<String, String> _form(HttpRequest request) =>
    Uri.splitQueryString(utf8.decode(request.body!));

OAuth2AuthorizationCodeGrantRequest _codeGrant(
  ClientRegistration registration,
) {
  final request = OAuth2AuthorizationRequest.forRegistration(
    registration,
    redirectUri: 'http://127.0.0.1:50000/callback',
  );
  return OAuth2AuthorizationCodeGrantRequest(
    registration,
    OAuth2AuthorizationExchange(
      request,
      OAuth2AuthorizationResponse(
        redirectUri: 'http://127.0.0.1:50000/callback',
        code: 'the-code',
        state: request.state,
      ),
    ),
  );
}

void main() {
  group('PKCE and the authorization request', () {
    test('the RFC 7636 example (appendix B)', () {
      expect(
        sha256Base64Url('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('random values are long, base64url and never repeat', () {
      final values = {for (var i = 0; i < 1000; i++) generateSecureKey()};
      expect(values, hasLength(1000));
      for (final value in values) {
        expect(value, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      }
      expect(() => generateSecureKey(16), throwsArgumentError);
    });

    test('state, nonce and S256 challenge; the secrets stay home', () {
      final registration = _registration();
      final request = OAuth2AuthorizationRequest.forRegistration(
        registration,
        redirectUri: 'http://127.0.0.1:50000/callback',
        additionalParameters: {'prompt': 'login', 'code_challenge': 'forged'},
      );
      final query = request.authorizationRequestUri.queryParameters;
      expect(query['response_type'], 'code');
      expect(query['client_id'], 'neon-app');
      expect(query['scope'], 'openid profile');
      expect(query['state'], request.state);
      expect(query['prompt'], 'login');
      expect(query['code_challenge_method'], 'S256');
      expect(query['code_challenge'], sha256Base64Url(request.codeVerifier!));
      expect(query['nonce'], sha256Base64Url(request.nonce!));
      expect(request.codeVerifier!.length, greaterThanOrEqualTo(43));
      expect(request.codeVerifier!.length, lessThanOrEqualTo(128));
      expect(
        query.values,
        isNot(anyOf(contains(request.codeVerifier), contains(request.nonce))),
      );
      expect('$request', isNot(contains(request.state)));
    });

    test('no nonce without openid', () {
      final request = OAuth2AuthorizationRequest.forRegistration(
        _registration(scopes: {'profile'}),
        redirectUri: 'http://127.0.0.1/callback',
      );
      expect(request.nonce, isNull);
      expect(
        request.authorizationRequestUri.queryParameters.containsKey('nonce'),
        isFalse,
      );
      expect(request.codeVerifier, isNotNull); // PKCE always
    });

    test('a client_credentials registration has no authorization request', () {
      expect(
        () => OAuth2AuthorizationRequest.forRegistration(
          ClientRegistration.withRegistrationId('x')
              .clientId('c')
              .authorizationGrantType(AuthorizationGrantType.clientCredentials)
              .tokenUri('https://t')
              .build(),
          redirectUri: 'http://127.0.0.1/cb',
        ),
        throwsArgumentError,
      );
    });
  });

  group('the authorization_code client', () {
    test(
      'a public client sends the code, the redirect URI and the verifier',
      () async {
        final transport = MockHttpTransport()
          ..when(HttpMethod.post, 'https://sso.test/token').respond(
            200,
            json: {
              'access_token': 'at',
              'token_type': 'bearer',
              'expires_in': '300',
              'refresh_token': 'rt',
              'id_token': 'x.y.z',
            },
          );
        final grant = _codeGrant(_registration());
        final now = DateTime.utc(2026, 10, 28, 12);
        final response = await DefaultAuthorizationCodeTokenResponseClient(
          transport,
          clock: () => now,
        ).getTokenResponse(grant);

        final request = transport.lastRequest;
        expect(request.headers['Authorization'], isNull);
        expect(
          request.headers['Content-Type'],
          startsWith('application/x-www-form-urlencoded'),
        );
        expect(request.followRedirects, isFalse);
        expect(_form(request), {
          'grant_type': 'authorization_code',
          'code': 'the-code',
          'redirect_uri': 'http://127.0.0.1:50000/callback',
          'code_verifier':
              grant.authorizationExchange.authorizationRequest.codeVerifier,
          'client_id': 'neon-app',
        });
        expect(response.accessToken.tokenValue, 'at');
        expect(
          response.accessToken.expiresAt,
          now.add(const Duration(minutes: 5)),
        );
        // No scope in the answer: the requested ones (RFC 6749 §5.1).
        expect(response.accessToken.scopes, {'openid', 'profile'});
        expect(response.refreshToken?.tokenValue, 'rt');
        expect(response.additionalParameters, {'id_token': 'x.y.z'});
        expect('$response', isNot(contains('at')));
      },
    );

    test('client_secret_basic form-encodes id and secret first (RFC 6749 '
        '§2.3.1)', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.post, 'https://sso.test/token').respond(
          200,
          json: {'access_token': 'at', 'token_type': 'Bearer'},
        );
      await DefaultAuthorizationCodeTokenResponseClient(transport)
          .getTokenResponse(
            _codeGrant(
              _registration(
                method: ClientAuthenticationMethod.clientSecretBasic,
                clientId: 'my app',
                secret: 'p@ss:w&rd~é',
              ),
            ),
          );
      final header = transport.lastRequest.headers['Authorization']!;
      expect(
        utf8.decode(base64Decode(header.substring('Basic '.length))),
        'my+app:p%40ss%3Aw%26rd%7E%C3%A9',
      );
      expect(
        _form(transport.lastRequest).containsKey('client_secret'),
        isFalse,
      );
      expect(_form(transport.lastRequest).containsKey('client_id'), isFalse);
    });

    test('client_secret_post puts both in the form', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.post, 'https://sso.test/token').respond(
          200,
          json: {'access_token': 'at', 'token_type': 'Bearer'},
        );
      await DefaultAuthorizationCodeTokenResponseClient(transport)
          .getTokenResponse(
            _codeGrant(
              _registration(
                method: ClientAuthenticationMethod.clientSecretPost,
                secret: 's',
              ),
            ),
          );
      final form = _form(transport.lastRequest);
      expect(form['client_id'], 'neon-app');
      expect(form['client_secret'], 's');
    });

    test('an unsupported authentication method fails', () {
      expect(
        DefaultAuthorizationCodeTokenResponseClient(MockHttpTransport())
            .getTokenResponse(
              _codeGrant(
                _registration(
                  method: ClientAuthenticationMethod.privateKeyJwt,
                ),
              ),
            ),
        throwsA(
          isA<OAuth2AuthorizationException>().having(
            (e) => e.error.errorCode,
            'code',
            'invalid_client',
          ),
        ),
      );
    });
  });

  group('token responses (RFC 6749 §5.1, §5.2)', () {
    Future<OAuth2AccessTokenResponse> answer(
      int status, {
      Object? json,
      String? body,
    }) {
      final transport = MockHttpTransport()
        ..when(
          HttpMethod.post,
          'https://sso.test/token',
        ).respond(status, json: json, body: body);
      return DefaultAuthorizationCodeTokenResponseClient(transport)
          .getTokenResponse(_codeGrant(_registration()));
    }

    Matcher failsWith(String code) => throwsA(
      isA<OAuth2AuthorizationException>().having(
        (e) => e.error.errorCode,
        'code',
        code,
      ),
    );

    test("an error answer is the provider's error", () async {
      await expectLater(
        answer(
          400,
          json: {
            'error': 'invalid_grant',
            'error_description': 'Code not valid',
            'error_uri': 'https://sso.test/errors',
          },
        ),
        throwsA(
          isA<OAuth2AuthorizationException>().having(
            (e) => e.error,
            'error',
            const OAuth2Error(
              'invalid_grant',
              'Code not valid',
              'https://sso.test/errors',
            ),
          ),
        ),
      );
    });

    test('an error without a body', () async {
      await expectLater(answer(500), failsWith('invalid_token_response'));
      await expectLater(
        answer(502, body: '<html>bad gateway</html>'),
        failsWith('invalid_token_response'),
      );
    });

    test('a token type other than Bearer', () async {
      await expectLater(
        answer(200, json: {'access_token': 'at', 'token_type': 'mac'}),
        failsWith('invalid_token_response'),
      );
    });

    test('no access token, or not JSON', () async {
      await expectLater(
        answer(200, json: {'token_type': 'Bearer'}),
        failsWith('invalid_token_response'),
      );
      await expectLater(
        answer(200, body: 'access_token=at'),
        failsWith('invalid_token_response'),
      );
      await expectLater(
        answer(200, json: ['at']),
        failsWith('invalid_token_response'),
      );
    });

    test('a bad expires_in', () async {
      await expectLater(
        answer(
          200,
          json: {
            'access_token': 'at',
            'token_type': 'Bearer',
            'expires_in': 'x',
          },
        ),
        failsWith('invalid_token_response'),
      );
    });

    test('the scope of the answer wins', () async {
      final response = await answer(
        200,
        json: {'access_token': 'at', 'token_type': 'Bearer', 'scope': 'openid'},
      );
      expect(response.accessToken.scopes, {'openid'});
    });

    test('no token in error messages', () async {
      try {
        await answer(
          200,
          json: {'access_token': 'secret-at', 'token_type': 'mac'},
        );
        fail('accepted');
      } on OAuth2AuthorizationException catch (e) {
        expect('$e', isNot(contains('secret-at')));
      }
    });

    test('an unreachable provider', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.post, 'https://sso.test/token').fail(
          HttpTransportException('connection refused'),
        );
      await expectLater(
        DefaultAuthorizationCodeTokenResponseClient(transport)
            .getTokenResponse(_codeGrant(_registration())),
        failsWith('invalid_token_response'),
      );
    });
  });

  group('refresh and client credentials', () {
    test('a refresh keeps the old refresh token when none is issued', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.post, 'https://sso.test/token').respond(
          200,
          json: {'access_token': 'new', 'token_type': 'Bearer'},
        );
      final old = OAuth2RefreshToken('rt');
      final response = await DefaultRefreshTokenTokenResponseClient(transport)
          .getTokenResponse(
            OAuth2RefreshTokenGrantRequest(
              _registration(),
              OAuth2AccessToken(
                TokenType.bearer,
                'old',
                scopes: {'openid', 'profile'},
              ),
              old,
            ),
          );
      expect(_form(transport.lastRequest), {
        'grant_type': 'refresh_token',
        'refresh_token': 'rt',
        'client_id': 'neon-app',
      });
      expect(response.refreshToken, same(old));
      expect(response.accessToken.scopes, {'openid', 'profile'});
    });

    test('client credentials send the scopes', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.post, 'https://sso.test/token').respond(
          200,
          json: {
            'access_token': 'at',
            'token_type': 'Bearer',
            'expires_in': 60,
          },
        );
      await DefaultClientCredentialsTokenResponseClient(transport)
          .getTokenResponse(
            OAuth2ClientCredentialsGrantRequest(
              _registration(
                grant: AuthorizationGrantType.clientCredentials,
                method: ClientAuthenticationMethod.clientSecretBasic,
                secret: 's',
                scopes: {'orders.read'},
              ),
            ),
          );
      expect(_form(transport.lastRequest), {
        'grant_type': 'client_credentials',
        'scope': 'orders.read',
      });
    });
  });

  group('revocation (RFC 7009)', () {
    final registration =
        ClientRegistration.withClientRegistration(
          _registration(),
        ).providerConfigurationMetadata({
          'revocation_endpoint': 'https://sso.test/revoke',
        }).build();

    test('sends the token with its type hint', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.post, 'https://sso.test/revoke').respond(200);
      expect(
        await OAuth2TokenRevocationClient(transport).revoke(
          registration,
          OAuth2RefreshToken('rt'),
        ),
        isTrue,
      );
      expect(_form(transport.lastRequest), {
        'token': 'rt',
        'token_type_hint': 'refresh_token',
        'client_id': 'neon-app',
      });
    });

    test('a refusal is an OAuth2AuthorizationException', () {
      final transport = MockHttpTransport()
        ..when(HttpMethod.post, 'https://sso.test/revoke').respond(
          400,
          json: {'error': 'unsupported_token_type'},
        );
      expect(
        OAuth2TokenRevocationClient(transport).revoke(
          registration,
          OAuth2AccessToken(TokenType.bearer, 'at'),
        ),
        throwsA(isA<OAuth2AuthorizationException>()),
      );
    });

    test('nothing without an endpoint', () async {
      expect(
        await OAuth2TokenRevocationClient(MockHttpTransport()).revoke(
          _registration(),
          OAuth2RefreshToken('rt'),
        ),
        isFalse,
      );
    });
  });
}
