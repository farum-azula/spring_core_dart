## Unreleased

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

## 0.1.0

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
