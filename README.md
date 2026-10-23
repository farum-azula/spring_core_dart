# spring_core_dart

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Spring Core for Dart: IoC container, environment and `application.properties`
configuration, events, messages, resources, type conversion, SpEL, validation
with data binding, and AOP. Pure Dart, works in Flutter (no `dart:mirrors`):
annotations are processed at build time by `spring_core_dart_generator`.

Repository: <https://github.com/farum-azula/spring_core_dart>.
Flutter widgets (bean builders, event listeners in the widget tree) will be a
separate library.

## Packages

| Package | Path | What it is |
|---|---|---|
| `spring_core_dart` | [`spring_core_dart/`](spring_core_dart/README.md) | Runtime: annotations, container, environment, events, SpEL, validation, AOP. No dependencies. |
| `spring_boot_dart` | [`spring_boot_dart/`](spring_boot_dart/README.md) | Spring Boot on top of the core: `@SpringBootApplication` on `main`, `SpringApplication.run`, `@ConfigurationProperties`, auto-configuration conditions, runners, failure reports. A separate package (depends only on the core) so it can move to its own repository. |
| `spring_boot_starter_logging` | [`spring_boot_starter_logging/`](spring_boot_starter_logging/README.md) | Logging backend: console with patterns, log files with rollover, `logging.*` properties, an in-memory `LogBuffer` (filters, streams, export) for an in-app log screen. Add the dependency, nothing else. |
| `spring_boot_starter_scheduling` | [`spring_boot_starter_scheduling/`](spring_boot_starter_scheduling/README.md) | `@Scheduled` methods with a fixed rate, a fixed delay or a cron expression (placeholders from properties), a `TaskScheduler` bean; tasks stop with the context. Add the dependency, nothing else. |
| `spring_boot_starter_cache` | [`spring_boot_starter_cache/`](spring_boot_starter_cache/README.md) | `@Cacheable`, `@CachePut`, `@CacheEvict`, `@Caching` on bean methods (sync and async) with SpEL keys and conditions; an in-memory `CacheManager` with TTL and size limits from `spring.cache.*`. |
| `spring_web_dart` | [`spring_web_dart/`](spring_web_dart/README.md) | Spring Web basics: `@GetMapping`, `@PostMapping`, `@PathVariable`, `@RequestParam`, `@RequestBody`, `ResponseEntity`, `HttpHeaders`, HTTP and WebSocket client transports (`dart:io`; `fetch` and `WebSocket` on the web), server-sent events as `EventStream<T>` (also the return type of Feign methods), and mocks for tests. |
| `spring_boot_starter_feign` | [`spring_boot_starter_feign/`](spring_boot_starter_feign/README.md) | Feign clients: an abstract class with `@FeignClient` and mapping annotations becomes an injectable HTTP client; JSON via `ObjectMapper`, interceptors, retries, fallbacks, `spring.cloud.openfeign.client.config.*`. |
| `spring_boot_starter_websocket` | [`spring_boot_starter_websocket/`](spring_boot_starter_websocket/README.md) | Declarative WebSocket clients: an abstract class with `@WebSocketClient`, `@OnMessage` (`Stream<T>`) and `@SendMessage` methods becomes an injectable socket; JSON via `ObjectMapper`, one shared connection opened on demand, reconnection with backoff, handshake interceptors. Spring has no declarative WebSocket client: this follows the `@FeignClient` style. |
| `spring_boot_starter_test` | [`spring_boot_starter_test/`](spring_boot_starter_test/README.md) | Tests: `springBootTest` (`@SpringBootTest`), `BeanOverride` (`@MockitoBean`), `ApplicationContextRunner`, matchers, `captureLogs`. Works with `package:test` and `flutter_test`. |
| `spring_core_dart_generator` | [`spring_core_dart_generator/`](spring_core_dart_generator/README.md) | `build_runner` builder that turns annotations into `*.beans.dart` modules. |
| `spring_boot_feign_example` | [`example/spring_boot_feign/`](example/spring_boot_feign/README.md) | A small Spring Boot app against real public servers: a Feign client (REST, JSONPlaceholder), server-sent events (Wikimedia, `EventStream<T>`) and a `@WebSocketClient` (an echo server): run it with `dart run bin/main.dart`. |
| `spring_core_dart_example` | [`example/`](example/README.md) | NEON Books: a runnable tour (`dart run bin/main.dart`) where every feature is used and prints its result, with end-to-end tests over the generated code. |

Libraries of the runtime (import one, or `package:spring_core_dart/spring_core_dart.dart` for all):

| Library | Spring counterpart |
|---|---|
| `core.dart` | `spring-core`: `Environment`, property sources, profiles, `ConversionService`, resources, `AntPathMatcher`, Spring Boot config data |
| `beans.dart` | `spring-beans`: `BeanDefinition`, `DefaultListableBeanFactory`, `FactoryBean`, post-processors, scopes, `BeanWrapper`, introspection |
| `context.dart` | `spring-context`: annotations, `ApplicationContext`, conditions, events, lifecycle, `MessageSource` |
| `expression.dart` | `spring-expression` (SpEL) |
| `validation.dart` | `org.springframework.validation` + Bean Validation style constraints |
| `aop.dart` | `spring-aop`: aspects, advice, pointcut expressions, advisors |
| `json.dart` | Jackson's `ObjectMapper`: JSON on generated metadata, Jackson-style annotations |

