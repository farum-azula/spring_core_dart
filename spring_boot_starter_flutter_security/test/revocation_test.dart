// The token revocation of the app logout (RFC 7009): the form, the client
// authentication, the provider's refusal.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show MockHttpTransport;

ClientRegistration _registration({
  ClientAuthenticationMethod method = ClientAuthenticationMethod.none,
  String? secret,
  Map<String, Object?> metadata = const {
    'revocation_endpoint': 'https://sso.test/revoke',
  },
}) =>
    ClientRegistration.withRegistrationId('keycloak')
        .clientId('neon-app')
        .clientSecret(secret)
        .clientAuthenticationMethod(method)
        .authorizationGrantType(AuthorizationGrantType.authorizationCode)
        .redirectUri('http://127.0.0.1/callback')
        .authorizationUri('https://sso.test/auth')
        .tokenUri('https://sso.test/token')
        .providerConfigurationMetadata(metadata)
        .build();

Map<String, String> _form(HttpRequest request) =>
    Uri.splitQueryString(utf8.decode(request.body!));

void main() {
  final registration = _registration();

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
        _registration(metadata: const {}),
        OAuth2RefreshToken('rt'),
      ),
      isFalse,
    );
  });

  test('a confidential client authenticates with HTTP Basic', () async {
    final transport = MockHttpTransport()
      ..when(HttpMethod.post, 'https://sso.test/revoke').respond(200);
    await OAuth2TokenRevocationClient(transport).revoke(
      _registration(
        method: ClientAuthenticationMethod.clientSecretBasic,
        secret: 's&1',
      ),
      OAuth2AccessToken(TokenType.bearer, 'at'),
    );
    final request = transport.lastRequest;
    expect(
      request.headers['Authorization'],
      'Basic ${base64Encode(utf8.encode('neon-app:s%261'))}',
    );
    expect(_form(request), {'token': 'at', 'token_type_hint': 'access_token'});
  });
}
