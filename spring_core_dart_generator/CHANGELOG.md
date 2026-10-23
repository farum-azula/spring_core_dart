## 0.1.7

- an error in the sources never removes or changes an existing `*.beans.dart` (`build_runner watch` while typing no longer deletes and regenerates it on every keystroke): while a scanned library has syntax errors the builder skips generation, writes the existing file again unchanged and logs one warning per output until the next successful generation; a generator error (private type, unknown bean, bad annotation, cycle, ...) keeps the file too and is reported with `log.severe`, so `build_runner build` still fails; without an existing output (a cold build) both fail as before. `SpringBuilder` takes an optional `readExistingOutput` (tests inject it) and its constructor is no longer `const`
- `@ComponentScan(includeFilters:, excludeFilters:, useDefaultFilters:, lazyInit:)` evaluated at build time: `Filter` by annotation (also its subclasses), assignable type or a regex on the class name makes classes beans without `@Component` (abstract ones skipped) or keeps them out (excludes win); `useDefaultFilters: false` scans only the includes; `lazyInit: true` makes every scanned bean (components and their `@Bean` methods) lazy unless `@Lazy(false)`; a filter without the argument its type uses or with an invalid pattern fails the build (needs the matching `spring_core_dart`)
- `@Bean` methods, `@Autowired` members, `@PostConstruct` / `@PreDestroy` and `@EventListener` methods of superclasses and mixins are found (Spring scans the hierarchy; mixin lifecycle methods run in Dart's linearization order); the members of a generic superclass (`UserService extends BaseService<User>`) get the type arguments substituted; an inherited static `@Bean` method is called on its declaring class; an override without `@Bean` of an annotated superclass method still creates the bean
- breaking: a private bean class, `@Bean` return type, injected type (also as a type argument), event type or default value (a private function, class or constructor) fails the build with a message naming the declaration, its library and the fix, instead of a generated file that does not compile; the full-mode `@Configuration` errors no longer suggest `proxyBeanMethods: false` for private types (it would not help)
- AOP argument binding: an advice parameter named in the pointcut (`@annotation(timed)`, `@within(timed)`, `@target(timed)`, `this(proxy)`, `target(bean)`, `args(id, ..)`) receives the bound value, checked against its type; `@AfterReturning(returning:)` / `@AfterThrowing(throwing:)` name the value parameter; advice and `@Pointcut` methods of an aspect's superclasses and mixins are inherited; a parameter the pointcut does not bind, or a bound name without a parameter, fails the build (needs the matching `spring_core_dart`)
- breaking: subclass AOP proxies (`aop_proxies: all`): a component class that cannot be implemented (private members, operators, `base`) and has no interface is created as a generated subclass that runs advice (`AopProxyFactory.subclass`); one that cannot be extended either (`final`, `sealed`, `interface`, factory constructor) fails the build saying what to change, instead of failing at startup when advice matches; a `@Bean` method's type still keeps its signatures
- proxies copy constant default values that are not literals (`const Duration(seconds: 1)`, enum values, top-level constants) instead of refusing the bean
- `@PostConstruct` / `@PreDestroy` methods and `@Bean(initMethod:, destroyMethod:)` may return a `Future` (awaited by the context's `refreshAsync()` / `closeAsync()`): their callbacks are written as `async` closures (needs the matching `spring_core_dart`); those of a `@Configurable` stay synchronous
- breaking: full-mode `@Configuration` (Spring's default `proxyBeanMethods = true`): the configuration bean is a generated subclass whose instance `@Bean` methods return the container's bean, so a `@Bean` method calling another one gets the singleton (a prototype: a new instance; arguments of the call are used when it creates the bean, like Spring's `getBean(name, args)`); static methods are not intercepted. A class with instance `@Bean` methods that another library cannot extend (`final`, `sealed`, `interface`, factory or private constructor, private parameter types) fails the build: change it or use `@Configuration(proxyBeanMethods: false)` (needs the matching `spring_core_dart`)
- `@Bean` types inferred from the method body: the static type of the returned expression(s) (with type arguments; several returns: their common supertype) registers the definition under the concrete class and its supertypes as well as the declared type, so lookups, `@ConditionalOnBean` / `@ConditionalOnMissingBean`, lifecycle methods and AOP proxies see it before the bean exists
- declarations with conditions (`@Profile`, `@Conditional`, `@ConditionalOn...`) may share a bean name (`dataSource` in a dev and a prod configuration); only two unconditional declarations of one name fail the build, the container's override check reports both matching at refresh
- breaking: a `@ConfigurationProperties` class whose only public generative constructor has parameters is created by `ConstructorBound.from` (Spring Boot's constructor binding: parameters bound from properties) instead of getting beans injected; its introspection uses that constructor (needs the matching `spring_boot_dart`)
- breaking: a constraint on a type it cannot check (`@Size` on an `int`, `@Past` on a `String`) fails the build
- validation proxies for `@Validated` beans carry the parameter annotations (method validation)
- generated advice closures take the pointcut's bindings (needs the matching `spring_core_dart`)
- Breaking: `@Cacheable` / `@CachePut` (spring_boot_starter_cache) on a method returning a `Stream` fail the build: a stream can be listened to once; return a `Future<List<T>>`.
- `@InterfaceProxy` annotations: a `bool primary` field of the annotation itself overrides the marker's default and a `List<String> qualifiers` field adds bean qualifiers (`@FeignClient(primary: false, qualifiers: [...])`).
- `@AfterReturning` with a non-nullable `Object` parameter no longer throws for a `void` method (or a `null` result): the advice is skipped; declare `Object?` to receive `null`
- `@SpringBootApplication(exclude:, excludeName:)` is passed to the generated `springApplication`; `order` / `before` / `after` of `@AutoConfigurationModule` are passed as `autoConfigurationMetadata` (needs the matching `spring_boot_dart`)
- discovered auto-configuration modules are listed by package name, then variable name; `SpringApplication` sorts them

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

- Generated modules and `springApplication` are getters (a hot reload replaces their bodies), with a `fingerprint` of the generated code and `reloadApplication` / `reloadApplicationAsync` (with `runners:`).
- Example guide on pub.dev (`example/README.md`): setup, what is generated, build-time errors, options.

## 0.1.0

- Generated code compiles for SDK types as beans (`HttpClient` imported
  from `dart:io`, internal supertypes such as `EfficientLengthIterable`
  left out), `Future<T>?` members, `toString` with parameters, members
  named `advisors` / `targetObject`, and classes with the same name in two
  directories (unique proxy class names). Tests now compile the generated
  code against the runtime.
- Beans that cannot be proxied get `AopProxyFactory.unavailable` with the
  reason (private members without an interface, operators, ...).
- Optional fields and setters are only assigned when a bean or value is
  found, so initializers are kept.
- `@Lazy` on constructor parameters, fields and setters generates one
  lazy proxy class per type (`_$BookServiceLazy`, independent of
  `aop_proxies`) and `Dependency.lazy`; clear build errors for nullable,
  collection, `@Value`, generic, SDK and non-implementable types.
- Constructor and `@Bean` method parameters keep their Dart default value
  when no bean or property is found; required collections there resolve to
  an empty collection (Spring's single-constructor fallback).
- Objects returned from `@Bean` methods get their `@Autowired` / `@Value`
  members, `@PostConstruct` / `@PreDestroy` methods and event listeners
  processed; an init or destroy method that is also annotated runs once.
- `@Import`ed classes keep their explicit name and inherit the importer's
  conditions; `@PropertySource` declarations carry their class's
  conditions.
- `@SpringBootApplication` on `main`: scans `lib/` and the directory of
  `main`, and generates `springApplication` / `runApplication(args)`.
- Starters' `requires` ranges are checked against the `spring_boot_dart`
  version in use; an incompatible starter stops the build with an
  explanation.
- Class conditions are emitted as one `ConditionGroup` per class.
- `@SpringBootApplication`: auto-configuration modules of all dependencies
  (`lib/spring_auto_configuration.dart`) are discovered and passed to the
  generated `springApplication`; `runApplicationAsync` is generated too.
- Files under `lib/resources/` are embedded into generated modules as
  `classpath:` resources (text as-is, binaries base64, > 1 MB skipped).
- Proxy signatures include annotation type names (`annotationTypes`,
  `targetAnnotationTypes`) for release-safe `@annotation` matching.


Initial release.

- `@ComponentScan` modules with bean definitions for every stereotype and
  `@Bean` method, constructor / field / setter / method injection,
  collections, providers and `@Value`.
- Lifecycle callbacks, inferred destroy methods, event listeners,
  `FactoryBean` products, conditions, `@Import`, `@PropertySource`,
  `@Configurable` configurers.
- `@Introspected` metadata for data binding, validation and SpEL.
- `@Aspect` metadata and AOP proxy classes (`aop_proxies` option).
- Build-time validation with errors pointing at the source.
- Dart 3.13 syntax: primary constructors (annotations on declaring
  parameters), `class const`, `new` / `factory` constructor declarations,
  private named parameters.
