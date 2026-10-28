import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

/// `GET /api/me`: `{"name": "root", "roles": ["ADMIN", "USER"]}`.
@Introspected()
class Me {
  const Me({required this.name, required this.roles});

  final String name;

  /// Without the `ROLE_` prefix.
  final List<String> roles;
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
  Me me(Authentication authentication) => Me(
    name: authentication.name,
    roles: [
      for (final authority in authentication.authorities)
        if (authority.authority case final name? when name.startsWith('ROLE_'))
          name.substring('ROLE_'.length),
    ]..sort(),
  );
}
