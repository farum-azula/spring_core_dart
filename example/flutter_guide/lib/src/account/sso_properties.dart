import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// `neon.sso.*`: single sign-on with Keycloak (the `sso` profile).
@ConfigurationProperties('neon.sso')
class SsoProperties {
  /// Whether the Login screen offers "Sign in with Keycloak" instead of
  /// the name and password form; `true` with the `sso` profile.
  bool enabled = false;

  /// The registration of the native apps
  /// (`spring.security.oauth2.client.registration.keycloak.*`), and the
  /// one the server's `/oauth2/authorization/{id}` logs the web app in
  /// with.
  String registrationId = 'keycloak';

  /// Where Keycloak sends the login window after a native app's logout
  /// ended the Keycloak session; Keycloak must allow it.
  String? postLogoutRedirectUri;
}
