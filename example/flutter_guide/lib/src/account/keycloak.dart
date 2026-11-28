// The native apps' Keycloak login (the `sso` profile, not on the web):
// the realm's roles as Spring Security roles, the user's access token on
// the server calls.
import 'package:neon_books_app/src/account/sso_properties.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

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

  /// `Authorization: Bearer <access token>` on the calls of a Keycloak
  /// user to the server (the `server` group of HTTP services), refreshed
  /// before it expires; when Keycloak binds the token to the app's key
  /// (DPoP), `Authorization: DPoP <access token>` and a proof per call,
  /// signed by the [DPoPKey] bean. A 401 to a token that looked valid
  /// (revoked at Keycloak, the realm's keys changed) marks it expired, so
  /// the next call gets a fresh one.
  @Bean()
  RestClientHttpServiceGroupConfigurer keycloakTokens(
    OAuth2AuthorizedClientManager manager,
    OAuth2AuthorizedClientService clients,
    SsoProperties sso,
    DPoPKey? dPoPKey,
  ) {
    final tokens = KeycloakTokenInterceptor(
      OAuth2ClientHttpRequestInterceptor(
        manager,
        defaultClientRegistrationId: sso.registrationId,
        authorizedClientService: clients,
        dPoPKey: dPoPKey,
      ),
    );
    return RestClientHttpServiceGroupConfigurer.of(
      (groups) => groups
          .filterByName(['server'])
          .forEachClient(
            (group, builder) => builder.requestInterceptor(tokens),
          ),
    );
  }
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

/// The starter's [OAuth2ClientHttpRequestInterceptor], while a Keycloak
/// user is logged in.
///
/// With `spring.security.oauth2.client.restclient.client-registration-id`
/// the starter's own interceptor would send the token on every call, and
/// as in Spring Security it fails a call made while nobody is logged in:
/// right for an API that is all private, wrong here, where the catalog and
/// the live stock are public. So this interceptor, on the `server` group
/// only, asks it for the token only when the security context holds a
/// Keycloak login; anonymous calls go out as they are.
final class KeycloakTokenInterceptor implements ClientHttpRequestInterceptor {
  KeycloakTokenInterceptor(this.tokens);

  /// Gets the token (refreshing it when it expires within a minute).
  final OAuth2ClientHttpRequestInterceptor tokens;

  @override
  Future<HttpResponse> intercept(
    HttpRequest request,
    List<int>? body,
    ClientHttpRequestExecution execution,
  ) {
    final user = SecurityContextHolder.getContext().authentication;
    if (user is OAuth2AuthenticationToken) {
      return tokens.intercept(request, body, execution);
    }
    return execution.execute(request, body);
  }
}
