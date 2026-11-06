// The security configuration of the security tests: the endpoints get a
// chain of their own, matched with EndpointRequest.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import '../spring_gen/secured/secured_app.spring.dart';

@ComponentScan()
final BeanModule securedTestBeans = $securedTestBeans;

@Configuration()
class ActuatorSecurity {
  /// The endpoints: health, info and the links for everybody, the others
  /// for administrators.
  @Bean()
  @Order(1)
  SecurityFilterChain actuator(HttpSecurity http) => http
      .securityMatcherOf(EndpointRequest.toAnyEndpoint())
      .authorizeHttpRequests(
        (auth) => auth
            .requestMatchersOf([
              EndpointRequest.to(['health', 'info']),
              EndpointRequest.toLinks(),
            ])
            .permitAll()
            .anyRequest()
            .hasRole('ADMIN'),
      )
      .httpBasic()
      .sessionManagement(
        (session) =>
            session.sessionCreationPolicy(SessionCreationPolicy.stateless),
      )
      .csrf((csrf) => csrf.disable())
      .build();

  /// Everything else: any logged-in user.
  @Bean()
  @Order(2)
  SecurityFilterChain rest(HttpSecurity http) => http
      .authorizeHttpRequests((auth) => auth.anyRequest().authenticated())
      .httpBasic()
      .sessionManagement(
        (session) =>
            session.sessionCreationPolicy(SessionCreationPolicy.stateless),
      )
      .csrf((csrf) => csrf.disable())
      .build();

  @Bean()
  UserDetailsService users() => InMemoryUserDetailsManager([
    User.withUsername('ada').password('{noop}ada').roles(['USER']).build(),
    User.withUsername('root').password('{noop}root').roles(['ADMIN']).build(),
  ]);
}
