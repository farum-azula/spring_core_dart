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
| `spring_core_dart` | [`spring_core_dart/`](spring_core_dart/README.md) | Runtime: annotations, container, environment, events, SpEL, validation, AOP. Only the Dart team's `package:yaml`. |
| `spring_boot_dart` | [`spring_boot_dart/`](spring_boot_dart/README.md) | Spring Boot on top of the core: `@SpringBootApplication` on `main`, `SpringApplication.run`, `@ConfigurationProperties`, auto-configuration conditions, runners, failure reports. A separate package (depends only on the core) so it can move to its own repository. |
| `spring_boot_starter_logging` | [`spring_boot_starter_logging/`](spring_boot_starter_logging/README.md) | Logging backend: console with patterns, log files with rollover, `logging.*` properties, an in-memory `LogBuffer` (filters, streams, export) for an in-app log screen. Add the dependency, nothing else. |
| `spring_boot_starter_scheduling` | [`spring_boot_starter_scheduling/`](spring_boot_starter_scheduling/README.md) | `@Scheduled` methods with a fixed rate, a fixed delay or a cron expression (placeholders from properties), a `TaskScheduler` bean; tasks stop with the context. Add the dependency, nothing else. |
| `spring_boot_starter_cache` | [`spring_boot_starter_cache/`](spring_boot_starter_cache/README.md) | `@Cacheable`, `@CachePut`, `@CacheEvict`, `@Caching` on bean methods (sync and async) with SpEL keys and conditions; an in-memory `CacheManager` with TTL and size limits from `spring.cache.*`. |
| `spring_web_dart` | [`spring_web_dart/`](spring_web_dart/README.md) | Spring Web basics: `@GetMapping`, `@PostMapping`, `@PathVariable`, `@RequestParam`, `@RequestBody`, `ResponseEntity`, `HttpHeaders`, HTTP and WebSocket client transports (`dart:io`; `fetch` and `WebSocket` on the web), server-sent events as `EventStream<T>` (also the return type of Feign methods), and mocks for tests. |
| `spring_boot_starter_feign` | [`spring_boot_starter_feign/`](spring_boot_starter_feign/README.md) | Feign clients: an abstract class with `@FeignClient` and mapping annotations becomes an injectable HTTP client; JSON via `ObjectMapper`, interceptors, retries, fallbacks, `spring.cloud.openfeign.client.config.*`. |
| `spring_boot_starter_websocket` | [`spring_boot_starter_websocket/`](spring_boot_starter_websocket/README.md) | Declarative WebSocket clients: an abstract class with `@WebSocketClient`, `@OnMessage` (`Stream<T>`) and `@SendMessage` methods becomes an injectable socket; JSON via `ObjectMapper`, one shared connection opened on demand, reconnection with backoff, handshake interceptors. Spring has no declarative WebSocket client: this follows the `@FeignClient` style. |
| `spring_boot_starter_test` | [`spring_boot_starter_test/`](spring_boot_starter_test/README.md) | Tests: `springBootTest` (`@SpringBootTest`), `BeanOverride` (`@MockitoBean`), `ApplicationContextRunner`, matchers, `captureLogs`. Works with `package:test` and `flutter_test`. |
| `spring_core_dart_generator` | [`spring_core_dart_generator/`](spring_core_dart_generator/README.md) | `build_runner` builder that turns annotations into `*.spring.dart` modules. |
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
          aop_prune: true    # all: skip proxies of beans no pointcut matches
```

## Quick start

With Spring Boot (`spring_boot_dart`) the entry point is all you write —
see [`spring_boot_dart/`](spring_boot_dart/README.md):

```dart
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.spring.dart';

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
import '../bin/main.spring.dart';

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
import 'package:my_app/src/beans.spring.dart';

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
| `@Component([name])`, `@Service`, `@Repository`, `@Controller`, `@Named` | A bean. Default name: lowerCamelCase class name (`URLService` stays); an explicit name or alias must not be empty, blank or padded with spaces. Subclass `Component` for your own stereotypes. Only classes are beans: on a mixin, enum, extension or extension type (erased at runtime) the build fails and says what to use instead. The scan skips abstract classes, as Spring's does; a generic class is registered under its raw type (`Repo<T>` as `Repo<dynamic>`, type arguments at their bounds). |
| `@Configuration(name:, proxyBeanMethods:)` | A bean whose `@Bean` methods declare more beans. Like Spring's default (`proxyBeanMethods: true`), the container creates a generated subclass whose `@Bean` methods return its beans, so a `@Bean` method calling another one gets the singleton (a prototype: a new instance; static methods are not intercepted); `proxyBeanMethods: false` ("lite", also `@Component` classes and `@AutoConfiguration`) calls them as written. `@Lazy` / `@Profile` / conditions on it (also on a lite `@Component` with `@Bean` methods) apply to its `@Bean` methods, unless a method says otherwise (`@Lazy(false)`). |
| `@Bean(name:, aliases:, initMethod:, destroyMethod:, autowireCandidate:)` | A bean produced by a method; type = what the method body returns (`DataSource ds() => HikariDataSource()` is a `HikariDataSource`, also found as `DataSource`); parameters are injected. Destroy method is inferred (`close`, `shutdown`, `dispose`) unless `destroyMethod: ''`. The method may return `null` (declared `T?`): the bean is a `NullBean`, found by name but absent for type lookups and injection (`getBean<T>()` and required points fail, `findBean<T>()` and optional points get `null`, collections leave it out), and an inter-bean call returns `null`. A function type (`String Function(String)`, a typedef) or record type is a bean too, injected by that exact type into single injection points. |
| `@Scope('prototype', proxyMode:)` / `ScopeType.*` / custom name | Scope; custom scopes via `registerScope(name, CustomScope)` (e.g. `SimpleMapScope`). `proxyMode: ScopedProxyMode.targetClass` (or `interfaces`) injects a generated scoped proxy that asks the scope for the current instance on every call, so singletons can hold scoped beans (by hand: `BeanDefinition(scopedProxy:)`); without it a scoped bean injected directly into a singleton is logged as a warning. |
| `@Lazy()` | Singletons are eager by default; lazy ones are created on first use. |
| `@Primary()`, `@Fallback()`, `@Qualifier('x')` | Choosing between candidates. |
| `@DependsOn([...])`, `@Order(n)`, `@Description('...')` | Creation order, collection order, documentation. |

