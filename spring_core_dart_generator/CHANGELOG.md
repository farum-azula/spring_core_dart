## Unreleased

- `web_dev_config.yaml`: `spring.flutter.web.content-security-policy` adds the page's Content Security Policy to the dev server's answers (`content-security-policy-report-only=true`: the report-only header); with `spring.flutter.security.web.mode=spa` and no policy set, a ready one (`WebDevServerSettings.spaContentSecurityPolicy`: the app's and Flutter's scripts, `'wasm-unsafe-eval'` and no `eval`, connections to the origin, Flutter's CDN and the origins of the `spring.security.oauth2.client.provider.*` URIs, `frame-ancestors 'none'`). The property and a `headers.Content-Security-Policy` both set fail the build.

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs
- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- fix: the release tests at any version; Flutter and Dart in the startu… (#6)
- chore(deps): bump package_config from 2.2.0 to 3.0.0 (#5)
- feat: spring_security_core, spring_boot_starter_security and a CI quality gate

## 0.3.2

- feat: hot reload on the Dart VM, flutter_notes example, fixes for example resources and workspace builds
- feat: spring_boot_starter_web, WebSocket server endpoints, uploads and downloads

## 0.3.1

- **Test classes, the way Spring writes tests.** A new builder (`spring_test`, applied like the main one) reads every `test/**_test.dart` with `@SpringBootTest` classes and writes `test/spring/<path>.test.spring.dart` with `runSpringTests()`: `@Autowired`, `@Value` and `@CapturedOutput` fields injected before each test, `@TestBean` fields as bean overrides, `@Test` methods (`@DisplayName`, `@Disabled`, `@Tag`, `@TestOptions`), `@BeforeAll` / `@BeforeEach` / `@AfterEach` / `@AfterAll`, `@DirtiesContext`, `@Nested` groups, the class annotations `@ActiveProfiles`, `@TestPropertySource`, `@TestEnvironment`, `@DynamicPropertySource`, `@ContextInitializer`. Fields of type `List`, `Set`, `Map<String, T>`, `ObjectProvider` and nullable ones work as in constructor injection; annotated members of a superclass in the same file count. The application is the package's `@SpringBootApplication` entry point (or `@SpringBootTest(application: 'bin/x.dart')`). Mistakes fail the build with the file, line and column; while the test file does not parse, its generated file is kept. See `docs/testing.md`.
- `@SpringBootApplication` under `example/` (a library's or starter's example on pub.dev) scans only `example/` and uses the package's own auto-configuration, as for any application depending on the package; elsewhere nothing changes.

## 0.3.0

- feat(spring_boot_starter_flutter): themes from properties, free reads in Spring widgets

## 0.2.3

- add spring application handling
- docs(spring_boot_starter_flutter): add an example for pub.dev

## 0.2.2

- `@Value('asset:...')` is checked at build time: a missing file, or one not declared under `flutter: assets:` in pubspec.yaml, fails the build with the lines to add (placeholders and `packages/...` keys are not checked).

## 0.2.1

- `@Log`: an extension with a `log` getter (`fieldName:`) returning `const SpringLog('<package>.<Class>')` (`topic:`); private classes, invalid or reserved names and members with the getter's name fail the build
- spring_boot_starter_flutter: the proxy of a `@ChangeNotifierComponent` class mixes `ChangeNotifier` in; `exclude` names that are no members of the class, and `ChangeNotifier` members declared by such a class, fail the build; widget bindings list the beans of a record (`values`) so the widgets can subscribe to the `Listenable` ones
- `springApplication` gets `dartDefines:` with a `const String.fromEnvironment` for every key the application can read (annotation placeholders, `@ConditionalOnProperty` names, `@ConfigurationProperties` fields, the keys and placeholders of the `application*` config files, `spring.profiles.active`), each also in its environment form, so `--dart-define` / `-D` values reach the environment on the VM, in AOT builds and on the web (needs the matching `spring_boot_dart`)
- spring_boot_starter_flutter: `@BuildContextAccess` beans get getters in a generated `extension SpringBeans on BuildContext` (named after the bean or `name:`, typed with the bean's class or the `@Bean` method's declared return type); invalid, reserved, clashing (with `BuildContext`, `Object` or `SpringBuildContext` members) or duplicate getter names and `@BuildContextAccess` on a class that is no bean fail the build
- spring_boot_starter_flutter: `SpringStatelessWidget<R>` classes and `SpringState<W, R>` states get a `SpringWidgetBindings` bean per module that fills their bean records (positional fields by type, named fields by type then by name, nullable fields optional); a record field that is no bean type or an unresolved type parameter fails the build

## 0.2.0

- `@Import` of a registrar or selector emits `ImportDeclaration(..., importer: 'library#Class')`, so the import is ordered with its importing class also when that class has no conditions (needs the matching `spring_core_dart`)
- AOP: the proxy metadata carries `superclassAnnotations` (the annotations of the superclasses and mixins of the class declaring the member's body), so `@CacheConfig` and class-level cache annotations on a base class reach the cache starter; proxy pruning sees them and the class annotations of inherited members (needs the matching `spring_core_dart`)
- AOP: the proxy metadata carries `mergedAnnotations` (the annotations of every overridden or implemented declaration) next to the `@annotation(...)` set, so annotation-driven advisors find `@Cacheable` / `@Validated` on a superclass or mixin method that the bean overrides without them (they were lost with the AspectJ `@annotation` change); proxy pruning and the `Stream` cache check see them too (needs the matching `spring_core_dart`)
- AOP: a component class that cannot be implemented (private members, `base`) gets a subclass proxy also when it has an implementable superclass, interface or mixin; it got a proxy implementing only those, so advice matched on the class (`@annotation`, its private-state members, mixin members) did not run and `execution(* Orders.*(..))` failed the start with `BeanNotOfRequiredTypeException`
- wildcard parameters (`void m(int _, int _)`, also in constructors) are forwarded under generated names (`p0`, `p1`); the generated code did not compile
- a full-mode `@Configuration` `@Bean` method with wildcard parameters (`Label label(int _)`) is overridden under generated names; the generated code did not compile
- method validation: parameter and return value constraints (and `@Valid`) declared on every overridden declaration (implemented interfaces and their superinterfaces, superclasses, mixins) apply to the proxy method, like Hibernate Validator's constraint inheritance; `register(@NotBlank() String email)` on an interface of a `@Validated` class with a subclass proxy (or another level of the hierarchy) was never validated
- AOP: `@annotation(...)` (and the other annotation-based matching) sees the annotations of the method that runs and of the interface declarations it implements (abstract members, members of implemented types), not those of a superclass or mixin method it overrides, like AspectJ: an override without `@Audited` is no longer advised because the overridden method has it (in `aop_proxies: all` and subclass proxies it was); constraints and `@Valid` are still inherited from every declaration
- annotations with `Symbol` (`#name`) and record values are kept in the runtime metadata (were left out); one with a private symbol (`#_name`) is still left out
- `@EventListener` methods that return a value get `resultType: EventResultType<R>()` (the declared type, the element type of an `Iterable`), so their results reach `PayloadApplicationEvent<R>` listeners (needs the matching `spring_core_dart`)
- A `void` type argument is described as `DynamicType.forVoid()` (Feign's `Future<ResponseEntity<void>>` ignores the body).
- AOP: an `@Aspect` class returned by a `@Bean` method is an aspect (aspect metadata, proxy pruning, `@DeclareParents`), also in nested `@ComponentScan` modules
- AOP: `@DeclareParents` applies to subclass proxies too (was skipped silently); needs the matching `spring_core_dart`
- AOP: `FutureOr<T>` methods and getters go through `invokeFutureOr<T>`, `Future<T>` getters through `invokeAsync<T>`, so after-style advice runs when the future completes (was synchronous)
- AOP: proxy pruning sees the advisor beans of auto-configurations: one whose pointcut is not an `AnnotationPointcut` (`DefaultPointcutAdvisor(ExpressionPointcut(...), ...)`) turns pruning off; `execution` type patterns are checked at build time (`String||int` without parentheses, `Animal+`)
- a `@nonVirtual` member is not overridden by a subclass proxy (inherited and not advised, with a build warning); generated files also ignore `deprecated_member_use`, `invalid_use_of_visible_for_testing_member`, `invalid_use_of_internal_member` and `invalid_use_of_protected_member`
- an annotation whose values include a private constant or function (`@Audit(_format)`) is left out of the generated metadata instead of breaking the build; a constraint or `@Valid` with one fails the build with the reason
- an abstract class with `@Lookup` methods and another abstract member fails the build naming the members (the generated subclass did not compile)
- introspection includes the members of mixins (`class Person extends Base with Named`), so JSON, validation and SpEL see them
- a missing import is reported with the unresolved type and the import to add also for `@Autowired` setters, type arguments (`List<Clock>`, `ObjectProvider<Clock>`), advice parameters and `@Lookup` return types; a subclass proxy method with a parameter named `_$i` compiles
- JSON: `@JsonValue` on an enum getter and `@JsonProperty('NAME')` on enum constants are written into the `EnumType`; build errors for more than one `@JsonValue` per class, `@JsonValue` on a setter, a static or private member, a method with required parameters (or any method of an enum), and `@JsonValue` together with `@JsonProperty` names on one enum
- `@Lookup` methods: a bean class with them (abstract ones included, unlike other abstract classes the scan skips) is created as a generated subclass `_$<Class>Lookup` overriding each to return `getBean<T>()` / `findBean<T>()` / `getBeanByName(name)`; a subclass AOP proxy extends it; build errors for lookup methods with parameters, private, static or generic ones, getters, by-type lookups without a class return type, classes that cannot be extended and full-mode `@Configuration` classes (needs the matching `spring_core_dart`)
- breaking: proxy pruning (`aop_prune`) happens only in the `@SpringBootApplication` output and sees the aspects and advisor beans of the nested `@ComponentScan` modules it imports (an auto-configuration with aspects turns it off); a `@ComponentScan` module keeps every proxy class, since any other module may import it and advise its beans
- a `final` / `sealed` / `interface` component, or one with only a factory constructor, no longer fails the build in `aop_proxies: all`: it keeps its signatures (`AopProxyFactory.unavailable`) and the context fails at startup only when advice matches it
- generated code is clash-free: proxies read `this._target` / `this._invoker` and name their locals `_$i` / `_$args`, so parameters named `_target`, `_invoker`, `invoker`, `_resolve` or `arguments` (full-mode `@Bean`) compile; `unnecessary_cast` is in the generated `ignore_for_file`
- generated proxies implement `Advised.addAdvisor` / `removeAdvisor` / `addAdvice` / `removeAdvice` (these names are reserved like `aopTarget`); signatures carry `implementingTypes` (+ annotations) for inherited members and `isProtected` for `@protected` ones; aspects carry `typeTests` for `args(Type)`, `argumentAnnotations` for `@args(...)` and the `perClause` of `@Aspect('perthis(...)')` / `'pertarget(...)'` (a singleton per-instance aspect, `percflow` and `pertypewithin` fail the build); `@DeclareParents` fields make the proxies of the module's matching beans implement the interface (`AopProxyFactory(introductions:)`); needs the matching `spring_core_dart`
- `@Bean` methods may return `null` (`T?`: a `NullBean`; an inter-bean call returns `null`), a function type or a record type (registered and injected by that exact type, `Type _$typeOf<T>()` for types without a literal); generic `@Component` and `@Configuration` classes are registered under their raw type; the scan skips abstract classes instead of failing (an `@Import`ed abstract class still fails)
- a type the analyzer cannot resolve (a missing import) is reported with its name and the import to add (`add import 'package:app/src/clock.dart';`) instead of "Cannot inject InvalidType"
- full mode: a defaulted `@Bean` parameter left out of an inter-bean call is resolved like the container resolves it (a bean, else the Dart default) instead of always getting the Dart default

- generic `@Introspected` classes (erased introspection plus `specialize`); introspections carry `className`; classes named by `@JsonSubTypes`, `@JsonTypeInfo(defaultImpl:)` and `@JsonView` are introspected (needs the matching `spring_core_dart`)
- build-time checks of constraint attributes (`Size(min: -1)`, min > max, ...) and of `@Each` / `@EachKey` element types
- breaking: the generated file is `<name>.spring.dart` (was `<name>.beans.dart`): change the imports and delete the old files
- `@Import` of a `BeanRegistrar`, `ImportSelector` or `ImportBeanDefinitionRegistrar` class is emitted as `ImportDeclaration(Type.new, conditions: ...)` in `BeanModule.registrars` (the class needs a public no-argument constructor) instead of being scanned as a configuration class (needs the matching `spring_core_dart`)
- `@Async` on an `@EventListener` method is emitted as `async: Async(...)`; `@Async` on other methods fails the build
- `@Scope(..., proxyMode: ScopedProxyMode.targetClass)` / `interfaces` emits `scopedProxy:` with the lazy proxy class of the bean's type (build error on a singleton, a `FactoryBean` or a type that cannot be implemented); needs the matching `spring_core_dart`
- JSR-330 `Provider<T>` injection points (from `package:spring_core_dart/jakarta.dart`) are resolved like `ObjectProvider<T>`; JSR-250 `@Resource` on fields and setters emits `r.resource<T>('name')` (`fallbackToType: true` without an explicit name) and `Dependency.resource`; on parameters, with collections, `@Qualifier`, `@Lazy`, `@Autowired` or `@Value` it is a build error
- depends on `spring_core_dart` (the same version): pointcut expressions are parsed at build time with the runtime's parser
- an `@EventListener` method (or `ApplicationListener`) of `PayloadApplicationEvent<P>` is emitted as `EventListenerMethod.forPayload<B, P>`, matching on the payload's runtime type (needs the matching `spring_core_dart`)
- AOP: every advice and `@Pointcut` expression is parsed at build time with the runtime's parser; a syntax error fails the build naming the aspect, the advice and the character position (a reference to a pointcut of a class outside the module is left to the runtime)
- AOP: the implicit getters and setters of public fields carry the field's annotations (`@annotation(Timed)` matches `@Timed() int count = 0;`), except constraints and `@Valid`; a getter is no longer listed with its own annotations twice
- breaking: with `aop_proxies: all`, no proxy class is generated for a bean no pointcut of the module can match (it keeps its signatures: an advisor from another module that matches it fails the startup with the reason); nothing is skipped without advice, with an advisor bean, for beans annotated from outside `spring_core_dart` or `@Validated`, and for subclass proxies. Build option `aop_prune: false` restores a proxy class for every bean
- breaking: constructor selection like Spring's `AutowiredAnnotationBeanPostProcessor`: a required `@Autowired()` constructor must be the only `@Autowired` one; several `@Autowired(required: false)` constructors are candidates and the generated `create` calls the one with the most parameters whose beans exist (`r.containsBeanOfType(...)`), the constructor callable without arguments last; without `@Autowired` the only public constructor (generative before factories), else the primary constructor, else the one callable without arguments is used — the unnamed constructor no longer wins over others by itself; anything else fails the build listing the constructors (needs the matching `spring_core_dart`)
- breaking: `@Autowired(required: false)` on a field, setter or method fails the build (make the type nullable)
- super parameters (`B(super.url)`) carry the `@Value` / `@Qualifier` / `@Named` / `@Lazy` of the super constructor's parameter unless they have their own
- breaking: unsupported targets fail the build naming the target and what to use instead: `@Component` (or a stereotype) on a mixin, enum, extension or extension type, `@Bean` on a top-level function, `@ComponentScan` on anything but a top-level variable, injecting or returning an extension type
- subclasses of `Profile` and `Conditional` count like the base annotation (Spring meta-annotations)
- breaking: class-level `@Lazy` on a lite configuration (`@Component` with `@Bean` methods) makes its `@Bean` methods lazy unless they say otherwise, like on `@Configuration`
- breaking: a directory with its own `@ComponentScan` belongs to that scan: the enclosing scan or `@SpringBootApplication` imports its module (`BeanModule.imports`) instead of registering its beans again; two `@ComponentScan` roots in one directory fail the build
- glob characters in the scanned directory's name are escaped
- breaking: an empty, blank or space-padded explicit bean name or alias fails the build
- independent validation errors of one build are reported together (`N problems in this build:`), each with its library URI and location
- generated code is free of the recommended lints too: bean-method proxy classes are named `_$Config$MethodProxy` (UpperCamelCase), and a declaration of a package that is not a direct dependency is imported through the user's library that exports it (no `depend_on_referenced_packages`); new dependency on `package:yaml` (reads the root `pubspec.yaml`), `analyzer` 14.3 or later
- `@PropertySource(encoding: ...)` is passed to `PropertySourceDeclaration.encoding` (needs the matching `spring_core_dart`)
- the return type of a `@ConfigurationProperties` `@Bean` method gets introspection metadata (also a class of another package), so `spring_boot_dart` can bind it

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
