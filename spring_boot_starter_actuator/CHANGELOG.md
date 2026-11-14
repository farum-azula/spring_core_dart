## 0.8.1

- No changes of its own; released with the family version 0.8.1.

## 0.8.0

- No changes of its own; released with the family version 0.8.0.

## 0.7.4

- The `isolatesEndpoint` bean: the `isolates` endpoint over HTTP once exposed (`management.endpoints.web.exposure.include=isolates`).
- The `qps` endpoint (`QpsEndpoint`, `GET /actuator/qps` and `/actuator/qps/now`) of the web starter's debug feature, in the build by the same property (`spring.web.debug.qps.enabled: true`); answered the same by every isolate of a pool.
- The modules are only where a server can run (`ModulePlatform.native`).

## 0.7.3

- The `jsonSchemasEndpoint` bean: the `jsonschemas` endpoint, over HTTP once exposed (`management.endpoints.web.exposure.include=jsonschemas`).

## 0.7.2

- README: the link goes to the package's own page on farum-azula.org, and what the README says was checked against the code and brought up to date.
- The package's page on pub.dev links its documentation, [farum-azula.org](https://farum-azula.org) (`documentation` in `pubspec.yaml`).

## 0.7.1

- First version: the endpoints of `spring_boot_actuator` over HTTP through the web starter: `/actuator/health` (with `{*path}`, groups, the Kubernetes probes and their additional paths, `503` for `DOWN` and `OUT_OF_SERVICE`), `/actuator/info`, `/actuator/mappings`, the discovery page with `_links`, Spring Boot's media types (`application/vnd.spring-boot.actuator.v3+json`, `v2`, `application/json`), `management.endpoints.web.base-path`, `.exposure.include` / `.exclude` (only `health` by default), `.path-mapping`, `.discovery.enabled`, `management.endpoint.<id>.enabled` / `.access` and `management.endpoints.enabled-by-default`; the request attribute `EndpointRequest` of the security starter reads.