A bean is registered under its own type and all its public supertypes.
Generic supertypes are matched by the full type (`Store<User>`).
A `FactoryBean<T>` exposes its product by name and type; `&name` returns the
factory. A `FactoryBean` given to `registerSingleton` is found by its
`objectType` (`T`).

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

Candidates follow Spring's `DefaultListableBeanFactory`: a bean is never
injected into itself, and a configuration's own `@Bean` products are left
out of its collections and single dependencies unless nothing else matches
(a collection then gets them, never the configuration itself). Beans of
parent contexts take part (their `@Primary`, `@Order`,
`autowireCandidate` and qualifiers kept; a local bean of the same name
hides them); for a single dependency a local `@Primary` beats a parent's,
the parameter name matches bean names and aliases (not qualifier values),
then the `@Qualifier` value as a bean name, and two `@Primary` candidates
are an error.

The JSR-330 / JSR-250 names that clash with other libraries live in
`package:spring_core_dart/jakarta.dart`: a `Provider<T>` injection point
gets the same lazy provider as `ObjectProvider<T>` (`get()`), and
`@Resource` on a field or setter injects by bean name (the member name, or
by type when no bean has it; `@Resource(name: 'x')` exactly that bean):

```dart
import 'package:spring_core_dart/jakarta.dart' as jakarta;

@Service()
class Reports {
  Reports(this.clock);
  final jakarta.Provider<Clock> clock;       // clock.get() on every use

  @jakarta.Resource(name: 'archiveStore')
  late final Store store;
}
```

#### Lookup methods

A method marked `@Lookup()` returns a bean of the container on every call
(Spring's lookup method injection): the bean of its return type, or the
bean named by `@Lookup('name')`; a nullable return type gives `null` when
no bean matches. The usual case is a singleton that needs a new prototype
per call. The bean is created as a generated subclass overriding the
methods, so they can be abstract, and an abstract `@Component` class with
`@Lookup` methods is a bean (the scan skips other abstract classes). A
concrete method works too; its body never runs.

```dart
@Component()
@Scope(ScopeType.prototype)
class Command { ... }

@Component()
abstract class CommandManager {
  @Lookup()
  Command createCommand();        // a new Command per call

  @Lookup('auditLog')
  AuditLog auditLog();

  void process() => createCommand().run();
}
```

The build fails when a `@Lookup` method takes parameters, is private,
static or generic, or (looked up by type) returns no class type, and when
the class cannot be extended from the generated library (`final`,
`sealed`, `interface`, only factory or private constructors, several
`@Autowired(required: false)` constructors) or is a full-mode
`@Configuration` class. If the bean is advised, its AOP proxy wraps the
generated subclass (a subclass proxy extends it), so lookup methods can be
advised too.

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

#### Choosing the constructor

Like Spring's `AutowiredAnnotationBeanPostProcessor`: an `@Autowired()`
constructor is used (it must be the only `@Autowired` one); several
`@Autowired(required: false)` constructors are candidates, and the bean is
created with the one with the most parameters whose beans exist (checked
when the bean is created, the constructor callable without arguments as
the last resort). Without `@Autowired`: the only public constructor
(generative ones count before factories), else the primary constructor
(like Kotlin's in Spring), else the one callable without arguments;
anything else fails the build and lists the constructors.
`required: false` only applies to constructors; on fields, setters and
methods a nullable type makes the dependency optional.

A super parameter carries the `@Value` / `@Qualifier` / `@Named` / `@Lazy`
of the super constructor's parameter unless it has its own:

```dart
abstract class Client {
  Client(@Value(r'${api.url}') this.url);
  final String url;
}

@Component()
class OrdersClient extends Client {
  OrdersClient(super.url); // injected from ${api.url}
}
```

Selection when several beans match: the only candidate, else the single
`@Primary`, else the only non-`@Fallback`, else the one named like the
parameter. A bean's name or alias (also one from `registerAlias`) matches
`@Qualifier` and the parameter name. A bean with `autowireCandidate: false`
is never injected, not even through a `@Qualifier`, but `getBean` still
finds it by name or as the only bean of its type. A bean is never injected
into itself (Spring's self-reference rule), so a `@Primary` composite or
decorator of `Greeter` receives the *other* greeters. A constructor or
`@Bean` parameter with a Dart default value keeps the default when no bean
(or property) is found, and a required `List`/`Set`/`Map` there is empty
when nothing matches (Spring's single-constructor fallback; field and setter
injection still require a bean). `List<T>` / `Set<T>` / `Map<String, T>`
receive every candidate (also from parent contexts); only a `List` is
sorted, by `PriorityOrdered` → `Ordered` → `@Order` (an `@Order` on a
`@Bean` method beats the bean's `Ordered.order`, an `@Order` on its class
does not), a `Set` or `Map` keeps registration order. This works for
primary constructors too (`class Greeter(this._all) { final List<String>
_all; }`), with the field declared in the header or in the body. `BeanFactory`,
`ApplicationContext`, `ApplicationEventPublisher`, `ResourceLoader` and
`Environment` can be injected.

A dependency that cannot be resolved (no bean, several candidates, a
dependency that fails to create) fails `refresh()` or the bean's creation
with an `UnsatisfiedDependencyException` naming the bean and the injection
point (`Bean 'shop' has an unsatisfied dependency Greeter 'greeter': ...`);
its `cause` is the lookup error or the nested bean's failure, so the message
shows the chain of beans.

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

Asynchronous callbacks: an init callback (`@PostConstruct`,
`afterPropertiesSet`, init method) or a destroy callback (`@PreDestroy`,
`DisposableBean.destroy`, destroy method) may return a `Future`.
`refreshAsync()` (also `ApplicationContext.runAsync`, Spring Boot's
`runAsync`) awaits the init callbacks of the beans created during the
refresh — each bean's one after another; the bean is injected into others
meanwhile — before `SmartInitializingSingleton`, the lifecycle start and
`ContextRefreshedEvent`; a failure fails the refresh naming the bean. The
synchronous `refresh()` fails for such a callback, and a bean created
after the refresh (lazy, prototype, scoped) needs synchronous ones.
`closeAsync()` awaits the destroy callbacks, dependents first; `close()`
logs an asynchronous one and goes on without waiting.

`SmartInitializingSingleton` runs after all eager singletons;
`Lifecycle` / `SmartLifecycle` beans are started by phase (auto-startup at
refresh) and stopped in reverse on `stop()` / `close()`; a bean's
dependencies start before it and its dependents stop before it, whatever
their phase (a plain `Lifecycle` dependency of an auto-startup bean starts
at refresh); a lazy plain `Lifecycle` bean is not created for that, like
Spring. A created singleton counts by its instance too (a `@Bean Object
server()` returning a `SmartLifecycle`), like Spring matching the
singleton's actual type. Mix in `SmartLifecycle` (`with`) for Spring's defaults
(auto-startup, default phase). `closeAsync()` waits for the
`stopWithCallback` callbacks of each phase, at most
`DefaultLifecycleProcessor.timeoutPerShutdownPhase` (10 seconds) or the
phase's entry in `timeoutsForShutdownPhases` (declare a
`lifecycleProcessor` bean to change them); then the beans still running
are logged and the next phase is stopped. When a refresh fails, the beans
started so far are stopped. Like Spring's `doClose`, `close()` never throws because of a failing `ContextClosedEvent`
listener or a bean that fails to stop: the error is logged and shutdown
continues (a `close()` from a `ContextClosedEvent` listener is ignored; one
from a `ContextRefreshedEvent` listener closes the context, like Spring).

Like Spring 7, `context.pause()` stops the running lifecycle beans except
the `SmartLifecycle` beans whose `isPauseable` is `false`, and
`context.restart()` (stopping the pauseable beans first if still running)
starts the auto-startup beans again, restoring the state after refresh —
a fit for Flutter's `paused` / `resumed`. They publish
`ContextPausedEvent` (a `ContextStoppedEvent`) and `ContextRestartedEvent`
(a `ContextStartedEvent`); `pauseAsync()` waits for the `stopWithCallback`
callbacks like `closeAsync()`. A custom `LifecycleProcessor` implements
`onPause` / `onPauseAsync` / `onRestart`.

`context.registerShutdownHook()` closes the context on SIGINT / SIGTERM
and ends the process with `128 + signal`, like Spring's JVM hook (once per
context; the signals are released when the context closes; nothing on the
web). Subclasses of `AnnotationConfigApplicationContext` can override
Spring's template hooks: `postProcessBeanFactory(beanFactory)` (all
definitions loaded, before the bean factory post-processors), `onRefresh()`
(message source and multicaster ready, before the listeners and the eager
singletons) and `onClose()` (last in `close()` / `closeAsync()`, after the
singletons are destroyed).

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
  / `application.yml` / `application.yaml` and their
  `application-{profile}` variants, in Boot's two location groups:
  `classpath:/;classpath:/config/` (= `lib/resources/`), overridden by
  `file:./;file:./config/;file:./config/*/` (profile-specific files win
  within a group, so `./application.properties` beats a packaged
  `application-prod.properties`; `.properties` beats YAML in one
  location). Also `spring.config.location` / `additional-location` (`,`
  separates groups, `;` joins locations into one) / `name`, multi-doc files
  (`#---`, YAML `---`) with `spring.config.activate.on-profile`,
  `spring.config.import` (files or directories, relative to the importing
  file, with their `-{profile}` variants; also from the command line or
  `SPRING_CONFIG_IMPORT`, above every location), `spring.profiles.include`
  / `group.*`, `optional:` locations (a non-optional file or directory that
  does not exist fails the start). Profiles follow Boot's rules: the
  command line wins over a file's `spring.profiles.active`, profiles set
  with `setActiveProfiles` are kept and the file's added after them,
  `spring.profiles.default` (file, command line or environment) selects
  the profile files while none is active, groups expanded. A
  `defaultProperties` source stays below the config files. Works with
  async-only resources (Flutter assets) via `processAndApply()`.
