## Unreleased

- README: the link goes to the package's own page on farum-azula.org, and what the README says was checked against the code and brought up to date.
- The package's page on pub.dev links its documentation, [farum-azula.org](https://farum-azula.org) (`documentation` in `pubspec.yaml`).

## 0.7.1

- First version: `@Endpoint`, `@ReadOperation`, `@Selector` and `@EndpointWebExtension` with the endpoint discoverer; the `health` endpoint (`HealthIndicator`, `Health`, `Status` aggregated in Spring Boot's order, the HTTP status mapping, groups, `show-details` / `show-components`, the `ping`, `diskSpace`, `livenessState` and `readinessState` indicators); the `info` endpoint (`InfoContributor`, `BuildProperties` from `build-info.properties`, `GitProperties` from `git.properties`, the `build`, `git`, `env`, `os` and `dart` contributors); the `mappings` endpoint over the `MappingDescriptions` beans; the typed `management.*` and `spring.info.*` properties.
