## Unreleased

- `VerifiableRateLimitStore` and `RateLimitStoreSetupException`: a rate limit store that can say at startup whether what it keeps its buckets in is there (a table, a database function, a binding). `spring.web.rate-limit.verify-store` (`true` by default) has the web starter ask it once.
- The rate limiter's contract, for the web starter and for every starter that brings a store: `RateLimitStore` (one atomic `tryAcquire(key, limit, permits:)`), `RateLimit` (a token bucket: `RateLimit.parse('5/1m', burst:)`, `capacity`, `refillPerSecond`), `RateLimitDecision` (allowed, remaining, retry-after) and `TokenBucket` (the arithmetic, for a store of one's own).
- `InMemoryRateLimitStore` (one isolate; at most `maxEntries` keys: the buckets that are full again go, then the keys not used for the longest) and `PrimaryIsolateRateLimitStore` with `PrimaryIsolateRateLimitHandler` (one set of buckets in the application's first isolate for a pool of isolates).
- `RateLimitProperties` (`spring.web.rate-limit.*`: `enabled`, `store`, `on-store-failure`, `store-failure-retry-after`, `trusted-proxies`, `client-address-header`, `ipv6-prefix-length`, `hash-addresses`, `hash-secret`, `headers`, `memory.max-entries`, `rules[n].name` / `path` / `methods` / `key` / `limit` / `burst` / `on-store-failure`), `RateLimitStoreFailure`, and the conditions `ConditionalOnRateLimiting` and `ConditionalOnRateLimitStore(name, byDefault:)`, by which a library offers its store as the one asked for or as the default.
- A context closed with the synchronous `close()` no longer logs "Destroy callback of bean 'isolateTaskExecutor' failed": the pool's shutdown does all its work before it returns.
- **Fixed:** environment variables that write a dash of a property as an underscore bind lists and maps too, at every level, as they bound scalars and nested objects: `SPRING_WEB_RATE_LIMIT_RULES_0_LIMIT=5/1m` is `spring.web.rate-limit.rules[0].limit` (it was dropped without a word, which left the rate limiter off), `SPRING_WEB_RATE_LIMIT_TRUSTED_PROXIES_0`, a map below a dashed name, and `..._RULES_0_ON_STORE_FAILURE` inside an element; the two spellings may be mixed (`SPRING_WEB_RATELIMIT_RULES_0_ON_STORE_FAILURE`), and the one without the underscore wins when both are set.
- **Fixed:** readiness is `ReadinessState.refusingTraffic` from the moment the context begins to close (`ContextClosedEvent`, before the lifecycle beans, the web server among them, stop), as with Spring Boot: `/actuator/health/readiness` no longer answers UP during a graceful shutdown.
- **Fixed:** `InMemoryRateLimitStore` refuses a `maxEntries` below 1 with an `ArgumentError` that names `spring.web.rate-limit.memory.max-entries` (the start fails): with 0 every new key emptied the store, and nothing was limited.
- **Fixed:** `RateLimit.parse` requires a unit on the duration (`100/60` was 100 every 60 milliseconds, which never limits; the error says to write `100/60s` or `100/60m`), reads the count as decimal digits only (`0x10/1m` and `+5/1m` are refused), up to `RateLimit.maxCount` (a thousand million: `9223372036854775807/1s` gave a negative rate), and a duration of `ms`, `s`, `m`, `h` or `d` of a year at most. A `RateLimit` built with a count, period or burst that is not positive cannot be used: `RateLimit.requireValid()`, and with it `refillPerSecond`, `fullAfter`, `TokenBucket` and `InMemoryRateLimitStore.acquire`, throw an `ArgumentError` before any bucket changes (the bucket held "not a number" of tokens from then on); the store's `tryAcquire` gives that error in its future.

## 0.7.4

- `AutoConfigurationModule(platform:)` with `ModulePlatform.native` or `ModulePlatform.web`: a module only where its code works; the generated application lists it under the compiler's constant of that platform, so a browser build has no server code and a server no browser code; `-DSPRING_ALL_PLATFORMS=true` keeps them all (server code run as JavaScript under Node on purpose).
- `IsolateAutoConfiguration`: the beans `isolateInfo`, `isolateLoadSampler`, `isolateTaskExecutor` (`spring.task.execution.isolates.core-size`, `max-size`, `keep-alive`, `queue-capacity`, `allow-core-timeout`, `name-prefix`; shut down with the context), `isolateLoads`, `isolateReports` and `primaryIsolate` (with `isolateLoadsHandler`, which answers every isolate's load to any of them), each left out when the app declares its own.
- `@ConditionalOnPrimaryIsolate`: a bean only in the application's first isolate, for what must exist once and not once per isolate of a server's pool.
- `ApplicationLaunch` (the bean `springApplicationLaunch`, with `SpringApplication.run(hotReload:)`, which the generated `runApplication` passes): how the application was started, so the same one can be started in another isolate (`start`); kept across a hot reload.
- `spring.observations.annotations.enabled` is a property of `ObservationsProperties` (`spring.observations.*`), with its documentation in the editor metadata.
- The events of `SpringApplication`, `ExitCodeEvent` and `AvailabilityChangeEvent` (with its state) name themselves (`eventName`), readable in a release build.
- Observations: the `observationRegistry` bean with every `ObservationHandler` bean (`ObservationAutoConfiguration`), and `@Observed` put into effect by the `observedAdvisor` of `springBootObservedAnnotationsAutoConfiguration`, a module in the build only with `spring.observations.annotations.enabled: true`: without it the beans marked `@Observed` get no proxy at all.
- `spring.resources.prefetch` (`locations`, `stage`, `delay`): the files a Flutter web app downloads together, after it is shown or behind its splash (`ResourcesPrefetchProperties`).

## 0.7.3

- `spring.resources.embed.exclude` in the metadata (`ResourcesProperties`), the files the build leaves out of the binary.
- `JsonSchemaAutoConfiguration`: the `jsonSchemaRegistry` bean (left out when the app declares its own `JsonSchemaRegistry`), filled by every `JsonSchemaRegistryCustomizer` bean whoever declares the registry; `propertiesJsonSchemas` adds the schemas of `spring.json.schemas`, of every `@JsonSchemaSource` and of every `JsonSchema` bean (`spring.json.schemas-registry.properties=false`: none), and the `ObjectMapper` gets the registry as its `schemaResolver`, so reading a class with `@JsonSchemaSource` checks the JSON first. The keys of a list under `spring.json.*` (`spring.json.schemas[0].location`) are no unknown keys any more.

## 0.7.2

- README: the link goes to the package's own page on farum-azula.org, and what the README says was checked against the code and brought up to date.
- `AutoConfigurationModule(build: AutoConfigurationBuild(property, whenMissing:))`: the application's configuration decides when the generator runs whether a module is in the application: `true` always, `false` never (no code at all), not set as `whenMissing` (`BuildInclusion.notInRelease` by default: in debug and profile builds, compiled away from a release).
- `SpringApplication(applicationStartup:)`: the recorder of the start's steps (`spring.boot.application.starting`, `environment-prepared`, `context`) and of the beans; none by default.
- `SpringApplication(addressResolvers:)` adds the application's `RemoteAddressResolver`s, asked before the built-in ones; the context has the chain as the `remoteAddresses` bean (`SpringApplication.remoteAddresses`). They are passed to the application because the themes are read before the beans exist.

## 0.7.1

### Changes

- Application availability, as Spring Boot's: `LivenessState` (`correct`, `broken`), `ReadinessState` (`acceptingTraffic`, `refusingTraffic`), `AvailabilityChangeEvent` and `ApplicationAvailability`, kept by the `applicationAvailability` bean (`ApplicationAvailabilityBean`, `ApplicationAvailabilityAutoConfiguration`). `SpringApplication` publishes `LivenessState.correct` after `ApplicationStartedEvent` and `ReadinessState.acceptingTraffic` after `ApplicationReadyEvent`; a listener of every event now also receives these two.

## 0.7.0

### Fixes

- An auto-configuration module with a class excluded (`@SpringBootApplication(exclude: ...)`, `spring.autoconfigure.exclude`) keeps its `typeTests`, `typeDepths` and `aopProxies`; they were dropped with the rebuilt module.

## 0.6.3

### Changes

- `SpringApplication.progressListener` and `StartupProgress` (`done`, `total`, `fraction`): how far a start has come (bean definitions created and runners called, never going back, 1 when the application is ready), for a splash screen. Nothing is counted without a listener.
- The settings of `SpringApplication` and the auto-configurations (`spring.main.*`, `spring.application.*`, `spring.banner.*`, `spring.devtools.restart.*`, `spring.lifecycle.*`, `spring.messages.*`, `spring.json.*`, `debug`, `trace`) are now read through their `@ConfigurationProperties` classes (`lib/src/properties/boot_properties.dart`, bound by the generated code), so the editor metadata and the reading cannot drift apart. Keys and defaults are unchanged. `spring.json.*` booleans are bound strictly like other properties: a value that is not a boolean fails with a `ConfigurationPropertiesBindException` instead of turning the flag off. The `spring.json.datatype.datetime.*` keys have no default of their own in the metadata (they follow the `serialization.` / `deserialization.` ones).
- The binder accepts `false` (what YAML makes of an unquoted `off`) for an enum with an `off` constant, and `true` for one with `on`: `spring.main.banner-mode: off` in YAML.
- `spring.messages.cache-duration` is a `Duration` with `@DurationUnit(ChronoUnit.seconds)`; the lifecycle processor and the message source take their properties classes as beans.
- Generated files live in `spring_gen/` next to their source root (`lib/spring_gen/main.spring.dart`, `bin/spring_gen/main.spring.dart`): imports of `main.spring.dart` change to `spring_gen/main.spring.dart` (see `spring_core_dart_generator`).

## 0.6.2

### Changes

- The banner (`resources:banner.txt`) and the message bundles (`spring.messages.basename`) are looked up with the `resources:` prefix; `classpath:` still works with a warning (see `spring_core_dart`).

## 0.6.1

- No changes of its own; released with the family version 0.6.1.

## 0.6.0

### Breaking

- Properties renamed, as this project's own names (Java's servlet, Jackson, Spring Cloud, Logback and Flyway mean nothing in Dart): `spring.jackson.*` is `spring.json.*` (the `ObjectMapper` bean's settings). The table is in `docs/configuration.md` ("Renamed properties").
- An old name stops the start: `RenamedPropertiesEnvironmentPostProcessor` (always run, after the config files are read) fails with `RenamedPropertiesException` when any property source holds a key under `spring.cloud.openfeign`, `spring.jackson`, `spring.servlet.multipart`, `server.servlet`, `logging.logback.rollingpolicy` or `spring.flyway` (in a file, an argument, a `--dart-define` or an environment variable such as `SPRING_JACKSON_TIMEZONE`), and the `APPLICATION FAILED TO START` report lists each key with its new name (`spring.jackson.time-zone is now spring.json.time-zone`). The table is `RenamedPropertiesEnvironmentPostProcessor.renamed`; Spring Boot's `spring-boot-properties-migrator` only warns.
- Without `spring_boot_starter_logging` the default log level is `info`, as Spring's (it was `warning`; see `spring_core_dart`): set `logging.level.root=warn` for the old output.

### Changes

- `@ConfigurationProperties` binding works on a description that has no methods (the generator describes these classes with getters and setters only) and reads a property's current value only when it has a getter; a class described without its constructor and setters fails with an `IntrospectionPartError`.
- The predefined log groups `web` (`spring.web`, `spring.websocket`) and `sql` (`spring.jdbc.core.JdbcTemplate`, `spring.jdbc.core.StatementCreatorUtils`) work in `logging.level.*` as in Boot (`logging.level.web=debug`); a `logging.group.web` of the application replaces the list. They are `SpringApplication.predefinedLoggerGroups`.
- `--debug` (`debug=true`) also sets the container, Boot and the web server (`spring_core_dart`, `spring_boot_dart`, `spring.web.server`) to `debug`, and `--trace` (`trace=true`) to `trace`, as Boot does for its own loggers; `logging.level.*` wins. `debug=false` is off.
- `Running with Spring Boot v...` at `debug`, as Boot's startup logger.

## 0.5.0

### Changes

- `AsyncStartup`: beans that finish starting after the refresh (the web starter's server, which binds its port asynchronously) are awaited before the `Started ...` line, the `ApplicationStartedEvent`, the runners and the `ApplicationReadyEvent`. A failure fails the start like a failed refresh (the report, `ApplicationFailedEvent`, the context closed, `runAsync` throws, a non-zero exit code), as a port in use does in Spring Boot.
- `LifecycleAutoConfiguration` registers the `lifecycleProcessor` with `spring.lifecycle.timeout-per-shutdown-phase` (30 s by default, as in Boot) as its timeout per shutdown phase. The context waited 10 s whatever the property said, so beans were destroyed under running requests. Switch it off with `spring.autoconfigure.exclude=LifecycleAutoConfiguration`.
- Hot reload: after a restart that failed, the next reload starts the application again (it stopped restarting), as DevTools restarts at the next change.

## 0.4.3

- Flutter security (#15)
- feat: single sign-on with OAuth 2.0 / OpenID Connect (spring_boot_sta… (#11)
- docs: the READMEs and docs/ rewritten: what it is, why and when you need it, an example, then Spring (#10)

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs
- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- The startup line names the runtime: `Starting app using Dart 3.13.5 with PID 42`, in a Flutter app `using Flutter 3.47.7 (Dart 3.13.5)` (also on the web, where the Dart version comes from the Flutter tool).

## 0.3.2

- feat: hot reload on the Dart VM, flutter_notes example, fixes for example resources and workspace builds
- feat: spring_boot_starter_web, WebSocket server endpoints, uploads and downloads

## 0.3.1

- The example is a Spring Boot application written by the generator (`@ConfigurationProperties`, a `@Service`, a `CommandLineRunner`).

## 0.3.0

- feat(spring_boot_starter_flutter): themes from properties, free reads in Spring widgets

## 0.2.3

- add spring application handling
- docs(spring_boot_starter_flutter): add an example for pub.dev

## 0.2.2

- ci: run only the tests of the packages a change affects

## 0.2.1

- `--dart-define` values as properties: `SpringApplication(dartDefines: ...)` (filled by the generator) adds them right below the command-line arguments with relaxed names like environment variables (`API_URL` answers `api.url`; `SPRING_PROFILES_ACTIVE` activates profiles)
- `run` / `runAsync(additionalProfiles: [...])`: profiles for one launch after the application's own `additionalProfiles`, kept by `reload` / `reloadAsync` (Flutter's platform profiles)

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
