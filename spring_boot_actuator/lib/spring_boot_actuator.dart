/// What a running application tells about itself, as Spring Boot
/// Actuator's endpoints: the same names, properties and JSON, so the same
/// tools read them.
///
/// It holds the endpoints and their model, without HTTP: the actuator
/// starter (`spring_boot_starter_actuator`) brings them to an application
/// and answers them under `/actuator`. What it contains:
///
/// - `@Endpoint`, `@ReadOperation`, `@Selector` and
///   `@EndpointWebExtension`, to write an endpoint of your own, and the
///   discoverer that finds them;
/// - `health`: `HealthIndicator` beans (`ping`, `diskSpace`, the
///   `livenessState` and `readinessState` of the probes, the data
///   starter's `db`), `Health` and `Status`, the aggregation, the groups
///   and who sees the details;
/// - `info`: `InfoContributor` beans (`build`, `git`, `env`, `os`, `dart`)
///   and `BuildProperties` / `GitProperties`;
/// - `mappings`: every `MappingDescriptions` bean (the web server's
///   handlers, an app's screens).
///
/// ```dart
/// // In the report as "inbox", and in /actuator/health.
/// @Component()
/// class InboxHealthIndicator implements HealthIndicator {
///   @override
///   Future<Health> health() async =>
///       Health.up().withDetail('pending', 3).build();
/// }
/// ```
///
/// Spring Boot (Java): `spring-boot-actuator`.
library;

export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
export 'package:spring_web_dart/spring_web_dart.dart' show MappingDescriptions;

export 'src/endpoint/annotations.dart';
export 'src/endpoint/endpoint_access.dart';
export 'src/endpoint/endpoint_discoverer.dart';
export 'src/endpoint/operation.dart';
export 'src/health/contributor.dart';
export 'src/health/disk_space.dart';
export 'src/health/groups.dart';
export 'src/health/health.dart';
export 'src/health/health_endpoint.dart';
export 'src/health/indicators.dart';
export 'src/info/contributors.dart';
export 'src/info/info.dart';
export 'src/info/info_properties.dart';
export 'src/isolate/isolates_endpoint.dart';
export 'src/json/json_schemas_endpoint.dart';
export 'src/properties/actuator_properties.dart';
export 'src/properties/properties.dart';
export 'src/web/endpoint_request_target.dart';
export 'src/web/mappings_endpoint.dart';
