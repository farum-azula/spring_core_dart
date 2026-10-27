// A resource server: stateless, bearer JWTs from the test keys.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import 'jwt.spring.dart';
import 'keys.dart';

@ComponentScan()
final BeanModule jwtSecurityBeans = $jwtSecurityBeans;

@Configuration()
class JwtSecurityConfig {
  @Bean()
  SecurityFilterChain api(HttpSecurity http) => http
      .authorizeHttpRequests(
        (auth) => auth
            .requestMatchers('/public/**')
            .permitAll()
            .requestMatchers('/api/admin', '/api/admin/**')
            .hasAuthority('SCOPE_admin')
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

  @Bean()
  JwtDecoder jwtDecoder() => NimbusJwtDecoder.withJwkSource(
    StaticJwkSource([
      testKeys.rsa.verificationKey,
      testKeys.ec.verificationKey,
    ]),
  );
}
