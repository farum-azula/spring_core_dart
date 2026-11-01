import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_test/src/containers/generic_container.dart';
import 'package:spring_boot_starter_test/src/containers/wait.dart';

/// Keycloak in a container in development mode, with an admin user and
/// optionally a realm imported from a JSON export, ready for the security
/// tests: the issuer URI of the realm is what an application's
/// `@ServiceConnection()` receives.
///
/// As a `@ServiceConnection()` it sets
/// `spring.security.oauth2.resourceserver.jwt.issuer-uri` (a resource
/// server validating Keycloak's tokens) and
/// `spring.security.oauth2.client.provider.<id>.issuer-uri` (a client
/// logging in through it; [withProviderId] names the provider, `keycloak`
/// by default), both `http://host:port/realms/<realm>`. The realm is the
/// one of the imported file, else `master`.
///
/// ```dart
/// @Container()
/// @ServiceConnection()
/// static final keycloak = KeycloakContainer('quay.io/keycloak/keycloak:26.8')
///     .withRealmImport('../example/keycloak/neon-realm.json');
/// ```
///
/// Testcontainers (Java): `KeycloakContainer` of the community module
/// `dasniko/testcontainers-keycloak` (`withRealmImportFile`,
/// `getAuthServerUrl()`).
class KeycloakContainer extends GenericContainer
    implements ServiceConnectionProperties {
  /// Keycloak from [image] (`quay.io/keycloak/keycloak:26.8` unless given),
  /// started with `start-dev`, with the admin user `admin`/`admin`.
  KeycloakContainer([super.image = 'quay.io/keycloak/keycloak:26.8']) {
    withAdminCredentials('admin', 'admin');
    withCommand(['start-dev']);
    withExposedPorts([port]);
    withStartupTimeout(const Duration(minutes: 3));
    _waitForRealm();
  }

  /// Keycloak's HTTP port in the container.
  static const port = 8080;

  /// The imported realm, or `master`.
  String get realm => _realm;
  String _realm = 'master';

  /// The admin user.
  String get adminUsername => _adminUsername;
  String _adminUsername = 'admin';

  /// The admin user's password.
  String get adminPassword => _adminPassword;
  String _adminPassword = 'admin';

  String _providerId = 'keycloak';

  /// Sets the admin user created at the first start
  /// (`KC_BOOTSTRAP_ADMIN_USERNAME`, `KC_BOOTSTRAP_ADMIN_PASSWORD`).
  KeycloakContainer withAdminCredentials(String username, String password) {
    _adminUsername = username;
    _adminPassword = password;
    withEnv('KC_BOOTSTRAP_ADMIN_USERNAME', username);
    withEnv('KC_BOOTSTRAP_ADMIN_PASSWORD', password);
    return this;
  }

  /// Imports the realm exported to the JSON file at [hostPath] when
  /// Keycloak starts (`--import-realm`); the container is ready when that
  /// realm answers, and [realm] is its name.
  ///
  /// The file is read now, for the realm's name. A relative path starts at
  /// the working directory (the package, under `dart test`).
  KeycloakContainer withRealmImport(String hostPath) {
    final file = File(hostPath);
    if (!file.existsSync()) {
      throw ArgumentError.value(
        hostPath,
        'hostPath',
        'withRealmImport: no such file (a relative path starts at '
            '${Directory.current.path})',
      );
    }
    final name = (jsonDecode(file.readAsStringSync()) as Map)['realm'];
    if (name is! String || name.isEmpty) {
      throw ArgumentError.value(
        hostPath,
        'hostPath',
        'withRealmImport: the file has no "realm" name',
      );
    }
    _realm = name;
    withCopyFile(
      hostPath,
      '/opt/keycloak/data/import/${hostPath.split(RegExp(r'[/\\]')).last}',
    );
    withCommand(['start-dev', '--import-realm']);
    _waitForRealm();
    return this;
  }

  /// Names the OAuth2 client provider that `connectionProperties` sets the
  /// issuer URI of (`spring.security.oauth2.client.provider.<id>`).
  KeycloakContainer withProviderId(String id) {
    _providerId = id;
    return this;
  }

  void _waitForRealm() => waitingFor(
    Wait.forHttp('/realms/$_realm').forPort(port).forStatusCode(200),
  );

  /// The server's address, `http://host:port`.
  String get authServerUrl => baseUrl(port);

  /// The realm's issuer URI, `http://host:port/realms/<realm>`: the `iss`
  /// of its tokens.
  String get issuerUri => '$authServerUrl/realms/$_realm';

  @override
  Map<String, String> get connectionProperties => {
    'spring.security.oauth2.resourceserver.jwt.issuer-uri': issuerUri,
    'spring.security.oauth2.client.provider.$_providerId.issuer-uri': issuerUri,
  };

  @override
  String toString() => 'KeycloakContainer($image)';
}
