## Unreleased

- `ApplicationContextRunner` attaches relaxed names to its environment, like an application started by `SpringApplication` (`app.read-timeout` finds `app.readTimeout`)
- breaking: `ApplicationContextRunner.withBean` registers an extra bean before the configurations are processed, like Boot's (a `@ConditionalOnMissingBean` backs off; a missing back-off gives a second bean), instead of replacing definitions; `withBeanOverride` replaces a bean like `BeanOverride`; `ApplicationContextRunner.beans` holds bean definitions, the overrides moved to `overrides`
- `withPropertyValues` accepts `key:value` like `TestPropertyValues`; breaking: values are trimmed
- `springBootTest(dynamicProperties:)` with `DynamicPropertyRegistry`: properties evaluated when the context starts (`@DynamicPropertySource`)
- `app.output` no longer holds the startup line (Spring Boot's startup info is now logged through `SpringLog`)
- `springBootTest` keeps the application's auto-configuration order and exclusions, and does not register the shutdown hook (it closes its own context)

## 0.1.6

- update road map
- ci: release with a button on main, skip new packages when publishing; shorter pubspec descriptions

## 0.1.5

- add feign runner + web socket runner
- add web core + faign starter for http calling

## 0.1.4

- feat: ObjectMapper in core — JSON on generated metadata (@Introspected, @JsonProperty/@JsonIgnore/@JsonInclude/@JsonCreator/@JsonValue), spring.jackson.* in Boot

## 0.1.3

- add scheduling + cache starters
- fix extension add aop docs

## 0.1.2

- ci: release only from the release branch; fix version-dependent test; Node 24 actions
- fix tests

## 0.1.1

- Example on pub.dev (`example/`) and a description within 180 characters.

## 0.1.0

Initial version.

- `springBootTest` (`@SpringBootTest`): the `test/resources/` test
  classpath (`resourceDirectories`), `propertyFiles`
  (`@TestPropertySource`), properties, profiles, environment,
  initializers, `markDirty` (`@DirtiesContext`), restored `SpringLog`
  state.
- `BeanOverride` (`@MockitoBean` / `@TestBean`), keeping name, aliases,
  qualifiers and `@Primary` / `@Fallback`.
- `ApplicationContextRunner` with `AssertableApplicationContext`.
- Matchers: `hasSingleBean`, `hasBean`, `doesNotHaveBean`, `hasBeanNamed`,
  `hasFailed`.
- `captureLogs`.
- Built on `test_api` + `matcher` for `flutter_test` compatibility.
