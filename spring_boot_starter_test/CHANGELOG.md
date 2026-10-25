## 0.2.0

- `hasSingleBean`, `hasBean` and `doesNotHaveBean` count the beans of the parent contexts too (`withParent`), like AssertJ's default `Scope.INCLUDE_ANCESTORS`.
- `BeanOverride` by type replaces the single `@Primary` bean among several (it failed); `BeanOverride(name:)` takes an alias and replaces the bean it names, keeping every alias (it failed).
- Breaking: initializers are `ApplicationContextInitializer` objects (`ApplicationContextInitializer.of((context) => ...)`), following `spring_boot_dart`.
- `ApplicationContextRunner.runAsync` refreshes with `refreshAsync()` (asynchronous `@PostConstruct` / init methods are awaited; a failed start is closed with `closeAsync()`).
- `ApplicationContextRunner` sorts its auto-configurations like Boot's `AutoConfigurations.of(...)`: by name, `order`, then `before` / `after` (`withAutoConfiguration(module, metadata)` takes the module's `@AutoConfigurationModule`).
- `ApplicationContextRunner.withParent`, `withAllowBeanDefinitionOverriding` and `withAllowCircularReferences` (`true` fails the run: circular references are always an error).
- `BeanOverride` names a new bean like `withBean` (`defaultBeanName`: `URLService` stays, type arguments are left out).
- Breaking: `ApplicationContextRunner.withBean<T>(supplier)` takes a supplier like Boot's `withBean(type, supplier)`: each run gets a new instance (an instance was reused after a previous run destroyed it).
- `springBootTest` closes its context with `closeAsync()` (asynchronous `@PreDestroy` and lifecycle stops are awaited); `ApplicationContextRunner.runAsync` too.

## 0.1.7

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
