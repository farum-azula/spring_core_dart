## Unreleased

- breaking: a constraint on a type it cannot check (`@Size` on an `int`, `@Past` on a `String`) fails the build
- validation proxies for `@Validated` beans carry the parameter annotations (method validation)
- generated advice closures take the pointcut's bindings (needs the matching `spring_core_dart`)
- Breaking: `@Cacheable` / `@CachePut` (spring_boot_starter_cache) on a method returning a `Stream` fail the build: a stream can be listened to once; return a `Future<List<T>>`.

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
