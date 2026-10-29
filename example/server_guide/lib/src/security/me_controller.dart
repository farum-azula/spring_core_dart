import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

/// `GET /api/me`: who holds the session or token, as
/// `{"name": "root", "roles": ["ADMIN", "USER"], "authorities": [...],
/// "registrationId": "keycloak"}`.
///
/// The Flutter web app asks it at startup (its starter's user endpoint,
/// `spring.flutter.security.web.user-endpoint=/api/me`): `name` and
/// `authorities` become the user of the app, `registrationId` (only after
/// a Keycloak login of the browser) makes it an OAuth 2.0 login there.
/// The native apps read `name` and `roles`.
@Introspected()
class Me {
  const Me({
    required this.name,
    required this.roles,
    required this.authorities,
    this.registrationId,
  });

  final String name;

  /// Without the `ROLE_` prefix.
  final List<String> roles;

  /// Every authority, as Spring Security names it (`ROLE_USER`,
  /// `OIDC_USER`, `SCOPE_email`).
  final List<String> authorities;

  /// The registration of a Keycloak login of the browser
  /// (`oauth2Login()`), else `null`.
  final String? registrationId;
}

@RestController()
@RequestMapping('/api/me')
class MeController {
  /// The logged-in user. An `Authentication` parameter, whatever the
  /// login was: a form login (`UserDetails` of the UserDetailsService), a
  /// Keycloak login of the browser (an `OidcUser`, named by
  /// `preferred_username`), or a native app's bearer token (a `Jwt`, named
  /// by the same claim); each has a name and authorities.
  @GetMapping()
  Me me(Authentication authentication) {
    final authorities = [
      for (final authority in authentication.authorities) ?authority.authority,
    ]..sort();
    return Me(
      name: authentication.name,
      roles: [
        for (final name in authorities)
          if (name.startsWith('ROLE_')) name.substring('ROLE_'.length),
      ],
      authorities: authorities,
      registrationId: authentication is OAuth2AuthenticationToken
          ? authentication.authorizedClientRegistrationId
          : null,
    );
  }
}
