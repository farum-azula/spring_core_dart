## 0.2.0

- breaking: `@ConditionalOnBean`, `@ConditionalOnMissingBean` and `@ConditionalOnSingleCandidate` are `registerBean`-phase `ConfigurationCondition`s, like Boot's `OnBeanCondition`: they are decided when the configuration class is read, class by class (application classes before auto-configurations; a scanned `@Component` or an `@Import`ed class counts as a class too, at its place in that order), so the beans of an `@Import`ed `BeanRegistrar` / `ImportBeanDefinitionRegistrar` and of earlier classes make an auto-configuration, or a later `@ConditionalOnMissingBean` `@Bean`, back off (there were two `CacheManager`s, `ObjectMapper`s or `HttpTransport`s), and a `@Component` `@ConditionalOnMissingBean` / `@ConditionalOnBean` sees the beans of earlier classes' `@Bean` methods and registrars; a class-level bean condition decides the class, its `@Bean` methods and its imports once (a skipped class runs no registrar; a `@ConditionalOnMissingBean(X)` class importing the class that defines `X` stays, like Boot's `PooledDataSourceConfiguration`) and no longer stops the class's `@PropertySource`s; the built-in auto-configuration beans are `@Bean` methods (`factoryMethodName`); excluding one class of an auto-configuration module keeps the `@Import`s of its other classes (they were dropped) and drops the excluded class's own
- `ApplicationRunner` / `CommandLineRunner` and `ExitCodeGenerator` beans registered with `registerSingleton` (no bean definition) are called and asked for their code; they failed with a `NoSuchBeanDefinitionException`
- the lines logged before `logging.level.*` applies (`ApplicationStartingEvent` / `ApplicationEnvironmentPreparedEvent` listeners, config data, the banner in log mode) are held and emitted at the final levels (were dropped below WARN); the levels apply right after `ApplicationEnvironmentPreparedEvent`, before the banner, like Boot's `LoggingApplicationListener`
- `@ConfigurationProperties(ignoreInvalidFields: true)`: a comma list with an invalid element keeps the default, like Boot (was the valid elements)
- validation auto-configuration: `defaultValidator` backs off only for a `BeanValidator` bean (a plain form `Validator` no longer removes it) and method validation uses the unique `BeanValidator` (two plain `Validator` beans no longer fail the start)
- breaking: `@ConditionalOnBean` / `@ConditionalOnMissingBean` without arguments check the `@Bean` method's return type; `.where(types:, names:, annotations:, search:)` (and `ignored:` for the missing one), `.named(..., search:)`; new `SearchStrategy`; the auto-configured `messageSource` looks at the current context only (`SearchStrategy.current`), like Boot
- `@ConditionalOnCloudPlatform(CloudPlatform.x)`
- `@ConfigurationProperties(ignoreInvalidFields:, ignoreUnknownFields:)`
- binding: a nullable nested value object none of whose own keys is set stays `null` (was "no value bound" for its required parameters)
- breaking: `ApplicationContextInitializer` is a class (`initialize(context)`, or `ApplicationContextInitializer.of(...)`), sorted by `Ordered`; `LazyInitializationExcludeFilter` beans; `SPRING_APPLICATION_JSON` / `spring.application.json` (`SpringApplicationJsonEnvironmentPostProcessor`)
- `spring.messages.encoding`, `always-use-message-format`, `common-messages`; `runAsync` prints a `banner.txt` that is readable asynchronously only (a Flutter asset)
- an exit code generator that throws, followed by one returning 0, gives 1 (was 0); `ApplicationFailedEvent` reaches the listeners added with `context.addApplicationListener` when the context did not start
- `selectAutoConfigurations` is exported (Boot's exclusions and `AutoConfigurationSorter` order, used by `ApplicationContextRunner`).
- A failed start is logged like Spring Boot: the failure analysis at error level under `spring_boot_dart.diagnostics.LoggingFailureAnalysisReporter`, any other failure as `Application run failed` with the error and stack trace (refresh failures without an analysis were not reported at all). Breaking: `SpringApplication(out:)` is optional and, when given, receives the reports instead of the log.
- `DeferredLogs`: what is logged while an application starts is handed to the logging system (bean `springBootDeferredLogs`), which replays it.
- `logging.level.<logger>: false` (YAML's `off`) is OFF, like Boot's lenient enum conversion.
- Jackson: `spring.jackson.deserialization.fail-on-null-for-primitives` (`true`, Jackson 3's default)
- Jackson: `spring.jackson.datatype.datetime.write-durations-as-timestamps` / `write-date-timestamps-as-nanoseconds` / `read-date-timestamps-as-nanoseconds`, `deserialization.accept-float-as-int`, `mapper.default-view-inclusion`; `default-property-inclusion` accepts `non_absent` and `non_default`; breaking: date timestamps are seconds with the fraction (Jackson 3), durations stay ISO-8601 unless `write-durations-as-timestamps`
- `@ConditionalOnBean` / `@ConditionalOnMissingBean` documented and tested to ignore `autowireCandidate: false` and `defaultCandidate: false` beans, like Boot 3.4+
- the shutdown hook (`registerShutdownHook: true` / `spring.main.register-shutdown-hook`) delegates to the core's `context.registerShutdownHook()`; behaviour unchanged (off by default)
- breaking: the auto-configured mapper bean is named `jacksonJsonMapper` (Boot 4's name) instead of `objectMapper`
- Jackson: `spring.jackson.datatype.datetime.write-dates-as-timestamps` (Boot 4; wins over `spring.jackson.serialization.write-dates-as-timestamps`); any other unsupported `spring.jackson.*` key is logged as a warning naming it; a named `spring.jackson.time-zone` fails with a message that only `UTC` and fixed offsets are supported
- `${random.*}` placeholders: `SpringApplication` adds a `RandomValuePropertySource` after the system environment, like Boot
- binding: environment variables bind nested objects under dashed names (`APP_MAIN_SERVER_HOST` → `app.main-server.host`, Boot's legacy ancestor check); `@Name`, `@DurationUnit(ChronoUnit.x)`, `@DataSizeUnit(DataUnit.x)`; `BindHandler` (`Binder.bind(handler:)`); `BindResult.map` / `ifBound` / `orElseGet` / `orElseThrow`
- `@ConfigurationProperties` on `@Bean` methods binds the returned object (`@Validated()` on the method validates it); `ConfigurationPropertiesBinder(beanFactory:)`
- validation of bound objects like Boot: the `configurationPropertiesValidator` bean (`ConfigurationPropertiesBinder.validatorBeanName`) and self-validating properties classes (a properties class that is a `Validator`)
- `EnvironmentPostProcessor` (`SpringApplication(environmentPostProcessors:)`), run before or after config data by order (`EnvironmentPostProcessor.configDataOrder`)
- conditions: `ConditionalOnProperty(prefix:)` and `ConditionalOnProperty.names([...])`, `@ConditionalOnBooleanProperty`, `@ConditionalOnSingleCandidate`, `@ConditionalOnExpression`, `@ConditionalOnResource`, `ConditionalOnBean.named`; `ConditionEvaluationReport`, logged at INFO for `--debug` / `debug=true` (with a hint after a failed start otherwise)
- `JsonMapperBuilderCustomizer` beans for the auto-configured mapper: they receive the core `JsonMapperBuilder` (`jsonMapperBuilderFromProperties`)
- banner: `Banner`, `SpringBootBanner`, `ResourceBanner`, `BannerMode` (`SpringApplication(banner:, bannerMode:)`, `spring.main.banner-mode`, `classpath:banner.txt` / `spring.banner.location`); printed by default like Boot
- failure analysis for `BeanDefinitionOverrideException`, missing config data (`ConfigDataResourceNotFoundException`, `ConfigDataLocationNotFoundException`) and invalid property names
- breaking: `SpringApplication.exit` and failed runs take the first non-zero code of the generators sorted by order (Boot 3+), not the highest
- breaking: an invalid `logging.level.*` value fails the start (Boot's binding to `LogLevel`); `logging.group.<name>` and `spring.messages.basename` accept YAML lists
- `ApplicationArguments` parses like `SimpleCommandLinePropertySource`: a lone `--` ends the options, `--=x` is an error
- `spring.messages.cache-duration` keeps sub-second values (`500ms`); `spring.messages.use-code-as-default-message` / `fallback-to-system-locale` are read case-insensitively

## 0.1.7

- `SpringApplication.runAsync` / `reloadAsync` refresh with the context's `refreshAsync()` (asynchronous `@PostConstruct` / init methods are awaited before the runners) and close with `closeAsync()`; `run` fails for an asynchronous init callback
- breaking: `SpringApplication.run` and `ApplicationFailedEvent.exception` report a missing or ambiguous dependency as an `UnsatisfiedDependencyException` (its `cause` is the `NoSuchBeanDefinitionException` / `NoUniqueBeanDefinitionException`); the failure analysis is unchanged
- `SpringApplication(defaultProperties:)` / `setDefaultProperties` (Boot's `setDefaultProperties`): the `defaultProperties` source below every other one, config files included; `additionalProfiles:` (Boot's `setAdditionalProfiles`)
- `@AutoConfiguration` is `proxyBeanMethods: false`, like Boot's: its `@Bean` methods are called as written
- `@ConfigurationProperties` bind collections like Boot's `Binder`: indexed lists (`app.hosts[0]`, YAML lists, `APP_HOSTS_0_`) next to comma lists, maps (`app.headers.X-Shop`, `app.headers[x.y]`; keys keep their form), lists and maps of nested objects (`app.servers[0].name`, `app.backends.eu.url`); a list from a higher-precedence source replaces the whole list, map entries merge per key; elements are converted through the conversion service and failures name the property (`app.ports[0]: failed to convert to int (was "x")`). `Binder` / `BindResult` bind outside of a properties class
- constructor binding: a `@ConfigurationProperties` class whose only constructor has parameters is created through it, parameters bound from properties, with `@DefaultValue` (Boot's), Dart defaults, `null` for nullable parameters, nested constructor-bound classes and collections; a missing required value fails the start naming the property (`ConstructorBound`, used by the generated code)
- application events in Boot's order: `ApplicationStartingEvent`, `ApplicationEnvironmentPreparedEvent`, `ApplicationContextInitializedEvent`, `ApplicationPreparedEvent`, `ApplicationStartedEvent`, `ApplicationReadyEvent`, `ApplicationFailedEvent`; listeners on `SpringApplication(listeners:)` / `addListeners` / `addListener`, the later events also reach `@EventListener` beans
- breaking: a `@ConfigurationProperties` prefix must be in canonical form (`my-app`, not `myApp`), as in Boot; `ConfigurationPropertiesBindException.beanName` is nullable (`null` for `Binder.bind`); `ConfigurationPropertiesBinder.kebabCase` is removed
- breaking: `SpringApplication` loads `application.yml` / `application.yaml` too, searches Boot's two location groups (`./application.properties` beats a packaged `application-prod.properties`, `./config/*/` is searched) and attaches relaxed names (`app.read-timeout` finds `app.readTimeout`, `APP_READTIMEOUT`), see `spring_core_dart`
- `logging.level.ROOT` (any case) sets the root level instead of a logger named "ROOT"
- breaking: the auto-configured message source is a `ReloadableResourceBundleMessageSource`; `spring.messages.fallback-to-system-locale` (default `true`) and `spring.messages.cache-duration` (seconds without a unit) are supported
- the context id is `spring.application.name` (or `application`), like Spring Boot's `ContextIdApplicationContextInitializer`
- breaking: `@ConfigurationProperties` are validated only with `@Validated()` on the class, like Spring Boot; `ConfigurationProperties(validate:)` is removed
- `ValidationAutoConfiguration`: a `defaultValidator` (`BeanValidator`, backs off for an application `Validator`) and a `methodValidationPostProcessor` (not applied to `@ConfigurationProperties` classes)
- `FailureAnalyzer` (Boot's interface), registered on `SpringApplication(failureAnalyzers:)` or as beans; consulted before the built-in analysis
- breaking: startup info is logged through `SpringLog` (`spring_boot_dart.SpringApplication`) at INFO like Boot's: `Starting <app> using Dart <version> with PID <pid>`, the active / default profiles, `Started <app> in <x> seconds` (was a printed `Started <app> in <n> ms (profiles: ...)` line); `out` only gets failure reports
- `spring.main.lazy-initialization` (`LazyInitializationBeanFactoryPostProcessor`) and `spring.main.allow-bean-definition-overriding` (default `false`)
- dotted `spring.messages.basename` values are paths (`config.i18n.messages` → `config/i18n/messages`), like Boot
- `JacksonAutoConfiguration` registers `JsonSerializer` / `JsonDeserializer` beans (Boot's `@JsonComponent`) and reads `spring.jackson.time-zone` (`UTC` or a fixed offset such as `+02:00`)
- breaking: the JSON property order is Jackson 3's / Boot 4's (sorted by JSON name, constructor parameters first); `spring.jackson.mapper.sort-properties-alphabetically=false` restores declaration order
- breaking: auto-configurations are registered in Boot's `AutoConfigurationSorter` order (module name, `AutoConfigurationModule.order`, `before` / `after`; a cycle fails the start), not in the order they are listed
- `AutoConfigurationModule(before:, after:)`; `SpringApplication(autoConfigurationMetadata:)` carries them from the generated code
- auto-configuration exclusion: `@SpringBootApplication(exclude:, excludeName:)`, `SpringApplication(exclude:, excludeName:)` and `spring.autoconfigure.exclude` (types, class names or module names), applied before conditions run; excluding a type that is no auto-configuration fails the start
- `SpringApplication.exit(context, [generators])` with `ExitCodeGenerator` beans (highest non-zero code wins), `ExitCodeEvent`, `ExitCodeExceptionMapper` beans and `SpringApplication.exitCodeOf(error)` for failed runs
- shutdown hook: with `spring.main.register-shutdown-hook=true` or `SpringApplication(registerShutdownHook: true)` the context is closed on SIGINT / SIGTERM and the process exits with `130` / `143`; off by default, unlike Boot, because the signal listener keeps a Dart program alive until the context closes; nothing on the web

## 0.1.6

- update road map
- ci: release with a button on main, skip new packages when publishing; shorter pubspec descriptions

## 0.1.5

- Runners as in Spring Boot: `ApplicationRunner` / `CommandLineRunner` may return a `Future`; runners run one after another (a runner's `Future` completes before the next starts), `runAsync` / `runApplicationAsync` complete after the last one, a failing runner is reported (`Application run failed`) and closes the context. The startup line now comes before the runners, as in Spring Boot.

## 0.1.4

- feat: ObjectMapper in core — JSON on generated metadata (@Introspected, @JsonProperty/@JsonIgnore/@JsonInclude/@JsonCreator/@JsonValue), spring.jackson.* in Boot

## 0.1.3

- add scheduling + cache starters
- fix extension add aop docs

## 0.1.2

- ci: release only from the release branch; fix version-dependent test; Node 24 actions
- fix tests

## 0.1.1

- Hot reload: `SpringApplication(fingerprint:)`, `reload` / `reloadAsync` keep the running context when the generated code is unchanged and restart it with the same arguments otherwise; `runners: false` skips `ApplicationRunner` / `CommandLineRunner` beans after such a restart.
- Example on pub.dev (`example/`) and a description within 180 characters.
- Failure reports point to `lib/resources/application.properties` and suggest `@Lazy()` for dependency cycles.

## 0.1.0

Initial version.

- `@SpringBootApplication` (with `spring_core_dart_generator`: package-wide
  scan and a generated `runApplication`), `SpringApplication.run` /
  `runAsync`.
- `@ConfigurationProperties` binding (kebab-case, camelCase and environment
  variable names) with validation.
- `@AutoConfiguration`, `@ConditionalOnProperty`, `@ConditionalOnBean`,
  `@ConditionalOnMissingBean`.
- Starters: `@AutoConfigurationModule` in `lib/spring_auto_configuration.dart`,
  discovered by the generator in all dependencies;
  `MessageSourceAutoConfiguration`; `ConditionalOnMissingBean.named`.
- `AutoConfigurationModule(requires:)` with a build-time compatibility
  check against `springBootVersion`.
- Generated `runApplicationAsync` for asynchronous config (Flutter assets).
- `ApplicationArguments`, `ApplicationRunner`, `CommandLineRunner` (both
  kinds sorted together by order, a bean implementing both called as
  both), startup line and failure analysis reports.
- `logging.level.root`, `logging.level.<logger>`, `logging.group.*` and
  `LOGGING_LEVEL_*` variables applied to `SpringLog`
  (`SpringApplication.applyLoggingLevels`).
- `SpringApplication(initializers:)` (`ApplicationContextInitializer`) and
  `run(args, properties:)` with the highest precedence.