- Binding follows Boot's binder: indexed keys (`spring.profiles.include[0]`,
  `SPRING_PROFILES_ACTIVE_0_`) form a list, and a list comes whole from the
  highest source that has it (`--spring.profiles.active[0]=dev` replaces a
  file's list). `${...}` in a file's `spring.config.import` and on-profile
  guard is resolved against the command line and environment first, then
  the files; an unresolvable placeholder in an `optional:` import just
  skips it. A non-optional wildcard location (`file:./config/*/`) needs at
  least one subdirectory.
- `${random.int}`, `${random.int(10)}`, `${random.int[5,10]}`,
  `${random.long}`, `${random.uuid}`, `${random.value}`
  (`RandomValuePropertySource`, added by `SpringApplication`; call
  `RandomValuePropertySource.addToEnvironment` otherwise).
- Placeholders follow Spring 6.2's parser: `${db:url}` is first looked up as
  the key `db:url`, then as `db` with the default `url`; an unclosed `${`
  is plain text (`${a ${b}` resolves `${b}`).
- `.properties` files are UTF-8; for ISO-8859-1 (what Spring reads) use
  `PropertiesPropertySourceLoader(encoding: latin1)` in
  `ConfigDataEnvironment(loaders: ...)` or `@PropertySource(encoding:
  'ISO-8859-1')`.
- YAML is flattened like Boot's `YamlPropertySourceLoader`: `app.hosts[0]`,
  `app.servers[0].name`, empty values and `~` as `''`. `@Value` and
  `getProperty('app.hosts[0]')` see list items; `@ConfigurationProperties`
  binds only comma-separated lists so far.
- Relaxed names (Boot's attached `ConfigurationPropertySources`, added by
  `ConfigDataEnvironment` / `SpringApplication`): `app.read-timeout` in
  `getProperty`, `${...}` and `@Value` also finds `app.readTimeout`,
  `app.read_timeout` or `APP_READTIMEOUT`; the first property source with
  any form wins.
- `@PropertySource([...], factory: ...)` on a component adds files; the
  last declared wins. It is loaded only when the declaring class's
  conditions (`@Profile`, `@Conditional`, ...) match; classes pulled in with
  `@Import` inherit the importer's conditions. As in Spring it reads
  `.properties`; for YAML pass a `PropertySourceFactory` that uses
  `YamlPropertySourceLoader`. Async-only resources (Flutter assets behind a
  `ProtocolResolver`) work with `refreshAsync()` / `runAsync`, which reads
  them before the modules are loaded.

There is no `.env` support by design: configuration lives in property files.

### Conditions

`@Profile(['dev'])`, `@Conditional([MyCondition])` (or your own subclass of
either, `class Dev extends Profile { const Dev() : super(const ['dev']); }`,
like a Spring meta-annotation), or any const annotation class that
implements `Condition` (attribute-style conditions such as
`@ConditionalOnProperty('feature.x')`). Conditions see the environment, the
definitions registered before them and, as `context.definition`, the
definition being evaluated (its `annotations`, name and types — Spring's
`AnnotatedTypeMetadata`; `null` for `@PropertySource` conditions).

### Modules

`@ComponentScan` (on a top-level variable) generates a `BeanModule` per
package (directory). Combine modules in the application;
`@Import([OtherConfig])` pulls in configuration classes outside the scan. A
subdirectory with its own `@ComponentScan` belongs to that scan (its
filters apply): the enclosing scan, or `@SpringBootApplication`, imports its
module instead of scanning the files again, so every bean is registered
once even when both modules are used. One directory has one scan root. Contexts can have a parent; beans of the parent
are visible to the child.

Programmatic registration follows Spring 7. A `BeanRegistrar` registers
beans with a supplier and Spring's `Spec` options; put it in
`@Import([...])` (the generator creates it with its no-argument
constructor when the importing class is registered, so it follows that
class's conditions) or `context.register(...)` it. `ImportSelector`
(returns `BeanModule`s, loaded before the importing module) and
`ImportBeanDefinitionRegistrar` (gets the `BeanDefinitionRegistry`) work
the same way and may implement `EnvironmentAware`, `BeanFactoryAware`,
`ResourceLoaderAware`. `context.registerBean<T>(supplier, ...)` is
Spring's `GenericApplicationContext.registerBean`. Registration happens
while the modules load, in registration order; registering anything after
`refresh()` fails with a `StateError` saying so.

```dart
class MessagingRegistrar implements BeanRegistrar {
  const MessagingRegistrar();

  @override
  void register(BeanRegistry registry, Environment env) {
    registry.registerBean<Clock>((_) => SystemClock(), name: 'clock');
    if (env.containsProperty('mail.host')) {
      registry.registerBean<Mailer>(
        (context) => SmtpMailer(context.dependency<Clock>()),
        name: 'mailer', primary: true, lazy: true, description: 'SMTP',
      ); // unnamed: `Mailer#0`, like Spring's uniqueBeanName
    }
  }
}

