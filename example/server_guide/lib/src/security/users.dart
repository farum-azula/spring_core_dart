// The shop's users, from configuration: `neon.security.users.<name>.*`
// (a map, so the prod environment can replace one password:
// NEON_SECURITY_USERS_ROOT_PASSWORD='{argon2}...').
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

class UserEntry {
  /// A hash with its encoder id (`{argon2}...`), never the password: a
  /// plain password stops the start.
  @Matches(r'^\{[a-z0-9]+\}.+$', message: 'must be a hash with its {id}')
  String password = '';

  /// Roles without the `ROLE_` prefix (`USER`, `ADMIN`).
  @NotEmpty()
  List<String> roles = [];
}

/// `@Validated` with `@Valid()`: the constraints of every entry of the
/// map are checked too (a cascade).
@ConfigurationProperties('neon.security')
@Validated()
class UsersProperties {
  @Valid()
  Map<String, UserEntry> users = {};
}

@Configuration()
class UsersConfig {
  /// The encoder logins are checked with: Spring's delegating encoder,
  /// reading the `{id}` prefix of each hash (`{argon2}`, `{pbkdf2}`,
  /// `{scrypt}`) and hashing new passwords with Argon2.
  @Bean()
  PasswordEncoder passwordEncoder() =>
      PasswordEncoderFactories.createDelegatingPasswordEncoder();

  /// With this bean (and the encoder) the starter builds the
  /// AuthenticationManager the form login uses.
  @Bean()
  UserDetailsService userDetailsService(UsersProperties properties) =>
      InMemoryUserDetailsManager([
        for (final MapEntry(key: name, value: user) in properties.users.entries)
          User.withUsername(name)
              .password(user.password)
              .roles(user.roles)
              .build(),
      ]);
}
