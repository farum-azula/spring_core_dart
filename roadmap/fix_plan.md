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

- [ ] **High.** `ObjectProvider` injection points: resolve on behalf of the injecting bean (self-reference exclusion, dependent registration) and pass the parameter/field name, like `@Lazy` points — today a `@Primary` decorator or a composite using one ends in a `StackOverflowError`.
- [ ] **High.** `@Bean` definitions carry the type the generator infers from the method body (`DataSource dataSource() => HikariDataSource(url)` is a `HikariDataSource`), with full generic arguments: lookups, `@ConditionalOnBean` / `@ConditionalOnMissingBean` and AOP see the concrete class before the bean exists. Better than Spring, whose definition has no class (`beanClassName` is `null`) and knows only the declared return type until the bean is created — state it as a deliberate difference.
- [ ] Exclude beans produced by a configuration's own `@Bean` methods from its collections (`factoryBeanName`, Spring's `isSelfReference`).
- [ ] Parent contexts: collections should see grandparent beans; keep the parent beans' `@Order` and `autowireCandidate=false`; shadow by `containsLocalBean`.
- [ ] Single dependencies: merge local and parent candidates (parent `@Primary` may win, local wins a tie), pass the parameter name to the parent, validate ambiguity in the parent.
- [ ] `autowireCandidate=false` must be excluded from qualified injection too, without breaking `getBean<T>(qualifier: name)` (Spring's `getBean(name, Class)` returns non-candidates); `getBean<T>()` should still return the only non-candidate bean.
- [ ] `defaultCandidate` (Spring 6.2 `@Bean(defaultCandidate: false)`): injected only where a qualifier selects it; honoured by `@ConditionalOnBean` / `@ConditionalOnMissingBean`.
- [ ] Aliases from `registerAlias` must count for `@Qualifier` and parameter-name matching.
- [ ] `determineAutowireCandidate` details: two `@Primary` beans always ambiguous; parameter name matches bean names/aliases only; Spring 6.2 "qualifier-suggested name" step.
- [ ] Exception hierarchy like Spring: `UnsatisfiedDependencyException` and `BeanCurrentlyInCreationException` extend `BeanCreationException`; `BeanDefinitionOverrideException` extends `BeanDefinitionStoreException`; `BeanIsNotAFactoryException` extends `BeanNotOfRequiredTypeException`.
- [ ] Wrap runtime resolution errors in `UnsatisfiedDependencyException` with the bean chain and injection point.
- [ ] Allow `registerBeanDefinition` / `removeBeanDefinition` after `freezeConfiguration` (in Spring a metadata-cache hint): clear the resolution caches instead of throwing.
- [ ] De-duplicate init/destroy callbacks (`initMethod: 'afterPropertiesSet'` on an `InitializingBean`, inferred `close()` on a `DisposableBean`).
- [ ] Clean dependency bookkeeping on `removeBeanDefinition`; forbid bean creation while singletons are being destroyed.
- [ ] Log destroy-callback errors with `SpringLog` and expose them on the factory interface.
- [ ] Warn when a custom-scoped bean is injected directly into a singleton; scoped proxies.
- [ ] `Map`/`Set` injection in registration order (Spring sorts only `List`); `@Order` on a `@Bean` method beats `Ordered.getOrder()`, a class-level `@Order` does not (track where `BeanDefinition.order` came from).
- [ ] Inject superclass members first, and per class fields before methods (Spring's `buildAutowiringMetadata`).
- [ ] Generic lookups: raw/erased types (`Store<dynamic>`), `Object` lookups returning all beans.
- [ ] `getBeanNamesForType` / `getBeansOfType` for a `FactoryBean` type return `&name`.
- [ ] `getSortedBeans` includes ancestors; `getBeanProvider` streams include `autowireCandidate=false` beans (only injected providers filter).
- [ ] Keep `registerSingleton` objects out of `beanDefinitionNames`; dereference registered `FactoryBean`s.
- [ ] Alias overriding when `allowBeanDefinitionOverriding` is on; dangling alias chains after removal.
- [ ] `ObjectProvider.toString()`/`isEmpty` must not create beans; clearer cycle message for re-entrant `FactoryBean` products.
- [ ] `initializeBean` on `@Configurable` objects runs their `@PostConstruct` (Spring's `CommonAnnotationBeanPostProcessor`).
- [ ] Linear shutdown (destroy order bookkeeping is O(n²)).
- [ ] `@Value` with a custom SpEL template prefix (always delegate to the expression resolver).
- [ ] Missing APIs: `beanNamesForTypeIncludingAncestors`, `destroyBean`, `SmartFactoryBean`, `isFactoryBean`, `isTypeMatch`, annotation lookups (`getBeansWithAnnotation`), `ObjectFactory<T>` / `Provider<T>` (`@Inject`) injection points, `@Resource`.

## Context, events, lifecycle (`context`)

- [ ] Detect `GenericApplicationListener` / `SmartApplicationListener` beans (today they get no events, silently), listeners hidden behind a `@Bean` method's declared type and `registerSingleton` objects; de-duplicate listeners.
- [ ] `Future`-returning `@EventListener`s: republish the result, route errors to the error handler.
- [ ] Programmatic registration: Spring 7's `BeanRegistrar` (`registerBean<T>(name, spec)`) through `@Import` and `context.register(registrar)`, `ImportSelector` / `ImportBeanDefinitionRegistrar`, `registerBean` on the context.
- [ ] Lifecycle: start dependencies first / stop dependents first; stop already started beans when refresh fails.
- [ ] `DefaultLifecycleProcessor` must not create lazy plain `Lifecycle` beans (only created singletons and `SmartLifecycle` beans).
- [ ] `SmartLifecycle` with Spring's defaults (`isAutoStartup` true, `phase` = default phase, `stop(callback)`), e.g. an abstract mixin class.
- [ ] Spring 7 `pause()` / `restart()`: `ContextPausedEvent` / `ContextRestartedEvent`, `LifecycleProcessor.onPause` / `onRestart`, `SmartLifecycle.isPauseable` (maps onto Flutter's paused/resumed).
- [ ] `isActive` during refresh; `close()` from a `ContextRefreshedEvent` listener.
- [ ] `PayloadApplicationEvent<T>` listeners; `@EventListener` / `addListener` parameters typed `Object` get the payload; `Ordered` on listener beans; `@EventListener` methods on `FactoryBean` classes.
- [ ] Early events: replay them when listeners are registered and deliver events published during singleton creation synchronously.
- [ ] Asynchronous delivery: an executor-like option on `SimpleApplicationEventMulticaster` and `@Async` listeners (with the `TaskExecutor` of the scheduling starter).
- [ ] Listener conditions inside the error handler; lifecycle discovery by instance type.
- [ ] Phased creation of post-processors (`PriorityOrdered` → `Ordered` → rest, re-querying names).
- [ ] `ConditionContext` access to the definition being evaluated.
- [ ] `EmbeddedValueResolverAware` evaluating SpEL; descriptive errors for infrastructure misuse; `publishEvent` before refresh or after a failed refresh skips local delivery like Spring 7 instead of throwing (after `close()` already matches).
- [ ] Child message lookups use the parent's message source, not the parent context; unique context ids; `conversionService` from ancestors.
- [ ] Spring names for the bundle message source: `ReloadableResourceBundleMessageSource`, `fallbackToSystemLocale`, `cacheSeconds`; `MessageSourceAccessor`.
- [ ] Template hooks (`postProcessBeanFactory`, `onRefresh`, `onClose`), `registerShutdownHook()`.
- [ ] Asynchronous lifecycle: `refreshAsync()` / `closeAsync()`, async init/destroy and `SmartLifecycle.stop` with per-phase timeouts.

## Configuration (`core`)

- [ ] **High.** Load `application.yml` / `.yaml` by default: a `YamlPropertySourceLoader` (`package:yaml`, Dart team) in `ConfigDataEnvironment` — today YAML files are silently ignored unless the application adds a loader.
- [ ] **High.** Location groups (`,` = separate groups, `;` = one group) and the `config/*/` default location. The defaults are two groups (`classpath:/;classpath:/config/` and `file:./;file:./config/;file:./config/*/`); today all act as one, so a packaged `application-prod.properties` beats `./application.properties`.
- [ ] `spring.config.import` from the command line / environment; directory imports; missing non-optional directories fail.
- [ ] `spring.profiles.default` from config files (load `application-{default}.properties`, expand groups).
- [ ] Lenient placeholders in optional imports; command line beats a file's own placeholders in imports and guards.
- [ ] `.properties` beats YAML in the same location; `defaultProperties` stays below config data.
- [ ] Reject legacy `spring.profiles`; support indexed keys (`spring.profiles.include[0]`); empty `on-profile`.
- [ ] Validate profile names like Boot (letters, digits, `- _ . + @`, starting and ending with a letter or digit; `spring.profiles.validate=false`).
- [ ] Merge programmatic active profiles with the file's `spring.profiles.active`; profile variants of imported files.
- [ ] Encoding option (Latin-1) for `.properties`; `--` end of options on the command line.
- [ ] Prefix-less locations (`app.properties`) resolve against the classpath (`lib/resources/`) in `DefaultResourceLoader` and contexts, not the working directory.
- [ ] `@Value` → `Resource` conversion uses the context's resource loader (protocol resolvers, Flutter assets), not a new `DefaultResourceLoader`.
- [ ] `classpath:` / `classpath*:` patterns in `PathMatchingResourcePatternResolver` over embedded resources.
- [ ] `AntPathMatcher.extractUriTemplateVariables` on backtracking `**` paths; `FileSystemResource` directories.
- [ ] Placeholder parser details (`${a ${b}`, `key:default` tried as a key); `containsProperty` for null values; list values as `a,b`.
- [ ] `Duration` (`P-1D`, ISO output), lenient enum names (`my-value`); pattern resolver pruning; `file:` URL decoding.
- [ ] Relaxed binding (`${app.my-prop}` finds `app.myProp`), `random.*`, `package:` resources, async `@PropertySource` for Flutter assets.

## Spring Boot (`spring_boot_dart`)

- [ ] **High.** `@ConfigurationProperties`: bind indexed lists (`app.hosts[0]`, `APP_HOSTS_0_`), map entries (`app.headers.*`) and lists/maps of nested objects — today only comma lists bind, the rest stays empty without an error (and YAML lists arrive as indexed keys).
- [ ] **High.** Constructor binding for `@ConfigurationProperties` (final fields, one constructor with parameters) with `@DefaultValue`.
- [ ] **High.** Application events: `ApplicationStartingEvent` … `ApplicationStartedEvent`, `ApplicationReadyEvent`, `ApplicationFailedEvent`; listeners on `SpringApplication` for the early ones.
- [ ] Relaxed names resolved by property source precedence, not by form (today the kebab form wins over a camelCase key in a higher source); accept the underscore form (`app.max_size`).
- [ ] Auto-configuration ordering (`@AutoConfiguration(before:, after:)`, `@AutoConfigureOrder`) and exclusion (`@SpringBootApplication(exclude:)`, `spring.autoconfigure.exclude`).
- [ ] Validate `@ConfigurationProperties` only when asked (Boot: `@Validated`); today always.
- [ ] Auto-configure a `Validator` bean (`BeanValidator` on the context's introspector) and `methodValidationPostProcessor`, like Boot's `ValidationAutoConfiguration`.
- [ ] Failure analyzers from starters (a `FailureAnalyzer` interface; today a closed `switch`).
- [ ] `SpringApplication.exit(context)` with `ExitCodeGenerator` beans; close the context on SIGINT/SIGTERM by default (`spring.main.register-shutdown-hook`).
- [ ] Startup info through `SpringLog` at INFO ("Starting …", active profiles, "Started … in … seconds"), so it follows the pattern, file and levels.
- [ ] `spring.main.lazy-initialization`, `spring.main.allow-bean-definition-overriding`.
- [ ] Dotted basenames in `spring.messages.basename` (`config.i18n.messages`).

## SpEL (`expression`)

- [ ] `SimpleEvaluationContext` forbids variable assignment (`#v = …`, `#v++`) through `EvaluationContext.assignVariable` (Spring's EL1080E) — it matters for untrusted input.
- [ ] Web: real literals (`7.0 / 2`) and int/double semantics under dart2js.
- [ ] Limits: maximum expression length (10 000), nesting depth, maximum operations per evaluation (10 000, `MAX_OPERATIONS_EXCEEDED`, Spring 6.2.19+), overflow in `'x' * n`; patterns with nested quantifiers (`(a+)+`, the shape of catastrophic backtracking) rejected — Dart's `RegExp` cannot be interrupted the way Spring's `matches` counts accesses. (The regex length limit of 1000 is done.)
- [ ] Subtypes accepted by introspected properties and methods (`#{svc.process(@english)}` with an interface parameter).
- [ ] Deep `==` for collections; `^` saturation like Java; `T(Math)` returning doubles; numeric edge cases.
- [ ] `+` and template parts convert non-strings with the context's `TypeConverter` (`'a' + {1,2}` is `a1,2`).
- [ ] Enums of one type compare by index; selection criteria must be boolean; `'d' - 3` is `'a'`.
- [ ] `systemEnvironment` / `systemProperties` / `environment.getProperty(...)` in `@Value`; the factory's `ConversionService`.
- [ ] Map selection `.^[`/`.$[` returning `null`; indexes evaluated against the root; selection result types.
- [ ] Safe navigation per step (Spring 6.2); user exceptions rethrown unwrapped; better diagnostics; caching.
- [ ] Spring's exception layer (`EvaluationException`, `ParseException`), `SpelMessage` names and `EL1xxxE` codes.
- [ ] `SpelParserConfiguration` with 7.0's builder (auto-grow, maximum length and operations), Java type names (`T(Integer)`), varargs, array construction (`new int[4]`), missing String/List/Map methods.
- [ ] Missing APIs: `Expression.getValueType`, `IndexAccessor` (6.2), `ConstructorResolver`, `BeanFactoryAccessor`.

## JSON (`json`, Jackson auto-configuration)

- [ ] **High.** Write local `DateTime`s with their offset (or in UTC) like Jackson's `Instant` / `OffsetDateTime`; `spring.jackson.time-zone` — today `2026-01-01T12:00:00.000` without a zone, which a Spring `Instant` field rejects.
- [ ] Register `JsonSerializer` / `JsonDeserializer` beans in the auto-configured mapper (Boot's `@JsonComponent` / `@JacksonComponent`), as their docs promise.
- [ ] Unsupported `spring.jackson.*` keys fail or warn; accept Boot 4's `spring.jackson.datatype.datetime.*`; bean name like Boot (`jacksonJsonMapper`).
- [ ] Naming strategies keep acronyms like Jackson (`myURLValue` → `my_urlvalue`).
- [ ] Pick the baseline: Jackson 3 / Boot 4 defaults (properties sorted alphabetically) or Jackson 2 order (superclass first) — and say which; `@JsonPropertyOrder`.
- [ ] `readValue<Map<String, dynamic>>` / `readValue<List<dynamic>>` without a `TypeInfo`.
- [ ] `NaN` / `Infinity` written as strings (Jackson's default) instead of throwing.

## AOP (`aop`)

- [ ] Proxies for classes with private members, operators or non-literal default values and no interface: the runtime has subclass proxies (`AopProxyFactory.subclass`), the generator must emit them; `final` / `sealed` classes fail the build with a message saying what to change.
- [ ] `@AfterReturning(Object result)` on `void` methods.
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
- [ ] Spring's `headers: ['Name=value']` syntax in mapping annotations (today only Feign's `Name: value`).
- [ ] `required` / `defaultValue` on `@RequestParam` / `@RequestHeader`, `required` on `@PathVariable` / `@RequestBody`; `@CookieValue`.
- [ ] `HttpHeaders` like Spring 7: `forEach((name, values))`, `toSingleValueMap()` (first value), `setBearerAuth` / `setBasicAuth` / `contentType` / `location`; `HttpStatus` with all constants (7.0 names: `unprocessableContent`, `contentTooLarge`), `is2xxSuccessful`-style helpers, `series`.
- [ ] Spring's WebSocket names: the connection is a `WebSocketSession` (`sendMessage`, `acceptedProtocol`), `WebSocketStatus` → `CloseStatus` with Spring's constants; the starter's reconnecting session gets another name (`WebSocketConnectionManager`).

## Feign starter

- [ ] **High.** `Map` parameters of `@RequestParam` / `@RequestHeader` expand into one query parameter / header per entry (today they are sent as JSON); other object values fail at startup.
- [ ] **High.** Config keys in camelCase as in the Spring Cloud docs (`readTimeout`, `loggerLevel`, `defaultRequestHeaders`) under `spring.cloud.openfeign.client.config.*` and `spring.websocket.client.config.*` — today silently ignored (part of relaxed binding).
- [ ] `RequestInterceptor`s run on every retry, from a fresh template (a refreshed token reaches the retry).
- [ ] Default `connect-timeout` 10 s and `read-timeout` 60 s like Feign's `Request.Options()`; `read-timeout` as time without data, not a deadline for the whole call.
- [ ] `/` kept in `@PathVariable` values (Spring Cloud's `decode-slash`, default true).
- [ ] `@FeignClient` attributes `dismiss404`, `contextId`, `qualifiers`, `primary`; `default-query-parameters`, `follow-redirects`.
- [ ] `dismiss404` keeps throwing for `void` methods, like Feign.
- [ ] `RequestTemplate.header` appends like Feign; `Retry-After` as an HTTP date; `ERROR` / `RETRYING` log lines only above `logger-level: none`.

## WebSocket starter

- [ ] Reconnect with jitter and a multiplier, named like Spring 7's `RetryPolicy` (`delay`, `multiplier`, `max-delay`, `jitter`, `max-retries`).

## Scheduling starter

- [ ] `spring.task.scheduling.shutdown.await-termination[-period]`: wait for running tasks on close.

## Docs: differences to state

Until fixed, or by design, these belong in the packages' "Differences
from Spring" sections:

- [ ] `spring_core_dart`: refresh validates lazy beans, prototypes and `@Lazy` points too; `@Bean` beans match the type inferred from the method body from the start (Spring: the declared type until the bean is created); `getBean` returns `registerResolvableDependency` values; custom qualifiers match by value only; listener conditions are functions; no async multicaster, stop timeouts or shutdown hook; events published during refresh arrive after all singletons exist; `@Import` takes classes only, imported classes get simple names; default context id `application`; bundles: no reload, UTF-8 only; SpEL: the `T()` registry and Dart type names, accessors on by default in `SimpleEvaluationContext`, `?.` short-circuits the whole chain, mutable inline lists; regular expressions are Dart's `RegExp` and String methods are Dart's (`replaceAll` with a string is literal); JSON: enums by Dart name (`inStock`), `BigInt` as strings, non-nullable types reject `null`; AOP: `@annotation` also matches interface methods, `@Configuration` classes are never proxied, `@AfterReturning(String result)` skips `null`.
- [ ] `spring_boot_dart`: plain resource paths are files; config precedence across the default locations; comma lists only; YAML needs a loader; `spring.messages.default-locale` is not Boot's; the startup line format.
- [ ] `spring_web_dart`: a "Differences" section for the HTTP types: `headers` syntax, single-valued `produces` / `consumes`, required `path`, whole-call timeout, `toMap` joins values, `HttpMethod.parse` throws on unknown methods.
- [ ] Feign: default `Accept: application/json`, spaces as `+`, masked `Authorization` in logs, logger names `feign.<Interface>`.