@Configuration()
@Import([MessagingRegistrar]) // or: context.register(const MessagingRegistrar())
class AppConfig {}

final context = AnnotationConfigApplicationContext([appBeans])
  ..registerBean<Clock>((_) => FixedClock(), name: 'testClock', primary: true)
  ..refresh();
```

The scan takes Spring's filters, evaluated at build time: `includeFilters`
make classes beans without `@Component` (`Filter(classes: [Plugin])` for an
annotation, `Filter(type: FilterType.assignableType, classes: [Handler])`,
`Filter(type: FilterType.regex, pattern: ['.*Repository'])` on the class
name; abstract classes are skipped), `excludeFilters` keep classes out
(they win), `useDefaultFilters: false` scans only the includes and
`lazyInit: true` makes every scanned bean (components and their `@Bean`
methods) lazy unless annotated `@Lazy(false)`.

`@Bean` methods, `@Autowired` members, `@PostConstruct` / `@PreDestroy` and
`@EventListener` methods are also found in superclasses and mixins (Spring
scans the hierarchy), with the type arguments of a generic superclass
(`UserService extends BaseService<User>`) substituted. Generated code cannot
name private declarations: a private bean class, `@Bean` return type,
injected type or default value fails the build with a message naming it,
its library and the fix.

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

Non-null results are published again; a `Future` result is published
when it completes, and its error goes to the multicaster's error handler
(or is logged). `ApplicationListener<E>`, `GenericApplicationListener` and
`SmartApplicationListener` beans work too, also behind another declared
`@Bean` type, as do listener objects given to `registerSingleton` (an
`ApplicationListener<E>` object needs
`ApplicationListenerAdapter.forListener<E>`); a listener is registered
once. `context.addListener<E>(...)` returns a removable registration.
Events published before the listeners are registered (while the bean
factory post-processors run) are replayed once they are; later ones, e.g.
from a bean's constructor, reach the listeners right away (a listener bean
is created for it if needed). Events propagate to the parent context.
A published object that is not an `ApplicationEvent` is wrapped in a
`PayloadApplicationEvent<T>` of its static type: listeners of `T` get the
payload, listeners of `PayloadApplicationEvent<T>` the event; generated
listeners of `PayloadApplicationEvent<T>` match on the payload's runtime
type, like Spring. `@EventListener` methods of a `FactoryBean` run on the
factory, not on its product.

Asynchronous delivery: `SimpleApplicationEventMulticaster(taskExecutor:
SimpleAsyncTaskExecutor())` (as an `applicationEventMulticaster` bean)
calls every listener on the executor, like Spring's `setTaskExecutor`;
errors go to its `errorHandler` (without one the executor logs them).
`@Async()` on an `@EventListener` method runs just that method on a
`TaskExecutor` bean (`@Async('name')` picks one; otherwise the only or
`@Primary` one, else `taskExecutor`), its failure going to the error
handler or the log and its result being published when it arrives. Like
`@EnableAsync`, it is switched on by having a `TaskExecutor` bean: the
scheduling starter registers `applicationTaskExecutor` (alias
`taskExecutor`); without one `@Async` is ignored. The generator accepts
`@Async` on `@EventListener` methods only. As in Spring, a listener's
`condition` runs inside the multicaster's error handling (on the executor
when there is one), so a failing condition reaches the `errorHandler`.

```dart
@Component()
class Mailer {
  @EventListener()
  @Async()
  Future<void> onPlaced(OrderPlaced order) => sendConfirmation(order);
}
```

### Messages, resources, conversion

- `MessageSource`: `StaticMessageSource`,
  `ReloadableResourceBundleMessageSource` (`messages_ru_RU.properties` →
  `messages_ru` → default or system locale → base, `cacheSeconds`
  reloading), `MessageSourceAccessor`, locale fallback,
  `MessageFormat` placeholders, quotes, `number`, `date` / `time`
  (styles and `SimpleDateFormat` patterns), `choice`. Define a bean
  named `messageSource`; the context delegates to it. In a child context
  it falls back to the parent's message source (not the parent context),
  like Spring.
- Resources: `lib/resources/` is the classpath — the generator embeds its
  files, so `classpath:...` works in CLI, AOT, Flutter and web without asset
  declarations; `@Value('classpath:templates/mail.txt') Resource template`
  (resolved by the context's resource loader, so custom protocols and
  asset loaders apply).
  `ResourceLoader` with `classpath:` (also plain paths such as
  `app.properties`, as in Spring), `file:` (percent-decoded:
  `file:my%20dir/a.txt`), `package:my_app/config/app.yml` (the package's
  file through the package config; not on the web or in AOT executables)
  and custom protocols (`ProtocolResolver`, tried first: this is how a
  Flutter asset loader plugs in), `PathMatchingResourcePatternResolver`
  with `AntPathMatcher` for `file:` and classpath patterns: `classpath:`
  searches the first classpath root with the pattern's base directory,
  `classpath*:` every root (added directories, then the embedded
  resources); matching directories are returned too and directories the
  pattern cannot match are not walked. `FileSystemResource` of a directory
  exists but is not readable, like Spring's.

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
  `PT5M`), collections and enums. A `conversionService` bean (also in an
  ancestor context) is used for `@Value` conversion.

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
Elvis, ternary). Numbers follow Spring 7's operators: `int` arithmetic
for integers (`7 / 2` is `3`, `1 / 0` throws `UnsupportedError` like
Java's `ArithmeticException`), `double` once a real number is involved
(`7.0 / 2` is `3.5`, also on the web, where `7.0` is an `int` at run time:
real literals, `T(Math)` functions and the operators on them are tracked),
`^` like `OpPower` (a long above `Integer.MAX_VALUE`, saturating), `==`
with Java's double semantics (`NaN != NaN`) and deep for lists and maps,
`'d' - 3` is `'a'`. Selection (`.?[...]`) keeps the element type of the
source list. `T()` knows the common `java.lang` names (`T(Integer)`,
`T(Character)`, `T(Math)`, `new int[4]`, `new char[2]`), and String has
Java's `format` / `formatted`, `getBytes` and `chars` on top of the Dart
methods. Dart has no reflection: user classes are reached through
`@Introspected` metadata, `FunctionPropertyAccessor` / `FunctionMethodResolver`
or maps. `SimpleEvaluationContext` restricts expressions for data binding
(no types, constructors, bean references or variable assignment).

Safe navigation is Spring 6.2's: a `null` before a `?.` step ends the whole
chain with `null` (`a?.b.c` is `null` when `a` is), for `?.[i]`, `?.?[...]`,
`?.![...]`, `?.^[...]` and `?.$[...]` too. An exception thrown by a called
method or constructor is rethrown as is; failures of accessors and of SpEL
itself are `SpelParseException` / `SpelEvaluationException` with Spring's
`SpelMessage` codes and the position (`Expression [1 + * 2] @4: EL1070E:
Problem parsing left operand`).

`SpelParserConfiguration` (Spring 7's builder) sets auto-grow and the limits
against hostile expressions: length 10 000, nesting depth 1000, operations
per evaluation 10 000 (`EL1085E`; the default follows
`-Dspring.expression.maxOperations`), `'x' * n` up to 256 characters, string
`+` up to 100 000, `matches` patterns (Dart `RegExp` syntax) up to 1000
characters and without nested quantifiers (`(a+)+` is refused as `EL1073E`:
Dart's `RegExp` cannot be interrupted like Spring's matcher).

```dart
final parser = SpelExpressionParser(
  SpelParserConfiguration.builder().maximumOperations(50000).build(),
);
```

In `@Value('#{...}')` the root is the bean factory (`#{mailer}`, `#{@mailer}`)
with `systemEnvironment` (the environment variables), `systemProperties`
(Dart has no JVM system properties: the `--key=value` command-line
arguments, the `commandLineArgs` property source of the `environment` bean,
stand in), `environment['app.name']` and
`environment.getProperty('app.name', 'default')`. Conversions use the
factory's `ConversionService`, parsed expressions are cached by the
resolver, and `-Dspring.context.expression.maxLength` changes the length
limit of `@Value` expressions.

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
group sequences (`@GroupSequence`, `BeanValidator(groupSequences:)`),
`@ConvertGroup`, container element constraints (`@Each([NotBlank()])`,
`@EachKey`), `${validatedValue}` in messages, `@Valid` cascade, custom
`Constraint` subclasses. A constraint on a type it cannot check (`@Size` on
an `int`) or with invalid attributes (`Size(min: -1)`) fails the build, and
at runtime throws `UnexpectedTypeException` / `ConstraintDeclarationException`
like Hibernate Validator. Error codes and arguments follow
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
// {"author":{"born":1920,"name":"Herbert"},"availability":"in_stock",
//  "isbn":"1","published_at":null,"tags":[],"title":"Dune"}
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
| `@JsonInclude(JsonInclusion.nonNull)` | on a property or class: skip `null` values (`nonAbsent`, `nonEmpty`, `nonDefault`: also empty / default values) |
| `@JsonIgnoreProperties(value: ['x'], ignoreUnknown: true)` | on a class: names to ignore; accept unknown properties |
| `@JsonPropertyOrder(['id', 'title'])` | on a class: these properties first, the rest after; `@JsonPropertyOrder.alphabetic()` sorts the rest whatever the mapper says |
| `@JsonCreator()` | the constructor to read with |
| `@JsonValue()` | on an enum field: the JSON form of each value (also for enum map keys) |
| `@JsonAlias(['name', 'fullName'])` | other JSON names accepted when reading |
| `@JsonFormat(pattern: 'dd.MM.yyyy', timezone: '+01:00', shape:)` | date pattern and offset; `JsonFormatShape.number` / `string` |
| `@JsonAnyGetter()` / `@JsonAnySetter()` | a map property written as extra properties / receiving the unknown ones |
| `@JsonUnwrapped(prefix:, suffix:)` | the nested object's properties inline |
| `@JsonNaming(PropertyNamingStrategy.snakeCase)` | on a class: its naming strategy |
| `@JsonView(Public)` | written / read only with that view (`writerWithView`, `readerWithView`) |
| `@JsonTypeInfo(...)`, `@JsonSubTypes([...])`, `@JsonTypeName('cat')` | polymorphic types: the id as a property, an existing property, a wrapper object or array, or by deduction; `defaultImpl` |

