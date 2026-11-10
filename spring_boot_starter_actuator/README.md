# spring_boot_starter_actuator

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-boot-actuator](https://farum-azula.org/components/spring-boot-actuator)

Spring Boot Actuator for
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) servers:
what a running application tells about itself (whether it works, which
version it is, which addresses it answers) under `/actuator`, with Spring
Boot's paths, properties and JSON.

A load balancer asks `/actuator/health` whether to send requests;
Kubernetes asks `/actuator/health/liveness` and `/readiness`; an operator
asks `/actuator/info` which build runs. Without this starter each
application writes its own controller for that, in its own shape. With
it, adding the dependency is enough, and the answers are those every
Spring tool already reads.

It is the Dart counterpart of `spring-boot-starter-actuator`. The
endpoints themselves are in
[`spring_boot_actuator`](https://pub.dev/packages/spring_boot_actuator)
(re-exported); this starter declares them as beans and answers them over
the web starter.

## Installation

```yaml
dependencies:
  spring_boot_starter_actuator: ^0.7.4

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.7.4   # required: finds the starter and your beans
```

```bash
dart run build_runner build
```

## Quick example

```dart
import 'package:spring_boot_starter_actuator/spring_boot_starter_actuator.dart';

import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
```

```console
$ curl -i localhost:8080/actuator/health
HTTP/1.1 200 OK
content-type: application/vnd.spring-boot.actuator.v3+json

{"status":"UP"}
```

The answer is `503` when the application is `DOWN` or `OUT_OF_SERVICE`.
Only `health` is exposed by default, as in Spring Boot; the others are
added with a property:

```properties
# lib/resources/application.properties
management.endpoints.web.exposure.include=health,info,mappings
management.endpoint.health.show-details=always
```

```console
$ curl localhost:8080/actuator/health
{"status":"UP","components":{"diskSpace":{"status":"UP","details":{"total":499963174912,"free":91300605952,"threshold":10485760,"path":"/srv/shop/.","exists":true}},"ping":{"status":"UP"}}}
```

## The endpoints

| Endpoint | Path | Shows |
|---|---|---|
| `health` | `/actuator/health`, `/actuator/health/{*path}` | the aggregated status, the components, the groups |
| `info` | `/actuator/info` | the build, git, `info.*` properties, the OS and Dart version |
| `mappings` | `/actuator/mappings` | the web server's handlers (Spring WebFlux's `dispatcherHandlers`) and, in an app with the navigation starter, its `screens` |
| the discovery page | `/actuator` | `_links` to every exposed endpoint |

An endpoint answers when it is **enabled** and **exposed**:

```properties
# Exposed over HTTP: ids, or * for all (default: health).
management.endpoints.web.exposure.include=*
management.endpoints.web.exposure.exclude=mappings
# Enabled: each endpoint, or all by default.
management.endpoint.info.enabled=false
management.endpoints.enabled-by-default=true
# Spring Boot 3.4's spelling is read too: none, read-only, unrestricted.
management.endpoint.mappings.access=none
# Where: the base path (/ for the root, without the discovery page) and
# another path for one endpoint.
management.endpoints.web.base-path=/manage
management.endpoints.web.path-mapping.health=healthcheck
management.endpoints.web.discovery.enabled=true
```

The answers are `application/vnd.spring-boot.actuator.v3+json`;
a client that asks for `application/json` gets it, one that asks for
`...v2+json` gets the version 2 JSON (the health's parts under
`details`), one that accepts neither a `406`. Another method than `GET`
and `HEAD` is a `405`.

### The discovery page

```json
{"_links": {
  "self": {"href": "http://localhost:8080/actuator", "templated": false},
  "health": {"href": "http://localhost:8080/actuator/health", "templated": false},
  "health-path": {"href": "http://localhost:8080/actuator/health/{*path}", "templated": true},
  "info": {"href": "http://localhost:8080/actuator/info", "templated": false}}}
```

## Health

Every `HealthIndicator` bean is part of the report, under its bean name
without `HealthIndicator` (`OrdersHealthIndicator` is `orders`):

