## 0.6.1

### Changes

- Each module that has `typeTests` also gets `typeDepths`: the longest chain of supertypes (superclass, interfaces, mixins) up to `Object` of every class type written in an annotation, so the runtime can tell which of two matching types is the closer. Regenerate the `.spring.dart` files that have `typeTests`.
- The glue table has a row for `spring_boot_starter_data`'s `lib/src/web/paging_argument_resolver.dart.tmpl`: an application depending on both the web and the data starter gets the bean `pagingArgumentResolvers` (a `WebMvcConfigurer`, made from the `Environment`) that fills `Pageable` and `Sort` controller parameters. The data starter's resolver for data errors also maps `InvalidDataArgumentException` to a 400.
- `@DataTest` tests: `@Transactional(transactionManager: 'name')` on a test method, a `@Nested` group or the test class picks the transaction manager of that test (the innermost one that names a manager wins, then `@DataTest(transactionManager:)`); the generated `runInTestTransaction` gets it as `transactionManager:`. Regenerate the `.test.spring.dart` files.

## 0.6.0

### Breaking

- A class is described only for what the application does with it, as far as the build sees: `BeanIntrospection`s lose the getters, the constructor and setters or the methods that no use asks for (see "Generate only what runs" in the README). A class the build finds only as a WebSocket reply or a client's argument has getters; a controller's return type and an `@ExceptionHandler`'s answer get the constructor and setters too (a test reads the answer back with `mapper.readValue<T>(res.body)`, and `test/` is not scanned); one that is a `@RequestBody` or `@RequestPart`, a WebSocket message or a client's answer has the constructor and setters (and, with `@Valid()`, the getters of the properties that have constraints); `@ConfigurationProperties` classes have both; methods only where SpEL may call them (`@PreAuthorize`, `@PostAuthorize`, `@PreFilter`, `@PostFilter`, and cache keys and conditions that name an argument or the result; the methods marked with `@JsonValue`, `@JsonAnyGetter` or `@JsonAnySetter` stay). A class used some other way the build cannot see (a value of type `Object` that is written as JSON, a `BeanWrapper` on a request body) fails at run time with an `IntrospectionPartError` that says to add `@Introspected()`, which keeps everything; so does a class in `@Introspected(classes: [...])` and what it is made of. A class a `@Scheduled`, `@Secured` or WebSocket `@OnOpen`/`@OnClose`/`@OnError` method uses is no longer described, and a method of a custom `@BeanMethodAnnotation()` still describes everything. Regenerate the `.spring.dart` files.

### Changes