**Property order** is Jackson 3's / Spring Boot 4's: the properties of an
object are written sorted by JSON name (`SORT_PROPERTIES_ALPHABETICALLY`),
the constructor parameters first and the other properties after them
(`SORT_CREATOR_PROPERTIES_FIRST`), each group sorted. This is a change from
earlier versions, which wrote the declaration order (superclass first):
`ObjectMapper(sortPropertiesAlphabetically: false)` — in Spring Boot
`spring.jackson.mapper.sort-properties-alphabetically=false` — brings that
back. `@JsonPropertyOrder` wins either way: the listed names (JSON or Dart
names) come first, the others follow in the mapper's order. Reading does not
depend on the order.

Built in: `String`, `int`, `double`, `num`, `bool` (numbers and booleans in
strings are accepted; `NaN` / infinities as `"NaN"`, `"Infinity"`,
`"-Infinity"`), `DateTime` (ISO-8601 like Jackson writes an
`OffsetDateTime`: `2026-01-01T12:00:00.000+02:00` for local times, `Z` for
UTC, so a Spring `Instant` reads it; with `writeDatesAsTimestamps` epoch
seconds with the fraction, `1700000000.123456`, like Jackson 3),
`Duration` (ISO-8601 `PT1M30S`, or seconds with
`writeDurationsAsTimestamps`; also reads `90s` and numbers as seconds), `Uri`, `BigInt` (as a string), enums, `List`, `Set`,
`Map`, nullable types and nested objects; `readValue<Map<String, dynamic>>`,
`readValue<List<dynamic>>` and `readValue<Object?>` give the plain decoded
JSON. A class that already has `fromJson` / `toJson` (`json_serializable`,
`freezed`) is converted with them. Anything else: a `JsonSerializer<T>` /
`JsonDeserializer<T>`, passed to `ObjectMapper(serializers:,
deserializers:)`, declared as a bean or grouped in a `JsonModule` bean
(Spring Boot adds every serializer, deserializer and `JsonModule` bean, like
`@JsonComponent`s and Jackson `Module`s).

