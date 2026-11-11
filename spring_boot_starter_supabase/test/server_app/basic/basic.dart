// A server with a login of its own beside the project's tokens: HTTP
// Basic for the users it declares, bearer tokens for those of Supabase.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import '../../spring_gen/server_app/basic/basic.spring.dart';

@ComponentScan()
final BeanModule basicLoginBeans = $basicLoginBeans;

@Configuration()
class BasicLoginConfig {
  @Bean()
  SecurityFilterChain filterChain(HttpSecurity http) => http
      .authorizeHttpRequests((auth) => auth.anyRequest().authenticated())
      .sessionManagement(
        (session) =>
            session.sessionCreationPolicy(SessionCreationPolicy.stateless),
      )
      .csrf((csrf) => csrf.disable())
      .httpBasic()
      .oauth2ResourceServer((server) => server.jwt())
      .build();

  @Bean()
  UserDetailsService users() => InMemoryUserDetailsManager([
    User.withUsername('ada').password('{noop}ada-pw-51c9').roles([
      'USER',
    ]).build(),
  ]);
}