```dart
@Component()
class OrdersHealthIndicator extends HealthIndicator {
  OrdersHealthIndicator(this.orders);
  final Orders orders;

  @override
  Future<Health> health() async => await orders.reachable()
      ? Health.up().withDetail('pending', await orders.pending()).build()
      : Health.down().build();
}
```

An indicator may answer later (a `Future`); one that throws is `DOWN` with
the error as detail. `AbstractHealthIndicator` does the same with a
builder. The starter adds:

| Indicator | What | Switched by |
|---|---|---|
| `ping` | always `UP` | `management.health.ping.enabled` |
| `diskSpace` | free space of `management.health.diskspace.path` (`.`) above `.threshold` (10 MB) | `management.health.diskspace.enabled` |
| `livenessState`, `readinessState` | the application's availability | the probes, or `management.health.livenessstate.enabled` |
| `db` | each data source of the data starter (`isValid()`) | `management.health.db.enabled` |

`management.health.defaults.enabled=false` switches off every indicator
whose own key is not set.

**Who sees what.** By default the report shows only the status.

```properties
# never (default), always, or when-authorized: a logged-in user, with one
# of the roles when roles are set (needs the security starter).
management.endpoint.health.show-details=when-authorized
management.endpoint.health.roles=ADMIN
# The components without their details (default: as show-details).
management.endpoint.health.show-components=always
```

**Aggregation and HTTP status**, as in Spring Boot:

```properties
management.endpoint.health.status.order=fatal,down,out-of-service,unknown,up
management.endpoint.health.status.http-mapping.fatal=500
```

**Groups** are parts of the report at their own path:

```properties
management.endpoint.health.group.core.include=ping,db
management.endpoint.health.group.core.show-details=always
management.endpoint.health.group.core.additional-path=server:/healthz
```

`/actuator/health/core` answers the group, `/actuator/health/db` one
component, `/actuator/health/db/reporting` a part of it. A group that
names a contributor that does not exist stops the start
(`management.endpoint.health.validate-group-membership=false` allows it).

### Kubernetes probes

```properties
management.endpoint.health.probes.enabled=true
management.endpoint.health.probes.add-additional-paths=true
```

They add the `liveness` and `readiness` groups (and `/livez`, `/readyz`),
from the application's `ApplicationAvailability`: `SpringApplication`
publishes `LivenessState.correct` after the start and
`ReadinessState.acceptingTraffic` once the runners are done; code
publishes an `AvailabilityChangeEvent` to change them:

```dart
AvailabilityChangeEvent.publish(context, ReadinessState.refusingTraffic);
```

On Kubernetes and Cloud Foundry the probes are on without the property.

## Info

```properties
management.endpoints.web.exposure.include=health,info
```