## Installation

```yaml
dependencies:
  spring_core_dart: ^0.1.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.1.0
```

Unreleased versions can be used from git with
`git: {url: https://github.com/farum-azula/spring_core_dart.git, path: spring_core_dart}`
(and `path: spring_core_dart_generator`). Generator option (in your `build.yaml`):

```yaml
targets:
  $default:
    builders:
      spring_core_dart_generator:spring_core_dart:
        options:
          aop_proxies: all   # all (default) | interfaces | none
```

## Quick start

With Spring Boot (`spring_boot_dart`) the entry point is all you write —
see [`spring_boot_dart/`](spring_boot_dart/README.md):

```dart
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.beans.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
```

Starters are discovered automatically: add a package with a
`lib/spring_auto_configuration.dart` to `pubspec.yaml`, re-run
`build_runner`, and its beans are part of the application. Anyone can
write one — see
[Writing your own starter](spring_boot_dart/README.md#writing-your-own-starter).

Tested with `spring_boot_starter_test` (a dev dependency):

```dart
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';
import '../bin/main.beans.dart';

void main() {
  final app = springBootTest(
    springApplication,
    profiles: ['test'], // + test/resources/application-test.properties
    properties: {'app.title': 'Test'},
    overrides: [BeanOverride<Greeter>(FakeGreeter())],
  );

  test('greets', () => expect(app.getBean<Greeter>().greet('Ada'), 'fake'));
}
```

With the core only:

```properties
# lib/resources/application.properties (the classpath)
app.title=NEON
spring.profiles.active=dev
```

```dart
// lib/src/beans.dart — everything under lib/src/ is scanned
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:my_app/src/beans.beans.dart';

@ComponentScan()
final BeanModule appBeans = $appBeans;
```

```dart
abstract interface class Greeter {
  String greet(String name);
}

@Service()
class EnglishGreeter implements Greeter {
  EnglishGreeter(@Value(r'${app.title}') this.title);

  final String title;

  @override
  String greet(String name) => 'Hello $name from $title';
}
```

```bash
dart run build_runner build   # or watch
```

```dart
Future<void> main(List<String> args) async {
  final environment = StandardEnvironment()
    ..propertySources.addFirst(SimpleCommandLinePropertySource(args));
  await ConfigDataEnvironment(environment).processAndApply();

  final context = ApplicationContext.run([appBeans], environment: environment);
  print(context.getBean<Greeter>().greet('Ada'));
  context.close();
}
```

## Guide

### Declaring beans

| Annotation | Meaning |
|---|---|
| `@Component([name])`, `@Service`, `@Repository`, `@Controller`, `@Named` | A bean. Default name: lowerCamelCase class name (`URLService` stays). Subclass `Component` for your own stereotypes. |
| `@Configuration([name])` | A bean whose `@Bean` methods declare more beans. `@Lazy` / `@Profile` / conditions on it apply to its `@Bean` methods. |
| `@Bean(name:, aliases:, initMethod:, destroyMethod:, autowireCandidate:)` | A bean produced by a method; type = declared return type; parameters are injected. Destroy method is inferred (`close`, `shutdown`, `dispose`) unless `destroyMethod: ''`. |
| `@Scope('prototype')` / `ScopeType.*` / custom name | Scope; custom scopes via `registerScope(name, CustomScope)` (e.g. `SimpleMapScope`). |
| `@Lazy()` | Singletons are eager by default; lazy ones are created on first use. |
| `@Primary()`, `@Fallback()`, `@Qualifier('x')` | Choosing between candidates. |
| `@DependsOn([...])`, `@Order(n)`, `@Description('...')` | Creation order, collection order, documentation. |

A bean is registered under its own type and all its public supertypes.
Generic supertypes are matched by the full type (`Store<User>`).
A `FactoryBean<T>` exposes its product by name and type; `&name` returns the
factory.

### Injection

```dart
@Service()
class OrderService {
  OrderService(
    this.repository,                         // single bean
    @Qualifier('fast') this.cache,          // by name / qualifier
    this.listeners,                          // List<Listener>: all, ordered
    {this.audit,                             // nullable = optional
    required this.reports,                   // ObjectProvider<Report>: lazy
    @Value(r'${orders.limit:100}') required this.limit});

  @Autowired()
  late final Clock clock;                    // field

  @Autowired()
  set metrics(Metrics value) {}              // setter

  @Autowired()
  void init(Environment environment) {}      // method

  ...
}
```

`@Lazy()` on an injection point injects a generated proxy that finds the
bean on first use (Spring's lazy-resolution proxy). It breaks cycles and
lets a bean call itself through its AOP proxy:

```dart
@Service()
class BookService implements Books {
  BookService(@Lazy() this._self);   // also on fields and setters
  final Books _self;

  @Timed()
  @override
  Book find(String isbn) => ...;

  List<Book> findAll(List<String> isbns) =>
      [for (final isbn in isbns) _self.find(isbn)];   // advised; this.find() is not
}
```

The bean must exist and be unique (checked at refresh). The type must be
an interface or a class without private members, not generic, and the
point must not be nullable; otherwise the build stops and suggests
`ObjectProvider<T>`.

#### Primary constructors and other new syntax

Dart 3.13+ syntax works with the generator: primary constructors (also on
`@Configuration` and `@Introspected` classes, with annotations on their
parameters), `class const`, in-body `new(...)` / `new name(...)` /
`factory name(...)` constructors and private named parameters (injected
under their public name).

```dart
@Component()
class Settings(@Value(r'${pool.size:1}') final int capacity);

@Service()
class Inventory {
  final Settings settings;
  final Clock _clock;
  new(this.settings, {required this._clock}); // called as clock: ...
}

@Service()
class Report {
  final Inventory inventory;
  new _(this.inventory);

  @Autowired()
  factory of(Inventory inventory) => Report._(inventory);
}

@Introspected()
class StockForm(@NotBlank() var String sku, {@Min(1) var int quantity = 1});
```

Selection when several beans match: the only candidate, else the single
`@Primary`, else the only non-`@Fallback`, else the one named like the
parameter. A bean is never injected into itself (Spring's self-reference
rule), so a `@Primary` composite or decorator of `Greeter` receives the
*other* greeters. A constructor or `@Bean` parameter with a Dart default
value keeps the default when no bean (or property) is found, and a required
`List`/`Set`/`Map` there is empty when nothing matches (Spring's
single-constructor fallback; field and setter injection still require a
bean). `List<T>` / `Set<T>` / `Map<String, T>` receive every candidate
(also from parent contexts) sorted by `PriorityOrdered` → `Ordered` →
`@Order`. `BeanFactory`, `ApplicationContext`, `ApplicationEventPublisher`,
`ResourceLoader` and `Environment` can be injected.

`@Value` resolves `${key:default}` placeholders, evaluates `#{...}` SpEL and
converts the result to the target type (`int`, `Duration`, `List<String>`,
enums with `addEnum`, ...). A nullable target gets `null` when a placeholder
has no value.

`refresh()` validates the whole graph before creating the application's
beans (missing and ambiguous dependencies, unresolvable placeholders,
`@DependsOn` names, cycles), so configuration errors fail at startup. Only
post-processors and infrastructure beans (`messageSource`, ...) are created
before that check.

### Lifecycle

Creation: constructor → fields/setters/methods → `BeanNameAware` /
`BeanFactoryAware` → context aware interfaces (`EnvironmentAware`,
`ApplicationContextAware`, ...) → `postProcessBeforeInitialization` →
`@PostConstruct` → `InitializingBean.afterPropertiesSet` → init method →
`postProcessAfterInitialization`. Destruction (on `close()`, dependents
first): `DestructionAwareBeanPostProcessor` → `@PreDestroy` →
`DisposableBean.destroy` → destroy method.

`SmartInitializingSingleton` runs after all eager singletons;
`Lifecycle` / `SmartLifecycle` beans are started by phase (auto-startup at
refresh) and stopped in reverse on `stop()` / `close()`. Like Spring's
`doClose`, `close()` never throws because of a failing `ContextClosedEvent`
listener or a bean that fails to stop: the error is logged and shutdown
continues (a `close()` from inside a listener is ignored).

Problems the framework recovers from are logged through `SpringLog`
(warnings are printed by default): set `SpringLog.level` and
`SpringLog.handler` to route them, e.g. to `package:logging`.

### Environment and configuration

- `StandardEnvironment`: property sources (command line, OS environment,
  config files, `@PropertySource`), `${...}` placeholders with defaults,
  nesting and escapes, typed `getPropertyAs<T>`, required properties.
- Profiles: `spring.profiles.active` / `.default`, expressions
  `dev & (eu | us) & !prod`.
- `ConfigDataEnvironment` (Spring Boot config data): `application.properties`
  and `application-{profile}.properties` from `classpath:/` and
  `classpath:/config/` (= `lib/resources/`), overridden by `file:./` and
  `file:./config/`
  (or `spring.config.location` / `additional-location` / `name`), multi-doc
  files with `#---` and `spring.config.activate.on-profile`,
  `spring.config.import`, `spring.profiles.include` / `group.*`,
  `optional:` locations. Works with async-only resources (Flutter assets)
  via `processAndApply()`.
- `@PropertySource([...], factory: ...)` on a component adds files; the
  last declared wins. It is loaded only when the declaring class's
  conditions (`@Profile`, `@Conditional`, ...) match; classes pulled in with
  `@Import` inherit the importer's conditions.
- YAML: implement `PropertySourceLoader` (`yml`, `yaml`) for config data and
  `PropertySourceFactory` for `@PropertySource` — the core needs no change.

There is no `.env` support by design: configuration lives in property files.

### Conditions

`@Profile(['dev'])`, `@Conditional([MyCondition])`, or any const annotation
class that implements `Condition` (attribute-style conditions such as
`@ConditionalOnProperty('feature.x')`). Conditions see the environment and
the definitions registered before them.

### Modules

`@ComponentScan` generates a `BeanModule` per package (directory). Combine
modules in the application; `@Import([OtherConfig])` pulls in configuration
classes outside the scan. Contexts can have a parent; beans of the parent
are visible to the child.

### Events

```dart
@Component()
class Shipping {
  @EventListener()                       // payloads or ApplicationEvents
  OrderShipped onPlaced(OrderPlaced order) => OrderShipped(this, order.id);

  @EventListener(condition: isBigOrder)  // top-level / static predicate
  @Order(1)
  void onBig(OrderPlaced order) {}

  @EventListener(classes: [ContextRefreshedEvent, ContextClosedEvent])
  void onContext() {}
}
```

Non-null results are published again. `ApplicationListener<E>` beans work
too; `context.addListener<E>(...)` returns a removable registration. Events
published during refresh are delivered once listeners are ready; events
propagate to the parent context.

### Messages, resources, conversion

- `MessageSource`: `StaticMessageSource`, `PropertiesMessageSource`
  (`messages_ru_RU.properties` → `messages_ru` → base), locale fallback,
  `MessageFormat` placeholders, quotes, `number`, `choice`. Define a bean
  named `messageSource`; the context delegates to it.
- Resources: `lib/resources/` is the classpath — the generator embeds its
  files, so `classpath:...` works in CLI, AOT, Flutter and web without asset
  declarations; `@Value('classpath:templates/mail.txt') Resource template`.
  `ResourceLoader` with `classpath:`, `file:` and custom protocols
  (`ProtocolResolver`), `PathMatchingResourcePatternResolver` with
  `AntPathMatcher`.

  Why `lib/resources/` and not `bin/` or the project root: `lib/` is the
  only part of a Dart package that other packages can use, so a starter
  keeps its defaults and messages in its own `lib/resources/` and they
  join the application's classpath exactly like the application's files
  (its generated module embeds them). Files elsewhere would stay invisible
  for dependencies and would be missing in AOT executables, Flutter apps
  and the web, which have no project folder at runtime. An app with only
  `bin/main.dart` still keeps its resources in `lib/resources/`; `lib/`
  may contain nothing else:

  ```text
  my_app/
    bin/main.dart              # @SpringBootApplication
    lib/resources/
      application.properties   # classpath:application.properties
  ```

  Tests see `test/resources/` first (`spring_boot_starter_test`), like
  `src/test/resources` before `src/main/resources` in Java.
- `DefaultConversionService` with Spring Boot duration syntax (`10s`,
  `PT5M`), collections and enums.

### SpEL

```dart
final parser = SpelExpressionParser();
parser.parseExpression("name.toUpperCase()").getValue(context, user);
parser.parseExpression('Total: #{price * 2}', ParserContext.template).getValue(context);
```

Literals, inline lists/maps, properties, indexing, safe navigation (`?.`,
short-circuiting the chain), methods, variables and functions, `T(Type)`
statics, constructors, `@bean` references, selection/projection,
assignment and `++`/`--`, all operators (`div`, `between`, `matches`,
Elvis, ternary). Dart has no reflection: user classes are reached through
`@Introspected` metadata, `FunctionPropertyAccessor` / `FunctionMethodResolver`
or maps. `SimpleEvaluationContext` restricts expressions for data binding.

### Validation and data binding

```dart
@Introspected()
@PasswordsMatch()                   // class-level constraint
class SignupForm {
  @NotBlank() @Size(max: 20) String name = '';
  @NotNull() @Email() String? email;
  @Min(18) int age = 0;
  @Valid() Address address = Address();
}

final binder = DataBinder(form, objectName: 'signup')
  ..validators.add(BeanValidator(introspector: context.getBean<BeanIntrospector>()))
  ..bind({'name': 'Ada', 'age': '36'})
  ..validate();
binder.bindingResult.fieldError('age');   // typeMismatch / Min ... with Spring codes
```

Constraints: `NotNull`, `MustBeNull`, `NotEmpty`, `NotBlank`, `Size`, `Min`,
`Max`, `DecimalMin`, `DecimalMax`, `Positive(OrZero)`, `Negative(OrZero)`,
`Matches` (`@Pattern`), `Email`, `Digits`, `AssertTrue/False`, `Past`,
`PastOrPresent`, `FutureDate` (`@Future`), `FutureOrPresent`, groups,
`@Valid` cascade, custom `Constraint` subclasses. A constraint on a type it
cannot check (`@Size` on an `int`) fails the build, like Hibernate
Validator's `UnexpectedTypeException`. Error codes and arguments follow
Spring (`NotBlank.signup.name`, `NotBlank.name`, `NotBlank.String`,
`NotBlank`), so messages come from a `MessageSource`.

Method validation works like Spring's `@Validated`: with a
`MethodValidationPostProcessor` bean, constraints on the parameters and the
return value of a `@Validated` bean's methods are checked through the
generated proxy, and a violation throws `ConstraintViolationException`:

```dart
@Service()
@Validated()
class Registration {
  @NotBlank()
  String register(@Email() @NotBlank() String email) => 'id-$email';
}

@Configuration()
class ValidationConfig {
  @Bean()
  MethodValidationPostProcessor methodValidationPostProcessor(
    BeanIntrospector introspector,
  ) => MethodValidationPostProcessor(BeanValidator(introspector: introspector));
}
```

Immutable classes are bound through their constructor with
`DataBinder.construct` (Spring 6.1's constructor binding).

### JSON (`ObjectMapper`)

`ObjectMapper` converts objects to JSON and back, like Jackson — on metadata
the generator writes, so no reflection and no `fromJson` / `toJson`
boilerplate. One `@Introspected()` on a model is enough: classes of the same
package that it uses (property and constructor types) are introspected
automatically.

```dart
enum Availability {
  inStock('in_stock'),
  soldOut('sold_out');

  const Availability(this.json);
  @JsonValue()                     // "in_stock" instead of "inStock"
  final String json;
}

class Author {                     // no annotation needed: used by Book
  const Author(this.name, {this.born});
  final String name;
  final int? born;
}

@Introspected()
class Book {
  const Book({
    required this.isbn,
    required this.title,
    required this.author,
    this.tags = const [],
    this.availability = Availability.inStock,
    this.publishedAt,
  });
  final String isbn;
  final String title;
  final Author author;
  final List<String> tags;
  final Availability availability;
  @JsonProperty('published_at')
  final DateTime? publishedAt;
}

final mapper = context.getBean<ObjectMapper>();   // Spring Boot: auto-configured
final json = mapper.writeValueAsString(book);
// {"isbn":"1","title":"Dune","author":{"name":"Herbert","born":1920},
//  "tags":[],"availability":"in_stock","published_at":null}
final again = mapper.readValue<Book>(json);
final books = mapper.readList<Book>('[{"isbn":"2","title":"Ubik","author":{"name":"Dick"}}]');
```

Immutable classes are created through their constructor: `final` fields,
`required` and default values (a missing optional property keeps its
default). Classes with setters and a no-argument constructor work too. The
constructor is the unnamed one, or the one marked `@JsonCreator()`.

| Method | Does |
|---|---|
| `writeValueAsString(value)` | JSON text |
| `valueToTree(value)` | maps / lists / scalars (what `jsonDecode` returns) |
| `readValue<T>(json)` | a `T` from JSON text |
| `readList<E>(json)`, `readMap<V>(json)` | `List<E>`, `Map<String, V>` |
| `readValue(json, const ListType<Book>(ClassType<Book>()))` | any generic type, described with `TypeInfo` |
| `treeToValue<T>(tree)`, `convertValue<T>(value)` | from decoded JSON; from another object |

| Annotation | Meaning |
|---|---|
| `@JsonProperty('published_at')` | the JSON name |
| `@JsonIgnore()` | left out in both directions |
| `@JsonInclude(JsonInclusion.nonNull)` | on a property or class: skip `null` (or empty: `nonEmpty`) values |
| `@JsonIgnoreProperties(value: ['x'], ignoreUnknown: true)` | on a class: names to ignore; accept unknown properties |
| `@JsonCreator()` | the constructor to read with |
| `@JsonValue()` | on an enum field: the JSON form of each value |

Built in: `String`, `int`, `double`, `num`, `bool` (numbers and booleans in
strings are accepted), `DateTime` (ISO-8601; epoch milliseconds with
`writeDatesAsTimestamps`), `Duration` (ISO-8601 `PT1M30S`; also reads `90s`
and milliseconds), `Uri`, `BigInt` (as a string), enums, `List`, `Set`,
`Map`, nullable types and nested objects. A class that already has
`fromJson` / `toJson` (`json_serializable`, `freezed`) is converted with
them. Anything else: a `JsonSerializer<T>` / `JsonDeserializer<T>`, passed to
`ObjectMapper(serializers:, deserializers:)` or grouped in a `JsonModule`
bean (Spring Boot adds every `JsonModule` bean, like Jackson `Module`s).

Settings: `namingStrategy` (`snakeCase`, `kebabCase`, `upperCamelCase`,
...), `inclusion`, `failOnUnknownProperties` (off, like Spring Boot),
`writeDatesAsTimestamps`, `indentOutput` — in Spring Boot from
`spring.jackson.*` (see `spring_boot_dart`).

Errors name the place: `items[2].price: expected a number, got "abc"`,
`missing property "isbn" (required by Book)`.

Classes of other packages are introspected with
`@Introspected(classes: [ExternalDto])`. Not supported yet: polymorphic
types (`@JsonTypeInfo` / `@JsonSubTypes`), date patterns (`@JsonFormat`),
getters without a field, generic model classes.

### AOP

AOP (aspect-oriented programming) runs your code before, after or around
methods of other beans without editing them. Use it for things that cut
across many classes: logging, timing, auditing, permission checks,
retries, caching.

| Term | What it is | In code |
|---|---|---|
| Aspect | A bean holding the extra code | a class with `@Aspect()` and `@Component()` |
| Advice | One piece of extra code and when it runs | a method with `@Before`, `@After`, `@AfterReturning`, `@AfterThrowing` or `@Around` |
| Pointcut | Which methods the advice applies to | the string in the annotation: `'@annotation(Timed)'`, `'execution(* OrderService.*(..))'` |
| Join point | One intercepted call | the `JoinPoint` / `ProceedingJoinPoint` parameter |
| Proxy | The generated wrapper that calls the advice | written by the generator, injected instead of the bean |

#### A first aspect

Time every method marked `@Timed()`:

```dart
// An annotation is a plain class with a const constructor.
class Timed {
  const Timed();
}

@Aspect()
@Component()
class TimingAspect {
  @Around('@annotation(Timed)')
  Object? time(ProceedingJoinPoint call) {
    final watch = Stopwatch()..start();
    try {
      return call.proceed(); // runs the real method
    } finally {
      print('${call.signature.name}: ${watch.elapsedMilliseconds} ms');
    }
  }
}

@Service()
class Search {
  @Timed()
  List<String> find(String text) => ['dart', 'spring'];
}

// context.getBean<Search>().find('d'); // prints "find: 0 ms"
```

How it works: the generator (`spring_core_dart_generator`, required)
writes a proxy class for each bean. When the context starts, every bean
that some pointcut matches is replaced by its proxy, and the proxy is what
other beans and `getBean` receive. A call to `search.find(...)` goes
through the proxy, which runs the advice. Beans that no pointcut matches
are not wrapped and cost nothing.

Rules to remember:

- The aspect must be a bean: `@Aspect()` plus `@Component()` (or a
  `@Bean` method). Aspects can inject other beans as usual; they are never
  proxied themselves.
- Only calls from outside go through the proxy. A call through `this`
  inside the bean (`find` calling `count`) skips the advice, exactly as in
  Spring. Call through another bean, or inject the bean into itself with
  `@Lazy()` (see Injection) or `ObjectProvider<T>`.
- The proxy implements the bean class or its interfaces, so the bean
  needs public members or an interface with the advised methods (the error
  message says which). See "Proxies" below.

#### Kinds of advice

| Annotation | Runs | Parameters (all optional unless noted) | Can change the result |
|---|---|---|---|
| `@Before` | before the method | `JoinPoint` | no; throwing stops the call |
| `@After` | after the method, whether it returned or threw (like `finally`) | `JoinPoint` | no |
| `@AfterReturning` | after it returned normally | `JoinPoint`, then the result | no |
| `@AfterThrowing` | after it threw; the error is rethrown afterwards | `JoinPoint`, then the error | no |
| `@Around` | instead of the method; you decide if and how to call it | `ProceedingJoinPoint` (required) | yes |

```dart
@Aspect()
@Component()
class AuditAspect {
  // A named pointcut: the method body is empty, its name is the pointcut.
  @Pointcut('within(OrderService)')
  void orders() {}

  @Before('orders()')
  void before(JoinPoint call) => print('calling ${call.toShortString()} '
      'with ${call.args}');

  // Runs only when the result is a double: the parameter type filters.
  @AfterReturning('orders()')
  void returned(JoinPoint call, double total) => print('total: $total');

  // Runs only for StateError; other errors pass by.
  @AfterThrowing('orders()')
  void failed(StateError error) => print('failed: ${error.message}');

  @After('orders()')
  void after() => print('done');

  // Change arguments, the result, or skip the call entirely.
  @Around('execution(* OrderService.discount(..))')
  Object? clamp(ProceedingJoinPoint call) {
    final [percent] = call.args;
    return call.proceed([(percent! as int).clamp(0, 50)]);
  }
}
```

Parameters are positional and matched by type: `JoinPoint` /
`ProceedingJoinPoint` by exact type, and in `@AfterReturning` /
`@AfterThrowing` the first other parameter gets the result or the error.
Anything else is a build error.

Async methods: for a method returning a `Future`, `@After`,
`@AfterReturning` and `@AfterThrowing` run when the future completes
(with its value or error), not when the method returns. In `@Around`,
`proceed()` returns the future; make the advice `async` and `await` it to
work with the value. Other advice may be `async` too: on a method returning
a `Future` it is awaited before the call goes on; on a synchronous method
an `async` advice is an error:

```dart
@Around('execution(Future *(..))')
Future<Object?> timeAsync(ProceedingJoinPoint call) async {
  final watch = Stopwatch()..start();
  try {
    return await (call.proceed()! as Future<Object?>);
  } finally {
    print('${call.signature.name}: ${watch.elapsedMilliseconds} ms');
  }
}
```

What a `JoinPoint` gives you:

| Member | Example value |
|---|---|
| `signature.name` | `find` |
| `signature.declaringType` | `Search` |
| `signature.targetType` | the bean class, e.g. `DefaultSearch` |
| `signature.returnType`, `signature.parameterTypes` | `List`, `[String]` |
| `signature.kind` | `MemberKind.method`, `getter` or `setter` |
| `signature.annotations` | the method's annotation objects, e.g. `[Timed()]` |
| `args` | the arguments, `['d']` |
| `target`, `proxy` | the bean, the proxy |
| `toShortString()` | `execution(Search.find(..))` |
| `proceed([args])` (`ProceedingJoinPoint` only) | calls the next advice or the method; `args` replaces the arguments |

#### Pointcut syntax

A pointcut is one or more designators combined with operators:

```text
designator(pattern)  [&& | || | !  designator(pattern) ...]
```

| Designator | Matches | Example |
|---|---|---|
| `execution(ret Type.name(params))` | methods by return type, declaring type, name and parameters | `execution(* OrderService.find*(..))` |
| `within(TypePattern)` | every member of beans whose class matches; `Type+` also subtypes | `within(*Repository)`, `within(Repository+)` |
| `target(Type)`, `this(Type)` | every member of beans of that type or a subtype (interfaces too) | `target(PaymentGateway)` |
| `args(types)` | methods whose parameters have these declared types (`..` any number) | `args(String, ..)` |
| `bean(namePattern)` | every member of beans with that name, an alias or a qualifier value | `bean(order*)` |
| `@annotation(Annotation)` | methods carrying the annotation (also when it is on the interface method they implement) | `@annotation(Timed)` |
| `@within(Annotation)`, `@target(Annotation)` | every member of beans whose class carries the annotation | `@within(Service)` |
| `name()` | a named pointcut: a `@Pointcut` method of the same aspect; another aspect's as `Type.name()` | `orders()`, `AuditAspect.orders()` |

Patterns:

- `*` in a name matches any characters: `find*`, `*Service`, `*`.
- In `execution` parameters, `..` matches any number of parameters
  (including none) and `*` exactly one: `(..)`, `()`, `(String, ..)`,
  `(*, int)`.
- The return type comes first; `*` means any: `execution(* *(..))`,
  `execution(void *(..))`, `execution(Future *(..))`. The type before the
  method name is optional: `execution(* find*(..))` matches `find*`
  methods of every bean.
- Generics and `?` are ignored when matching: `Future<int>` matches
  `Future`, `int?` matches `int`.
- Type names are simple names. Dart has no packages, so `com.x.Service`
  means `Service`, and a package wildcard like `within(com.x..*)` is an
  error instead of silently matching everything.
- `Type+` in `within` and `execution` means the type and its subtypes:
  `execution(* Repository+.*(..))`.

Operators: `&&` / `and`, `||` / `or`, `!` / `not`, and parentheses.

Examples:

| Pointcut | Advises |
|---|---|
| `execution(* *(..))` | every method of every bean (methods only, not getters/setters) |
| `within(OrderService)` | everything of the `OrderService` bean, getters and setters included |
| `execution(* OrderService.*(..))` | the methods of `OrderService` |
| `execution(* find*(..))` | methods whose name starts with `find`, in any bean |
| `execution(Future *(..))` | async methods |
| `execution(void *(String, ..))` | `void` methods whose first parameter is a `String` |
| `target(PaymentGateway)` | every bean implementing `PaymentGateway` |
| `bean(order*)` | beans named `order…` |
| `@annotation(Timed)` | methods marked `@Timed()` |
| `@within(Service)` | every member of `@Service` classes |
| `within(*Service) && !execution(* get*(..))` | services, except `get…` methods |
| `orders() \|\| bean(payments)` | a named pointcut or the `payments` bean |

Named pointcuts are shared by all aspects: refer to them as `orders()` or,
to be explicit, `AuditAspect.orders()`.

Not supported yet: argument binding (`args(...)`, `@annotation(timed)`
with a parameter name). Read annotations from `joinPoint.signature.annotations`
instead. An invalid pointcut fails when the context starts, with the
reason; the Zed extension (`dart_spring`) underlines it while you type.

#### Order of advice

- Several aspects: `@Order` on the aspect class decides; the lower value
  is the outer one (its `@Before` runs first, its `@After` last). Aspects
  without `@Order` come last.
- Inside one aspect: around → before → after → afterReturning →
  afterThrowing, as in Spring.

```dart
@Aspect() @Component() @Order(1) class SecurityAspect { ... } // outer
@Aspect() @Component() @Order(2) class TimingAspect { ... }   // inner
```

#### Advice without annotations

A `PointcutAdvisor` bean is applied like an aspect. Write the pointcut as
an `ExpressionPointcut` (same syntax) or as your own `AopPointcut` class:

```dart
class UpperCase implements MethodInterceptor {
  @override
  Object? invoke(MethodInvocation invocation) =>
      (invocation.proceed()! as String).toUpperCase();
}

@Configuration()
class AopConfig {
  @Bean()
  PointcutAdvisor upperCase() =>
      DefaultPointcutAdvisor(ExpressionPointcut('bean(slogans)'), UpperCase());
}
```

Aspects and advisors are ordered by `@Order` or by implementing `Ordered`
(lower runs outside); those of parent contexts apply too.

A call a bean makes to its own method skips the advice, as in Spring. Call
through `AopContext.currentProxy()` to get it; unlike Spring the proxy is
always exposed (no `exposeProxy` flag), also in the asynchronous code an
advised `Future` method starts:

```dart
Future<Book> refresh(String isbn) =>
    (AopContext.currentProxy() as Books).find(isbn);   // advised
```

#### Proxies

Proxies are generated classes that implement the bean class (when it has
no private members and is not `final`, `base` or `sealed`) and its
interfaces, so the bean can be injected by either. If advice matches a bean
that cannot be proxied, the context fails at startup and says why; add an
interface with the advised methods and inject the bean by it.
`AopUtils.getTarget(bean)` unwraps a proxy. The generator option
`aop_proxies` (`all` by default, `interfaces`, `none`) controls which
proxies are generated (see `spring_core_dart_generator`). Annotations are
matched by names the generator writes, so `@annotation(Timed)` also works in
minified and obfuscated release builds.

### Logging

`SpringLog` is the logging facade (Spring's commons-logging / SLF4J): the
framework, starters and applications log through it; a backend such as
`spring_boot_starter_logging` decides where records go. Without one,
warnings and errors are printed.

```dart
const log = SpringLog('neon.checkout');

log.info('order placed', fields: {'order': 42});
log.debug(() => 'basket: ${basket.dump()}');   // built only if enabled
log.error('payment failed', error: e, stackTrace: s);

SpringLog.setLevel('neon.checkout', SpringLogLevel.debug); // and below
SpringLog.withFields({'request': id}, () => handle(request)); // like MDC
```

With Spring Boot, levels come from `logging.level.*` properties.

### Other extension points

`BeanFactoryPostProcessor` / `BeanDefinitionRegistryPostProcessor`,
`BeanPostProcessor`, custom scopes, hand-written `BeanDefinition`s and
`BeanModule`s, `registerSingleton`, `@Configurable` + `autowireBean` for
objects created elsewhere (e.g. Flutter `State`).

Your own interface implementations: mark an annotation class with
`@InterfaceProxy()` and every abstract class carrying that annotation
becomes a bean whose implementation the generator writes — each method hands
the call, with its annotations, parameter names and types, to an
`InvocationHandler` that an `InvocationHandlerFactory` bean creates (Java's
dynamic proxies, without reflection). This is how `@FeignClient` works, and
how Spring Data repositories will:

```dart
@InterfaceProxy()
class Remote {
  const Remote(this.name);
  final String name;
}

@Remote('greetings')
abstract interface class Greeter {
  Future<String> greet(String name);
}

final class RemoteHandlers implements InvocationHandlerFactory {
  @override
  bool supports(InterfaceMetadata<Object> metadata) =>
      metadata.annotation<Remote>() != null;

  @override
  InvocationHandler create(InterfaceMetadata<Object> metadata) => MyHandler(metadata);
}
```

Your own method annotations: mark the annotation class with
`@BeanMethodAnnotation()` and the generator lists every bean method that
carries it in `BeanDefinition.annotatedMethods`, with its annotations and a
closure that calls it — what Spring does with reflection
(`MethodIntrospector`). This is how `@Scheduled` finds its methods:

```dart
@BeanMethodAnnotation()
class Poll {
  const Poll(this.every);
  final Duration every;
}

@Component()
class Inbox {
  @Poll(Duration(seconds: 30))
  void check() { ... }
}

// In a BeanPostProcessor (with BeanFactoryAware) or after refresh:
for (final method in beanFactory.getBeanDefinition(name).annotatedMethods) {
  final poll = method.annotations.whereType<Poll>().firstOrNull;
  if (poll != null) {
    Timer.periodic(poll.every, (_) => method.invoke(bean, const []));
  }
}
```

## Differences from Spring

| Spring | Here | Why |
|---|---|---|
| Reflection, runtime classpath scanning | `build_runner` code generation, `@ComponentScan` per directory | No reflection in Flutter/AOT |
| `PropertySource` class | `AbstractPropertySource` | `@PropertySource` is the annotation |
| `Scope` SPI, `Pointcut` interface | `CustomScope`, `AopPointcut` | `@Scope`, `@Pointcut` are the annotations |
| `@Null`, `@Pattern`, `@Future` | `MustBeNull`, `Matches`, `FutureDate` (codes unchanged) | Clash with Dart's `Null`, `Pattern` and `Future` |
| `Validator.supports(Class)` | `supports(Object target)` | Dart cannot test subtypes on a `Type` |
| CGLIB `@Configuration` proxies | Call other `@Bean`s through parameters | No subclass proxies |
| CGLIB / JDK proxies | Generated `implements` proxies | Final or private-member classes are proxied through interfaces only |
| Circular references (opt-in) | Always an error | Same as Spring Boot's default |
| Asynchronous initialization | Synchronous `refresh()`; load config first with `processAndApply()` | Predictable startup |
| Package-qualified AOP type patterns, argument binding | Simple type names; qualified wildcards and binding are rejected | No packages in Dart; binding not implemented yet |
| Jackson `ObjectMapper` (reflection) | `ObjectMapper` on generated metadata; a model needs `@Introspected()` (its classes of the same package are included) | No reflection |
| Optional `@Value` with `${x:#{null}}` | A nullable target gets `null` when a placeholder is missing | Dart null safety |

## Roadmap

Plans and sketches of coming features are in [`roadmap/`](roadmap/README.md),
one file per package: Spring Web, Security, Data, retry, HTTP client, next
steps of the existing starters, Flutter (`flutter_spring` with signals, Flutter
Scene and Rust), the editor extensions, and the
[fix plan](roadmap/fix_plan.md) — open differences from Spring found in
reviews.

## License

Apache License 2.0, see [LICENSE](LICENSE). Spring is a trademark of
Broadcom Inc.; this project is an independent port and is not affiliated
with or endorsed by the Spring team.

## Development

```bash
dart pub get
dart run melos run check   # versions + dependencies + gen + analyze + format + test
dart run tool/check_dependencies.dart   # only this repository, the Dart SDK and Dart-team packages
dart run tool/test_all.dart   # tests of every package (also the example), from each package and from the root
dart run melos run version -- 0.2.0   # release train: one version for every package
dart run melos run coverage
```

Dependency policy: the packages use only each other, the Dart SDK and
packages published on pub.dev by the Dart and Google teams (`dart.dev`,
`tools.dart.dev`, `labs.dart.dev`, `google.dev`, `flutter.dev`),
transitive dependencies included; the packages that end up in
applications (`spring_core_dart`, `spring_boot_dart`,
`spring_boot_starter_logging`) depend on nothing outside this repository
at all. CI enforces it with
`tool/check_dependencies.dart`; any other package needs an exception there
with a reason and the packages allowed to use it (today: `melos` for the
workspace scripts, `node_preamble` pulled by `package:test`; database
drivers will be added the same way).

The library is developed outside any Flutter workspace on purpose: Flutter
pins `test_api`, which keeps `package:test` and `build_test` on an older
analyzer than `build_runner` / `source_gen` need. Consumers are unaffected.

Tests: 398 (runtime), 97 (generator), 21 (Spring Boot), 14 (web), 29
(logging starter), 62 (scheduling starter), 43 (cache starter), 13 (Feign
starter), 25 (test starter), 20 end-to-end over the generated code of the
example (tour and Spring Boot app), 29 (language server). Generated `*.beans.dart` files are committed. CI
(`.github/workflows/ci.yml`) also checks that generated code is up to date,
runs the tour, and runs the AOP release check as minified JavaScript.
