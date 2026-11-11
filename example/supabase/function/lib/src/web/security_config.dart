import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

@Configuration()
class SecurityConfig {
  /// The bearer tokens are the project's access tokens: the keys, the
  /// issuer, the audience and the roles are the Supabase starter's
  /// defaults. No sessions: a function keeps nothing between requests.
  @Bean()
  SecurityFilterChain apiChain(HttpSecurity http) => http
      .authorizeHttpRequests(
        (auth) => auth
            .requestMatchers('/health')
            .permitAll()
            .anyRequest()
            .authenticated(),
      )
      .sessionManagement(
        (session) =>
            session.sessionCreationPolicy(SessionCreationPolicy.stateless),
      )
      .csrf((csrf) => csrf.disable())
      .oauth2ResourceServer((server) => server.jwt())
      .build();
}
