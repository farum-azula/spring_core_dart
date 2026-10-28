// The native apps' Keycloak login (the `sso` profile, not on the web):
// the realm's roles as Spring Security roles, the user's access token on
// the server calls.
import 'package:neon_books_app/src/account/sso_properties.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

@Configuration()
@Profile(['sso & !web'])
class KeycloakConfig {
  /// The roles of the user: Keycloak puts the realm roles into a `roles`
  /// claim (`["USER", "ADMIN"]`), which become `ROLE_USER` and
  /// `ROLE_ADMIN`, so `@PreAuthorize("hasRole('ADMIN')")` and
  /// `Session.isAdmin` work as with the form login. `OAuth2LoginService`
  /// uses this bean at every login and restore.
  @Bean()
  GrantedAuthoritiesMapper keycloakRoles() => const KeycloakRolesMapper();

  /// `Authorization: Bearer <access token>` on the Feign calls of a
  /// Keycloak user, refreshed before it expires.
  @Bean()
  KeycloakTokenInterceptor keycloakTokens(
    OAuth2AuthorizedClientManager manager,
    OAuth2AuthorizedClientService clients,
    SsoProperties sso,
  ) => KeycloakTokenInterceptor(
    OAuth2AccessTokenInterceptor(
      manager,
      clientRegistrationId: sso.registrationId,
      authorizedClientService: clients,
    ),
  );

  /// A 401 to a token that looked valid (revoked at Keycloak, the realm's
  /// keys changed) marks it expired, so the next call gets a fresh one.
  /// Everything else as Feign's default decoder does.
  @Bean()
  ErrorDecoder errorDecoder(KeycloakTokenInterceptor tokens) =>
      OAuth2AccessTokenErrorDecoder(const DefaultErrorDecoder(), tokens.tokens);
}

/// Adds `ROLE_<role>` for each entry of the `roles` claim of the user,
/// keeping the authorities it had (`OIDC_USER`, `SCOPE_profile`, ...).
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

/// The starter's [OAuth2AccessTokenInterceptor], while a Keycloak user is
/// logged in.
///
/// `spring.cloud.openfeign.oauth2.enabled=true` would put the starter's
/// interceptor on every call, and as in Spring Cloud OpenFeign it fails a
/// call made while nobody is logged in: right for an API that is all
/// private, wrong here, where the catalog and the live stock are public.
/// So this bean (every `RequestInterceptor` bean applies to all Feign
/// clients) asks it for the token only when the security context holds a
/// Keycloak login; anonymous calls go out as they are.
final class KeycloakTokenInterceptor implements RequestInterceptor {
  KeycloakTokenInterceptor(this.tokens);

  /// Gets the token (refreshing it when it expires within a minute).
  final OAuth2AccessTokenInterceptor tokens;

  @override
  Future<void> apply(RequestTemplate template) async {
    final user = SecurityContextHolder.getContext().authentication;
    if (user is OAuth2AuthenticationToken) {
      await tokens.apply(template);
    }
  }
}
