# Fix plan

Open differences from Spring found in reviews: first against Spring
Framework 6.2 / Spring Boot 3, then (October 2026) against Spring Framework
7.0, Spring Boot 4.0 and Spring Cloud OpenFeign 5.0 across every package.
Items marked **High** are the ones a Spring developer trips over first.
Before 1.0 renames are made outright, with no deprecated aliases.

Already fixed (with regression tests): Dart default values of
constructor parameters, empty collections for constructors and `@Bean`
methods, `@Bean` products processed like components, `@PropertySource` /
`@Import` gated by the declaring class's conditions, negated `on-profile`
documents, relative import cycles, self-references (composites,
decorators), early events reaching the parent twice, exception-safe and
re-entrant `close()`, violation messages mangled by `MessageFormat`,
`disallowedFields` bypasses, release-safe `@annotation` matching,
package-qualified AOP wildcards, SDK types as beans (`HttpClient`,
`Uint8List`, `List<String>`), proxies for `Future<T>?` members,
`toString` with parameters, members named like `Advised`'s and classes
with the same name in two directories, advice silently skipped for beans
that cannot be proxied, optional fields and setters overwritten with
`null`, `DataBinder.bind` throwing on malformed keys and failing setters,
and the order of `spring.profiles.include`. Fixed after the October 2026
review: the whole validation, binding and messages section; the logging,
cache and test starters; cron day names and lists, `@Scheduled(scheduler:)`;
in AOP `Type+`, `@target`, `this`, `args`, per-aspect named pointcuts,
`bean()` aliases and qualifiers, `Ordered` aspects, plain and ancestor
advisors, the auto proxy creator's order, `AopContext.currentProxy()`,
argument copies, async advice and `Future` methods throwing synchronously.
Second batch: `ObjectProvider` injection points, the container's exception
hierarchy, callbacks, `FactoryBean` names, ancestors in sorted beans,
registration after freezing, superclass-first injection, `ObjectFactory`;
lifecycle (lazy beans, `SmartLifecycle` defaults, `isActive`), payload
listeners, `publishEvent` before refresh, the bundle message source and
`MessageSourceAccessor`, unique context ids; profile names, legacy keys,
`--`, null values, `Duration`, lenient enums, classpath plain paths; Boot's
`@Validated` properties, validation auto-configuration, failure analyzers,
startup logging, `spring.main.*`, dotted basenames; SpEL assignment in
`SimpleEvaluationContext`, enum order, boolean selection, `+` conversion,
map selection; JSON dates with offsets and `spring.jackson.time-zone`,
serializer beans, naming acronyms, raw maps/lists, `NaN`; the HTTP types,
Feign and WebSocket items except relaxed config keys and optional paths.

## How close to Spring (October 2026)

Per area: **API** — public names and signatures that match Spring
(a change forced by Dart counts half); **behaviour** — 15–50 behaviours
per area a Spring developer relies on, checked in the code and with probe
tests; **coverage** — share of the commonly used features of the Spring
counterpart. Estimates, ±5–10 points, measured before those fixes.

| Area | API | Behaviour | Coverage |
|---|---|---|---|
| Container (`beans`) | 86% | 65% | 69% |
| Context, events, lifecycle | 87% | 65% | 66% |
| Configuration, resources (`core`) | 91% | 63% | 67% |
| SpEL | 64% | 67% | 77% |
| Validation, binding | 84% | 62% | 58% |
| JSON (vs Jackson) | 70% | 67% | 44% |
| AOP | 80% | 66% | 66% |
| Annotations, generator | 91% | 77% | 73% |
| `spring_boot_dart` | 67% | 60% | 56% |
| `spring_web_dart` | 73% | 55% | 45% |
| Feign starter | 77% | 60% | 52% |
| WebSocket starter (declarative by design) | 62% | 64% | 56% |
| Logging starter | 70% | 66% | 50% |
| Scheduling starter | 71% | 78% | 55% |
| Cache starter | 90% | 81% | 63% |
| Test starter | 73% | 70% | 58% |
| **All, weighted by code size** | **81%** | **67%** | **64%** |

## Container (`beans`)