- The glue of the database drivers has a row for `postgres` (`lib/src/jdbc/drivers/postgres.dart.tmpl` of `spring_boot_starter_data`, the bean `postgresJdbcDriver`), written into the modules of an application that depends on both; the placeholders of a template may name a `dart:` library too (`{{dart:io#SecurityContext}}`).
- `@DataTest(transactionManager: 'name')`: the generated tests pass it to `runInTestTransaction`, so they run in that manager's transaction only.
- The `:#{...}` expressions of a `@Query` are compiled to Dart (`compileSpel`, `spel_compiler.dart`): a function of the method's arguments and the starter's `QueryExpressionContext`, `(arguments, context) => (arguments[0] as Book).title`, in `QueryMethod.expressions` (which makes the field a `static final`). The variables are the interpreter's (`#name`, `#p0`, `#a0`, `#root` the arguments, `#entityName`, `#methodName`), `@bean` is `context.bean('x')` typed by the application's bean, `@environment.getProperty(k, default)` the context's environment; `+ - * / % ^`, comparisons, `and`/`or`/`!`, `? :`, `?:`, indexing and properties and methods of the static types are written with `SpelOperations`, so they give what the interpreter gives. A typo (`#book.titel`: `No property 'titel' on type 'Book'; did you mean 'title'?`), an unknown `#variable`, a wrong number of arguments, a member on a nullable value without `?.` and a SpEL syntax error are build errors of the repository; what the compiler leaves to the interpreter (`T(...)`, `new`, selection, `matches`, `instanceof`, Java-style `size()`, members of `Object`) stays `null` in the list and is interpreted at run time. A name that indexes a value of an unknown type (`#filter[address][city]` with a `Map<String, Object?>`) may be a map's key, so it is left to the interpreter, not read as a property of `#root`; a conditional that is the test of another is parenthesized (`(a ? b : c) ? d : e`); `@environment.toString()`, `hashCode()` and `equals(x)` stay with the interpreter; the beans an interpreted expression names (`@catalog.lookup(...)`) are described for SpEL like its arguments. For a `double` variable the code follows the static type (`'n=' + #whole` is `n=7.0` on the web too, as in Java), where the web interpreter finds an `int`. The classes of the arguments are described for SpEL only for a method with such an expression: compiled expressions need no introspection.
- The `@Query` methods of a data repository (`spring_boot_starter_data`) are checked by the build, in the one error of their repository: the method against its annotation (return type, `Future`/`Stream`, `Pageable` and `Sort`, `@Modifying`, `rowMapper` and `resultSetExtractor` by the function's type, `@Lock`, `countQuery`, the result type), the text (`:name` against the method's parameters, a plain `?`, `#{...}`, an expression not closed), the `{Entity}` and `{Entity.property}` placeholders, and misspelled tables and columns when a known name is close (`did you mean`). The schema is the `@Table` classes (names by default, `@Table`, `@Column`, `@MappedCollection` children; not the names derived by default when a bean of the application extends `NamingStrategy`) and the `db/migration` and init scripts of `lib/resources/` (`spring.sql.migration.locations`, `spring.sql.init.schema-locations` read from `application.properties`, `application.yml` and `application.yaml`; a profile file or a profile-specific YAML document that sets them, a `spring.config.import` or the settings of a named data source turns the typo check off; with `{vendor}` in a location the migrations of each database are alternative schemas, and a column of any is known). The texts are checked once every library is scanned (`BeanScanner.throwErrors`), so the entities and beans of the whole module are known; the new `BeanScanner.sqlResources` carries the text of the resources. A `@Query` method is written as a constant `QueryMethod` (`ResultShape`, `ModifyingResult`; `expressions: [null, ...]` for each `:#{...}` for the compiled form to fill) instead of a `ProxyMethod`.
- `closestName` (`did_you_mean.dart`) is the "did you mean" of derived-query properties and of the SQL checks. A name of one or two characters has no close name (`bk` is not a typo of `b`), so a short alias is never reported; the SQL checks also read aliases after `(values ...)`, `${property}` and parenthesized joins, after `returning` and `with ordinality`, `on conflict on constraint x`, `indexed by x`, `for update of x`, the type of `cast(x as T)` and `x::T`, the CTEs after a `values` or data-changing one, and leave the trailing `order by` of a union to the union; `create table if not exists` leaves a table that is there, a statement of a migration that names its table with a `${placeholder}` makes the known tables incomplete (`${schema}.books` is `books`), and a column such as `period varchar(16)` or `key varchar(255)` is not taken for a constraint. A `{Entity}` that is no `@Table` class of the module is a build problem only when a class of the module is close to it or the repository's library sees a class of that name that is no `@Table`; an entity of another package that the library sees is written into `QueryMethod.entities` through it, and any other name is left to the start up (a DTO of the name of an entity is no longer taken for it).
- A class that appears in the cache annotations' expressions (`@Cacheable(key: '#book.isbn')`, `unless: '#result...'`) is described with getters and methods, as for the security expressions (it was not described at all before).
- Direct calls of the `ObjectMapper` in the package's libraries describe the classes their static types name, for what the call does: `readValue<Book>`, `treeToValue`, `readList`, `readMap` and `convertValue<T>` read `T` in (constructor and setters), `writeValueAsString`, `valueToTree` and `convertValue` write the static type of their value out (getters), as do `sendJson(value)` and `broadcast(pattern, value)` of `spring_boot_starter_websocket`, which write a value through the mapper. Only classes of the package of the call; a library that names none of these methods is not resolved (`sendJson` and `broadcast`, names `StreamController.broadcast` shares, count only in a library that imports the WebSocket starter).
- `IntrospectionNeed` (`bean_model.dart`) is what a use asks of a class (read, write, validate, methods); the scanner merges the requests for a class, and what it is made of takes the same, so a class reached by several routes gets the union.
- `@JsonView` classes are registered without properties or methods (they are only compared). A class with class-level `@JsonInclude(JsonInclusion.nonDefault)` that is written out is described for creation too.
- The test builder reads `@DataTest` classes (`spring_boot_starter_data`, Spring's `@DataJdbcTest`) like `@SpringBootTest` ones: the generated group starts the application through `DataTestSetup` (its data beans on an in-memory database; `include:` and `replaceDatabase:` are passed on) with the slice's properties and initializer first among `properties:` and `initializers:`, and runs each test in `runInTestTransaction` of `package:spring_boot_starter_data/testing.dart` (imported as `_data`, only when a `@DataTest` class exists), with the `@BeforeEach` methods of the test class and its `@Nested` groups before the test and their `@AfterEach` methods after it, inside the transaction (so they are not registered with `setUp` and `tearDown`). `@Commit()` and `@Rollback(false)` on a test, a class or a `@Nested` field or class turn the rollback off (`rollback: false`; the innermost wins; a constant argument of `@Rollback` is written with its class's name). Build errors: `@DataTest` with `@SpringBootTest` on one class, `@Commit` or `@Rollback` in a class that is not a `@DataTest`, on a method that is not a `@Test` or on a field that is not `@Nested`, and both on one element.
- The test builder reads `@Container()` and `@ServiceConnection()` fields (`spring_boot_starter_test`'s `containers.dart`) and `@Testcontainers()`: the generated group starts with a `TestContainers` of the class's static `@Container` fields (`setUpAll($containers.start)`, and `tearDownAll($containers.stop)` declared before everything else, so it runs last), before the `@BeforeAll` methods and the context; `@ServiceConnection` fields make `dynamicProperties:` call `$containers.registerConnections(registry)` before the `@DynamicPropertySource` methods; the group gets `skip: TestContainers.skipReason()` (with `skipWithoutDocker:` from `@Testcontainers(disabledWithoutDocker:)`; a `@Disabled` on the class wins). Works for `@DataTest` classes too. Build errors: a `@Container` field that is not static, is in a `@Nested` class or has no value, `@ServiceConnection` without `@Container`, `@Testcontainers` on a method.
- `application:` of `@SpringBootTest` and `@DataTest` may name an entry point anywhere in the package (`test/app/shop_app.dart`), not only in `bin/` or `lib/`; without it only those two directories are searched, as before.
- Classes of `spring_boot_starter_data` are described compactly: a `@Table` class, and a class a `@Query` method of a data repository returns (a DTO, unless a `rowMapper` or `resultSetExtractor` builds it), get an `EntityIntrospection` (name, properties with their `TypeInfo`, annotations, `parameter`, `writable` and default values, and the `get` (one property by index), `create` and `write` closures) instead of a `BeanIntrospection`. A module with any registers one `EntityIntrospections` bean, named `entityIntrospections#<module>`. Reading a row has to be able to fill the class, so the build fails for a private, abstract or generic class, one without a public unnamed constructor, a required constructor parameter that names no field, a `final` field no parameter takes (unless `@Transient`), a constructor parameter whose type does not accept the type of the field it names (`Link({required String url}) : url = Uri.parse(url)`), and a constant default of a parameter the build cannot write (a private constant) when the field has no initializer. A getter written out (`bool get isNew => id == null`, `hashCode`) is no property unless a constructor parameter takes its name; the fields of a generic superclass have its type arguments (`List<T>` of `Base<String>` is a `List<String>`). A `@Table` class is no longer introspected, so it and the classes it uses (`AggregateReference`) leave the `introspections` of the module unless something else asks for them. A `@Query` whose text has SpEL (`#{`) introspects the parameter types of its method.
- Proxy pruning reads advisor beans: a `@Bean` method building `DefaultPointcutAdvisor(ExpressionPointcut('<constant>'), ...)` (or an annotation pointcut) no longer turns pruning off; its expression is matched against the beans like an aspect's. The `@ComponentScan` modules of an application package (`publish_to: none`) are pruned too (nothing outside imports them): the server guide's generated module drops from 12549 to 9328 lines.
- The introspection of a class describes default values: `BeanParameter.hasDefaultValue`/`defaultValue` for the default of each constructor parameter (also `this.x = 5` and `super.x = 5`), and `BeanProperty.hasInitialValue`/`initialValue` for a field initialized with a constant. A field's initializer is read from the resolved source and evaluated for literals (also negative numbers and `int` for a `double` field), `null`, enum values and public or private `const` variables, and `const` lists, sets and maps of those; a call (`DateTime.now()`), a non-`const` collection or an interpolated string gives no initial value. Only a parameter or field with such a value changes in the regenerated files.
- A module of an application that lists `sqlite3` (and `spring_boot_starter_data`) gets the starter's driver glue: a thin adapter over `package:sqlite3`, copied from the starter's template with its symbols imported through the module's prefixes, and a `sqlite3JdbcDriver` bean registered once however many modules carry it. Without the driver, or without the starter, nothing changes.
- A module of an application that depends on both `spring_boot_starter_web` and `spring_boot_starter_data` gets the data starter's resolver for data errors, from the starter's template (one more row of the driver glue table): a `dataAccessExceptionResolver` bean (a web `HandlerExceptionResolver`, registered once, replaced by a bean of that name) that answers `OptimisticLockingFailureException` and `DuplicateKeyException` with a 409 and `EmptyResultDataAccessException` with a 404. With only one of the two starters, nothing changes.
- An interface extending `spring_boot_starter_data`'s `DataRepository` (directly or through `CrudRepository` and the others) is a bean, annotated or not, as in Spring Data; a generic one is a base for others, never a bean. `@Repository('name')` names it. It no longer goes through the `@InterfaceProxy` machinery: the class written for it extends the starter's `SimpleRepository` (the CRUD methods) and has one line for each other method, and nothing is described for the starter to read at start up (no `InterfaceMetadata`, no `ProxyMethod` but those of `@Query` methods): a derived query (`findByTitleAndYear`) is a constant `PartTree` and a call of `RepositoryOperations` (`list`, `set`, `one`, `single`, `stream`, `page`, `slice`, `countBy`, `existsBy`, `deleteBy`, `deleteByReturning`, by the return type, with `Sort`, `Pageable` and `@Lock` passed along), `@Query` is `operations.query`/`queryStream`, a `findById` with `@Lock` passes the lock. `$create` asks the `RepositoryFactory` bean for `operations<T, ID>`, with the interface's annotations and its `@Query` methods.
- The build reads and checks the names of derived queries (the parser the starter had at start up, with its rules): subjects `find`/`read`/`get`/`query`/`search`/`stream`/`count`/`exists`/`delete`/`remove`, `Distinct`, `Top`/`First`, `And`/`Or`, `IgnoreCase`/`AllIgnoreCase`, `OrderBy`, every keyword; each property against the fields of the entity (not `@Transient`), the parameters (`Sort` and `Pageable` anywhere, argument counts and types, `AggregateReference` by the reference or its id) and the return type. A wrong method is a build error naming the interface and listing every problem of it (`BookRepository.findByTitel: No property 'titel' found for type 'Book'; did you mean 'title'?`), also a method that is neither CRUD nor derived, a CRUD name with a signature that does not fit, a synchronous method, `@Lock` where no row is read, a getter, a generic method.
- A repository method's `@Query`, `@Modifying` and `@Lock` are read from the method (and the declarations it overrides), not from the annotations the proxy keeps: a `rowMapper` or `resultSetExtractor` that is a private function is a build problem (`the rowMapper of @Query must be public: the generated code refers to it`) instead of turning the method into a derived query. The generated methods call `this.operations`, so a parameter called `operations` cannot hide it, and a method named `operations` or `$create` is a build problem.
- An interface proxy's bean takes the name of its `@Component`/`@Repository` annotation when it has one.
- Each module gets `typeTests`: a `value is T` test for every class type written in an annotation of its classes, so a `Type` in an annotation matches subtypes at run time. Regenerated files change where annotations hold types.

## 0.5.0

### Breaking

- The `web_dev_config.yaml` builder never fails or warns in an app whose config files set no `spring.flutter.web.*` key and no `spring.flutter.security.web.mode`: it loads no config, writes nothing and deletes a file it generated before, so a pure Dart server builds as if the builder were not there.
- With such a key, an import a browser cannot read is skipped instead of failing the build: `file:`, `configtree:` and `package:` imports (or absolute paths), with a wildcard or not, are not read from the build machine's disk (a warning names the first required one when the file is written), and `asset:`, `http(s):` and `classpath:` files missing from `lib/resources/` are skipped silently.
- A placeholder that only the environment can resolve is never a build error: a profile name holding one is left out (`dev,${ENV}-eu` is read as `dev`), in every form of the profile keys (`spring.profiles.group[prod]`, `spring.profiles[active]`); `spring.profiles.validate` or `spring.main.cloud-platform` with one is read as unset; an import location with one is not read; a document whose `spring.config.activate.*` guard has one is skipped; each with a warning.
- A placeholder in `spring.flutter.security.web.mode` must resolve at build time, as one in a `spring.flutter.web.*` value (it was silently ignored).
- A config file the app reads that does not parse fails the build and keeps the generated file (a YAML syntax error deleted it).
- Generated `@TestBean(name: ...)` overrides are wrapped in `_$named(...)`, so they are registered under the field's type too; a fake created with a constructor (`= FakeGateway()`, also a named, private or prefixed class's constructor, in parentheses or with a cascade) is registered under that class and all its public supertypes, whatever the field's declared type.
- A generic bean whose supertype has a private type argument is also exposed in raw form (`Repo<_Draft>` as `Repo<dynamic>`), so a raw injection point finds it and can become ambiguous, as in Spring.

### Changes

- `build_runner build --workspace`: the existing output kept on an error, and the Flutter assets that `@Value('asset:...')` checks, are read from each package's own directory, so a failed build never writes another package's generated file.
- Two `@Log` classes with the same name in different libraries no longer break the build (the later extension is `$CheckoutLog2`).
- Bean names, logger topics and scanned directories are escaped in generated doc comments, so a line break in them cannot turn into code.
- A bean or a `@TestBean` fake of a `dart:io` type (`HttpClient`, `HttpServer`) keeps that interface, imported through `dart:io`.
- Nullable `@TestBean` fields compile, also of a nullable type alias (`typedef MaybeMailer = Mailer?;`) or with an inferred type; a `null` value fails the test file with a `StateError`.
- The web dev config builder reads imports as the app does, Boot 4.1 file hints included (`classpath:dev.conf[.yaml]`, `[encoding=iso-8859-1]`, a hinted file in a bracketed directory), and still checks where a key may be (`spring.profiles.active` in `application-web.yaml` fails the build whatever its value).
- spa mode's ready Content-Security-Policy lists in `connect-src` the built-in endpoints of Google, GitHub, Facebook and Apple and the hosts Google's and Microsoft's discovery documents name (the browser blocked Google's token request); the new `spring.flutter.web.content-security-policy-connect-src` adds the APIs the app calls and other providers' hosts.
- `SpringBuilder.resources(warn: false)` leaves out the warning about files too large to embed, so builders that read `lib/resources/` after the main one do not repeat it.

## 0.4.3

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
