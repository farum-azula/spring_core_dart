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
  /// The logged-in user, as the UserDetailsService gave it.
  @GetMapping()
  Me me(@AuthenticationPrincipal() UserDetails user) => Me(
    name: user.username,
    roles: [
      for (final authority in user.authorities)
        if (authority.authority case final name? when name.startsWith('ROLE_'))
          name.substring('ROLE_'.length),
    ]..sort(),
  );
}