| Contributor | Shows | Default |
|---|---|---|
| `build` | `resources:build-info.properties` (`spring.info.build.location`): `build.name`, `build.version`, `build.time`, ... | on when the file exists |
| `git` | `resources:git.properties` (`spring.info.git.location`); `management.info.git.mode=simple` (branch, short commit id, time) or `full` | on when the file exists |
| `env` | the `info.*` properties, without the prefix | off |
| `os` | the operating system's name, version and architecture | off |
| `dart` | the Dart version (Spring Boot's `java`) | off |

Each is switched by `management.info.<id>.enabled`; `build` and `git`
follow `management.info.defaults.enabled`. The `BuildProperties` and
`GitProperties` beans give the same values to the application. An
`InfoContributor` bean of the application adds its own details.

```json
{"git": {"branch": "main", "commit": {"id": "4faa522", "time": "2026-11-04T18:02:11Z"}},
 "build": {"name": "shop", "version": "1.4.0", "time": "2026-11-05T09:12:44Z"}}
```

## Mappings

```json
{"contexts": {"application": {"mappings": {
  "dispatcherHandlers": {"webHandler": [
    {"predicate": "{GET [/api/books/{isbn}], produces [application/json]}",
     "handler": "BookController#find(String)",
     "details": {"handlerMethod": {"className": "BookController", "name": "find",
       "descriptor": "(String isbn) -> Future<Book>"},
       "requestMappingConditions": {"consumes": [], "headers": [], "methods": ["GET"],
       "params": [], "patterns": ["/api/books/{isbn}"],
       "produces": [{"mediaType": "application/json", "negated": false}]}}},
    {"predicate": "/**", "handler": "ResourceWebHandler [resources:static/, resources:public/]"}]}},
  "parentId": null}}}
```

Every `MappingDescriptions` bean adds its key: the web starter's
`dispatcherHandlers`, the navigation starter's `screens`. The context is
named after `spring.application.name` (`application` by default).

## An endpoint of your own

```dart
// GET /actuator/features and GET /actuator/features/{name}
@Endpoint(id: 'features')
class FeaturesEndpoint {
  FeaturesEndpoint(this.flags);
  final FeatureFlags flags;

  @ReadOperation()
  Map<String, bool> features() => flags.all;

  @ReadOperation()
  bool? feature(@Selector() String name) => flags.all[name];
}
```

A `@Selector()` parameter is a path segment (`SelectorMatch.allRemaining`
takes the rest of the path as a `List<String>`), another parameter a
query parameter converted to its type (missing or unconvertible: `400`),
a `SecurityContext` parameter the request's user. `null` answers `404`;
a `WebEndpointResponse` sets the status. An `@EndpointWebExtension` bean
replaces operations over HTTP, as the health endpoint's does.

## Security

With [`spring_boot_starter_security`](https://pub.dev/packages/spring_boot_starter_security)
the endpoints pass the security filter chain like any request.
`EndpointRequest` matches them without repeating their paths:

```dart
@Bean()
@Order(1)
SecurityFilterChain actuator(HttpSecurity http) => http
    .securityMatcherOf(EndpointRequest.toAnyEndpoint())
    .authorizeHttpRequests((auth) => auth
        .requestMatchersOf([EndpointRequest.to(['health', 'info'])])
        .permitAll()
        .anyRequest()
        .hasRole('ADMIN'))
    .httpBasic()
    .build();
```

`EndpointRequest.toAnyEndpoint().excluding([...])`,
`.excludingLinks()` and `EndpointRequest.toLinks()` narrow it.
`show-details=when-authorized` reads the roles of the request's
`Authentication` (`ROLE_ADMIN` is the role `ADMIN`).

## Testing

```dart
final app = springBootTest(springApplication);

test('the application is up', () async {
  await app.mockMvc
      .get('/actuator/health')
      .andExpect(status: 200, json: {'status': 'UP'});
});
```

## Differences from Spring Boot

- **Endpoints of the first part:** `health`, `info` and `mappings`.
  `beans`, `env`, `conditions`, `loggers`, `startup`, `logfile` and
  `metrics` come later; only read operations exist so far.
- **No management port:** the endpoints are on the main server
  (`management.server.port` comes later), so an additional path is only
  `server:`; no management CORS settings.
- **Health:** one `HealthIndicator` for both of Spring Boot's
  `HealthIndicator` and `ReactiveHealthIndicator` (its `health()` may
  return a `Future`); an indicator that throws is `DOWN` with the error,
  where Spring Boot fails the request; a part of a group is only found
  through the group when it is a member. Spring Boot 4's names are used
  (`HealthDescriptor`, `CompositeHealthDescriptor`, `SystemHealthDescriptor`;
  `HealthComponent`, `CompositeHealth` and `SystemHealth` in Spring Boot 3).
- **Disk space** is measured with `df` (Linux, macOS) or .NET's
  `DriveInfo` (Windows), `UNKNOWN` where neither is there (iOS, the web).
- **Info:** `java` is `dart`; the `os` values are Dart's
  (`Platform.operatingSystem`); `process` and `ssl` do not exist. The
  `build-info.properties` and `git.properties` files are read from
  `resources:` (Spring Boot: `classpath:META-INF/build-info.properties`
  and `classpath:git.properties`); the build writes them.
- **Mappings:** in Spring WebFlux's shape (`dispatcherHandlers`, never
  `dispatcherServlets`); the `descriptor` of a method is its Dart
  signature, its `className` the Dart class name; `screens` is our own.
- **Properties:** both `management.endpoint.<id>.enabled` (Spring Boot
  2–3) and `management.endpoint.<id>.access` (Spring Boot 3.4+) are read;
  `access` wins.
- **`EndpointRequest`** is in the security starter and matches the
  requests the actuator's web layer recorded (a request attribute), not
  path patterns of its own.