Settings: `namingStrategy` (`snakeCase`, `kebabCase`, `upperCamelCase`,
...), `inclusion`, `failOnUnknownProperties` (off, like Spring Boot),
`writeDatesAsTimestamps`, `timeZone` (`UTC` or a fixed offset such as
`+02:00`), `indentOutput`, `sortPropertiesAlphabetically` (on) — in Spring Boot from
`spring.jackson.*` (see `spring_boot_dart`).

Errors name the place: `items[2].price: expected a number, got "abc"`,
`missing property "isbn" (required by Book)`.

Classes of other packages are introspected with
`@Introspected(classes: [ExternalDto])`. Generic model classes
(`Page<T>`) are read with their type arguments:
`mapper.readValue(json, const GenericType<Page<Book>>([ClassType<Book>()]))`. `readTree` gives a
`JsonNode` tree; `JsonMapper.builder()` / `mapper.rebuild()` configure with
Jackson's feature enums (`SerializationFeature`, `DeserializationFeature`,
`DateTimeFeature`, `MapperFeature`). Not supported yet: getters without a
field.

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
| `within(TypePattern)` | every member whose body is in a matching class: an inherited, not overridden member is within its superclass (AspectJ's lexical scope); `Type+` also subtypes | `within(*Repository)`, `within(Repository+)` |
| `target(Type)`, `this(Type)` | every member of beans of that type or a subtype (interfaces too) | `target(PaymentGateway)` |
| `args(types)` | methods whose arguments have these types: the declared parameter type, else the runtime argument (`..` any number) | `args(String, ..)` |
| `@args(Annotation, ..)` | methods whose arguments' classes carry the annotations | `@args(Audited)` |
| `bean(namePattern)` | every member of beans with that name, an alias or a qualifier value | `bean(order*)` |
| `@annotation(Annotation)` | methods carrying the annotation (also when it is on the interface method they implement) | `@annotation(Timed)` |
| `@within(Annotation)` | every member whose body is in a class carrying the annotation | `@within(Service)` |
| `@target(Annotation)` | every member of beans whose class carries the annotation | `@target(Service)` |
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
- `execution` modifiers: `public`, `protected` (Dart has no such modifier:
  it matches `@protected` members of `package:meta`) and `private` (never
  matches: private members are not proxied). A `throws` clause is an error,
  since Dart methods declare no exceptions; select errors with a typed
  `@AfterThrowing` parameter instead.

Operators: `&&` / `and`, `||` / `or`, `!` / `not`, and parentheses.

Examples:

| Pointcut | Advises |
|---|---|
| `execution(* *(..))` | every method of every bean (methods only: `execution` never matches getters or setters, explicit or the implicit ones of a public field) |
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

A pointcut binds advice parameters by name, as in AspectJ: a lowercase
identifier in `@annotation(timed)`, `@within(timed)`, `@target(timed)`,
`@args(audited)`, `this(proxy)`, `target(bean)` or `args(id, ..)` names a
parameter of the advice method, which receives the annotation, the proxy,
the bean or the argument (a type name starts with an uppercase letter; `int`, `double`,
`num`, `bool`, `dynamic` and `void` are types). The bound value must have
the parameter's type, else the call does not match.
`@AfterReturning(.., returning: 'result')` / `@AfterThrowing(.., throwing:
'error')` name the parameter that receives the return value or error (by
default the first one that is neither a `JoinPoint` nor bound). Advice and
`@Pointcut` methods of the aspect's superclasses and mixins are inherited.
A parameter the pointcut does not bind, or a bound name without a
parameter, fails the build; an invalid pointcut fails when the context
starts, with the reason; the Zed extension (`dart_spring`) underlines it
while you type.

```dart
@Around('@annotation(timed) && args(isbn, ..)')
Object? time(ProceedingJoinPoint joinPoint, Timed timed, String isbn) =>
    joinPoint.proceed();
```

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

Aspects can be per instance, as in Spring: `@Aspect('perthis(pointcut)')`
or `@Aspect('pertarget(pointcut)')` on a `@Scope('prototype')` aspect gives
one aspect instance per proxy or per target bean (a singleton per-instance
aspect, `percflow` and `pertypewithin` fail the build).
`@DeclareParents('Type+', defaultImpl: Impl) static Iface? mixin;` on an
aspect makes the generated proxies of the matching beans of its module
implement `Iface`, forwarding to one `Impl` per proxy; `this(iface)` binds
it. Proxies are `Advised`: `addAdvisor`, `removeAdvisor`, `addAdvice` and
`removeAdvice` change the advice of a live proxy. `ComposablePointcut`
combines pointcuts with `union` and `intersection`;
`ProxyFactory.forBean(beanFactory, name)` and `AspectJProxyFactory`
(`addAspect`) create more proxies of a bean's generated proxy class.

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
interfaces, so the bean can be injected by either. A component class that
cannot be implemented (private members, operators, `base`) and has no
interface is created as a generated subclass instead, which runs its
public methods, getters and setters through the advice (Spring's CGLIB
proxy): the bean is its own proxy, `AopUtils.isAopProxy` is true once
advice is attached, and a member the subclass cannot override (a private
type, a default value that is not a public constant) is inherited and not
advised, with a build warning. A component class that can be neither
implemented nor extended (`final`, `sealed`, `interface`, a factory
constructor), like a `@Bean` method's type that cannot be proxied, keeps
its signatures: advice matching it fails the context at startup with the
reason and what to change; add an interface with the advised methods and
inject the bean by it. `AopUtils.getTarget(bean)` unwraps a
proxy. The generator option `aop_proxies` (`all` by default, `interfaces`,
`none`) controls which proxies are generated (subclass proxies only in
`all`; see `spring_core_dart_generator`). Annotations are
matched by names the generator writes, so `@annotation(Timed)` also works in
minified and obfuscated release builds.

Public fields are advised like explicit getters and setters: a field `int
count` is an implicit getter `count` and (when not `final`) setter `count=`,
and the proxy overrides both. They are `MemberKind.getter` / `setter`
members, reached through `within`, `bean`, `target`, `@within`, custom
advisors and `@annotation(X)` (an annotation on the field counts for both
accessors, except constraints and `@Valid`, which validate the field). Spring
has no implicit accessors, so there is no `get*` name to match with
`execution`.

The build parses every advice and `@Pointcut` expression with the runtime's
own parser: a syntax error fails the build with the aspect, the advice and
the character position, instead of the context at startup (a reference to a
pointcut of a class outside the module is left to the runtime). In
`aop_proxies: all` the `@SpringBootApplication` output, which knows every
module of the application (its scan, the nested `@ComponentScan` modules it
imports, the auto-configurations), also skips the proxy class of a bean no
pointcut of the application can match (`execution` and `within` with a type
pattern, `@annotation` when no member carries the annotation, `bean(...)`;
decided with the same matcher the runtime uses). It keeps the bean's
signatures, so an advisor that turns out to match it anyway (a module added
by hand) fails the startup with the reason instead of being skipped
silently. Nothing is skipped in a `@ComponentScan` module (any other module
may import it), when no module has advice, when a module declares an
advisor bean or an auto-configuration declares aspects, for a bean whose
class or members carry an annotation from outside `spring_core_dart` or
`@Validated` (annotation-driven advisors such as `@Cacheable`), for beans
with a `@DeclareParents` introduction, or for subclass proxies. `aop_prune: false` in
`build.yaml` generates the proxies of every bean again.

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

Post-processor beans are created in Spring's phases
(`PostProcessorRegistrationDelegate`): `PriorityOrdered`, then `Ordered`
(or `@Order`), then the rest — each phase only after the previous one is
registered or invoked, so a `PriorityOrdered` `BeanPostProcessor` already
processes the `Ordered` ones; the names are queried again before each
phase (registry post-processors repeat the last phase while they register
more of themselves). A regular bean created while the `BeanPostProcessor`s
are registered (a dependency of one of them) misses the later ones; like
Spring's `BeanPostProcessorChecker` this is logged at info level ("Bean
'repo' of type [Repo] is not eligible for getting processed by all
BeanPostProcessors ...", naming the post-processor being created) — make
such a dependency an `ObjectProvider` or `@Lazy`. `EmbeddedValueResolverAware`
gets Spring's `EmbeddedValueResolver`: `${...}` placeholders, then `#{...}`
SpEL (`resolver(r"#{'${app.home}' + '/cache'}")`).

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
| `List<@NotBlank String>` (container element constraints) | `@Each([NotBlank()])` on the list (map values too), `@EachKey([...])` for map keys | Dart has no annotations on type arguments |
| `@GroupSequence` on a group interface | `BeanValidator(groupSequences: {Complete: [Default, Strict]})` (`@GroupSequence` on a validated class works as in Java) | Dart group types carry no annotations readable at runtime |
| `Validator.supports(Class)` | `supports(Object target)` | Dart cannot test subtypes on a `Type` |
| `@Autowired` on a private field or setter (reflection) | Only public fields and setters; a private field is injected through a constructor parameter (`this._repo`, Dart 3.13 primary constructors included) | The generated code is another library and cannot reach private members |
| CGLIB-enhanced `@Configuration` classes | A generated subclass in the `.spring.dart` file: a class with instance `@Bean` methods must be extendable from another library (not `final`, `sealed` or `interface`, public generative constructor) or use `proxyBeanMethods: false`, else the build fails; an inter-bean call of a `FactoryBean` method returns the container's factory itself (Spring: an enhanced factory whose `getObject()` returns the container's product) | No runtime bytecode generation |
| `@Bean` definitions know only the declared return type until the bean is created (`beanClassName` is `null`) | The type of the returned expression(s) is known at build time and the definition is registered under it and its supertypes: `getBean<HikariDataSource>()`, `getBeanNamesForType`, `@ConditionalOnBean` / `@ConditionalOnMissingBean` and AOP (`within(Impl)`, annotations on implementation methods) see it before the bean exists | Deliberately better: the generator sees the method body |
| Duplicate bean names are found at startup (Boot disables overriding) | Two unconditional declarations of one name fail the build; declarations with conditions (`@Profile`, `@Conditional...`) may share a name and are checked at refresh (`BeanDefinitionOverrideException` when both match) | Fail early when the clash is certain |
| CGLIB / JDK proxies | Generated `implements` proxies | Final or private-member classes are proxied through interfaces only |
| Circular references (opt-in) | Always an error | Same as Spring Boot's default |
| `SmartFactoryBean.getObject(Class)` | `getObjectForType(Type)`; the extra product types are served once the factory exists | No overloading; no reflection on types not created yet |
| `@Lookup` methods with arguments (passed to the bean's constructor by `getBean(name, args)`) | Lookup methods take no parameters (build error): inject an `ObjectProvider<T>` or a factory and pass the values yourself | Generated bean definitions resolve the constructor arguments themselves |
| CGLIB subclass for `@Lookup` methods | A generated subclass in the `.spring.dart` file: the class must be extendable from another library and the methods public | No runtime bytecode generation |
| `registerSingleton(name, object)` is found by every type of the object | Without `types:` it is found only by its runtime type: pass `types: [SystemClock, Clock]` to find it by its interfaces | Dart cannot list the supertypes of an object at runtime |
| `SmartInstantiationAwareBeanPostProcessor.getEarlyBeanReference` / `determineCandidateConstructors` | Only `predictBeanType` | No early references (circular references are errors); the generator picks the constructor |
| Asynchronous initialization | `refresh()` is synchronous (load config first with `processAndApply()`); `refreshAsync()` awaits `Future`-returning init callbacks, the bean being injectable meanwhile | Dart cannot block on a `Future` |
| `execution(* getName(..))` matches an explicit or generated getter (they are methods in Java) | `execution` matches methods only; a public field is an implicit getter / setter that the proxy advises (`MemberKind.getter` / `setter`, reached by `within`, `bean`, `@annotation`, custom advisors); an explicit getter is a getter too | Dart has getters and setters of its own and fields have implicit ones |
| Package-qualified AOP type patterns | Simple type names; qualified wildcards are rejected | No packages in Dart |
| `execution(protected ...)`, `throws` patterns | `protected` matches `@protected` members (`package:meta`), `private` matches nothing; a `throws` clause fails the build | Dart has no protected modifier and declares no exceptions |
| `args(Type)` / `@args(A)` test any runtime class (reflection) | Type tests the generator writes for the types named in the aspect and the scanned classes carrying the annotation | No reflection |
| `@DeclareParents` applies to any matching bean | To the generated proxies of the matching beans of the aspect's module | Proxy classes are written at build time |
| `ProxyFactory` proxies any object | `ProxyFactory` / `AspectJProxyFactory` need the generated proxy class of a bean (`ProxyFactory.forBean`) | No runtime proxy classes |
| A generic bean class matches generic injection points (`ResolvableType`) | Registered under its raw type (`Repo<dynamic>`); inject it by that type, or declare a `@Bean Repo<User>` | Type arguments of a class bean are not known at runtime |
| Beans of functional interfaces and records are classes | Function and record beans are found by their exact type, in single injection points only | Dart function and record types are structural |
| Jackson `ObjectMapper` (reflection) | `ObjectMapper` on generated metadata; a model needs `@Introspected()` (its classes of the same package are included) | No reflection |
| Optional `@Value` with `${x:#{null}}` | A nullable target gets `null` when a placeholder is missing | Dart null safety |
| Lazy beans, prototypes and `@Lazy` injection points fail on first use | `refresh()` validates them too (missing or ambiguous beans, cycles, placeholders) | Fail at startup, not later |
| `getBean` does not return `registerResolvableDependency` values | `getBean<BeanFactory>()`, `getBean<ApplicationContext>()` return them | Same objects that injection gets |
| Custom qualifier annotations match by type and attributes | They match by their qualifier value only | Annotations are not read at runtime |
| `@EventListener(condition = "#event.big")` (SpEL) | `condition:` takes a Dart function | Type-checked, no reflection |
| `@EnableAsync` switches `@Async` on; `@Async` on any bean method (proxies) | A `TaskExecutor` bean switches it on (the scheduling starter has one); `@Async` on `@EventListener` methods only; a `TaskExecutor` runs tasks in a later event-loop turn | No runtime proxies; Dart isolates have no threads |
| `ImportSelector.selectImports(metadata)` returns class names; registrars get the importing class's metadata; imported classes get fully-qualified names; `BeanRegistry.registerBean(Class)` instantiates the class | `selectImports()` returns `BeanModule`s, no metadata; simple bean names; `registerBean<T>` needs a supplier | No reflection, no packages in Dart |
| `SmartLifecycle.stop(Runnable callback)` blocks `close()`, `stop()` and `restart()` per phase | `stopWithCallback(callback)`; `closeAsync()` waits for a later callback (per-phase timeouts), `close()` goes on; a bean asked to start while its callback is pending (`restart()`, `start()` after `stop()`) starts when the callback fires | No overloading; Dart cannot block on a `Future` |
| A `null` result reaches an `@AfterReturning` parameter of any type | Only `Object?` / `dynamic` (and nullable types) get `null` | Dart null safety |
| Jackson writes Java enums by name (`IN_STOCK`) | Enums go over the wire by their Dart name (`inStock`); use `@JsonValue` to talk to Java peers | Dart naming conventions |
| Jackson `BigInteger` as a JSON number | `BigInt` as a string | `jsonEncode` has no arbitrary-precision numbers |
| Jackson's `null` / missing value for a primitive is `0` / `false` (unless `FAIL_ON_NULL_FOR_PRIMITIVES`) | A JSON `null` or missing value for a non-nullable type is an error | Dart null safety |
| `spring.jackson.time-zone` with any zone ID | `UTC` / `Z` or a fixed offset (`+02:00`, `GMT+2`); a named zone (`Europe/Berlin`) fails at startup with a message saying so | Dart has no time zone database |
| Boot binds every `spring.jackson.*` key (Jackson features, `date-format`, `locale`, ...) | Only the keys of the `spring_boot_dart` table are read; any other `spring.jackson.*` key is logged as a warning and ignored | The mapper has only the feature enums `JsonMapper.builder()` lists |
| SpEL `matches` and String methods are Java's | Dart's `RegExp` syntax and Dart's String methods (`replaceAll` with a string is literal) | Dart runtime |
| SpEL `T(java.lang.Math)` finds any class | `T()` needs registered types and takes Dart type names (`T(int)`) and the common `java.lang` ones | No reflection |
| SpEL on the JVM knows `7.0` from `7` | On the web an integral double that comes from outside SpEL (a variable, a bean property, an element of a collection SpEL did not build) counts as an `int` | JavaScript has one number type |
| SpEL `1 instanceof T(Long)` is `false` (an `Integer`) | `true`: `T(Long)`, `T(Integer)`, `T(Short)` and `T(Byte)` are all Dart's `int` | Dart has one integer type |
| Boot reads `.properties` config files as ISO-8859-1 | UTF-8 unless the loader says otherwise (`PropertiesPropertySourceLoader(encoding: latin1)`) | Dart files are UTF-8 |
| `ReloadableResourceBundleMessageSource` reload checks every resource's timestamp | File resources by modification time; others are re-read; preloaded (async-only) resources change only through `preload()` | Not every resource has a timestamp or sync reads |

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
except the Dart team's `package:yaml` (for `application.yml`). CI enforces
it with
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
example (tour and Spring Boot app), 29 (language server). Generated `*.spring.dart` files are committed. CI
(`.github/workflows/ci.yml`) also checks that generated code is up to date,
runs the tour, and runs the AOP release check as minified JavaScript.
