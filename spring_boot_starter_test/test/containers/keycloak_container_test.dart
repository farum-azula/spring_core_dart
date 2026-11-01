// KeycloakContainer on the real daemon: a smoke test. Skipped without
// Docker (and a failure with CONTAINERS_REQUIRED=true).
@Tags(['docker'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_test/containers.dart';
import 'package:test/test.dart';

import 'support/docker_support.dart';

void main() {
  test(
    'imports the realm and publishes its issuer',
    () async {
      // From the package, wherever the tests are started.
      final lib = await Isolate.resolvePackageUri(
        Uri.parse('package:spring_boot_starter_test/containers.dart'),
      );
      final realm = File.fromUri(
        lib!.resolve('../../example/keycloak/neon-realm.json'),
      ).path;
      final keycloak = KeycloakContainer()..withRealmImport(realm);
      addTearDown(keycloak.stop);
      await keycloak.start();

      expect(keycloak.realm, 'neon');
      final issuer = keycloak.issuerUri;
      expect(
        issuer,
        'http://127.0.0.1:${keycloak.mappedPort(8080)}/realms/neon',
      );

      // The realm's discovery document names the same issuer.
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('$issuer/.well-known/openid-configuration'),
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      final discovery =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;
      expect(discovery['issuer'], issuer);

      // What @ServiceConnection hands to the application.
      expect(
        keycloak.connectionProperties,
        containsPair(
          'spring.security.oauth2.resourceserver.jwt.issuer-uri',
          issuer,
        ),
      );
      expect(
        keycloak.connectionProperties,
        containsPair(
          'spring.security.oauth2.client.provider.keycloak.issuer-uri',
          issuer,
        ),
      );
    },
    skip: dockerSkip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
