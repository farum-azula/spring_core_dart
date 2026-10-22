# Fix plan

Findings of a review against Spring Framework 6.2 / Spring Boot 3 that are
still open. Already fixed (with regression tests): Dart default values of
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
and the order of `spring.profiles.include`.

## Container (`beans`)

- [ ] Exclude beans produced by a configuration's own `@Bean` methods from its collections (`factoryBeanName`, Spring's `isSelfReference`).
- [ ] Parent contexts: collections should see grandparent beans; keep the parent beans' `@Order`, qualifiers and `autowireCandidate=false`; shadow by `containsLocalBean`.
- [ ] Single dependencies: merge local and parent candidates (parent `@Primary` may win), pass the parameter name to the parent, validate ambiguity in the parent.
- [ ] `autowireCandidate=false` must be excluded from qualified injection too; `getBean<T>()` should still return the only non-candidate bean.
- [ ] Aliases from `registerAlias` must count for `@Qualifier` and parameter-name matching.
- [ ] `determineAutowireCandidate` details: two `@Primary` beans always ambiguous; parameter name matches bean names/aliases only; Spring 6.2 "qualifier-suggested name" step.
- [ ] De-duplicate init/destroy callbacks (`initMethod: 'afterPropertiesSet'` on an `InitializingBean`, inferred `close()` on a `DisposableBean`).
- [ ] Clean dependency bookkeeping on `removeBeanDefinition`; forbid bean creation while singletons are being destroyed.
- [ ] Log destroy-callback errors with `SpringLog` and expose them on the factory interface.
- [ ] Warn when a custom-scoped bean is injected directly into a singleton; scoped proxies.
- [ ] Wrap runtime resolution errors in `UnsatisfiedDependencyException` with the bean chain and injection point.
- [ ] `Map`/`Set` injection in registration order (Spring sorts only `List`); definition `@Order` beats `Ordered.getOrder()`.
- [ ] Generic lookups: raw/erased types (`Store<dynamic>`), `Object` lookups returning all beans.
- [ ] Keep `registerSingleton` objects out of `beanDefinitionNames`; dereference registered `FactoryBean`s.
- [ ] Alias overriding when `allowBeanDefinitionOverriding` is on; dangling alias chains after removal.
- [ ] `ObjectProvider.toString()`/`isEmpty` must not create beans; clearer cycle message for re-entrant `FactoryBean` products.
- [ ] Linear shutdown (destroy order bookkeeping is O(n²)).
- [ ] `@Value` with a custom SpEL template prefix (always delegate to the expression resolver).
- [ ] Missing APIs: `beanNamesForTypeIncludingAncestors`, `destroyBean`, `SmartFactoryBean`, `isFactoryBean`, `isTypeMatch`, annotation lookups (`getBeansWithAnnotation`).

## Context, events, lifecycle (`context`)

- [ ] `Future`-returning `@EventListener`s: republish the result, route errors to the error handler.
- [ ] Detect listener beans created by `@Bean` methods or `registerSingleton`; de-duplicate listeners.
- [ ] Lifecycle: start dependencies first / stop dependents first; stop already started beans when refresh fails.
- [ ] `isActive` during refresh; `close()` from a `ContextRefreshedEvent` listener.
- [ ] `PayloadApplicationEvent<T>` listeners; `Ordered` on listener beans; `@EventListener` methods on `FactoryBean` classes.
- [ ] Listener conditions inside the error handler; lifecycle discovery by instance type.
- [ ] Phased creation of post-processors (`PriorityOrdered` → `Ordered` → rest, re-querying names).
- [ ] `ConditionContext` access to the definition being evaluated (auto-configuration ordering exists in `spring_boot_dart`).
- [ ] `EmbeddedValueResolverAware` evaluating SpEL; descriptive errors for infrastructure misuse; `publishEvent` after `close()` throws.
- [ ] Child message lookups use the parent's message source, not the parent context; unique context ids; `conversionService` from ancestors.
- [ ] Template hooks (`postProcessBeanFactory`, `onRefresh`, `onClose`), `registerShutdownHook()`.
- [ ] Asynchronous lifecycle: `refreshAsync()` / `closeAsync()`, async init/destroy and `SmartLifecycle.stop` with per-phase timeouts.

## Configuration (`core`)

