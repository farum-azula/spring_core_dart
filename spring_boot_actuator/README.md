# spring_boot_actuator

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org](https://farum-azula.org/components)

Spring Boot Actuator's endpoints for Dart, without HTTP: the health
report, the info and the mappings of a running application, with Spring
Boot's names, properties and JSON.

Applications do not list this package: they list
[`spring_boot_starter_actuator`](https://pub.dev/packages/spring_boot_starter_actuator),
which brings it, declares the endpoints as beans and answers them under
`/actuator`. Its README describes the endpoints, their properties and the
differences from Spring Boot. This package is what they are made of, and
what a library builds on to contribute to them without the web starter:
the data starter's `db` indicator and the security starter's
`EndpointRequest` depend on it alone.

It is the Dart counterpart of `spring-boot-actuator` (Spring Boot 4's
`spring-boot-health` for the health model).

## What it contains

- **Endpoints:** `@Endpoint`, `@ReadOperation`, `@Selector`,
  `@EndpointWebExtension`, the `EndpointDiscoverer` that finds them in the
  bean definitions the generator writes (no reflection),
  `WebEndpointResponse`, `SecurityContext`, `EndpointId`, and the rules of
  `management.endpoint.<id>.enabled` / `.access` and
  `management.endpoints.web.exposure.*` (`isEndpointEnabled`,
  `IncludeExcludeEndpointFilter`).
- **Health:** `HealthIndicator`, `AbstractHealthIndicator`,
  `CompositeHealthContributor`, `HealthContributorRegistry`, `Health` and
  its builder, `Status`, `SimpleStatusAggregator`,
  `SimpleHttpCodeStatusMapper`, the groups (`HealthEndpointGroup`,
  `Show`), `HealthEndpoint` and `HealthEndpointWebExtension`; the
  indicators `ping`, `diskSpace`, `livenessState` and `readinessState`;
  `ConditionalOnEnabledHealthIndicator`.
- **Info:** `InfoContributor`, `InfoEndpoint`, `BuildProperties`,
  `GitProperties`, and the `build`, `git`, `env`, `os` and `dart`
  contributors; `ConditionalOnEnabledInfoContributor`.
- **Mappings:** `MappingsEndpoint` over every `MappingDescriptions` bean.
- **Properties:** the typed `management.endpoint.health.*`,
  `management.health.*`, `management.info.*`, `management.endpoints.*`
  and `spring.info.*` classes, for the editor and the starter.

## A health indicator of a library

```dart
import 'package:spring_boot_actuator/spring_boot_actuator.dart';

/// The health of the queue client, `DOWN` when the broker is gone.
class QueueHealthIndicator extends AbstractHealthIndicator {
  QueueHealthIndicator(this.client);
  final QueueClient client;

  @override
  Future<void> doHealthCheck(HealthBuilder builder) async {
    builder.up().withDetail('broker', client.broker);
    if (!await client.ping()) {
      builder.down();
    }
  }
}

// In the library's auto-configuration, switched by
// management.health.queue.enabled:
BeanDefinition<QueueHealthIndicator>(
  name: 'queueHealthIndicator',
  conditions: const [ConditionalOnEnabledHealthIndicator('queue')],
  create: (r) => QueueHealthIndicator(r.dependency<QueueClient>()),
)
```

## Without a server

The endpoints are plain objects, so code can ask them directly
([`example/`](example/)):

```dart
final health = HealthEndpoint(registry, groups);
final report = await health.health();
print(jsonEncode(report?.toJson())); // {"status":"UP","components":{...}}
```

## Differences from Spring Boot

See the
[actuator starter's README](https://pub.dev/packages/spring_boot_starter_actuator#differences-from-spring-boot).
