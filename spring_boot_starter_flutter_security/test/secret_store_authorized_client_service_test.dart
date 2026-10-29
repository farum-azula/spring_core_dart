// The app's authorized client service: each client as JSON in the
// SecretStore, under a key of its registration and principal; what does
// not belong to the key, or does not read, is removed.
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