- [ ] Location groups (`,` = separate groups, `;` = one group) and the `config/*/` default location.
- [ ] `spring.config.import` from the command line / environment; directory imports; missing non-optional directories fail.
- [ ] `spring.profiles.default` from config files (load `application-{default}.properties`, expand groups).
- [ ] Lenient placeholders in optional imports; command line beats a file's own placeholders in imports and guards.
- [ ] `.properties` beats YAML in the same location; `defaultProperties` stays below config data.
- [ ] Reject legacy `spring.profiles`; support indexed keys (`spring.profiles.include[0]`); empty `on-profile`.
- [ ] Merge programmatic active profiles with the file's `spring.profiles.active`; profile variants of imported files.
- [ ] Encoding option (Latin-1) for `.properties`; `--` end of options on the command line.
- [ ] `AntPathMatcher.extractUriTemplateVariables` on backtracking `**` paths; `FileSystemResource` directories.
- [ ] Placeholder parser details (`${a ${b}`, `key:default` tried as a key); `containsProperty` for null values; list values as `a,b`.
- [ ] `Duration` (`P-1D`, ISO output), lenient enum names (`my-value`); pattern resolver pruning; `file:` URL decoding.
- [ ] Relaxed binding (`${app.my-prop}` finds `app.myProp`), `random.*`, `package:` resources, async `@PropertySource` for Flutter assets.

## SpEL (`expression`)

- [ ] Web: real literals (`7.0 / 2`) and int/double semantics under dart2js.
- [ ] Limits: maximum expression length and nesting depth, regex length 256, overflow in `'x' * n`, catastrophic regexes.
- [ ] Subtypes accepted by introspected properties and methods (`#{svc.process(@english)}` with an interface parameter).
- [ ] `split`/`replaceAll` as regular expressions; Java regex syntax (`(?i)`, `\p{Alpha}`, `\A`).
- [ ] Deep `==` for collections; `^` saturation like Java; `T(Math)` returning doubles; numeric edge cases.
- [ ] `systemEnvironment` / `systemProperties` / `environment.getProperty(...)` in `@Value`; the factory's `ConversionService`.
- [ ] Map selection `.^[`/`.$[` returning `null`; indexes evaluated against the root; selection result types.
- [ ] Safe navigation per step (Spring 6.2); user exceptions rethrown unwrapped; better diagnostics; caching.
- [ ] Parser configuration (auto-grow), Java type names (`T(Integer)`), varargs, missing String/List/Map methods.

## Validation, binding, messages (`validation`)

- [ ] No constraint error on top of a binding failure (`typeMismatch` only).
- [ ] Collection auto-grow and element/key conversion in `BeanWrapper`.
- [ ] Full `DefaultMessageCodesResolver` codes (`NotBlank.city` for `address.city`) and Spring's error arguments.
- [ ] `BigInt` and numeric strings in `@Min`/`@Positive`/...; correct `@Digits`; Hibernate's `@Email`; `NotBlank` whitespace.
- [ ] Parent `MessageSource` with resolved arguments; locales with a script (`zh_Hant_TW`); basename-by-basename lookup.
- [ ] `@Valid` validating shared objects on every path; the most specific introspection for subclasses.
- [ ] Date constraints for date-only values, injectable clock; `getFieldValue` returning the rejected value.
- [ ] `MessageFormat` details (lone `}`, negative subpatterns, quoted literals, HALF_EVEN, locale symbols).
- [ ] Class-level violations attached to a property; `{key}` messages from a `MessageSource`; `DecimalMin`/`DecimalMax`.

## AOP (`aop`)

- [ ] Proxies for classes with private members, operators or non-literal default values and no interface (today: a clear startup error when advice matches such a bean, instead of skipping it).
- [ ] Named pointcuts resolved per aspect; advisor beans that depend on proxied beans; plain `Advisor` beans; ancestor contexts' advisors.
- [ ] `@AfterReturning(Object result)` on `void` methods; `Future` methods throwing synchronously; async non-around advice; `FutureOr`.
- [ ] Argument binding (`@annotation(timed)`, `args(...)`); inherited advice; pointcut holder classes.
- [ ] `JoinPoint.args` as a copy and validated `proceed(args)`; `Ordered` aspects; getters/setters not advised by default.
- [ ] Build-time validation of pointcut expressions; a smaller default than `aop_proxies: all`; `AopContext.currentProxy()`.

## Generator

- [ ] Private types/functions in generated code: clear build errors instead of compile errors.
- [ ] Annotations on primary-constructor fields lost when a library is resolved twice in one build.
- [ ] Inherited `@Bean` methods and mixin lifecycle methods; generic superclasses (`BaseService<R>`).
- [ ] Reject extension types and other unsupported targets (`@ComponentScan` on a class, `@Component` on mixins/enums).
- [ ] Subclasses of `Profile`/`Conditional`; class-level `@Lazy` on lite configuration classes.
- [ ] Nested `@ComponentScan` roots duplicating beans; escaping the scan glob; validating explicit names.
- [ ] `@Value` on super-constructor parameters; async `initMethod`/`destroyMethod`; constructor selection like Spring.
- [ ] Warning-free generated code; better error messages (several errors, library URIs).
