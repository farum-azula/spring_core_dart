// A security configuration with rules, users and both logins.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import 'rules.spring.dart';

@ComponentScan()
final BeanModule rulesSecurityBeans = $rulesSecurityBeans;

@Configuration()
class RulesSecurityConfig {
  @Bean()
  SecurityFilterChain filterChain(HttpSecurity http) => http
      .authorizeHttpRequests(
        (auth) => auth
            .requestMatchers('/public/**', '/form')
            .permitAll()
            .requestMatchers('/api/admin', '/api/admin/**')
            .hasRole('ADMIN')
            .requestMatchersFor(HttpMethod.get, ['/api/reports/**'])
            .authenticated()
            .requestMatchers('/api/users/{id}')
            .access(const SelfOrAdmin())
            .anyRequest()
            .authenticated(),
      )
      .formLogin()
      .httpBasic()
      .build();

  @Bean()
  UserDetailsService users() => InMemoryUserDetailsManager([
    User.withUsername('ada').password('{noop}ada-pw').roles(['USER']).build(),
    User.withUsername('root')
        .password('{noop}root-pw')
        .roles(['ADMIN'])
        .build(),
  ]);

  @Bean()
  CorsConfigurationSource corsConfigurationSource() =>
      UrlBasedCorsConfigurationSource()..registerCorsConfiguration(
        '/api/**',
        CorsConfiguration(
          allowedOrigins: ['https://trusted.example'],
          allowedMethods: ['GET', 'POST'],
          allowCredentials: true,
        ),
      );
}

/// `/api/users/{id}`: the user themself or an admin.
final class SelfOrAdmin
    implements AuthorizationManager<RequestAuthorizationContext> {
  const SelfOrAdmin();

  @override
  AuthorizationResult authorize(
    Authentication? Function() authentication,
    RequestAuthorizationContext context,
  ) {
    final user = authentication();
    final admin =
        user != null &&
        user.authorities.any((a) => a.authority == 'ROLE_ADMIN');
    return AuthorizationDecision(
      admin ||
          (user != null &&
              user is! AnonymousAuthenticationToken &&
              user.name == context.variables['id']),
    );
  }
}
