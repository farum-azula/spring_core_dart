// A WebSocket endpoint behind the security chain: the handshake is an HTTP
// request like any other, so the rules decide whether it is upgraded.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

import 'socket.spring.dart';

@ComponentScan()
final BeanModule socketSecurityBeans = $socketSecurityBeans;

@WebSocketEndpoint('/ws/whoami')
class WhoAmIEndpoint {
  /// The user of the handshake, and the context the message runs in.
  @OnMessage()
  String whoAmI(String text, Principal? user) =>
      '${user?.name} / '
      '${SecurityContextHolder.getContext().authentication?.name}';
}

@Configuration()
class SocketSecurityConfig {
  @Bean()
  SecurityFilterChain filterChain(HttpSecurity http) => http
      .authorizeHttpRequests(
        (auth) => auth
            .requestMatchers('/ws/whoami')
            .hasRole('USER')
            .anyRequest()
            .authenticated(),
      )
      .httpBasic()
      .build();

  @Bean()
  UserDetailsService users() => InMemoryUserDetailsManager([
    User.withUsername('ada').password('{noop}ada-pw').roles(['USER']).build(),
    User.withUsername('bob').password('{noop}bob-pw').roles(['GUEST']).build(),
  ]);
}
