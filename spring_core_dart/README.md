# spring_core_dart

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

`spring_core_dart` creates the objects of your application, gives each
one the other objects it needs, and configures them from settings files.
You write the classes and mark them with annotations; the package does
the wiring. It is the core of a port of Spring, the Java framework, to
Dart and Flutter.

**The problem it solves.** In a Dart program of some size, `main` ends up
building every service by hand, in the right order, and passing each one
its dependencies. Every new constructor parameter means editing `main` and
every test that builds the class. Settings are parsed by hand, and choosing
a fake payment service in development means an `if` somewhere. With this
package a class declares what it needs in its constructor, and the
container builds the whole graph, reads the settings, and picks the right
implementation for the active environment.

**Who needs it.** Dart servers, command-line tools and Flutter apps with
more than a handful of services, and teams who know Spring and want the
same structure in Dart. Most applications use it through
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart), which
starts everything from one annotation on `main`, or through
[`spring_boot_starter_flutter`](https://pub.dev/packages/spring_boot_starter_flutter)
in a Flutter app. This package is what both are built on, and what your
own classes use.

What it contains:

- a dependency injection container (beans, scopes, lifecycle, events);
- configuration from `application.properties` / `application.yml`,
  environment variables and the command line, with profiles;
- messages, resources and type conversion;
- SpEL, Spring's expression language;
- validation and data binding;
- JSON with an `ObjectMapper`;
- AOP: code that runs around the methods of other beans.

It is pure Dart and works in Flutter, AOT executables and on the web. Dart
there has no reflection (`dart:mirrors`), so the annotations are read at
build time by
[`spring_core_dart_generator`](https://pub.dev/packages/spring_core_dart_generator),
which writes plain Dart code that creates your objects.

Repository: <https://github.com/farum-azula/spring_core_dart>.

## Packages

| Package | Path | What it is |
|---|---|---|
| `spring_core_dart` | [`spring_core_dart/`](https://github.com/farum-azula/spring_core_dart/tree/main/spring_core_dart) | The runtime: annotations, container, environment, events, SpEL, JSON, validation, AOP. Its only dependency is the Dart team's `package:yaml`. |
| `spring_core_dart_generator` | [`spring_core_dart_generator/`](https://pub.dev/packages/spring_core_dart_generator) | The `build_runner` builder that turns the annotations into `*.spring.dart` modules. Required. |
| `neon_books_server`, `neon_books_app` | [`example/`](https://github.com/farum-azula/spring_core_dart/tree/main/example) | The guides: a bookstore's server and its Flutter app, which use every feature, chapter by chapter, with tests. |

The runtime is split into libraries. Import one of them, or
`package:spring_core_dart/spring_core_dart.dart` for all:

| Library | What it holds | Spring counterpart |
|---|---|---|
| `core.dart` | `Environment`, property sources, profiles, `ConversionService`, resources, `AntPathMatcher`, config files | `spring-core`, Spring Boot config data |
| `beans.dart` | `BeanDefinition`, `DefaultListableBeanFactory`, `FactoryBean`, post-processors, scopes, `BeanWrapper`, introspection | `spring-beans` |
| `context.dart` | annotations, `ApplicationContext`, conditions, events, lifecycle, `MessageSource` | `spring-context` |
| `expression.dart` | the expression language | `spring-expression` (SpEL) |
| `validation.dart` | constraints, `BeanValidator`, `DataBinder` | `org.springframework.validation`, Bean Validation |
| `aop.dart` | aspects, advice, pointcut expressions, advisors | `spring-aop` |
| `json.dart` | `ObjectMapper` and the JSON annotations | Jackson |
| `jakarta.dart` | `Provider<T>` and `@Resource`, kept apart because their names clash with other libraries (not exported by `spring_core_dart.dart`) | JSR-330, JSR-250 |

## Installation

```yaml
dependencies:
  spring_core_dart: ^0.5.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.5.0
```

The generator has two options, set in your package's `build.yaml`. They
only change how much code is generated (see [AOP](#aop)):

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

A settings file. Files in `lib/resources/` are the "classpath": the
generator embeds them, so they are found on every platform.

```properties
# lib/resources/application.properties
app.title=NEON
spring.profiles.active=dev
```

One file tells the generator where to look for beans: every class in its
directory and below.

```dart
// lib/src/beans.dart
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:my_app/src/beans.spring.dart'; // written by the generator

@ComponentScan()
final BeanModule appBeans = $appBeans;
```

A bean: a class the container creates. It asks for a setting in its
constructor.

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

Generate the code, again after every change to the annotations (or keep
`watch` running):

```bash
dart run build_runner build   # or: dart run build_runner watch
```

Start the container:

```dart
const log = SpringLog('neon');

Future<void> main(List<String> args) async {
  // Without a logging backend only warnings are shown; show info too.
  SpringLog.level = SpringLogLevel.info;

  // Creating the module registers the embedded lib/resources/ files.
  final modules = [appBeans];

  // Settings: command-line arguments (--app.title=X) win over the files.
  final environment = StandardEnvironment()
    ..propertySources.addFirst(SimpleCommandLinePropertySource(args));
  await ConfigDataEnvironment(environment).processAndApply();

  final context = ApplicationContext.run(modules, environment: environment);
  log.info(context.getBean<Greeter>().greet('Ada')); // Hello Ada from NEON
  context.close();
}
```

With [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) the
whole `main` is
`@SpringBootApplication() void main(List<String> args) => runApplication(args);`.

## Guide

### Declaring beans

A **bean** is an object the container creates, keeps and hands to the
objects that need it. You declare one by annotating a class, or by writing
a method that returns it. By default a bean is a **singleton**: one
instance, created at startup and shared.

```dart
@Repository()
class BookRepository {
  Book? find(String isbn) => null;
}

@Service()
class Catalog {
  Catalog(this.books); // the container passes the BookRepository bean
  final BookRepository books;
}

// A class you cannot annotate (it comes from another package) becomes a
// bean through a @Bean method of a configuration class.
@Configuration()
class HttpConfig {
  @Bean()
  http.Client httpClient() => http.Client(); // closed with the context
}
```

| Annotation | What it does |
|---|---|
| `@Component([name])`, `@Service`, `@Repository`, `@Controller`, `@Named` | Makes the class a bean. They differ only in name; subclass `Component` for your own stereotypes. |
| `@Configuration(name:, proxyBeanMethods:)` | A bean whose `@Bean` methods declare more beans. |
| `@Bean(name:, aliases:, initMethod:, destroyMethod:, autowireCandidate:)` | Makes the method's result a bean; the method's parameters are injected. |
| `@Scope('prototype', proxyMode:)` | Changes the scope: `ScopeType.*` constants or a custom scope's name. |
| `@Lazy()` | Creates the singleton on first use instead of at startup. |
| `@Primary()`, `@Fallback()`, `@Qualifier('x')` | Chooses between several beans of one type (see [Injection](#injection)). |
| `@DependsOn([...])` | Creates the named beans first. |
| `@Order(n)` | Position in an injected `List` (lower first). |
| `@Description('...')` | Documentation of the bean. |

**Names.** A bean's default name is its class name in lowerCamelCase
(`OrderService` is `orderService`; `URLService` stays `URLService`). An
explicit name or alias must not be empty, blank or padded with spaces.

**What can be a bean.** Only classes. On a mixin, enum, extension or
extension type (which does not exist at runtime) the build fails and says
what to use instead. The scan skips abstract classes, as Spring's does. A
generic class is registered under its raw type: `Repo<T>` as
`Repo<dynamic>`, type arguments at their bounds.

**Types.** A bean is registered under its own type and all its public
supertypes, so it can be injected by any of them. Generic supertypes are
matched by the full type (`Store<User>`).

**`@Bean` methods.** The bean's type is what the method body returns, not
only the declared type: `DataSource ds() => HikariDataSource()` is a
`HikariDataSource`, also found as `DataSource`. Its destroy method is
inferred (`close`, `shutdown` or `dispose`, called when the context
closes) unless you write `destroyMethod: ''`. A method may return a
function type (`String Function(String)`, a typedef) or a record type; such
a bean is injected by that exact type, into single injection points only.

A `@Bean` method may return `null` (declared `T?`). The bean is then a
`NullBean`: found by name, but absent for lookups by type and for
injection. `getBean<T>()` and required injection points fail,
`findBean<T>()` and optional points get `null`, collections leave it out,
and a call from another `@Bean` method returns `null`.

**`@Configuration` classes.** By default (`proxyBeanMethods: true`) the
container creates a generated subclass whose `@Bean` methods return the
container's beans. So a `@Bean` method that calls another one gets the
singleton, not a new object (for a prototype: a new instance; static
methods are not intercepted). With `proxyBeanMethods: false` ("lite"
mode, also for `@Component` classes with `@Bean` methods and for
`@AutoConfiguration`) the methods are called as written. `@Lazy`,
`@Profile` and conditions on the class (also on a lite `@Component` with
`@Bean` methods) apply to its `@Bean` methods, unless a method says
otherwise (`@Lazy(false)`).

**Scopes.** A **prototype** bean is created anew for every request.
Register your own scopes with `registerScope(name, CustomScope)`, for
example `SimpleMapScope`. A scoped bean injected directly into a singleton
would be fixed at injection time, which is logged as a warning. To avoid
that, give it `proxyMode: ScopedProxyMode.targetClass` (or `interfaces`):
the singleton then gets a generated scoped proxy that asks the scope for
the current instance on every call (by hand: `BeanDefinition(scopedProxy:)`).

**Factory beans.** A `FactoryBean<T>` is a bean that makes another object:
its product is found by the factory's name and by type `T`, and `&name`
returns the factory itself. A `FactoryBean` given to `registerSingleton`
is found by its `objectType` (`T`).

Spring: the same annotations, with `@Bean` definitions that know only
their declared type until created (see
[Differences from Spring](#differences-from-spring)).

### Injection

**Dependency injection** means a class does not build what it needs: it
declares it, and the container passes it in. A dependency can be declared
in the constructor (the usual way), on a field, a setter or a method.

```dart
@Service()
class OrderService {
  OrderService(
    this.repository,                // the only OrderRepository bean
    @Qualifier('fast') this.cache,  // the bean named or qualified 'fast'
    this.listeners,                 // every OrderListener bean, by @Order
    this.reports, {                 // a provider: the bean is made on demand
    this.audit,                     // nullable: null when there is no AuditLog
    @Value(r'${orders.limit:100}') required this.limit, // a setting
  });

  final OrderRepository repository;
  final Cache cache;
  final List<OrderListener> listeners;
  final ObjectProvider<ReportBuilder> reports;
  final AuditLog? audit;
  final int limit;

  @Autowired()
  late final Clock clock;                    // a field

  @Autowired()
  set metrics(Metrics value) {}              // a setter

  @Autowired()
  void init(Environment environment) {}      // a method
}
```

**What can be injected.**

- A single bean of the parameter's type.
- `List<T>`, `Set<T>` or `Map<String, T>`: every candidate, also from
  parent contexts. Only a `List` is sorted: `PriorityOrdered`, then
  `Ordered`, then `@Order`. An `@Order` on a `@Bean` method beats the
  bean's `Ordered.order`; an `@Order` on its class does not. A `Set` or
  `Map` keeps registration order.
- `ObjectProvider<T>`: asks for the bean only when your code calls it
  (lazy, optional, or one of several).
- The container's own objects: `BeanFactory`, `ApplicationContext`,
  `ApplicationEventPublisher`, `ResourceLoader` and `Environment`.
- `@Value('...')`: a setting or an expression (below).

**Optional dependencies.** A nullable type makes a dependency optional.
`@Autowired(required: false)` applies to constructors only. A constructor
or `@Bean` parameter with a Dart default value keeps the default when no
bean (or property) is found, and a required `List`, `Set` or `Map` there
is empty when nothing matches (Spring's single-constructor fallback).
Field and setter injection still require a bean.

**Choosing between several beans.** When more than one bean matches a
single dependency, the container takes, in this order:

1. the only candidate;
2. the single `@Primary` one (a local `@Primary` beats a parent context's;
   two `@Primary` candidates are an error);
3. the only one that is not `@Fallback`;
4. the one named like the parameter (bean names and aliases, not
   qualifier values), or the one whose name is the `@Qualifier` value.

A bean's name or alias, also one added with `registerAlias`, matches
`@Qualifier` and the parameter name. A bean with
`autowireCandidate: false` is never injected, not even through a
`@Qualifier`, but `getBean` still finds it by name or as the only bean of
its type.

**A bean is never injected into itself.** So a `@Primary` composite or
decorator of `Greeter` that asks for `List<Greeter>` receives the *other*
greeters. A configuration's own `@Bean` products are left out of its
collections and single dependencies unless nothing else matches (a
collection then gets them, never the configuration itself).

**Parent contexts.** Beans of parent contexts are candidates too, with
their `@Primary`, `@Order`, `autowireCandidate` and qualifiers. A local
bean of the same name hides a parent's.

**Settings with `@Value`.** `@Value` resolves `${key:default}`
placeholders, evaluates `#{...}` expressions, and converts the result to
the target type (`int`, `Duration`, `List<String>`, enums registered with
`addEnum`, ...). A nullable target gets `null` when a placeholder has no
value. Write the string raw (`r'${...}'`): in a normal Dart string
`${...}` is interpolation.

**Errors.** A dependency that cannot be resolved (no bean, several
candidates, a dependency that fails to create) fails `refresh()`, or the
bean's creation, with an `UnsatisfiedDependencyException` naming the bean
and the injection point (`Bean 'shop' has an unsatisfied dependency
Greeter 'greeter': ...`). Its `cause` is the lookup error or the nested
bean's failure, so the message shows the chain of beans.

`refresh()` checks the whole graph before creating the application's
beans: missing and ambiguous dependencies, unresolvable placeholders,
`@DependsOn` names and cycles. Configuration errors fail at startup, not
on first use. Only post-processors and infrastructure beans
(`messageSource`, ...) are created before that check.

#### Lazy injection points

`@Lazy()` on an injection point injects a generated proxy that looks the
bean up on first use. Use it to break a dependency cycle, or to let a bean
call itself through its AOP proxy, so that the advice runs:

```dart
@Service()
class BookService implements Books {
  BookService(@Lazy() this._self); // also on fields and setters
  final Books _self;

  @Timed()
  @override
  Book find(String isbn) => Book(isbn);

  // _self.find goes through the proxy, so @Timed applies; this.find
  // would skip it.
  List<Book> findAll(List<String> isbns) =>
      [for (final isbn in isbns) _self.find(isbn)];
}
```

The bean must exist and be unique (checked at refresh). The type must be
an interface or a class without private members, not generic, and the
injection point must not be nullable; otherwise the build stops and
suggests `ObjectProvider<T>`.

In Spring: the lazy-resolution proxy of `@Lazy` injection points.

#### `Provider` and `@Resource`

The JSR-330 and JSR-250 names clash with other libraries, so they live in
`package:spring_core_dart/jakarta.dart`. A `Provider<T>` injection point
gets the same lazy provider as `ObjectProvider<T>` (call `get()`).
`@Resource` on a field or setter injects by bean name: the member's name,
or by type when no bean has that name; `@Resource(name: 'x')` takes
exactly that bean.

```dart
import 'package:spring_core_dart/jakarta.dart' as jakarta;

@Service()
class Reports {
  Reports(this.clock);
  final jakarta.Provider<Clock> clock; // clock.get() on every use

  @jakarta.Resource(name: 'archiveStore')
  late final Store store;
}
```

#### Lookup methods

A method marked `@Lookup()` returns a bean of the container on every
call: the bean of its return type, or the bean named by
`@Lookup('name')`. A nullable return type gives `null` when no bean
matches. The usual use is a singleton that needs a new prototype each
time.

```dart
@Component()
@Scope(ScopeType.prototype)
class Command {
  void run() {}
}

@Component()
abstract class CommandManager {
  @Lookup()
  Command createCommand();        // a new Command per call

  @Lookup('auditLog')
  AuditLog auditLog();

  void process() => createCommand().run();
}
```

The bean is created as a generated subclass that overrides the lookup
methods, so they can be abstract. That is why an abstract `@Component`
class with `@Lookup` methods is a bean, while the scan skips other
abstract classes. A concrete method works too; its body never runs.

The build fails when a `@Lookup` method takes parameters, is private,
static or generic, or (looked up by type) returns no class type. It also
fails when the class cannot be extended from the generated library
(`final`, `sealed`, `interface`, only factory or private constructors,
several `@Autowired(required: false)` constructors) or is a full-mode
`@Configuration` class. If the bean is advised, its AOP proxy wraps the
generated subclass (a subclass proxy extends it), so lookup methods can be
advised too.

In Spring: lookup method injection.

#### Primary constructors and other new syntax

The generator understands the syntax of Dart 3.13 and later: primary
constructors (also on `@Configuration` and `@Introspected` classes, with
annotations on their parameters), `class const`, in-body `new(...)`,
`new name(...)` and `factory name(...)` constructors, and private named
parameters (injected under their public name).

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

Primary constructors work with collections too
(`class Greeter(this._all) { final List<String> _all; }`), with the field
declared in the header or in the body.

#### Choosing the constructor

When a class has several constructors, the container picks one:

- An `@Autowired()` constructor is used. It must be the only `@Autowired`
  one.
- Several `@Autowired(required: false)` constructors are candidates: the
  bean is created with the one with the most parameters whose beans
  exist, checked when the bean is created. The constructor callable
  without arguments is the last resort.
- Without `@Autowired`: the only public constructor (generative ones count
  before factories), else the primary constructor, else the one callable
  without arguments. Anything else fails the build and lists the
  constructors.

A super parameter carries the `@Value`, `@Qualifier`, `@Named` or `@Lazy`
of the super constructor's parameter, unless it has its own:

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

In Spring: `AutowiredAnnotationBeanPostProcessor`; the primary
constructor plays the role of Kotlin's.

### Lifecycle

A bean can run code after it is created and before the context shuts
down: open a connection, warm a cache, flush a buffer.

```dart
@Service()
@Log()
class SearchIndex {
  @PostConstruct()
  void load() => log.info('loading the index'); // dependencies are set by now

  @PreDestroy()
  void flush() => log.info('saving the index'); // on context.close()
}
```

**Order of creation:** constructor → fields, setters and methods →
`BeanNameAware` / `BeanFactoryAware` → the context's aware interfaces
(`EnvironmentAware`, `ApplicationContextAware`, ...) →
`postProcessBeforeInitialization` → `@PostConstruct` →
`InitializingBean.afterPropertiesSet` → init method →
`postProcessAfterInitialization`.

**Order of destruction** (on `close()`, dependents first):
`DestructionAwareBeanPostProcessor` → `@PreDestroy` →
`DisposableBean.destroy` → destroy method.

#### Asynchronous callbacks

An init callback (`@PostConstruct`, `afterPropertiesSet`, init method) or
a destroy callback (`@PreDestroy`, `DisposableBean.destroy`, destroy
method) may return a `Future`.

- `refreshAsync()` (also `ApplicationContext.runAsync` and Spring Boot's
  `runAsync`) awaits the init callbacks of the beans it creates, one bean
  after another, before `SmartInitializingSingleton`, the lifecycle start
  and `ContextRefreshedEvent`. Meanwhile the bean can already be injected
  into others. A failure fails the refresh and names the bean.
- The synchronous `refresh()` fails for such a callback. A bean created
  after the refresh (lazy, prototype, scoped) needs synchronous callbacks.
- `closeAsync()` awaits the destroy callbacks, dependents first. `close()`
  logs an asynchronous one and goes on without waiting.

#### Background work: `Lifecycle` and `SmartLifecycle`

A bean that runs something in the background (a client that stays
connected, a scheduler, a server) implements `Lifecycle` or mixes in
`SmartLifecycle`, and the context starts and stops it.

```dart
@Component()
class PriceFeed with SmartLifecycle {
  bool _running = false;

  @override
  void start() => _running = true; // connect

  @override
  void stop() => _running = false; // disconnect

  @override
  bool get isRunning => _running;
}
```

- `SmartInitializingSingleton` runs after all eager singletons exist.
- `Lifecycle` and `SmartLifecycle` beans are started by phase (with
  auto-startup at refresh) and stopped in reverse order on `stop()` or
  `close()`. Mixing in `SmartLifecycle` gives Spring's defaults:
  auto-startup and the default phase.
- A bean's dependencies start before it and its dependents stop before
  it, whatever their phase. A plain `Lifecycle` dependency of an
  auto-startup bean starts at refresh; a lazy plain `Lifecycle` bean is
  not created for that, as in Spring.
- A singleton counts by its instance too: a `@Bean Object server()` that
  returns a `SmartLifecycle` is started, as Spring matches the singleton's
  actual type.
- `closeAsync()` waits for the `stopWithCallback` callbacks of each phase,
  at most `DefaultLifecycleProcessor.timeoutPerShutdownPhase` (10 seconds)
  or the phase's entry in `timeoutsForShutdownPhases`; declare a
  `lifecycleProcessor` bean to change them. Then the beans still running
  are logged and the next phase is stopped.
- When a refresh fails, the beans started so far are stopped.

`close()` never throws because of a failing `ContextClosedEvent` listener
or a bean that fails to stop: the error is logged and shutdown continues,
as in Spring's `doClose`. A `close()` from a `ContextClosedEvent` listener
is ignored; one from a `ContextRefreshedEvent` listener closes the
context, as in Spring.

#### Pause and restart

`context.pause()` stops the running lifecycle beans, except the
`SmartLifecycle` beans whose `isPauseable` is `false`.
`context.restart()` (stopping the pauseable beans first if they still run)
starts the auto-startup beans again, which restores the state after the
refresh. This fits Flutter's `paused` and `resumed` app states. They
publish `ContextPausedEvent` (a `ContextStoppedEvent`) and
`ContextRestartedEvent` (a `ContextStartedEvent`). `pauseAsync()` waits
for the `stopWithCallback` callbacks, like `closeAsync()`. A custom
`LifecycleProcessor` implements `onPause`, `onPauseAsync` and `onRestart`.
This follows Spring 7.

#### Shutdown hook and template methods

`context.registerShutdownHook()` closes the context on SIGINT or SIGTERM
and ends the process with exit code `128 + signal`, like Spring's JVM
shutdown hook. It registers once per context, releases the signals when
the context closes, and does nothing on the web.

Subclasses of `AnnotationConfigApplicationContext` can override Spring's
template methods:

- `postProcessBeanFactory(beanFactory)`: all definitions are loaded, the
  bean factory post-processors have not run yet;
- `onRefresh()`: the message source and the event multicaster are ready,
  the listeners and the eager singletons are not;
- `onClose()`: last in `close()` / `closeAsync()`, after the singletons
  are destroyed.

#### Framework warnings

Problems the framework recovers from are logged through `SpringLog`;
warnings are printed by default. Set `SpringLog.level` and
`SpringLog.handler` to route them elsewhere, for example to
`package:logging` (see [Logging](#logging)).

### Environment and configuration

The **environment** holds the application's settings (properties) and its
active **profiles**. Beans read settings with `@Value(r'${key}')`, or
from the `Environment` bean. Settings come from several **property
sources**, searched in order: the first one that has a key wins.

```properties
# lib/resources/application.properties
shop.name=NEON Books
shop.delivery-time=2d
db.password=${DB_PASSWORD:changeme}
```

```dart
@Service()
class Shop {
  Shop(
    @Value(r'${shop.name}') this.name,
    @Value(r'${shop.delivery-time}') this.deliveryTime, // Duration(days: 2)
  );

  final String name;
  final Duration deliveryTime;
}
```

`StandardEnvironment` gives:

- property sources: the command line, OS environment variables, config
  files, `@PropertySource` files;
- `${...}` placeholders with defaults (`${port:8080}`), nesting and
  escapes;
- typed reads with `getPropertyAs<T>`, and required properties;
- profiles from `spring.profiles.active` and `spring.profiles.default`,
  with profile expressions such as `dev & (eu | us) & !prod`.

There is no `.env` support, by design: configuration lives in property
files.

#### Config files

`ConfigDataEnvironment` reads the application's config files into an
environment, following Spring Boot's config data rules. Call it once,
before the context is created: `processAndApply()` awaits resources that
can only be read asynchronously (Flutter assets, `http:` imports),
`processAndApplySync()` needs every resource readable synchronously
(files and the generated classpath are). `SpringApplication` in
`spring_boot_dart` does this for you.

**Which files.** `application.properties`, `application.yml` and
`application.yaml`, with their `application-{profile}` variants, in two
location groups, as in Boot:

1. `classpath:/;classpath:/config/`, which is `lib/resources/`;
2. `file:./;file:./config/;file:./config/*/`, which overrides the first.

Within a group a profile-specific file wins, so `./application.properties`
beats a packaged `application-prod.properties`. In one location
`.properties` beats YAML.

**Changing the locations.** `spring.config.location`,
`spring.config.additional-location` and `spring.config.name` work as in
Boot: `,` separates groups and `;` joins locations into one group.

- An `optional:` location may be missing. A non-optional file or directory
  that does not exist fails the start, unless
  `spring.config.on-not-found=ignore`; an import in a profile-specific
  file or document is no exception (as in Boot). Only the
  `-{profile}` variants searched by name may always be missing.
- A file named at several places is read once, at the place that wins,
  as in Boot: the later item of a list (`x,y,x` puts `x` above `y`), the
  command line's `spring.config.import` before `additional-location`
  before `location` (`--spring.config.additional-location=file:./config/`
  puts `./config/application.properties` above `./config/*/`), the first
  of two identical entries of a `;` group; that place's encoding hint
  applies (the file is not read at the other places).
- A directory location must end in `/` (also on Windows, where Boot also
  takes `\`), a `configtree:` one too. A
  non-optional wildcard location needs at least one subdirectory
  (`file:./config/*/`, `configtree:/etc/*/`), or a match when it names a
  file (`file:./config/*/app.yml`), unless
  `spring.config.on-not-found=ignore`.
- As in Boot, whether a location found anything is decided once the
  profile files are read, and its `-{profile}` variants count
  (`file:./config/*/app.yml` with only `app-dev.yml` loads when `dev` is
  active). A `classpath:` directory counts only when a file is found in
  it. A `;` group is one location, in `spring.config.import` too (in a
  file or not): optional when its first entry is, found when any entry
  finds something. A location that is not found is reported as written:
  the whole group, a relative import as it is, an extension hint kept.
- A file without a usable extension gets an extension hint:
  `file:./conf[.yml]`. As in Boot, extensions and hints are matched
  without case, and the loader's spelling names the file (`x.YAML` reads
  `x.yaml`).
- Spring Boot 4.1's file hints: `[encoding=iso-8859-1]` names a
  `.properties` file's charset (YAML stays UTF-8, as in Boot), several
  hints in any order (`x.conf[.properties][encoding=utf-8]`). Every
  bracketed part leaves a file location's path (`conf[x]/app.yml` reads
  `conf/app.yml`), not a directory's. The charsets are UTF-8, ISO-8859-1
  and US-ASCII, by Java's names and aliases (`utf8`, `latin1`, `ascii`);
  another fails the start, even when optional.
  `ConfigDataEnvironment.fileHints(location)` reads a location so.

**Several documents in one file.** `#---` (or `!---`) in `.properties` and
`---` in YAML start a new document. As in Boot, a `.properties` separator
must start its line, with exactly three hyphens, not right after a comment
of the same prefix nor on a continued line (`a=base\` then `#---` sets
`a` to `base#---`). A document applies only when its
`spring.config.activate.on-profile` matches, or its
`spring.config.activate.on-cloud-platform` matches the `CloudPlatform`
detected from environment variables (as Boot does) or set with
`spring.main.cloud-platform`.

**Imports.** `spring.config.import` loads more files or directories,
relative to the importing file, with their `-{profile}` variants (which,
as in Boot, win over the importing file's own profile files:
`x-dev.properties` over `application-dev.properties` when
`application.properties` imports `x.properties`). It can
also come from the command line or `SPRING_CONFIG_IMPORT`, above every
location. `configtree:` imports read a directory with one file per
property, as Kubernetes mounts secrets: `configtree:/etc/config/`,
`configtree:/etc/*/`. `${...}` in a file's `spring.config.import` and in
an on-profile guard is resolved against the command line and the
environment first, then the files. An unresolvable placeholder in an
`optional:` import just skips it.

**Profiles** follow Boot's rules:

- the command line wins over a file's `spring.profiles.active`;
- profiles set with `setActiveProfiles` are kept, and the file's are
  added after them;
- `spring.profiles.default` (from a file, the command line or the
  environment) selects the profile files while no profile is active;
- `spring.profiles.include` and `spring.profiles.group.*` add profiles.
  Groups are expanded depth-first, a group's members right after it; a
  group's name is matched exactly, as Boot's map keys are
  (`spring.profiles.group.Prod` is no group of `prod`);
- the profiles are decided before the profile files are read: a
  `-{profile}` file may not set the active, default or included profiles
  (its groups are ignored), an on-profile document read before them may
  set none of the four keys, and in a file a profile file or an
  on-profile document imports they are ignored. The keys are found under
  any relaxed spelling (`spring.profiles.Active`), as in Boot.

A `defaultProperties` source stays below the config files and the
`@PropertySource` files.

**Lists.** Binding follows Boot's binder: indexed keys
(`spring.profiles.include[0]`, `SPRING_PROFILES_ACTIVE_0_`) form a list,
and a list comes whole from the highest source that has it, so
`--spring.profiles.active[0]=dev` replaces a file's list. A bracketed
element that is not one of `[0]`, `[1]`... (`spring.config.import[x]`,
`[1]` without `[0]`) fails the start, as Boot's "left unbound";
`spring.config.activate.on-cloud-platform` and
`spring.main.cloud-platform` take one value (a list form is ignored).

**Encoding.** `.properties` files are read as UTF-8. Spring reads
ISO-8859-1; for that use `PropertiesPropertySourceLoader(encoding: latin1)`
in `ConfigDataEnvironment(loaders: ...)`, an encoding hint for one config
file (`classpath:legacy.properties[encoding=iso-8859-1]`), or
`@PropertySource(encoding: 'ISO-8859-1')`. A config file that is not
valid in its encoding fails with a `ConfigDataLoadException` naming the
file and the encoding.

**YAML** is flattened like Boot's `YamlPropertySourceLoader`:
`app.hosts[0]`, `app.servers[0].name`, empty values and `~` as `''`.
`@Value` and `getProperty('app.hosts[0]')` see list items, and
`@ConfigurationProperties` binds them as lists (also of nested objects).
Integers beyond `int` stay exact, as `BigInt` (SnakeYAML's `BigInteger`).

#### Placeholders, random values and relaxed names

**Placeholders** follow Spring 6.2's parser. `${db:url}` is first looked
up as the key `db:url`, then as `db` with the default `url`. An unclosed
`${` is plain text: `${a ${b}` resolves `${b}`.

**Random values:** `${random.int}`, `${random.int(10)}`,
`${random.int[5,10]}`, `${random.long}`, `${random.uuid}` and
`${random.value}` come from `RandomValuePropertySource`. `SpringApplication`
adds it; without Spring Boot call
`RandomValuePropertySource.addToEnvironment`.

**Relaxed names.** `ConfigDataEnvironment` and `SpringApplication` attach
Boot's `ConfigurationPropertySources`: a lookup of `app.read-timeout` (in
`getProperty`, `${...}` and `@Value`) also finds `app.readTimeout`,
`app.read_timeout` or `APP_READTIMEOUT`. The first property source with
any of the forms wins.

#### `@PropertySource`

`@PropertySource([...], factory: ...)` on a component adds property files;
the last one declared wins.

```dart
@Configuration()
@PropertySource(['classpath:mail.properties'])
class MailConfig {}
```

- It is loaded only when the declaring class's conditions (`@Profile`,
  `@Conditional`, ...) match. Classes pulled in with `@Import` inherit the
  importer's conditions.
- A pattern (`file:config/*.properties`, `classpath*:`) loads every match;
  no match is fine (Spring 6.1).
- As in Spring it reads `.properties`, exactly as `java.util.Properties`
  reads them (`PropertiesParser`), as UTF-8 unless `encoding:` says
  otherwise. Dart's UTF-8 decoder drops a leading byte order mark, which
  Java keeps (its first key then starts with `U+FEFF`). For YAML, pass a
  `PropertySourceFactory` that uses `YamlPropertySourceLoader`.
- Resources that can only be read asynchronously (Flutter assets behind a
  `ProtocolResolver`) work with `refreshAsync()` / `runAsync`, which read
  them before the modules are loaded.

### Conditions

A **condition** decides at startup whether a bean exists at all. Use one
when a bean belongs only to some environments or setups: a fake payment
service in development, a feature behind a setting.

```dart
@Service()
@Profile(['dev'])
class FakePayments implements Payments { ... } // no real money in dev

// A condition with an argument is a const class that implements Condition.
class ConditionalOnProperty implements Condition {
  const ConditionalOnProperty(this.name);
  final String name;

  @override
  bool matches(ConditionContext context) =>
      context.environment.getProperty(name) == 'true';
}

@Component()
@ConditionalOnProperty('feature.audit')
class AuditFeature {}
```

The forms:

- `@Profile(['dev'])`: the active profiles.
- `@Conditional([MyCondition])`: a `Condition` class with a no-argument
  constructor.
- Your own subclass of either, which acts like a Spring meta-annotation:
  `class Dev extends Profile { const Dev() : super(const ['dev']); }`.
- Any const annotation class that implements `Condition`, so conditions
  can take arguments (`@ConditionalOnProperty('feature.x')`).

A condition sees the environment, the definitions registered before it
and, as `context.definition`, the definition being evaluated: its
`annotations`, name and types (Spring's `AnnotatedTypeMetadata`; `null`
for `@PropertySource` conditions).

A `ConfigurationCondition` chooses when it is decided, with its
`ConfigurationPhase`:

- `parseConfiguration`: while parsing. A failing one also stops the
  class's imports and `@PropertySource`s.
- `registerBean`: when the class is read, after the classes before it have
  registered their beans and run their registrars (see [Modules](#modules)).
  This is for conditions on other beans, such as Boot's
  `@ConditionalOnBean`.

Plain conditions count in both phases.

### Modules

A **module** (`BeanModule`) is the list of bean definitions the generator
writes for one scan. You pass modules to the context.

`@ComponentScan` on a top-level variable generates one `BeanModule` for
its directory and everything below it. Combine several modules in one
application, and use `@Import([OtherConfig])` to pull in configuration
classes outside the scan.

A subdirectory with its own `@ComponentScan` belongs to that scan, and its
filters apply. The enclosing scan (or `@SpringBootApplication`) imports its
module instead of scanning the files again, so every bean is registered
once even when both modules are used. One directory has one scan root.

Contexts can have a parent: the parent's beans are visible to the child.

#### Scan filters

The scan takes Spring's filters, evaluated at build time:

```dart
@ComponentScan(
  // Classes annotated @Plugin become beans without @Component.
  includeFilters: [Filter(classes: [Plugin])],
  // No beans from classes whose name ends in Fake.
  excludeFilters: [Filter(type: FilterType.regex, pattern: ['.*Fake'])],
)
final BeanModule appBeans = $appBeans;
```

- `includeFilters` make classes beans without `@Component`:
  `Filter(classes: [Plugin])` for an annotation,
  `Filter(type: FilterType.assignableType, classes: [Handler])` for
  subtypes, `Filter(type: FilterType.regex, pattern: ['.*Repository'])` on
  the class name. Abstract classes are skipped.
- `excludeFilters` keep classes out; they win over the includes.
- `useDefaultFilters: false` scans only the includes.
- `lazyInit: true` makes every scanned bean (components and their `@Bean`
  methods) lazy, unless annotated `@Lazy(false)`.

`@Bean` methods, `@Autowired` members, `@PostConstruct` / `@PreDestroy`
and `@EventListener` methods are also found in superclasses and mixins,
as Spring scans the hierarchy, with the type arguments of a generic
superclass (`UserService extends BaseService<User>`) substituted.

Generated code cannot name private declarations. A private bean class,
`@Bean` return type, injected type or default value fails the build with
a message that names it, its library and the fix.

#### Registering beans in code

Sometimes beans depend on something only known at runtime: a setting, a
platform. A `BeanRegistrar` registers beans with a supplier function and
Spring 7's `Spec` options. Put it in `@Import([...])` (the generator
creates it with its no-argument constructor) or pass it to
`context.register(...)`.

```dart
class MessagingRegistrar implements BeanRegistrar {
  const MessagingRegistrar();

  @override
  void register(BeanRegistry registry, Environment env) {
    registry.registerBean<Clock>((_) => SystemClock(), name: 'clock');
    // A mailer only when a mail host is configured.
    if (env.containsProperty('mail.host')) {
      registry.registerBean<Mailer>(
        (context) => SmtpMailer(context.dependency<Clock>()),
        name: 'mailer', primary: true, lazy: true, description: 'SMTP',
      ); // without a name: `Mailer#0`, like Spring's uniqueBeanName
    }
  }
}

@Configuration()
@Import([MessagingRegistrar]) // or: context.register(const MessagingRegistrar())
class AppConfig {}

// A test replaces the clock before the context starts.
final context = AnnotationConfigApplicationContext([appBeans])
  ..registerBean<Clock>((_) => FixedClock(), name: 'testClock', primary: true)
  ..refresh();
```

- `ImportSelector` returns `BeanModule`s to import;
  `ImportBeanDefinitionRegistrar` gets the `BeanDefinitionRegistry`. Both
  are used like a registrar, and may implement `EnvironmentAware`,
  `BeanFactoryAware` and `ResourceLoaderAware`.
- `context.registerBean<T>(supplier, ...)` is Spring's
  `GenericApplicationContext.registerBean`.
- Registering anything after `refresh()` fails with a `StateError` that
  says so.

#### The order in which configuration is processed

This matters only for conditions on other beans. Imports follow Spring's
configuration class parser and reader:

1. **Parsing** (only parse-phase conditions count) loads a class's
   `@PropertySource`s and runs its selectors. The modules they select are
   parsed at once, and their classes are read before the importing class.
2. **Reading** goes class by class, application classes before
   auto-configurations, and decides each class once: it is skipped when
   every class that imports it was skipped, else its `registerBean`-phase
   conditions (`ConfigurationCondition`, such as Boot's
   `@ConditionalOnBean`) decide, for the class, its `@Bean` methods and
   its imports alike. A scanned component or an `@Import`ed class with
   such a condition counts as a class too, decided at its place in that
   order.
3. A kept class registers its `@Bean` methods (each one's own conditions
   decided at that moment), then runs its registrars, so every later class
   sees those beans. A skipped class registers nothing and runs no
   registrar.

### Events

**Events** let beans react to something without knowing who caused it.
The order service publishes "order placed"; the mailer and the analytics
listen. Neither knows the other.

```dart
class OrderPlaced {
  const OrderPlaced(this.id, this.total);
  final String id;
  final double total;
}

bool isBigOrder(OrderPlaced order) => order.total > 1000;

@Service()
class Orders {
  Orders(this.events);
  final ApplicationEventPublisher events;

  void place(String id, double total) =>
      events.publishEvent(OrderPlaced(id, total));
}

@Component()
class Shipping {
  @EventListener()                       // payloads or ApplicationEvents
  OrderShipped onPlaced(OrderPlaced order) => OrderShipped(order.id);

  @EventListener(condition: isBigOrder)  // a top-level or static predicate
  @Order(1)
  void onBig(OrderPlaced order) {}

  @EventListener(classes: [ContextRefreshedEvent, ContextClosedEvent])
  void onContext() {}
}
```

**Results.** A listener's non-null result is published as a new event. A
`Future` result is published when it completes, and its error goes to the
multicaster's error handler (or is logged).

**Any object is an event.** A published object that is not an
`ApplicationEvent` is wrapped in a `PayloadApplicationEvent<T>` of its
static type: listeners of `T` get the payload, listeners of
`PayloadApplicationEvent<T>` get the event. Generated listeners of
`PayloadApplicationEvent<T>` match on the payload's runtime type, as in
Spring.

**Other listener forms.** `ApplicationListener<E>`,
`GenericApplicationListener` and `SmartApplicationListener` beans work,
also behind another declared `@Bean` type. So do listener objects given to
`registerSingleton`; an `ApplicationListener<E>` object there needs
`ApplicationListenerAdapter.forListener<E>`. A listener is registered
once. `context.addListener<E>(...)` returns a registration you can remove.

**Timing.** Events published before the listeners are registered (while
the bean factory post-processors run) are replayed once they are. Later
events, for example from a bean's constructor, reach the listeners right
away; a listener bean is created for it if needed. Events propagate to the
parent context. `@EventListener` methods of a `FactoryBean` run on the
factory, not on its product.

#### Asynchronous listeners

By default a listener runs inside `publishEvent`, so the publisher waits
for it. Two ways to run listeners later:

- All of them: declare a `SimpleApplicationEventMulticaster(taskExecutor:
  SimpleAsyncTaskExecutor())` bean named `applicationEventMulticaster`
  (Spring's `setTaskExecutor`). Errors go to its `errorHandler`; without
  one the executor logs them.
- One method: `@Async()` on an `@EventListener` method runs it on a
  `TaskExecutor` bean. `@Async('name')` picks one; otherwise the only or
  `@Primary` executor is used, else the one named `taskExecutor`. Its
  failure goes to the error handler or the log; its result is published
  when it arrives.

```dart
@Component()
class Mailer {
  // The order is confirmed without the publisher waiting for the mail.
  @EventListener()
  @Async()
  Future<void> onPlaced(OrderPlaced order) => sendConfirmation(order);
}
```

`@Async` is switched on by having a `TaskExecutor` bean, as `@EnableAsync`
switches it on in Spring. The scheduling starter registers
`applicationTaskExecutor` (alias `taskExecutor`); without one, `@Async` is
ignored. The generator accepts `@Async` on `@EventListener` methods only.
As in Spring, a listener's `condition` runs inside the multicaster's error
handling (on the executor when there is one), so a failing condition
reaches the `errorHandler`.

### Messages, resources, conversion

#### Messages

A **message source** gives the texts of the application in the user's
language: `messages.properties`, `messages_de.properties`, and so on.

```properties
# lib/resources/messages.properties
greeting=Welcome to {0}!
# lib/resources/messages_de.properties
greeting=Willkommen bei {0}!
```

```dart
@Configuration()
class MessagesConfig {
  @Bean()
  MessageSource messageSource() =>
      ReloadableResourceBundleMessageSource(basenames: ['classpath:messages']);
}

context.getMessage('greeting', args: ['NEON'], locale: 'de');
// Willkommen bei NEON!
```

- Define a bean named `messageSource`; the context delegates to it. In a
  child context it falls back to the parent's message source (not the
  parent context), as in Spring.
- `ReloadableResourceBundleMessageSource` looks up
  `messages_ru_RU.properties` → `messages_ru` → the default or system
  locale → the base file, and reloads after `cacheSeconds`.
- `StaticMessageSource` holds messages added in code;
  `MessageSourceAccessor` wraps a source with a default locale.
- Placeholders follow `MessageFormat`: `{0}`, quotes, `number`, `date` /
  `time` (styles and `SimpleDateFormat` patterns) and `choice`.

#### Resources

A **resource** is a file the application reads, wherever it lives.
`lib/resources/` is the classpath: the generator embeds its files, so
`classpath:...` works in `dart run`, AOT executables, Flutter and the web,
without asset declarations.

```dart
@Service()
class WelcomeLetter {
  // Resolved by the context's resource loader, so custom protocols and
  // asset loaders apply.
  WelcomeLetter(@Value('classpath:templates/welcome.txt') this.template);
  final Resource template;

  String text() => template.readAsStringSync();
}
```

`ResourceLoader` understands:

- `classpath:` (also plain paths such as `app.properties`, as in Spring);
- `file:`, percent-decoded (`file:my%20dir/a.txt`);
- `package:my_app/config/app.yml`, the package's file through the package
  config (not on the web or in AOT executables);
- `http:` and `https:` (`UrlResource`, read asynchronously with
  `dart:io`);
- custom protocols through a `ProtocolResolver`, tried first. This is how
  a Flutter asset loader plugs in.

`PathMatchingResourcePatternResolver` resolves patterns with
`AntPathMatcher`, for `file:` and the classpath. `classpath:` searches the
first classpath root that has the pattern's base directory, `classpath*:`
every root (added directories, then the embedded resources). Matching
directories are returned too, and directories the pattern cannot match
are not walked. A `FileSystemResource` of a directory exists but is not
readable, as in Spring.

Patterns are cleaned as Spring's `StringUtils.cleanPath` cleans them:
`\\` (two backslashes) is read as one `/`, then each `\` left as `/`, and
`.` and `..` segments are resolved (`classpath*:mail\*.txt`,
`classpath*:mail/*/../*.txt` and `classpath*:mail/*\\..\\*.txt` are
`classpath*:mail/*.txt`). So a `{name:regex}` must not use `\`, which
becomes `/` (`classpath:mail/{n:\w+}.txt` matches nothing, in Spring
too): write character classes such as `[0-9]` or `[a-zA-Z0-9_]` instead.
As in Spring, a `file:` pattern's wildcards are those written: only the
directory before the first wildcard is percent-decoded
(`file:my%20dir/*.txt` searches `my dir/`), so `file:mail/%2A.txt` is
the one file named `*.txt` and the rest of a pattern matches `%` as it
is. Kept differences from Spring 7:

- a `..` that climbs above a classpath root finds nothing (Spring's
  `classpath*:mail/../../*.txt` can reach files next to a classpath
  directory);
- a `\` in the directory before the first wildcard of a `classpath*:`
  pattern is cleaned too (`classpath*:conf\sub/*.txt` finds
  `conf/sub/*.txt`, as `classpath:conf\sub/*.txt` does in both), where
  Spring hands the name to Java's class loader, which refuses it, and
  finds nothing;
- a `file:` pattern whose separators are `\` there is read the same way,
  so Windows paths work: `file:lib\resources\mail\*.txt` and
  `file:C:\config\*.properties` find their files, where Spring on
  macOS and Linux finds nothing (`Invalid URI [file:]`, as its root
  directory ends at the last `/`);
- a `classpath:` pattern whose base directory no root has
  (`classpath:nodir/*.txt`) gives an empty list, where Spring throws a
  `FileNotFoundException` (`class path resource [nodir/] cannot be
  resolved to URL because it does not exist`); `classpath*:` gives an
  empty list in both.

**Why `lib/resources/`**, and not `bin/` or the project root: `lib/` is
the only part of a Dart package that other packages can use. A starter
keeps its defaults and messages in its own `lib/resources/`, and they join
the application's classpath exactly like the application's files (its
generated module embeds them). Files elsewhere would be invisible to
dependencies and missing in AOT executables, Flutter apps and the web,
which have no project folder at runtime. An app with only `bin/main.dart`
still keeps its resources in `lib/resources/`; `lib/` may contain nothing
else:

```text
my_app/
  bin/main.dart              # @SpringBootApplication
  lib/resources/
    application.properties   # classpath:application.properties
```

Tests see `test/resources/` first (`spring_boot_starter_test`), as
`src/test/resources` comes before `src/main/resources` in Java.

#### Type conversion

Settings are text; beans want `int`, `Duration` or enums.
`DefaultConversionService` converts between them, for `@Value`, the
environment and data binding:

- durations in Spring Boot's syntax: `10s`, `PT5M`;
- collections, and a single value as a one-element list;
- maps: `Map` → `Map<String, V>`, and `addMapConverters<K, V>()` for
  other key types;
- `Encoding` (Spring's `Charset`), `BigInt`, and enums (an enum is its
  name as a string, also in `${...}`).

A `conversionService` bean (also in an ancestor context) is used for
`@Value` conversion.

### SpEL

**SpEL** (Spring Expression Language) evaluates small expressions written
as strings: `#{2 * 60}` in a `@Value`, a cache key, a security rule, a
validation message. Use it where a value must be computed from settings,
beans or a method's arguments, but the place only takes a string.

```dart
@Service()
class Shop {
  @Value('#{2 * 60}')                          // 120
  late final int seconds;

  @Value(r"#{'${shop.name}'.toUpperCase()}")   // NEON BOOKS
  late final String title;

  @Value('#{appInfo.name}')                    // property of the bean appInfo
  late final String appName;                   // (its class is @Introspected)
}
```

The parser can be used directly:

```dart
final parser = SpelExpressionParser();
// The generated descriptions of @Introspected classes live in the
// application context's introspector, a bean (`app` is the context; a bean
// can inject BeanIntrospector instead). An evaluation context made by hand
// reads only BeanIntrospector.shared, so give it the context's.
final introspector = app.getBean<BeanIntrospector>();
final evaluation = StandardEvaluationContext()
  ..addPropertyAccessor(IntrospectionPropertyAccessor(introspector))
  ..addMethodResolver(IntrospectionMethodResolver(introspector));
// A property and a method of an @Introspected object.
parser.parseExpression('name.toUpperCase()').getValue(evaluation, user);
// A template: text with #{...} parts.
parser
    .parseExpression('Total: #{price * 2}', ParserContext.template)
    .getValue(evaluation, item);
```

**What the language has:** literals, inline lists and maps, properties,
indexing, safe navigation (`?.`), methods, variables and functions,
`T(Type)` for static members, constructors, `@bean` references, selection
and projection, assignment and `++` / `--`, and all operators (`div`,
`between`, `matches`, Elvis `?:`, ternary).

**Numbers** follow Spring 7's operators:

- integers use `int` arithmetic: `7 / 2` is `3`, and `1 / 0` throws an
  `UnsupportedError` (Java's `ArithmeticException`);
- once a real number is involved the result is a `double`: `7.0 / 2` is
  `3.5`. This holds on the web too, where `7.0` is an `int` at runtime:
  real literals, `T(Math)` functions and the operators on them are
  tracked;
- `^` works like Spring's `OpPower`: a long above `Integer.MAX_VALUE`,
  saturating;
- `==` has Java's double semantics (`NaN != NaN`) and compares lists and
  maps deeply;
- `'d' - 3` is `'a'`.

**Types and strings.** Selection (`.?[...]`) keeps the element type of the
source list. `T()` knows the common `java.lang` names (`T(Integer)`,
`T(Character)`, `T(Math)`, `new int[4]`, `new char[2]`). Strings have
Java's `format` / `formatted`, `getBytes` and `chars` on top of the Dart
methods; `T(Objects)`, `T(System)` and `new StringBuilder()` work too.

**Your classes.** Dart has no reflection, so expressions reach your
classes through `@Introspected` metadata (read by default from
`BeanIntrospector.shared`), through `FunctionPropertyAccessor` /
`FunctionMethodResolver`, or through maps. `SimpleEvaluationContext`
restricts expressions for data binding: no types, constructors, bean
references or variable assignment.

**Safe navigation** is Spring 7's: a `?.` step on `null` gives `null` and
the chain goes on. So `a?.b.c` fails with EL1007E on `.c` when `a` is
`null`; write `a?.b?.c`. The same holds for `?.[i]`, `?.?[...]`,
`?.![...]`, `?.^[...]` and `?.$[...]`. Each `?.` covers one step, as in
Spring.

**Errors.** An exception thrown by a called method or constructor is
rethrown as is. Failures of accessors and of SpEL itself are
`SpelParseException` / `SpelEvaluationException`, with Spring's
`SpelMessage` codes and the position:
`Expression [1 + * 2] @4: EL1070E: Problem parsing left operand`.

**Limits.** `SpelParserConfiguration` (Spring 7's builder) sets auto-grow
and the limits that protect against hostile expressions:

| Limit | Default |
|---|---|
| expression length | 10 000 characters |
| nesting depth | 1000 |
| operations per evaluation | 10 000 (`EL1085E`; the default follows `-Dspring.expression.maxOperations`) |
| `'x' * n` | 256 characters |
| string `+` | 100 000 characters |
| `matches` pattern | 1000 characters, no nested quantifiers |

Patterns use Dart's `RegExp` syntax. A pattern with nested quantifiers
(`(a+)+`) is refused with `EL1073E`, because Dart's `RegExp` cannot be
interrupted the way Spring's matcher can.

```dart
// A service that evaluates user-supplied expressions allows more work.
final parser = SpelExpressionParser(
  SpelParserConfiguration.builder().maximumOperations(50000).build(),
);
```

**In `@Value('#{...}')`** the root is the bean factory, so `#{mailer}` and
`#{@mailer}` are beans. Also available:

- `systemEnvironment`: the environment variables;
- `systemProperties`: Dart has no JVM system properties, so the
  `--key=value` command-line arguments (the `commandLineArgs` property
  source of the `environment` bean) stand in;
- `environment['app.name']` and
  `environment.getProperty('app.name', 'default')`.

Conversions use the factory's `ConversionService`, parsed expressions are
cached, and `-Dspring.context.expression.maxLength` changes the length
limit of `@Value` expressions.

### Validation and data binding

**Validation** checks that an object's values are acceptable (a name is
not blank, an age is at least 18) and reports every problem at once, with
error codes that messages can translate. **Data binding** fills an object
from text input, such as form fields or query parameters, and records a
`typeMismatch` error instead of throwing when the text does not convert.

```dart
@Introspected()
@PasswordsMatch()                   // a class-level constraint of your own
class SignupForm {
  @NotBlank() @Size(max: 20) String name = '';
  @NotNull() @Email() String? email;
  @Min(18) int age = 0;
  @Valid() Address address = Address(); // validated too
}

final binder = DataBinder(SignupForm(), objectName: 'signup',
    introspector: context.getBean<BeanIntrospector>())
  ..validators.add(BeanValidator(introspector: context.getBean<BeanIntrospector>()))
  ..bind({'name': 'Ada', 'age': '17'}) // e.g. the fields of a form
  ..validate();

final error = binder.bindingResult.fieldError('age'); // Min, with Spring's codes
final message = context.getMessageFromResolvable(error!); // must be greater than or equal to 18
```

**Constraints:** `NotNull`, `MustBeNull`, `NotEmpty`, `NotBlank`, `Size`,
`Min`, `Max`, `DecimalMin`, `DecimalMax`, `Positive`, `PositiveOrZero`,
`Negative`, `NegativeOrZero`, `Matches` (`@Pattern`), `Email`, `Digits`,
`AssertTrue`, `AssertFalse`, `Past`, `PastOrPresent`, `FutureDate`
(`@Future`), `FutureOrPresent`, and your own `Constraint` subclasses.

Also supported:

- groups, group sequences (`@GroupSequence`,
  `BeanValidator(groupSequences:)`) and `@ConvertGroup`;
- constraints on the elements of a collection: `@Each([NotBlank()])`, and
  `@EachKey` for map keys;
- `${validatedValue}` in messages;
- the `@Valid` cascade into nested objects.

**Mistakes are caught.** A constraint on a type it cannot check (`@Size`
on an `int`) or with invalid attributes (`Size(min: -1)`) fails the build.
At runtime the same mistake throws `UnexpectedTypeException` or
`ConstraintDeclarationException`, as in Hibernate Validator.

**Error codes** follow Spring (`NotBlank.signup.name`, `NotBlank.name`,
`NotBlank.String`, `NotBlank`), so the texts come from a `MessageSource`.

**Immutable classes** (final fields, no setters) cannot be bound onto.
Create them through their constructor with `DataBinder.construct`
(Spring 6.1's constructor binding).

#### Method validation

Method validation checks the arguments and the result of a bean's methods
on every call. Mark the bean `@Validated()` and declare a
`MethodValidationPostProcessor` bean; the generated proxy then checks the
constraints, and a violation throws `ConstraintViolationException`:

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

Constraints on the parameters and return value of an overridden
declaration (an implemented interface, a superclass, a mixin) apply too,
as in Hibernate Validator's constraint inheritance.

In Spring: `@Validated` with `MethodValidationPostProcessor`.

### JSON (`ObjectMapper`)

`ObjectMapper` converts objects to JSON and back. It works on metadata the
generator writes, so there is no reflection and no `fromJson` / `toJson`
code to write. One `@Introspected()` on a model is enough: the classes of
the same package that it uses (property and constructor types) are
introspected automatically. In Spring this is Jackson's `ObjectMapper`.

```dart
enum Availability {
  inStock('in_stock'),
  soldOut('sold_out');

  const Availability(this.json);
  @JsonValue()                     // "in_stock" instead of "inStock"
  final String json;
}

class Author {                     // no annotation needed: Book uses it
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

final mapper = context.getBean<ObjectMapper>();   // Spring Boot configures it
final json = mapper.writeValueAsString(book);
// {"author":{"born":1920,"name":"Herbert"},"availability":"in_stock",
//  "isbn":"1","published_at":null,"tags":[],"title":"Dune"}
final again = mapper.readValue<Book>(json);
final books = mapper.readList<Book>('[{"isbn":"2","title":"Ubik","author":{"name":"Dick"}}]');
```

**How objects are created.** Immutable classes are created through their
constructor: `final` fields, `required` and default values (a missing
optional property keeps its default). Classes with setters and a
no-argument constructor work too. The constructor is the unnamed one, or
the one marked `@JsonCreator()`.

| Method | Does |
|---|---|
| `writeValueAsString(value)` | JSON text |
| `valueToTree(value)` | maps, lists and scalars (what `jsonDecode` returns) |
| `readValue<T>(json)` | a `T` from JSON text |
| `readList<E>(json)`, `readMap<V>(json)` | a `List<E>`, a `Map<String, V>` |
| `readValue(json, const ListType<Book>(ClassType<Book>()))` | any generic type, described with `TypeInfo` |
| `treeToValue<T>(tree)`, `convertValue<T>(value)` | from decoded JSON; from another object |

| Annotation | Meaning |
|---|---|
| `@JsonProperty('published_at')` | The JSON name (also on enum constants). `access: JsonPropertyAccess.readOnly` / `writeOnly` for one direction only. Jackson's `required = true` is the Dart parameter: a constructor parameter that is neither nullable nor has a default must be present. |
| `@JsonIgnore()` | Left out in both directions. |
| `@JsonInclude(JsonInclusion.nonNull)` | On a property or class: skip `null` values. `nonAbsent`, `nonEmpty`, `nonDefault` also skip empty or default values. |
| `@JsonIgnoreProperties(value: ['x'], ignoreUnknown: true)` | On a class: names to ignore; accept unknown properties. |
| `@JsonPropertyOrder(['id', 'title'])` | On a class: these properties first, the rest after. `@JsonPropertyOrder.alphabetic()` sorts the rest whatever the mapper says. |
| `@JsonCreator()` | The constructor to read with. |
| `@JsonValue()` | On an enum field or getter: the JSON form of each value (also for enum map keys; an `int` one is matched by value, never as an index). On a property or method of a class: the object is written as that value (also as a map key) and read back through its one-parameter constructor. One per class, else the build fails. |
| `@JsonAlias(['name', 'fullName'])` | Other JSON names accepted when reading. |
| `@JsonFormat(pattern: 'dd.MM.yyyy', timezone: '+01:00', shape:)` | Date pattern and offset; `JsonFormatShape.number` / `string`. |
| `@JsonAnyGetter()` / `@JsonAnySetter()` | A map property written as extra properties / receiving the unknown ones. |
| `@JsonUnwrapped(prefix:, suffix:)` | The nested object's properties inline. |
| `@JsonNaming(PropertyNamingStrategy.snakeCase)` | On a class: its naming strategy. |
| `@JsonView(Public)` | Written or read only with that view (`writerWithView`, `readerWithView`). |
| `@JsonTypeInfo(...)`, `@JsonSubTypes([...])`, `@JsonTypeName('cat')` | Polymorphic types: the type id as a property, an existing property, a wrapper object or array, or found by deduction; `defaultImpl`. |

**Property order** is that of Jackson 3 and Spring Boot 4. An object's
properties are written sorted by JSON name
(`SORT_PROPERTIES_ALPHABETICALLY`): the constructor parameters first, then
the other properties (`SORT_CREATOR_PROPERTIES_FIRST`), each group sorted.
Earlier versions wrote the declaration order (superclass first);
`ObjectMapper(sortPropertiesAlphabetically: false)` brings it back (in
Spring Boot: `spring.jackson.mapper.sort-properties-alphabetically=false`).
`@JsonPropertyOrder` wins either way: the listed names (JSON or Dart
names) come first, the others follow in the mapper's order. Reading does
not depend on the order.

**Built-in types:**

- `String`, `int`, `double`, `num`, `bool`. Numbers and booleans in
  strings are accepted; `NaN` and the infinities are `"NaN"`,
  `"Infinity"`, `"-Infinity"`.
- `DateTime` in ISO-8601, as Jackson writes an `OffsetDateTime`:
  `2026-01-01T12:00:00.000+02:00` for local times, `Z` for UTC, so a
  Spring `Instant` reads it. With `writeDatesAsTimestamps`: epoch seconds
  with the fraction, `1700000000.123456`, as in Jackson 3.
- `Duration` in ISO-8601 (`PT1M30S`), or seconds with
  `writeDurationsAsTimestamps`. Reading also accepts `90s` and numbers as
  seconds.
- `Uri`, `BigInt` (as a string), enums, `List`, `Set`, `Map`, nullable
  types and nested objects.
- `readValue<Map<String, dynamic>>`, `readValue<List<dynamic>>` and
  `readValue<Object?>` give the plain decoded JSON.

**Other classes.** A class that already has `fromJson` / `toJson`
(`json_serializable`, `freezed`) is converted with them. For anything else
write a `JsonSerializer<T>` / `JsonDeserializer<T>`, and pass it to
`ObjectMapper(serializers:, deserializers:)`, declare it as a bean, or
group several in a `JsonModule` bean. Spring Boot adds every serializer,
deserializer and `JsonModule` bean to its mapper, as it does with
`@JsonComponent`s and Jackson `Module`s.

**Settings:** `namingStrategy` (`snakeCase`, `kebabCase`,
`upperCamelCase`, ...), `inclusion`, `failOnUnknownProperties` (off, as in
Spring Boot), `writeDatesAsTimestamps`, `timeZone` (`UTC` or a fixed
offset such as `+02:00`), `indentOutput`, and `sortPropertiesAlphabetically`
(on). Spring Boot sets them from `spring.jackson.*` (see
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)).

**Errors name the place:** `items[2].price: expected a number, got "abc"`,
`missing property "isbn" (required by Book)`.

**More:**

- Classes of other packages are introspected with
  `@Introspected(classes: [ExternalDto])`.
- Generic model classes (`Page<T>`) are read with their type arguments:
  `mapper.readValue(json, const GenericType<Page<Book>>([ClassType<Book>()]))`.
- `readTree` gives a `JsonNode` tree.
- `JsonMapper.builder()` and `mapper.rebuild()` configure a mapper with
  Jackson's feature enums (`SerializationFeature`,
  `DeserializationFeature`, `DateTimeFeature`, `MapperFeature`).

Not supported yet: getters without a field.

### AOP

**AOP** (aspect-oriented programming) runs your code before, after or
around the methods of other beans, without editing them. Use it for
concerns that cut across many classes: logging, timing, auditing,
permission checks, retries, caching.

| Term | What it is | In code |
|---|---|---|
| Aspect | A bean holding the extra code | a class with `@Aspect()` and `@Component()` |
| Advice | One piece of extra code, and when it runs | a method with `@Before`, `@After`, `@AfterReturning`, `@AfterThrowing` or `@Around` |
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
@Log()
class TimingAspect {
  @Around('@annotation(Timed)')
  Object? time(ProceedingJoinPoint call) {
    final watch = Stopwatch()..start();
    try {
      return call.proceed(); // runs the real method
    } finally {
      log.info('${call.signature.name}: ${watch.elapsedMilliseconds} ms');
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

**How it works.** The generator (`spring_core_dart_generator`, required)
writes a proxy class for each bean. When the context starts, every bean
that some pointcut matches is replaced by its proxy, and the proxy is what
other beans and `getBean` receive. A call to `search.find(...)` goes
through the proxy, which runs the advice. Beans that no pointcut matches
are not wrapped and cost nothing.

Rules to remember:

- The aspect must be a bean: `@Aspect()` plus `@Component()`, or a `@Bean`
  method. Aspects can inject other beans as usual; they are never proxied
  themselves.
- Only calls from outside go through the proxy. A call through `this`
  inside the bean (`find` calling `count`) skips the advice, exactly as in
  Spring. Call through another bean, or inject the bean into itself with
  `@Lazy()` (see [Lazy injection points](#lazy-injection-points)) or
  `ObjectProvider<T>`.
- The proxy implements the bean class or its interfaces, so the bean
  needs public members or an interface with the advised methods; the
  error message says which. See [Proxies](#proxies).

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
@Log()
class AuditAspect {
  // A named pointcut: the method body is empty, its name is the pointcut.
  @Pointcut('within(OrderService)')
  void orders() {}

  @Before('orders()')
  void before(JoinPoint call) =>
      log.info('calling ${call.toShortString()} with ${call.args}');

  // Runs only when the result is a double: the parameter type filters.
  @AfterReturning('orders()')
  void returned(JoinPoint call, double total) => log.info('total: $total');

  // Runs only for StateError; other errors pass by.
  @AfterThrowing('orders()')
  void failed(StateError error) => log.warning('failed: ${error.message}');

  @After('orders()')
  void after() => log.info('done');

  // Change the arguments, the result, or skip the call entirely.
  @Around('execution(* OrderService.discount(..))')
  Object? clamp(ProceedingJoinPoint call) {
    final [percent] = call.args;
    return call.proceed([(percent! as int).clamp(0, 50)]);
  }
}
```

Parameters are positional and matched by type: `JoinPoint` and
`ProceedingJoinPoint` by exact type, and in `@AfterReturning` /
`@AfterThrowing` the first other parameter gets the result or the error.
Anything else is a build error.

**Async methods.** For a method or getter that returns a `Future` (or a
`FutureOr` whose value is a future), `@After`, `@AfterReturning` and
`@AfterThrowing` run when the future completes, with its value or error,
not when the method returns. In `@Around`, `proceed()` returns the future:
make the advice `async` and `await` it to work with the value. Other
advice may be `async` too: on a method that returns a `Future` it is
awaited before the call goes on; on a synchronous method an `async` advice
is an error.

```dart
@Around('execution(Future *(..))')
Future<Object?> timeAsync(ProceedingJoinPoint call) async {
  final watch = Stopwatch()..start();
  try {
    return await (call.proceed()! as Future<Object?>);
  } finally {
    log.info('${call.signature.name}: ${watch.elapsedMilliseconds} ms');
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
| `within(TypePattern)` | every member whose body is in a matching class. An inherited member that is not overridden is within its superclass (AspectJ's lexical scope). `Type+` also matches subtypes | `within(*Repository)`, `within(Repository+)` |
| `target(Type)`, `this(Type)` | every member of beans of that type or a subtype (interfaces too) | `target(PaymentGateway)` |
| `args(types)` | methods whose arguments have these types: the declared parameter type, else the runtime argument (`..` for any number) | `args(String, ..)` |
| `@args(Annotation, ..)` | methods whose arguments' classes carry the annotations | `@args(Audited)` |
| `bean(namePattern)` | every member of beans with that name, an alias or a qualifier value | `bean(order*)` |
| `@annotation(Annotation)` | methods carrying the annotation, also when it is on the interface method they implement. Not when only a superclass method they override has it, as in AspectJ. (Annotation-driven advisors such as `@Cacheable` and `@Validated` groups read `MethodSignature.mergedAnnotations`, which include the overridden methods' annotations, as in Spring) | `@annotation(Timed)` |
| `@within(Annotation)` | every member whose body is in a class carrying the annotation | `@within(Service)` |
| `@target(Annotation)` | every member of beans whose class carries the annotation | `@target(Service)` |
| `name()` | a named pointcut: a `@Pointcut` method of the same aspect; another aspect's is written `Type.name()` | `orders()`, `AuditAspect.orders()` |

Patterns:

- `*` in a name matches any characters: `find*`, `*Service`, `*`.
- In `execution` parameters, `..` matches any number of parameters
  (including none) and `*` exactly one: `(..)`, `()`, `(String, ..)`,
  `(*, int)`.
- The return type comes first; `*` means any: `execution(* *(..))`,
  `execution(void *(..))`, `execution(Future *(..))`. The type before the
  method name is optional: `execution(* find*(..))` matches the `find*`
  methods of every bean.
- Generics and `?` are ignored when matching: `Future<int>` matches
  `Future`, `int?` matches `int`.
- Type names are simple names. Dart has no packages, so `com.x.Service`
  means `Service`, and a package wildcard such as `within(com.x..*)` is an
  error instead of silently matching everything.
- `Type+` in `within` and `execution` means the type and its subtypes:
  `execution(* Repository+.*(..))`.
- `execution` modifiers: `public`; `protected`, which matches `@protected`
  members of `package:meta` (Dart has no such modifier); and `private`,
  which never matches, since private members are not proxied. A `throws`
  clause is an error, since Dart methods declare no exceptions; select
  errors with a typed `@AfterThrowing` parameter instead.

Operators: `&&` / `and`, `||` / `or`, `!` / `not`, and parentheses.

Examples:

| Pointcut | Advises |
|---|---|
| `execution(* *(..))` | every method of every bean (methods only: `execution` never matches getters or setters, explicit ones or the implicit ones of a public field) |
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
| `orders() \|\| bean(payments)` | a named pointcut of this aspect, or the `payments` bean |

**Named pointcuts belong to their aspect.** A bare `orders()` refers to a
`@Pointcut` method of the same aspect, including those inherited from its
superclasses and mixins. To use another aspect's named pointcut, qualify
it with the class: `AuditAspect.orders()`.

```dart
@Aspect()
@Component()
@Log()
class MetricsAspect {
  // AuditAspect's pointcut, reused here.
  @After('AuditAspect.orders()')
  void count() => log.info('order call');
}
```

**Binding values to parameters.** As in AspectJ, a lowercase identifier in
`@annotation(timed)`, `@within(timed)`, `@target(timed)`,
`@args(audited)`, `this(proxy)`, `target(bean)` or `args(id, ..)` names a
parameter of the advice method, which receives the annotation, the proxy,
the bean or the argument. A type name starts with an uppercase letter;
`int`, `double`, `num`, `bool`, `dynamic` and `void` are types too. The
bound value must have the parameter's type, else the call does not match.

```dart
// Receives the @Timed annotation object and the first argument.
@Around('@annotation(timed) && args(isbn, ..)')
Object? time(ProceedingJoinPoint joinPoint, Timed timed, String isbn) =>
    joinPoint.proceed();
```

`@AfterReturning(.., returning: 'result')` and
`@AfterThrowing(.., throwing: 'error')` name the parameter that receives
the return value or the error; by default it is the first one that is
neither a `JoinPoint` nor bound. Advice and `@Pointcut` methods of the
aspect's superclasses and mixins are inherited.

**Errors.** A parameter the pointcut does not bind, or a bound name
without a parameter, fails the build. An invalid pointcut fails the build
too (see [Build-time checks](#build-time-checks)); the Zed extension
(`dart_spring`) underlines it while you type.

#### Order of advice

- Several aspects: `@Order` on the aspect class decides. The lower value
  is the outer one: its `@Before` runs first, its `@After` last. Aspects
  without `@Order` come last.
- Inside one aspect: around → before → after → afterReturning →
  afterThrowing, as in Spring.

```dart
@Aspect() @Component() @Order(1) class SecurityAspect { ... } // outer
@Aspect() @Component() @Order(2) class TimingAspect { ... }   // inner
```

#### Advice without annotations

A `PointcutAdvisor` bean is applied like an aspect. This suits libraries
that decide in code what to advise. Write the pointcut as an
`ExpressionPointcut` (same syntax) or as your own `AopPointcut` class:

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

More tools, as in Spring:

- **Per-instance aspects:** `@Aspect('perthis(pointcut)')` or
  `@Aspect('pertarget(pointcut)')` on a `@Scope('prototype')` aspect gives
  one aspect instance per proxy or per target bean. A singleton
  per-instance aspect, `percflow` and `pertypewithin` fail the build.
- **Introductions:** `@DeclareParents('Type+', defaultImpl: Impl) static
  Iface? mixin;` on an aspect makes the generated proxies (subclass
  proxies too) of the matching beans of its module implement `Iface`,
  forwarding to one `Impl` per proxy. `this(iface)` binds it.
- **Changing advice at runtime:** proxies are `Advised`: `addAdvisor`,
  `removeAdvisor`, `addAdvice` and `removeAdvice` change the advice of a
  live proxy.
- `ComposablePointcut` combines pointcuts with `union` and `intersection`.
- `ProxyFactory.forBean(beanFactory, name)` and `AspectJProxyFactory`
  (`addAspect`) create more proxies of a bean's generated proxy class.

#### Calls a bean makes to itself

A call a bean makes to its own method skips the advice, as in Spring. This
also holds for a generated subclass proxy, where the bean is its own
proxy: while one of its advised members runs, including the code a
`Future` member runs after an `await`, calls on the bean go straight to
its code. The exception is a call through a `@Lazy` reference to the bean
itself (`@Lazy() this._self`), which is advised, as in Spring.

The body of an `async*` (`Stream`) or `sync*` (`Iterable`) member runs
only when its result is listened to or iterated, after the member has
returned, so the calls it makes on the bean are advised.

To get the advice on a call to yourself, call through
`AopContext.currentProxy()`. On a subclass proxy it advises the one call
made right after it, so call it for each call. Unlike Spring the proxy is
always exposed (there is no `exposeProxy` flag), also in the asynchronous
code that an advised `Future` method starts:

```dart
Future<Book> refresh(String isbn) =>
    (AopContext.currentProxy() as Books).find(isbn);   // advised
```

#### Proxies

A proxy is a generated class that stands in for the bean. Which kind a
bean gets depends on its class:

- **Implementing proxy.** When the bean class has no private members and
  is not `final`, `base` or `sealed`, the proxy implements the class and
  its interfaces, so the bean can be injected by either.
- **Subclass proxy.** A component class that cannot be implemented
  (private members, operators, `base`) is created as a generated subclass
  instead, even when it has an interface, superclass or mixin that could
  be implemented. The subclass runs its public methods, getters and
  setters through the advice, as Spring's CGLIB proxy does. The bean is
  its own proxy, and `AopUtils.isAopProxy` is true once advice is
  attached. A member the subclass cannot override (a private type, a
  default value that is not a public constant, `@nonVirtual`) is inherited
  and not advised, with a build warning.
- **Interface proxy only.** A component class that can be neither
  implemented nor extended (`final`, `sealed`, `interface`, a factory
  constructor, generic) is proxied through the interfaces it implements.
- **No proxy.** Without such an interface, as for a `@Bean` method's type
  that cannot be proxied, the bean keeps its signatures: advice that
  matches it fails the context at startup with the reason and what to
  change. Add an interface with the advised methods and inject the bean
  by it.

`AopUtils.getTarget(bean)` unwraps a proxy. The generator option
`aop_proxies` (`all` by default, `interfaces`, `none`) controls which
proxies are generated; subclass proxies only in `all` (see
[`spring_core_dart_generator`](https://pub.dev/packages/spring_core_dart_generator)).
Annotations are matched by names the generator writes, so
`@annotation(Timed)` also works in minified and obfuscated release
builds.

**Public fields** are advised like explicit getters and setters: a field
`int count` is an implicit getter `count` and, when not `final`, a setter
`count=`, and the proxy overrides both. They are `MemberKind.getter` /
`setter` members, reached through `within`, `bean`, `target`, `@within`,
custom advisors and `@annotation(X)`. An annotation on the field counts
for both accessors, except constraints and `@Valid`, which validate the
field. Spring has no implicit accessors, so there is no `get*` name to
match with `execution`.

#### Build-time checks

The build parses every advice and `@Pointcut` expression with the
runtime's own parser. A syntax error fails the build with the aspect, the
advice and the character position, instead of failing the context at
startup. A reference to a pointcut of a class outside the module is left
to the runtime.

**Pruning.** With `aop_proxies: all`, the `@SpringBootApplication` output
knows every module of the application: its scan, the nested
`@ComponentScan` modules it imports, and the auto-configurations. It skips
the proxy class of a bean that no pointcut of the application can match
(`execution` and `within` with a type pattern, `@annotation` when no
member carries the annotation, `bean(...)`), decided with the same matcher
the runtime uses. The bean keeps its signatures, so an advisor that
matches it anyway (a module added by hand) fails the startup with the
reason instead of being skipped silently.

Nothing is skipped:

- in a `@ComponentScan` module, since any other module may import it;
- when no module has advice;
- when a module declares an advisor bean;
- when an auto-configuration declares aspects, or an advisor bean whose
  pointcut is not an `AnnotationPointcut` by the static type the build
  sees (`DefaultPointcutAdvisor(const CacheAnnotationPointcut(), ...)`
  keeps pruning on);
- for a bean whose class or members carry an annotation from outside
  `spring_core_dart`, or `@Validated` (annotation-driven advisors such as
  `@Cacheable` match by annotation);
- for beans with a `@DeclareParents` introduction, and for subclass
  proxies.

`aop_prune: false` in `build.yaml` generates the proxies of every bean
again.

### Logging

`@Log()` on a class gives it a logger, so it can write `log.info(...)`
without declaring a field. The generator writes a `log` getter (an
extension in the scan's `.spring.dart` file, which the class's library
imports) that returns the logger `<package>.<Class>`. `topic:` sets
another logger name; `fieldName:` another getter name, needed where
`dart:math` or `dart:developer` are imported, since both declare a
function `log`.

The logger is a `SpringLog`, the logging facade of the whole family: the
framework, the starters and applications log through it, and a backend
such as `spring_boot_starter_logging` decides where the records go.
Without a backend, warnings and errors are printed.

```dart
import 'package:neon/app.spring.dart'; // the generated file

@Service()
@Log(topic: 'neon.checkout')
class Checkout {
  void pay(Order order) {
    log.info('order placed', fields: {'order': order.id});
    log.debug(() => 'basket: ${order.dump()}'); // built only if enabled
    try {
      gateway.charge(order);
    } on PaymentException catch (e, s) {
      log.error('payment failed', error: e, stackTrace: s);
    }
  }
}

@Component()
@Log(fieldName: 'logger')                       // logger 'neon.Payments'
class Payments {
  void refund() => logger.warning('refund');
}
```

Fields for every line logged inside a call (an MDC in Java logging):
`SpringLog.withFields({'request': id}, () => handle(request))`. With
Spring Boot, levels come from `logging.level.*` properties
(`logging.level.neon.checkout=debug`).

In Java: Lombok's `@Slf4j`, with commons-logging / SLF4J as the facade.

### Other extension points

These are for libraries and starters that extend the container itself;
most applications never write them.

- `BeanFactoryPostProcessor` / `BeanDefinitionRegistryPostProcessor`:
  change bean definitions before any bean is created.
- `BeanPostProcessor`: see or wrap every bean the container creates.
- Custom scopes, hand-written `BeanDefinition`s and `BeanModule`s,
  `registerSingleton`.
- `@Configurable` with `autowireBean`: inject beans into objects created
  elsewhere, such as a Flutter `State`.

```dart
// Logs every bean the container creates.
@Component()
@Log()
class Audit extends BeanPostProcessor {
  @override
  Object postProcessAfterInitialization(Object bean, String name) {
    log.info('created $name');
    return bean; // or a wrapper around it
  }
}
```

**When post-processors are created.** Post-processor beans are created in
Spring's phases (`PostProcessorRegistrationDelegate`): `PriorityOrdered`,
then `Ordered` (or `@Order`), then the rest. Each phase starts only after
the previous one is registered or invoked, so a `PriorityOrdered`
`BeanPostProcessor` already processes the `Ordered` ones. The names are
queried again before each phase; registry post-processors repeat the last
phase while they register more of themselves.

A regular bean created while the `BeanPostProcessor`s are being registered
(a dependency of one of them) misses the later ones. As Spring's
`BeanPostProcessorChecker` does, this is logged at info level ("Bean
'repo' of type [Repo] is not eligible for getting processed by all
BeanPostProcessors ...", naming the post-processor being created). Make
such a dependency an `ObjectProvider` or `@Lazy`.

`EmbeddedValueResolverAware` gets Spring's `EmbeddedValueResolver`: it
resolves `${...}` placeholders, then `#{...}` expressions
(`resolver(r"#{'${app.home}' + '/cache'}")`).

#### Your own interface implementations

Some libraries turn an abstract class into a working client: you declare
the methods, the library implements them. Mark an annotation class with
`@InterfaceProxy()`, and every abstract class carrying that annotation
becomes a bean whose implementation the generator writes. Each method
hands the call, with its annotations, parameter names and types, to an
`InvocationHandler` that an `InvocationHandlerFactory` bean creates. This
replaces Java's dynamic proxies, without reflection. It is how
`@FeignClient` works, and how Spring Data repositories will.

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

@Component()
class RemoteHandlers implements InvocationHandlerFactory {
  @override
  bool supports(InterfaceMetadata<Object> metadata) =>
      metadata.annotation<Remote>() != null;

  @override
  InvocationHandler create(InterfaceMetadata<Object> metadata) =>
      MyHandler(metadata);
}
```

#### Your own method annotations

Mark an annotation class with `@BeanMethodAnnotation()`, and the
generator lists every bean method that carries it in
`BeanDefinition.annotatedMethods`, with its annotations and a closure that
calls it. Spring does this with reflection (`MethodIntrospector`). This is
how `@Scheduled` finds its methods:

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

// In a BeanPostProcessor (with BeanFactoryAware) or after the refresh:
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
| Reflection, runtime classpath scanning | `build_runner` code generation, `@ComponentScan` per directory | No reflection in Flutter and AOT |
| `PropertySource` class | `AbstractPropertySource` | `@PropertySource` is the annotation |
| `Scope` SPI, `Pointcut` interface | `CustomScope`, `AopPointcut` | `@Scope` and `@Pointcut` are the annotations |
| `@Null`, `@Pattern`, `@Future` | `MustBeNull`, `Matches`, `FutureDate` (error codes unchanged) | They clash with Dart's `Null`, `Pattern` and `Future` |
| `List<@NotBlank String>` (container element constraints) | `@Each([NotBlank()])` on the list (map values too), `@EachKey([...])` for map keys | Dart has no annotations on type arguments |
| `@GroupSequence` on a group interface | `BeanValidator(groupSequences: {Complete: [Default, Strict]})`; `@GroupSequence` on a validated class works as in Java | Dart group types carry no annotations readable at runtime |
| `Validator.supports(Class)` | `supports(Object target)` | Dart cannot test subtypes on a `Type` |
| `@Autowired` on a private field or setter (reflection) | Only public fields and setters. A private field is injected through a constructor parameter (`this._repo`, Dart 3.13 primary constructors included) | The generated code is another library and cannot reach private members |
| CGLIB-enhanced `@Configuration` classes | A generated subclass in the `.spring.dart` file. A class with instance `@Bean` methods must be extendable from another library (not `final`, `sealed` or `interface`, with a public generative constructor) or use `proxyBeanMethods: false`, else the build fails. An inter-bean call of a `FactoryBean` method returns the container's factory itself (Spring: an enhanced factory whose `getObject()` returns the container's product) | No runtime bytecode generation |
| `@Bean` definitions know only the declared return type until the bean is created (`beanClassName` is `null`) | The type of the returned expression is known at build time, and the definition is registered under it and its supertypes: `getBean<HikariDataSource>()`, `getBeanNamesForType`, `@ConditionalOnBean` / `@ConditionalOnMissingBean` and AOP (`within(Impl)`, annotations on implementation methods) see it before the bean exists | Deliberately better: the generator sees the method body |
| Duplicate bean names are found at startup (Boot disables overriding) | Two unconditional declarations of one name fail the build. Declarations with conditions (`@Profile`, `@Conditional...`) may share a name and are checked at refresh (`BeanDefinitionOverrideException` when both match) | Fail early when the clash is certain |
| CGLIB and JDK proxies | Generated `implements` proxies. A class that cannot be implemented (private members, `base`) is created as a generated subclass, its own proxy. A `final`, `sealed` or `interface` class (or one with only factory constructors) is advised only through an interface it implements | No runtime bytecode generation; Dart cannot extend such classes from another library |
| A CGLIB proxy wraps a separate target, so only the bean's `this.` calls skip the advice | A generated subclass is the bean itself. While one of its advised members runs (also after an `await` in a `Future` member), every call on the bean skips the advice, also one coming back through another bean. A call through a `@Lazy` reference to the bean is advised, and `AopContext.currentProxy()` advises the one call made right after it. The body of a `Stream` (`async*`) or lazy `Iterable` (`sync*`) member runs later, when the result is listened to or iterated, so the calls it makes on the bean are advised | Dart cannot tell a `this.` call from another call on the same object |
| Circular references (opt-in) | Always an error | Same as Spring Boot's default |
| A `ConfigurationCondition` of the `registerBean` phase on a `@Bean` method sees the `@Bean` methods of the configuration classes processed before it | It is decided when its class is read, in the same class order. But `@Bean` methods without a `registerBean`-phase condition (in classes the reader does not decide) register while parsing, so it also sees those of later classes and modules | Only conditional definitions wait for the reader; the others keep the definition order |
| `UrlResource.exists()` sends a `HEAD` request | `exists()` is `true`; `existsAsync()` sends the `HEAD` request (config data imports, `optional:` and `@PropertySource(ignoreResourceNotFound: true)` use it, so a 404 is a missing file). Reading fails for a status of 400 or above | No synchronous HTTP in Dart |
| `SmartFactoryBean.getObject(Class)` | `getObjectForType(Type)`; the extra product types are served once the factory exists | No overloading; no reflection on types not created yet |
| `@Lookup` methods with arguments (passed to the bean's constructor by `getBean(name, args)`) | Lookup methods take no parameters (build error): inject an `ObjectProvider<T>` or a factory and pass the values yourself | Generated bean definitions resolve the constructor arguments themselves |
| CGLIB subclass for `@Lookup` methods | A generated subclass in the `.spring.dart` file: the class must be extendable from another library and the methods public. An abstract class may have no abstract members besides its lookup methods (a build error; Spring fails when one is called) | No runtime bytecode generation |
| `registerSingleton(name, object)` is found by every type of the object | Without `types:` it is found only by its runtime type: pass `types: [SystemClock, Clock]` to find it by its interfaces | Dart cannot list the supertypes of an object at runtime |
| `SmartInstantiationAwareBeanPostProcessor.getEarlyBeanReference` / `determineCandidateConstructors` | Only `predictBeanType` | No early references (circular references are errors); the generator picks the constructor |
| Asynchronous initialization | `refresh()` is synchronous (load the config first with `processAndApply()`); `refreshAsync()` awaits `Future`-returning init callbacks, and the bean can be injected meanwhile | Dart cannot block on a `Future` |
| `execution(* getName(..))` matches an explicit or generated getter (they are methods in Java) | `execution` matches methods only. A public field is an implicit getter / setter that the proxy advises (`MemberKind.getter` / `setter`, reached by `within`, `bean`, `@annotation`, custom advisors); an explicit getter is a getter too | Dart has getters and setters of its own, and fields have implicit ones |
| Package-qualified AOP type patterns | Simple type names; qualified wildcards are rejected | No packages in Dart |
| `execution(Animal+ *(..))` matches subtypes of any return or parameter type | `Type+` as an `execution` return or parameter type knows `Object`, `num`, `Iterable` and `Pattern` only; another fails the build (list the types: `(Dog \|\| Cat)`) | Signatures carry the declared type's name, not its supertypes |
| Annotations are read by reflection, whatever their values | An annotation whose values include a private constant, function or symbol (`#_name`) is left out of the runtime metadata (public symbols and records are kept), so `@annotation(X)` does not see it; a constraint or `@Valid` with one fails the build | Generated code cannot reference private declarations of another library |
| `execution(protected ...)`, `throws` patterns | `protected` matches `@protected` members (`package:meta`), `private` matches nothing; a `throws` clause fails the build | Dart has no protected modifier and declares no exceptions |
| `args(Type)` / `@args(A)` test any runtime class (reflection) | Type tests the generator writes for the types named in the aspect and the scanned classes carrying the annotation | No reflection |
| `@DeclareParents` applies to any matching bean | To the generated proxies (interface and subclass) of the matching beans of the aspect's module. A subclass proxy implements the interface even when a condition leaves the aspect out (its members then throw) | Proxy classes are written at build time |
| `ProxyFactory` proxies any object | `ProxyFactory` / `AspectJProxyFactory` need the generated proxy class of a bean (`ProxyFactory.forBean`) | No runtime proxy classes |
| A generic bean class matches generic injection points (`ResolvableType`) | Registered under its raw type (`Repo<dynamic>`); inject it by that type, or declare a `@Bean Repo<User>` | Type arguments of a class bean are not known at runtime |
| Beans of functional interfaces and records are classes | Function and record beans are found by their exact type, in single injection points only | Dart function and record types are structural |
| Jackson `ObjectMapper` (reflection) | `ObjectMapper` on generated metadata; a model needs `@Introspected()` (its classes of the same package are included) | No reflection |
| Optional `@Value` with `${x:#{null}}` | A nullable target gets `null` when a placeholder is missing | Dart null safety |
| Lazy beans, prototypes and `@Lazy` injection points fail on first use | `refresh()` checks them too (missing or ambiguous beans, cycles, placeholders) | Fail at startup, not later |
| `getBean` does not return `registerResolvableDependency` values | `getBean<BeanFactory>()` and `getBean<ApplicationContext>()` return them | The same objects that injection gets |
| Custom qualifier annotations match by type and attributes | They match by their qualifier value only | Annotations are not read at runtime |
| `@EventListener(condition = "#event.big")` (SpEL) | `condition:` takes a Dart function | Type-checked, no reflection |
| `@EnableAsync` switches `@Async` on; `@Async` on any bean method (proxies) | A `TaskExecutor` bean switches it on (the scheduling starter has one); `@Async` on `@EventListener` methods only; a `TaskExecutor` runs tasks in a later event-loop turn | No runtime proxies; Dart isolates have no threads |
| `ImportSelector.selectImports(metadata)` returns class names; registrars get the importing class's metadata; imported classes get fully qualified names; `BeanRegistry.registerBean(Class)` instantiates the class | `selectImports()` returns `BeanModule`s, without metadata; simple bean names; `registerBean<T>` needs a supplier | No reflection, no packages in Dart |
| `SmartLifecycle.stop(Runnable callback)` blocks `close()`, `stop()` and `restart()` per phase | `stopWithCallback(callback)`. `closeAsync()` waits for a later callback (per-phase timeouts), `close()` goes on. A bean asked to start while its callback is pending (`restart()`, `start()` after `stop()`) starts when the callback fires | No overloading; Dart cannot block on a `Future` |
| A `null` result reaches an `@AfterReturning` parameter of any type | Only `Object?` / `dynamic` (and nullable types) get `null` | Dart null safety |
| Jackson writes Java enums by name (`IN_STOCK`) | Enums go over the wire by their Dart name (`inStock`); use `@JsonValue` to talk to Java peers | Dart naming conventions |
| Jackson writes `BigInteger` as a JSON number | `BigInt` as a string | `jsonEncode` has no arbitrary-precision numbers |
| Jackson sets a JSON `null` or a missing creator value of a reference type (`String`, a class) to `null`; a primitive one fails with `FAIL_ON_NULL_FOR_PRIMITIVES` (Jackson 3's default) | A JSON `null` or a missing constructor value for any non-nullable type is an error. `int`, `double`, `num` and `bool` follow `DeserializationFeature.failOnNullForPrimitives` (on; off reads `0` / `false`, as in Jackson) | Dart null safety |
| `spring.jackson.time-zone` with any zone ID | `UTC` / `Z` or a fixed offset (`+02:00`, `GMT+2`); a named zone (`Europe/Berlin`) fails at startup with a message saying so | Dart has no time zone database |
| Boot binds every `spring.jackson.*` key (Jackson features, `date-format`, `locale`, ...) | Only the keys of the `spring_boot_dart` table are read; any other `spring.jackson.*` key is logged as a warning and ignored | The mapper has only the feature enums `JsonMapper.builder()` lists |
| SpEL `matches` and String methods are Java's | Dart's `RegExp` syntax and Dart's String methods (`replaceAll` with a string is literal) | Dart runtime |
| SpEL `T(java.lang.Math)` finds any class | `T()` needs registered types and takes Dart type names (`T(int)`) and the common `java.lang` / `java.util` ones (`Math`, `Integer`, `Objects`, `System`, `StringBuilder`, ...); `T(System).getProperty(name, default)` gives the default | No reflection; Dart has no system properties |
| SpEL on the JVM knows `7.0` from `7` | On the web, an integral double that comes from outside SpEL (a variable, a property not declared `double` on an `@Introspected` class, an element of a collection SpEL did not build) counts as an `int` | JavaScript has one number type |
| SpEL reads the public properties and methods of any object (reflection) | `StandardEvaluationContext` and `SimpleEvaluationContext` read the `@Introspected` classes of `BeanIntrospector.shared` (methods: `withInstanceMethods()` for the simple one); other objects need a `PropertyAccessor` / `MethodResolver` | No reflection |
| Jackson reads and writes any enum | An enum that no `@Introspected` class uses has no values known at runtime: `readValue<Color>` fails with a message; pass `EnumType<Color>(Color.values)` or call `introspector.registerEnum(...)` | No reflection |
| Jackson reads `Range<Integer>` of `class Range<T extends Number>` | A generic class with bounded type parameters is described raw (`Range<num>`): writing works, reading it with type arguments fails with a message (register a `JsonDeserializer`) | Dart cannot build `Range<X>` for a type parameter `X` without that bound |
| SpEL `1 instanceof T(Long)` is `false` (an `Integer`) | `true`: `T(Long)`, `T(Integer)`, `T(Short)` and `T(Byte)` are all Dart's `int` | Dart has one integer type |
| Boot reads `.properties` config files as ISO-8859-1 | UTF-8, unless the loader or the location says otherwise (`PropertiesPropertySourceLoader(encoding: latin1)`, `x.properties[encoding=iso-8859-1]`) | Dart files are UTF-8 |
| An encoding hint names any charset of Java; bytes invalid in it are read as `�` | UTF-8, ISO-8859-1 and US-ASCII (Java's names and aliases); another fails the start, also in a YAML location's hint (which Boot ignores), and so do invalid bytes | `dart:convert` decodes these three |
| `application.xml` and `spring.config.import=x.xml` are read (`Properties.loadFromXML`) | Not read: `application.xml` is not looked for, an `.xml` import fails the start ("XML properties files are not supported"), an `optional:` one is skipped | No XML parser in the core; `.properties` and YAML cover it |
| SnakeYAML refuses YAML nested more than 50 collections deep | Read up to some thousands of levels (3,000 on the VM), deeper fails with a `ConfigDataLoadException` | Dart's `package:yaml` has no such limit; only the stack stops it |
| A `.properties` file with tens of thousands of `\`-only lines overflows the stack (`StackOverflowError`) | Read | Continued lines are joined in a loop |
| A `.properties` comment right after `#---` (before the document's first key) joins the new document to the one before; after `#--- ` (trailing spaces) the next line is misread (a key with leading spaces dropped) | Both documents read as written | Boot's loader silently changes the file there |
| SnakeYAML reads YAML 1.1: `yes` / `no` / `on` / `off` are booleans (a `String` property gets `true` / `false`), `017` is octal (15), `1_000` is 1000 | YAML 1.2 (core schema): those stay the strings `yes`, `on`, ... (a `bool` property still converts them), `017` is 17, `0o17` is octal, `1_000` is a string. Quote such values to read the same in both | Dart's `package:yaml` implements YAML 1.2 |
| `ConversionService.canConvert(Class, Class)` | `canConvertType<S>(Type target)`; `canConvert(Object? source, Type target)` checks a value | Dart cannot pass a source type and test subtypes on a `Type` value |
| `ChronoUnit` (all `java.time` units) | `ChronoUnit` with `nanos` … `days` (no months or years), for `DurationStyle.parse(unit:)` | A Dart `Duration` has no calendar units |
| A relative import in a file found through a wildcard location (`file:./config/*/`) is resolved against the pattern (`config/*/x.yml`): read from every subdirectory, and a path with a directory fails ("must end with '*/'") | Relative to the importing file's own directory | Boot's quirk reads other directories' files |
| `configtree:` reads any file system; a location that is a file fails, even an `optional:` one | File system paths only (not `classpath:` or assets); values are strings; a location that is a file counts as missing (`optional:` skips it) | Config trees are mounted volumes |
| In a `;` group of locations, spaces around an entry are part of the location (`a.yml; b.yml` names ` b.yml`), and an empty entry is the importing file's directory (`b.yml;` also reads its `application.*`; `spring.config.location` fails on one) | Spaces are trimmed and empty entries skipped | A stray space or `;` should not change what is read |
| The first entry of a `;` group picks the resolver of the whole group: `x.yml;configtree:/run/secrets/` reads the tree entry as a plain directory (its `application.*`), `configtree:/run/secrets/;x.yml` fails (a config tree location not ending in `/`) | Each entry is read by its own prefix: both read `x.yml` and the tree | Each entry of a group is a location of its own |
| Boot 4.1.2 reads `spring.profiles.active`, `.default` and `.group.*` from on-profile documents (and documents of another cloud platform), applied or not; only `spring.profiles.include` fails there | Such a document fails when it applies and is ignored when it does not | What Boot's documentation describes |
| Profile keys of files read after the profiles are decided are ignored but stay readable with `getProperty` | The same, except that `spring.profiles.active` is hidden while no profile is active, and `spring.profiles.default` while the default profile is `default` | `StandardEnvironment` would read them as profiles then; Boot's environment never does |
| Placeholders in a document's `on-profile` and `spring.config.import` are resolved once, when the first pass reaches the document; a key from a document inactive at that point fails the start (`InactiveConfigDataAccessException`) | `on-profile` is resolved once the profiles are decided and again after each document activated, imports when they are read (after the profiles for an `on-profile` document); inactive documents are ignored. `on-profile=${P:dev}` with `P=prod` from a file the same file imports and `prod` active applies here, not in Boot | Deferred: Boot's result depends on when its first pass reaches the document |
| A profile group list with elements that do not bind (`spring.profiles.group.dev[1]=x` without `[0]`, a gap, `[0].a`) fails the start, even when the group is not active | Not checked: read up to the first missing index (`[0]=x`, `[2]=y` add only `x`), `[0].a` ignored | Deferred |
| Spring 7.0.10's `Profiles.of` accepts unbalanced or incomplete expressions such as `(dev`, `a)`, `a &`, `& a`, `(a)(b)`, `a b` | Refused ("Malformed profile expression"), in `on-profile` and `@Profile`; an expression both accept matches the same profiles | A malformed guard is more likely a mistake than intended |
| `ReloadableResourceBundleMessageSource` reload checks every resource's timestamp | File resources by modification time; others are read again; preloaded (async-only) resources change only through `preload()` | Not every resource has a timestamp or synchronous reads |

## Roadmap

Plans and sketches of coming features, one file per package:
[roadmap/](https://github.com/farum-azula/spring_core_dart/tree/main/roadmap).

## License

Apache License 2.0. Spring is a trademark of Broadcom Inc.; this project is
an independent port and is not affiliated with or endorsed by the Spring
team.
