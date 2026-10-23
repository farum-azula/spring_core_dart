## Unreleased

- AOP: `Type+` subtype patterns in `within` / `execution`, `@target`, `this`, `args(...)`; `bean()` also matches aliases and qualifier values
- AOP: named pointcuts resolved per aspect (`orders()` in its own aspect, `AuditAspect.orders()` for another's)
- AOP: aspects ordered by `Ordered` as well as `@Order`; plain `Advisor` beans; aspects and advisors of parent contexts apply
- AOP: `AopContext.currentProxy()`; the auto proxy creator runs first among ordered post-processors (later post-processors see the proxy)
- AOP: `JoinPoint.args` is a copy, `proceed(args)` checks the argument count; async non-around advice is awaited on `Future` methods and rejected on synchronous ones
- AOP runtime: advice binding (`@annotation(timed)`, `args(id, ..)`, `@AfterReturning(returning:)`, `@AfterThrowing(throwing:)`) and subclass proxies (`AopProxyFactory.subclass`); the generator does not emit them yet
- breaking: `@PastDate`, `@PastOrPresentDate`, `@FutureOrPresentDate` are renamed to Jakarta's `@Past`, `@PastOrPresent`, `@FutureOrPresent` (`@FutureDate` stays: `@Future` clashes with Dart's `Future`)
- validation: `DecimalMin` / `DecimalMax`, `BigInt` and numeric strings in number constraints, `@Digits` like `BigDecimal`, Hibernate's `@Email`, `@NotBlank` trimming like Java, `@Pattern` flags, date-only values and an injectable clock (`ClockProvider`)
- validation: method validation (`@Validated`, `MethodValidationPostProcessor`, `ConstraintViolationException`); class-level violations on a property; `{key}` messages from a `MessageSource`; shared `@Valid` objects validated on every path
- binding: no constraint error on top of a binding failure; `DataBinder.construct` (constructor binding); collection auto-grow and element/key conversion in `BeanWrapper`; full `DefaultMessageCodesResolver` codes and Spring's error arguments
- messages: the parent `MessageSource` gets resolved arguments; locales with a script (`zh_Hant_TW`); basename-by-basename lookup; `MessageFormat` details (quotes, lone `}`, negative subpatterns, HALF_EVEN, locale symbols)

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

- `ClasspathResources.registerAll(owner:)`: a module registering again (after a hot reload) replaces its own embedded files; `BeanModule` passes its name.
- Example guide on pub.dev (`example/README.md`): every feature in short blocks with the annotations to write.

## 0.1.0

- `Advised` members are `aopTarget` and `aopAdvisors` (were `targetObject`
  and `advisors`), so domain methods named `advisors` can be proxied.
- `AopProxyFactory.unavailable` and `AopConfigException`: advice that
  matches a bean the generator could not proxy fails the startup with the
  reason instead of being skipped silently.
- `DataBinder.bind`: malformed keys (`items[`, `a..b`) are skipped like
  unknown fields (`InvalidPropertyException` when `ignoreUnknownFields` is
  off); setters that throw become `methodInvocation` field errors
  (`MethodInvocationException`), and binding continues.
- Config data: `spring.profiles.include` profiles come before the active
  ones, so `application-{active}` files override included profile files,
  as in Spring Boot.
- `@Lazy` on injection points (constructor parameters, fields, setters):
  a generated lazy proxy resolves the bean on every call, on behalf of the
  injecting bean (self-exclusion still applies). Breaks cycles and allows
  self-injection through the AOP proxy. `Dependency.lazy` is validated at
  refresh like a single dependency but is not an edge of the cycle check;
  `DependencyResolver.lazyDependency`.
- Lookups are cached per requester once the factory is frozen.
- `ClasspathResources.addDirectory`: directories searched before the
  embedded `lib/resources/` files (the test classpath).
- `SpringLog` is the logging facade of the family: per-logger levels
  inherited by dots (`setLevel`, `levelOf`), lazy messages
  (`log.debug(() => ...)`), structured `fields`, zone-scoped context
  (`SpringLog.withFields`, like MDC), `listen` for extra listeners, and
  records with `time` and `sequence`. `parseSpringLogLevel` reads property
  values.
- A bean is no longer injected into itself: `@Primary` composites and
  decorators receive the other beans of their type (Spring's
  self-reference rule).
- `@PropertySource` declarations carry the declaring class's conditions and
  are loaded only when they match.
- Config data: documents guarded by `spring.config.activate.on-profile`
  (including negated guards such as `!prod`) are evaluated only once the
  profiles are known; relative import cycles terminate.
- `close()` is exception-safe and re-entrant like Spring's `doClose`: a
  failing `ContextClosedEvent` listener or lifecycle bean is logged and the
  shutdown continues.
- Events published during `refresh()` reach the parent context once.
- Bean Validation messages are shown as written (no `MessageFormat`
  mangling of `can't` or `[A-Z]{2,3}`) unless they contain `{0}`
  placeholders; invalid `MessageFormat` patterns are returned raw.
- `DataBinder` canonicalizes property names (`roles['admin']` →
  `roles[admin]`) and matches `disallowedFields` case-insensitively, also
  against dotted map access.
- AOP: `@annotation` / `@within` match generated annotation names, so they
  work in minified and obfuscated release builds; package-qualified
  wildcards and argument binding are rejected instead of matching every or
  no bean.
- `ConditionGroup`: a configuration class's conditions are evaluated once
  for the class, its `@Bean` methods and property sources (all or nothing).
- Type index like Spring's `allBeanNamesByType` (cleared when definitions
  change) and a cache of resolved lookups once the configuration is frozen:
  `getBean<T>()` no longer scans every definition (~0.1 µs regardless of the
  number of beans).
- New `SpringLog` logger for problems the framework recovers from.
- `classpath:` resources: files of `lib/resources/` embedded by the
  generator (`BeanModule.resources`, `ClasspathResources`), read from disk
  as a fallback; config data looks in `classpath:/` and `classpath:/config/`
  first; `@Value('classpath:...') Resource` injection.


Initial release.

- IoC container: `ApplicationContext`, `DefaultListableBeanFactory`, bean
  definitions, singleton / prototype / custom scopes, lazy beans,
  `@Primary` / `@Fallback` / `@Qualifier`, collection and `ObjectProvider`
  injection, `FactoryBean`, aware and lifecycle callbacks, bean
  (factory) post-processors, `Lifecycle` / `SmartLifecycle`, parent
  contexts, bean graph validation at refresh.
- Annotations for `spring_core_dart_generator`: stereotypes,
  `@Configuration` / `@Bean`, `@Autowired`, `@Value`, `@PostConstruct` /
  `@PreDestroy`, `@Profile`, `@Conditional`, `@Import`, `@PropertySource`,
  `@EventListener`, `@Configurable`, `@Introspected`, AOP annotations.
- Environment: property sources, `${...}` placeholders, profiles and profile
  expressions, command-line arguments, `application.properties` config data
  with profile files, multi-document files and imports.
- Type conversion, resources and `AntPathMatcher`, `.properties` parser.
- Events, `MessageSource` with `MessageFormat`.
- SpEL: parser, evaluation contexts, templates, `#{...}` in `@Value`.
- Validation and data binding: constraints, `BeanValidator`, `DataBinder`,
  Spring message codes.
- AOP: aspects, advice, pointcut expressions, advisors, generated proxies.
