// Single sign-on with Keycloak (chapter 4, the `sso` profile): where the
// web app is, and Keycloak's realm roles as Spring Security roles.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

/// `neon.app.*`: the Flutter web app this server logs users in for.
@ConfigurationProperties('neon.app')
@Validated()
class AppProperties {
  /// Where the browser goes after a Keycloak login and logout: the
  /// Flutter web app (`flutter run -d chrome --web-port 5050`). Only this
  /// setting decides it, never a request parameter (no open redirect);
  /// Keycloak must allow it as a post-logout redirect.
  @Matches(r'^https?://.+/$', message: 'must be an http(s) URL ending in /')
  String webUrl = 'http://localhost:5050/';
}

@Configuration()
@Profile(['sso'])
class SsoConfig {
  /// The roles of a Keycloak login (`oauth2Login()`, Flutter web): the
  /// realm puts the user's realm roles into a top-level `roles` claim of
  /// the ID token and the user info (`["USER", "ADMIN"]`), which become
  /// `ROLE_USER` and `ROLE_ADMIN` here, so `hasRole('ADMIN')` and
  /// `@PreAuthorize` work as with the form login. Bearer tokens of the
  /// native apps get theirs from the same claim through the properties
  /// (`authorities-claim-name=roles`, `authority-prefix=ROLE_`).
  @Bean()
  GrantedAuthoritiesMapper keycloakRoles() => const KeycloakRolesMapper();
}

/// Adds `ROLE_<role>` for each entry of the `roles` claim of an OpenID
/// Connect or OAuth 2.0 user, keeping the authorities it had (`OIDC_USER`,
/// `SCOPE_profile`, ...).
final class KeycloakRolesMapper implements GrantedAuthoritiesMapper {
  const KeycloakRolesMapper();

  @override
  List<GrantedAuthority> mapAuthorities(
    Iterable<GrantedAuthority> authorities,
  ) => [
    ...authorities,
    for (final authority in authorities)
      if (authority is OAuth2UserAuthority)
        if (authority.attributes['roles'] case final List<Object?> roles)
          for (final role in roles)
            if (role is String && role.isNotEmpty)
              SimpleGrantedAuthority('ROLE_$role'),
  ];
}
