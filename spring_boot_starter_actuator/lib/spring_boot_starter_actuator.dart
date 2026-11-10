/// Spring Boot Actuator over HTTP: what a running application tells
/// about itself (its health, its version, its mappings) under
/// `/actuator`, with Spring Boot's paths, properties and JSON, so load
/// balancers, Kubernetes probes and the usual tools read it.
///
/// Add the starter next to the web starter's controllers and
/// `GET /actuator/health` answers `{"status":"UP"}` (`503` when the
/// application is down). The other endpoints are exposed with
/// `management.endpoints.web.exposure.include` (only `health` by
/// default, as in Spring Boot):
///
/// ```properties
/// management.endpoints.web.exposure.include=health,info,mappings
/// management.endpoint.health.show-details=when-authorized
/// management.endpoint.health.probes.enabled=true
/// ```
///
/// What it contains: the endpoints of `spring_boot_actuator` (re-exported:
/// `HealthIndicator`, `InfoContributor`, `@Endpoint`), their answers over
/// the web starter's dispatcher (`WebEndpointHandlerMapping`), the
/// discovery page with its `_links`, and `management.endpoints.web.*`.
/// With the security starter, `EndpointRequest.toAnyEndpoint()` matches
/// the endpoints' requests in a `SecurityFilterChain`.
///
/// This one import is enough: it re-exports `spring_boot_actuator` and
/// the web starter.
///
/// Spring Boot (Java): `spring-boot-starter-actuator`.
library;

export 'package:spring_boot_actuator/spring_boot_actuator.dart';
export 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

export 'src/actuator_auto_configuration.dart' show healthEndpointGroupsOf;
export 'src/config/web_endpoint_properties.dart';
export 'src/web/qps_endpoint.dart';
export 'src/web/web_endpoint_handler_mapping.dart';
