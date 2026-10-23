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
Feign and WebSocket items except optional paths. Third batch: YAML out of
the box, location groups and `config/*/`, relaxed binding in the
environment (camelCase Feign/WebSocket keys), `@ConfigurationProperties`
lists, maps and constructor binding, application events, full-mode
`@Configuration`, conditional beans sharing a name, inferred `@Bean` types.

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

- [ ] Exclude beans produced by a configuration's own `@Bean` methods from its collections (`factoryBeanName`, Spring's `isSelfReference`).
- [ ] Parent contexts: collections should see grandparent beans; keep the parent beans' `@Order` and `autowireCandidate=false`; shadow by `containsLocalBean`.
- [ ] Single dependencies: merge local and parent candidates (parent `@Primary` may win, local wins a tie), pass the parameter name to the parent, validate ambiguity in the parent.
- [ ] `defaultCandidate` honoured by `@ConditionalOnBean` / `@ConditionalOnMissingBean` (the definition and injection already follow Spring 6.2).
- [ ] `determineAutowireCandidate` details: two `@Primary` beans always ambiguous; parameter name matches bean names/aliases only; Spring 6.2 "qualifier-suggested name" step.
- [ ] Clean dependency bookkeeping on `removeBeanDefinition`; forbid bean creation while singletons are being destroyed.
- [ ] Warn when a custom-scoped bean is injected directly into a singleton; scoped proxies.
- [ ] Generic lookups: `Object` lookups returning all beans.
- [ ] Dereference registered `FactoryBean`s (`registerSingleton`).
- [ ] Alias overriding when `allowBeanDefinitionOverriding` is on; dangling alias chains after removal.
- [ ] Clearer cycle message for re-entrant `FactoryBean` products.
- [ ] Linear shutdown (destroy order bookkeeping is O(n²)).
- [ ] `@Value` with a custom SpEL template prefix (always delegate to the expression resolver).
- [ ] Missing APIs: `beanNamesForTypeIncludingAncestors`, `destroyBean`, `SmartFactoryBean`, `isTypeMatch`, annotation lookups (`getBeansWithAnnotation`), `Provider<T>` (`@Inject`) injection points, `@Resource`.

## Context, events, lifecycle (`context`)

- [ ] Programmatic registration: Spring 7's `BeanRegistrar` (`registerBean<T>(name, spec)`) through `@Import` and `context.register(registrar)`, `ImportSelector` / `ImportBeanDefinitionRegistrar`, `registerBean` on the context.
- [ ] Spring 7 `pause()` / `restart()`: `ContextPausedEvent` / `ContextRestartedEvent`, `LifecycleProcessor.onPause` / `onRestart`, `SmartLifecycle.isPauseable` (maps onto Flutter's paused/resumed).
- [ ] `PayloadApplicationEvent<T>` listeners; `@EventListener` methods on `FactoryBean` classes.
- [ ] Asynchronous delivery: an executor-like option on `SimpleApplicationEventMulticaster` and `@Async` listeners (with the `TaskExecutor` of the scheduling starter).
- [ ] Listener conditions inside the error handler; lifecycle discovery by instance type.
- [ ] Phased creation of post-processors (`PriorityOrdered` → `Ordered` → rest, re-querying names).
- [ ] `ConditionContext` access to the definition being evaluated.
- [ ] `EmbeddedValueResolverAware` evaluating SpEL; descriptive errors for infrastructure misuse.
- [ ] Child message lookups use the parent's message source, not the parent context; `conversionService` from ancestors.
- [ ] Template hooks (`postProcessBeanFactory`, `onRefresh`, `onClose`), `registerShutdownHook()`.

## Configuration (`core`)

- [ ] Lenient placeholders in optional imports; command line beats a file's own placeholders in imports and guards.
- [ ] Indexed keys (`spring.profiles.include[0]`).
- [ ] Encoding option (Latin-1) for `.properties`.
- [ ] `classpath:` / `classpath*:` patterns in `PathMatchingResourcePatternResolver` over embedded resources.
- [ ] `AntPathMatcher.extractUriTemplateVariables` on backtracking `**` paths; `FileSystemResource` directories.
- [ ] Placeholder parser details (`${a ${b}`, `key:default` tried as a key).
- [ ] Pattern resolver pruning; `file:` URL decoding.
- [ ] `random.*`, `package:` resources, async `@PropertySource` for Flutter assets; a non-optional `config/*/` location without subdirectories fails.


## SpEL (`expression`)

- [ ] Web: real literals (`7.0 / 2`) and int/double semantics under dart2js.
- [ ] Subtypes accepted by introspected properties and methods (`#{svc.process(@english)}` with an interface parameter).
- [ ] Deep `==` for collections; `^` saturation like Java; `T(Math)` returning doubles; numeric edge cases.
- [ ] `'d' - 3` is `'a'` (single-character string minus int).
- [ ] Indexes evaluated against the root; selection result types.
- [ ] Java type names (`T(Integer)`), array construction (`new int[4]`), missing String/List/Map methods.
- [ ] Missing APIs: `Expression.getValueType`, `IndexAccessor` (6.2).

## JSON (`json`, Jackson auto-configuration)

- [ ] Unsupported `spring.jackson.*` keys fail or warn; accept Boot 4's `spring.jackson.datatype.datetime.*`; bean name like Boot (`jacksonJsonMapper`); named time zones (Dart has no tz database: only `UTC` and fixed offsets today).

## AOP (`aop`)

- [ ] Implicit field getters/setters not advised (explicit getters are methods, which Spring advises).
- [ ] Build-time validation of pointcut expressions; smaller generated code than `aop_proxies: all` without changing its meaning (skip beans no pointcut can match).

## Generator

- [ ] Annotations on primary-constructor fields lost when a library is resolved twice in one build.
- [ ] Reject extension types and other unsupported targets (`@ComponentScan` on a class, `@Component` on mixins/enums).
- [ ] Subclasses of `Profile`/`Conditional`; class-level `@Lazy` on lite configuration classes.
- [ ] Nested `@ComponentScan` roots duplicating beans; escaping the scan glob; validating explicit names.
- [ ] `@Value` on super-constructor parameters; constructor selection like Spring.
- [ ] Warning-free generated code; better error messages (several errors, library URIs).
- [ ] `build_runner watch` while typing: a library with syntax errors must not fail the build and lose the generated `*.beans.dart` (build_runner deletes the outputs of a failed step); keep the previous output and report the parse error once, so a large project is not red and rebuilt on every keystroke.

