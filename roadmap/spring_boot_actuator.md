# spring_boot_actuator (planned)

Spring Boot Actuator: what a running application knows about itself, as
endpoints with the same names and JSON shapes as Spring Boot's, so the same
data serves several viewers. Comes after the
[web starter](spring_boot_starter_web.md), which exposes the endpoints over
HTTP first.

## Endpoints

Pure Dart (no Flutter, no `dart:io` in the endpoint code), each an
`@Endpoint` bean, switched on and exposed with Boot's properties
(`management.endpoints.web.exposure.include=*`,
`management.endpoint.<id>.enabled`):

| Endpoint | Shows |
|---|---|
| `beans` | every bean: name, type, scope, dependencies, the module or auto-configuration it comes from |
| `env` | active profiles, property sources in order, each property with its origin; secrets masked (`management.endpoint.env.show-values`) |
| `conditions` | which auto-configurations applied and why the others did not (the condition evaluation report) |
| `loggers` | logger levels, changed at run time |
| `logfile` | the recent lines of the `LogBuffer` |
| `info` | application name and version, Dart / Flutter version, platform, start time |
| `health` | `HealthIndicator` beans, aggregated `UP` / `DOWN` |
| `startup` | how long each bean and phase of the start took |

## Viewers

- **HTTP** (`/actuator/*`), from the web starter: for servers, and for apps
  during development — the starter as a dev dependency next to the app
  (`--dart-define` or a profile switches it on), so a release build has none
  of it.
- **Editor extensions** (`dart_spring` and the language server): connect to
  the running app's endpoints and show beans, properties and logs next to
  the code, like the Spring tools of IntelliJ IDEA.
- **A web page** served by the actuator itself: a small dashboard over the
  same endpoints.
- **Inside a Flutter app** (later, maybe): an Actuator screen in
  `spring_boot_starter_flutter`, opened from a debug button when
  `management.flutter.enabled=true` (`application-dev.properties`), with the
  logs, beans, environment and conditions tabs.

## Packages

Like Spring Boot, where `spring-boot-actuator` holds the code and
`spring-boot-starter-actuator` only its dependencies:
`spring_boot_actuator` (the endpoints) and `spring_boot_starter_actuator`
(the endpoints plus their HTTP exposure through the web starter).
