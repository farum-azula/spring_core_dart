// The app's authorized client service: each client as JSON in the
// SecretStore, under a key of its registration and principal; what does
// not belong to the key, or does not read, is removed.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

import 'support/fake_provider.dart';

void main() {
  late LoginFixture fixture;

  setUp(() async {
    fixture = await LoginFixture.create();
  });

  group('SecretStoreOAuth2AuthorizedClientService', () {
    test('a JSON entry per registration and principal', () async {
      await fixture.service().login('keycloak');
      final key = SecretStoreOAuth2AuthorizedClientService.keyOf(
        'keycloak',
        'user-1',
      );
      expect(key, 'oauth2.authorized-client.keycloak.user-1');
      expect(await fixture.store.read(key), contains('"version":1'));
      expect(
        SecretStoreOAuth2AuthorizedClientService.keyOf('a.b', 'x y/z'),
        'oauth2.authorized-client.a%2Eb.x%20y%2Fz',
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
        SecretStoreOAuth2AuthorizedClientService.keyOf('keycloak', 'user-1'),
      );
      final other = SecretStoreOAuth2AuthorizedClientService.keyOf(
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

    test('two clients never share a key (a.b + c, a + b.c)', () async {
      expect(
        SecretStoreOAuth2AuthorizedClientService.keyOf('a.b', 'c'),
        isNot(SecretStoreOAuth2AuthorizedClientService.keyOf('a', 'b.c')),
      );
      final repository = InMemoryClientRegistrationRepository([
        _registration('a.b'),
        _registration('a'),
      ]);
      final store = InMemorySecretStore();
      final clients = SecretStoreOAuth2AuthorizedClientService(
        store,
        repository,
      );
      for (final (id, name) in [('a.b', 'c'), ('a', 'b.c')]) {
        await clients.saveAuthorizedClient(
          OAuth2AuthorizedClient(
            (await repository.findByRegistrationId(id))!,
            name,
            OAuth2AccessToken(TokenType.bearer, 'token of $id $name'),
          ),
          _Principal(name),
        );
      }
      expect(
        (await clients.loadAuthorizedClient(
          'a.b',
          'c',
        ))!.accessToken.tokenValue,
        'token of a.b c',
      );
      expect(
        (await clients.loadAuthorizedClient(
          'a',
          'b.c',
        ))!.accessToken.tokenValue,
        'token of a b.c',
      );
      await clients.removeAuthorizedClient('a', 'b.c');
      expect(await clients.loadAuthorizedClient('a', 'b.c'), isNull);
      expect(await clients.loadAuthorizedClient('a.b', 'c'), isNotNull);
    });

    test('a client stored by 0.4.x is read and moved to the new key', () async {
      await fixture.service().login('keycloak');
      final current = SecretStoreOAuth2AuthorizedClientService.keyOf(
        'keycloak',
        'user-1',
      );
      final stored = (await fixture.store.read(current))!;
      // As 0.4.x stored the client of ada@example.com: the dots kept.
      final record = (jsonDecode(stored) as Map<String, Object?>)
        ..['principalName'] = 'ada@example.com';
      const legacy = 'oauth2.authorized-client.keycloak.ada%40example.com';
      await fixture.store.delete(current);
      await fixture.store.write(legacy, jsonEncode(record));

      final client = await fixture.clients.loadAuthorizedClient(
        'keycloak',
        'ada@example.com',
      );
      expect(client!.principalName, 'ada@example.com');
      expect(await fixture.store.read(legacy), isNull);
      expect(
        await fixture.store.read(
          SecretStoreOAuth2AuthorizedClientService.keyOf(
            'keycloak',
            'ada@example.com',
          ),
        ),
        isNotNull,
      );

      // Removed under both keys.
      await fixture.store.write(legacy, jsonEncode(record));
      await fixture.clients.removeAuthorizedClient(
        'keycloak',
        'ada@example.com',
      );
      expect(await fixture.store.keys(), isNot(contains(legacy)));
      expect(
        await fixture.clients.loadAuthorizedClient(
          'keycloak',
          'ada@example.com',
        ),
        isNull,
      );
    });

    test("an 0.4.x key of another client is not taken or removed", () async {
      // 0.4.x stored (a.b, c) under the key (a, b.c) also had.
      final repository = InMemoryClientRegistrationRepository([
        _registration('a.b'),
        _registration('a'),
      ]);
      final store = InMemorySecretStore();
      const legacy = 'oauth2.authorized-client.a.b.c';
      await store.write(
        legacy,
        jsonEncode({
          'version': 1,
          'registrationId': 'a.b',
          'principalName': 'c',
          'accessToken': {'value': 't', 'scopes': <String>[]},
        }),
      );
      final clients = SecretStoreOAuth2AuthorizedClientService(
        store,
        repository,
      );
      expect(await clients.loadAuthorizedClient('a', 'b.c'), isNull);
      await clients.removeAuthorizedClient('a', 'b.c');
      expect(await store.read(legacy), isNotNull);
      expect(
        (await clients.loadAuthorizedClient(
          'a.b',
          'c',
        ))!.accessToken.tokenValue,
        't',
      );
    });

    test('a damaged entry is removed', () async {
      final key = SecretStoreOAuth2AuthorizedClientService.keyOf(
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
}

ClientRegistration _registration(String id) =>
    ClientRegistration.withRegistrationId(id)
        .clientId('app')
        .authorizationGrantType(AuthorizationGrantType.authorizationCode)
        .redirectUri('neonbooks:/oauth2/callback')
        .authorizationUri('https://sso.test/auth')
        .tokenUri('https://sso.test/token')
        .build();

final class _Principal extends AbstractAuthenticationToken {
  _Principal(this._name) : super(const []);
  final String _name;

  @override
  String get name => _name;

  @override
  Object? get credentials => null;

  @override
  Object? get principal => _name;
}