- [ ] **High.** `@Bean` definitions carry the type the generator infers from the method body (`DataSource dataSource() => HikariDataSource(url)` is a `HikariDataSource`), with full generic arguments: lookups, `@ConditionalOnBean` / `@ConditionalOnMissingBean` and AOP see the concrete class before the bean exists. Better than Spring, whose definition has no class (`beanClassName` is `null`) and knows only the declared return type until the bean is created — state it as a deliberate difference.
- [ ] Exclude beans produced by a configuration's own `@Bean` methods from its collections (`factoryBeanName`, Spring's `isSelfReference`).
- [ ] Parent contexts: collections should see grandparent beans; keep the parent beans' `@Order` and `autowireCandidate=false`; shadow by `containsLocalBean`.
- [ ] Single dependencies: merge local and parent candidates (parent `@Primary` may win, local wins a tie), pass the parameter name to the parent, validate ambiguity in the parent.
- [ ] `autowireCandidate=false` must be excluded from qualified injection too, without breaking `getBean<T>(qualifier: name)` (Spring's `getBean(name, Class)` returns non-candidates); `getBean<T>()` should still return the only non-candidate bean.
- [ ] `defaultCandidate` honoured by `@ConditionalOnBean` / `@ConditionalOnMissingBean` (the definition and injection already follow Spring 6.2).
- [ ] Aliases from `registerAlias` must count for `@Qualifier` and parameter-name matching.
- [ ] `determineAutowireCandidate` details: two `@Primary` beans always ambiguous; parameter name matches bean names/aliases only; Spring 6.2 "qualifier-suggested name" step.
- [ ] Wrap runtime resolution errors in `UnsatisfiedDependencyException` with the bean chain and injection point.
- [ ] Clean dependency bookkeeping on `removeBeanDefinition`; forbid bean creation while singletons are being destroyed.
- [ ] Warn when a custom-scoped bean is injected directly into a singleton; scoped proxies.
- [ ] `Map`/`Set` injection in registration order (Spring sorts only `List`); `@Order` on a `@Bean` method beats `Ordered.getOrder()`, a class-level `@Order` does not (track where `BeanDefinition.order` came from).
- [ ] Generic lookups: `Object` lookups returning all beans.
- [ ] Dereference registered `FactoryBean`s (`registerSingleton`).
- [ ] Alias overriding when `allowBeanDefinitionOverriding` is on; dangling alias chains after removal.
- [ ] Clearer cycle message for re-entrant `FactoryBean` products.
- [ ] Linear shutdown (destroy order bookkeeping is O(n²)).
- [ ] `@Value` with a custom SpEL template prefix (always delegate to the expression resolver).
- [ ] Missing APIs: `beanNamesForTypeIncludingAncestors`, `destroyBean`, `SmartFactoryBean`, `isTypeMatch`, annotation lookups (`getBeansWithAnnotation`), `Provider<T>` (`@Inject`) injection points, `@Resource`.

## Context, events, lifecycle (`context`)

- [ ] Detect `GenericApplicationListener` / `SmartApplicationListener` beans (today they get no events, silently), listeners hidden behind a `@Bean` method's declared type and `registerSingleton` objects; de-duplicate listeners.
- [ ] `Future`-returning `@EventListener`s: republish the result, route errors to the error handler.
- [ ] Programmatic registration: Spring 7's `BeanRegistrar` (`registerBean<T>(name, spec)`) through `@Import` and `context.register(registrar)`, `ImportSelector` / `ImportBeanDefinitionRegistrar`, `registerBean` on the context.
- [ ] Lifecycle: start dependencies first / stop dependents first; stop already started beans when refresh fails.
- [ ] Spring 7 `pause()` / `restart()`: `ContextPausedEvent` / `ContextRestartedEvent`, `LifecycleProcessor.onPause` / `onRestart`, `SmartLifecycle.isPauseable` (maps onto Flutter's paused/resumed).
- [ ] `PayloadApplicationEvent<T>` listeners; `@EventListener` methods on `FactoryBean` classes.
- [ ] Early events: replay them when listeners are registered and deliver events published during singleton creation synchronously.
- [ ] Asynchronous delivery: an executor-like option on `SimpleApplicationEventMulticaster` and `@Async` listeners (with the `TaskExecutor` of the scheduling starter).
- [ ] Listener conditions inside the error handler; lifecycle discovery by instance type.
- [ ] Phased creation of post-processors (`PriorityOrdered` → `Ordered` → rest, re-querying names).
- [ ] `ConditionContext` access to the definition being evaluated.
- [ ] `EmbeddedValueResolverAware` evaluating SpEL; descriptive errors for infrastructure misuse.
- [ ] Child message lookups use the parent's message source, not the parent context; `conversionService` from ancestors.
- [ ] Template hooks (`postProcessBeanFactory`, `onRefresh`, `onClose`), `registerShutdownHook()`.
- [ ] Asynchronous lifecycle: `refreshAsync()` / `closeAsync()`, async init/destroy and `SmartLifecycle.stop` with per-phase timeouts.

## Configuration (`core`)

- [ ] **High.** Load `application.yml` / `.yaml` by default: a `YamlPropertySourceLoader` (`package:yaml`, Dart team) in `ConfigDataEnvironment` — today YAML files are silently ignored unless the application adds a loader.
- [ ] **High.** Location groups (`,` = separate groups, `;` = one group) and the `config/*/` default location. The defaults are two groups (`classpath:/;classpath:/config/` and `file:./;file:./config/;file:./config/*/`); today all act as one, so a packaged `application-prod.properties` beats `./application.properties`.
- [ ] `spring.config.import` from the command line / environment; directory imports; missing non-optional directories fail.
- [ ] `spring.profiles.default` from config files (load `application-{default}.properties`, expand groups).
- [ ] Lenient placeholders in optional imports; command line beats a file's own placeholders in imports and guards.
- [ ] `.properties` beats YAML in the same location; `defaultProperties` stays below config data.
- [ ] Indexed keys (`spring.profiles.include[0]`).
- [ ] Merge programmatic active profiles with the file's `spring.profiles.active`; profile variants of imported files.
- [ ] Encoding option (Latin-1) for `.properties`.
- [ ] `@Value` → `Resource` conversion uses the context's resource loader (protocol resolvers, Flutter assets), not a new `DefaultResourceLoader`.
- [ ] `classpath:` / `classpath*:` patterns in `PathMatchingResourcePatternResolver` over embedded resources.
- [ ] `AntPathMatcher.extractUriTemplateVariables` on backtracking `**` paths; `FileSystemResource` directories.
- [ ] Placeholder parser details (`${a ${b}`, `key:default` tried as a key).
- [ ] Pattern resolver pruning; `file:` URL decoding.
- [ ] Relaxed binding (`${app.my-prop}` finds `app.myProp`), `random.*`, `package:` resources, async `@PropertySource` for Flutter assets.

## Spring Boot (`spring_boot_dart`)

- [ ] **High.** `@ConfigurationProperties`: bind indexed lists (`app.hosts[0]`, `APP_HOSTS_0_`), map entries (`app.headers.*`) and lists/maps of nested objects — today only comma lists bind, the rest stays empty without an error (and YAML lists arrive as indexed keys).
- [ ] **High.** Constructor binding for `@ConfigurationProperties` (final fields, one constructor with parameters) with `@DefaultValue`.
- [ ] **High.** Application events: `ApplicationStartingEvent` … `ApplicationStartedEvent`, `ApplicationReadyEvent`, `ApplicationFailedEvent`; listeners on `SpringApplication` for the early ones.
- [ ] Relaxed names resolved by property source precedence, not by form (today the kebab form wins over a camelCase key in a higher source); accept the underscore form (`app.max_size`).
- [ ] Auto-configuration ordering (`@AutoConfiguration(before:, after:)`, `@AutoConfigureOrder`) and exclusion (`@SpringBootApplication(exclude:)`, `spring.autoconfigure.exclude`).
- [ ] `SpringApplication.exit(context)` with `ExitCodeGenerator` beans; close the context on SIGINT/SIGTERM by default (`spring.main.register-shutdown-hook`).

## SpEL (`expression`)

- [ ] Web: real literals (`7.0 / 2`) and int/double semantics under dart2js.
- [ ] Limits: maximum expression length (10 000), nesting depth, maximum operations per evaluation (10 000, `MAX_OPERATIONS_EXCEEDED`, Spring 6.2.19+), overflow in `'x' * n`; patterns with nested quantifiers (`(a+)+`, the shape of catastrophic backtracking) rejected — Dart's `RegExp` cannot be interrupted the way Spring's `matches` counts accesses. (The regex length limit of 1000 is done.)
- [ ] Subtypes accepted by introspected properties and methods (`#{svc.process(@english)}` with an interface parameter).
- [ ] Deep `==` for collections; `^` saturation like Java; `T(Math)` returning doubles; numeric edge cases.
- [ ] `'d' - 3` is `'a'` (single-character string minus int).
- [ ] `systemEnvironment` / `systemProperties` / `environment.getProperty(...)` in `@Value`; the factory's `ConversionService`.
- [ ] Indexes evaluated against the root; selection result types.
- [ ] Safe navigation per step (Spring 6.2); user exceptions rethrown unwrapped; better diagnostics; caching.
- [ ] Spring's exception layer (`EvaluationException`, `ParseException`), `SpelMessage` names and `EL1xxxE` codes.
- [ ] `SpelParserConfiguration` with 7.0's builder (auto-grow, maximum length and operations), Java type names (`T(Integer)`), varargs, array construction (`new int[4]`), missing String/List/Map methods.
- [ ] Missing APIs: `Expression.getValueType`, `IndexAccessor` (6.2), `ConstructorResolver`, `BeanFactoryAccessor`.

## JSON (`json`, Jackson auto-configuration)

- [ ] Unsupported `spring.jackson.*` keys fail or warn; accept Boot 4's `spring.jackson.datatype.datetime.*`; bean name like Boot (`jacksonJsonMapper`); named time zones (Dart has no tz database: only `UTC` and fixed offsets today).
- [ ] Pick the baseline: Jackson 3 / Boot 4 defaults (properties sorted alphabetically) or Jackson 2 order (superclass first) — and say which; `@JsonPropertyOrder`.

## AOP (`aop`)

- [ ] Proxies for classes with private members, operators or non-literal default values and no interface: the runtime has subclass proxies (`AopProxyFactory.subclass`), the generator must emit them; `final` / `sealed` classes fail the build with a message saying what to change.
- [ ] Argument binding in generated advice (`@annotation(timed)`, `args(id, ..)`, `@AfterReturning(returning:)`): the runtime binds, the generator passes nothing yet; inherited advice.
- [ ] Implicit field getters/setters not advised (explicit getters are methods, which Spring advises).
- [ ] Build-time validation of pointcut expressions; smaller generated code than `aop_proxies: all` without changing its meaning (skip beans no pointcut can match).

## Generator

- [ ] **High.** Full-mode `@Configuration`: a generated subclass whose `@Bean` methods return the container's bean, so `other()` calling `calculator()` gets the singleton; `proxyBeanMethods: false` = today's lite mode; a `final` configuration class fails the build with a clear message.
- [ ] **High.** The same bean name on declarations with conditions (`@Profile('dev')` / `@Profile('prod')` both declaring `dataSource`) must build; leave clashes to the runtime override check.
- [ ] Private types/functions in generated code: clear build errors instead of compile errors.
- [ ] Annotations on primary-constructor fields lost when a library is resolved twice in one build.
- [ ] Inherited `@Bean` methods and mixin lifecycle methods; generic superclasses (`BaseService<R>`).
- [ ] Reject extension types and other unsupported targets (`@ComponentScan` on a class, `@Component` on mixins/enums).
- [ ] Subclasses of `Profile`/`Conditional`; class-level `@Lazy` on lite configuration classes.
- [ ] `@ComponentScan(includeFilters:, excludeFilters:, lazyInit:)`, evaluated at build time.
- [ ] Nested `@ComponentScan` roots duplicating beans; escaping the scan glob; validating explicit names.
- [ ] `@Value` on super-constructor parameters; async `initMethod`/`destroyMethod`; constructor selection like Spring.
- [ ] Warning-free generated code; better error messages (several errors, library URIs).

## HTTP types and annotations (`spring_web_dart`)

- [ ] Optional `path` in `@RequestMapping` / `@GetMapping` / … (`@GetMapping()`), needed by the planned web starter.
- [ ] `required` / `defaultValue` on `@RequestParam` / `@RequestHeader`, `required` on `@PathVariable`.
- [ ] `HttpHeaders`: `toSingleValueMap()` (first value), `setBearerAuth` / `setBasicAuth` / `contentType` / `location` / `contentLength` (if still missing).

## Feign starter

- [ ] **High.** Config keys in camelCase as in the Spring Cloud docs (`readTimeout`, `loggerLevel`, `defaultRequestHeaders`) under `spring.cloud.openfeign.client.config.*` and `spring.websocket.client.config.*` — today silently ignored (part of relaxed binding).

## Scheduling starter

- [ ] `spring.task.scheduling.shutdown.await-termination[-period]`: wait for running tasks on close (needs the asynchronous `closeAsync()` from the context section).
