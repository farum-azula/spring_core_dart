# spring_boot_actuator (planned; the first part with the navigation patch)

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

## First part, with the navigation patch

The owner, November 2026: the actuator starts in the release after
0.7.0, a little at a time:

- **The two packages** as above, `spring_boot_actuator` and
  `spring_boot_starter_actuator`, with `@Endpoint`, `@ReadOperation`,
  `management.endpoints.web.exposure.include` / `.exclude`,
  `management.endpoints.web.base-path` (`/actuator`) and
  `management.endpoint.<id>.enabled` as in Boot. Exposed by default over
  HTTP: `health` only, as in Boot.
- **`health`**: `HealthIndicator` beans, `Status` (`UP`, `DOWN`,
  `OUT_OF_SERVICE`, `UNKNOWN`) aggregated by Boot's order, groups
  (`management.endpoint.health.group.<name>.include`), the `liveness` and
  `readiness` groups (`management.endpoint.health.probes.enabled`) from
  the application's availability state, `show-details` / `show-components`
  (`never` by default, `when-authorized` through the security starter);
  ready indicators where the starters already know the state: `ping`,
  `diskSpace` on `dart:io`, `db` for the data starter's data sources.
- **`info`**: `InfoContributor` beans and `management.info.*`: `build`
  (name, version, time, written by the generator, Boot's
  `build-info.properties`), `git` (branch, commit, from `git.properties`
  when the build writes one), `env` (`info.*` properties, off by default
  as in Boot), `os` and `dart` (Boot's `java` contributor, renamed; both
  off by default as in Boot), each switched by
  `management.info.<id>.enabled`.
- **`mappings`**: in WebFlux's shape (`dispatcherHandlers`, Spring's own
  name, no `servlet`): the web starter's handlers (method, pattern, the
  controller method, consumes / produces, static resources) and, our
  addition, `screens` for a Flutter app with the navigation starter
  ([the screen map](spring_boot_starter_flutter_navigation.md#the-screen-map)),
  both read through `MappingDescriptions`.
- Security: the endpoints go through the security filter chain like any
  handler; `EndpointRequest.toAnyEndpoint()` for the chain's matchers.
  `management.server.port` (a port of their own) later.

Next patches, one or two endpoints each: `loggers`, `env`, `beans`,
`conditions`, `startup`, `logfile`, then `metrics` / Prometheus.

The site (the owner, November 2026) is on Cloudflare Pages: static, no
process of ours, so no `/actuator/health` there; Cloudflare's analytics
and an outside check watch it. The actuator watches the servers (the
server guide first) and later the site's functions on Cloudflare Workers
through the edge starter ([serverless.md](serverless.md)).
