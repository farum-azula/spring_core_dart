// Spring Boot Actuator in a Spring Boot application: add the starter and
// /actuator/health answers; a HealthIndicator bean is part of it, an
// @Endpoint bean is an endpoint of its own. The generator registers them
// (example.spring.dart, from `dart run build_runner build`). With the
// security starter, EndpointRequest gives the endpoints a chain of their
// own: health and info for everybody, the others for administrators.
//
//   dart run example/example.dart
//   curl localhost:8086/actuator/health
//   curl localhost:8086/actuator/health/readiness
//   curl localhost:8086/actuator/info
//   curl localhost:8086/actuator
//   curl -u admin:<the password in the log> localhost:8086/actuator/orders
import 'package:spring_boot_starter_actuator/spring_boot_starter_actuator.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import 'spring_gen/example.spring.dart';

/// The orders waiting to be shipped.
@Service()
class Orders {
  final pending = <String>['A-1', 'A-2'];
}

/// The orders in the health report: `DOWN` when too many are waiting.
/// In the report as `orders` (the bean name without `HealthIndicator`).
@Component()
class OrdersHealthIndicator extends HealthIndicator {
  OrdersHealthIndicator(this.orders);

  final Orders orders;

  @override
  Health health() => (orders.pending.length < 100 ? Health.up() : Health.down())
      .withDetail('pending', orders.pending.length)
      .build();
}

/// An endpoint of the application: `GET /actuator/orders` and
/// `GET /actuator/orders/{id}`.
@Endpoint(id: 'orders')
class OrdersEndpoint {
  OrdersEndpoint(this.orders);

  final Orders orders;

  @ReadOperation()
  Map<String, Object?> summary() => {'pending': orders.pending};

  @ReadOperation()
  Map<String, Object?>? order(@Selector() String id) =>
      orders.pending.contains(id) ? {'id': id, 'state': 'pending'} : null;
}

/// The version the build would write into build-info.properties.
@Component()
class ExampleInfoContributor implements InfoContributor {
  @override
  void contribute(InfoBuilder builder) =>
      builder.withDetail('example', {'name': 'orders', 'version': '1.0.0'});
}

@RestController()
class OrderController {
  OrderController(this.orders);

  final Orders orders;

  @GetMapping('/api/orders')
  List<String> all() => orders.pending;
}

@Configuration()
class ActuatorSecurity {
  /// The endpoints' own chain: health, info and the links for everybody,
  /// the others for the role ADMIN (`spring.security.user.*`).
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
      .build();
}

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
