import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

/// Who may call what: every request of `/api/` needs a bearer token of
/// the project. How a token is checked is not written here: the Supabase
/// starter gives the resource server its settings
/// (`spring.security.oauth2.resourceserver.jwt.*`: the project's keys,
/// issuer, audience and where the roles are).
@Configuration()
class SecurityConfig {
  @Bean()
  SecurityFilterChain apiChain(HttpSecurity http) => http
      .authorizeHttpRequests(
        (auth) => auth
            .requestMatchers('/api/**')
            .authenticated()
            .anyRequest()
            .denyAll(),
      )
      // A token with every request: no session, so no CSRF token either.
      .sessionManagement(
        (session) =>
            session.sessionCreationPolicy(SessionCreationPolicy.stateless),
      )
      .csrf((csrf) => csrf.disable())
      .oauth2ResourceServer((server) => server.jwt())
      .build();
}
