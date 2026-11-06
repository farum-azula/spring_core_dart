import 'package:spring_boot_starter_actuator/spring_boot_starter_actuator.dart';

/// A REST controller, listed by the mappings endpoint.
@RestController()
@RequestMapping('/api/books')
class BookController {
  @GetMapping.of(path: '/{isbn}', produces: MediaType.applicationJson)
  Map<String, Object?> find(@PathVariable() String isbn) => {'isbn': isbn};

  @PostMapping.of(consumes: MediaType.applicationJson, headers: ['X-Api=2'])
  Map<String, Object?> add(@RequestBody() Map<String, Object?> book) => book;
}

/// What the tests switch: the state of the inbox indicator.
@Component()
class InboxState {
  Status status = Status.up;
  int pending = 3;
  Exception? failure;
}

/// A health indicator of the application: `inbox` in the report.
@Component()
class InboxHealthIndicator extends HealthIndicator {
  InboxHealthIndicator(this.state);

  final InboxState state;

  @override
  Future<Health> health() async {
    if (state.failure case final failure?) {
      throw failure;
    }
    return Health.withStatus(
      state.status,
    ).withDetail('pending', state.pending).build();
  }
}

/// An endpoint of the application: `/actuator/features`.
@Endpoint(id: 'features')
class FeaturesEndpoint {
  final flags = <String, bool>{'dark-mode': true, 'beta': false};

  @ReadOperation()
  Map<String, bool> features() => flags;

  @ReadOperation()
  Map<String, Object?>? feature(@Selector() String name) =>
      flags.containsKey(name) ? {'name': name, 'enabled': flags[name]} : null;
}

/// An endpoint with query parameters: `/actuator/echo?text=...&times=2`.
@Endpoint(id: 'echo', enableByDefault: false)
class EchoEndpoint {
  @ReadOperation()
  Map<String, Object?> echo(String text, {int times = 1, String? suffix}) => {
    'text': List.filled(times, text).join(),
    'suffix': suffix,
  };
}

/// An endpoint that answers what the request's user is.
@Endpoint(id: 'whoami')
class WhoAmIEndpoint {
  @ReadOperation()
  Map<String, Object?> whoami(SecurityContext user) => {
    'name': user.principal?.name,
    'admin': user.isUserInRole('ADMIN'),
  };
}
