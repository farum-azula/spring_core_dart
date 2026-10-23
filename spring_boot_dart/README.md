# spring_boot_dart

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Spring Boot for Dart, on top of [`spring_core_dart`](../spring_core_dart)
(re-exported: one import is enough). A separate package so it can live in its
own repository later; it depends only on `spring_core_dart`.

```yaml
dependencies:
  spring_boot_dart: ^0.1.0
dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.1.0
```

## The whole application entry point

```dart
// bin/main.dart (or lib/main.dart in Flutter)
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'main.beans.dart'; // generated next to this file

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
```

`dart run build_runner build` scans the whole package (`lib/` and the
directory of `main`) — no `@ComponentScan`, no module variables — and writes
`main.beans.dart` with the beans, the `lib/resources/` files, the
auto-configuration of the dependencies and `runApplication` /
`runApplicationAsync`.

`runApplication(args)` (`SpringApplication.run`):

1. command-line arguments (`--key=value`) and OS environment variables;
2. config data: `classpath:application.properties` / `application.yml`
   (= `lib/resources/`), `application-{profile}` files, then the external
   group `./`, `./config/`, `./config/*/` overriding the packaged files
   (Boot's location groups), imports, profile groups,
   `${ENV_VAR:default}` placeholders; relaxed names (`app.read-timeout`
   also finds `app.readTimeout`, `app.read_timeout`, `APP_READTIMEOUT`);
3. `logging.level.root=debug` → `SpringLog`;
4. the context, with `ApplicationArguments` as a bean and
   `@ConfigurationProperties` binding;
5. startup info through `SpringLog` at INFO, like Spring Boot's
   (`Starting neon-books using Dart 3.9.0 with PID 4242`,
   `The following 1 profile is active: "dev"`,
   `Started neon-books in 0.07 seconds`; `spring.main.log-startup-info=false`
   turns it off) — or an `APPLICATION FAILED TO START` report explaining a
   missing bean, an ambiguity, a cycle, an unresolved placeholder or
   invalid properties (your own `FailureAnalyzer`s, as beans or on
   `SpringApplication(failureAnalyzers:)`, are asked first);
6. `ApplicationRunner` / `CommandLineRunner` beans, one after another in
   `@Order` order, as in Spring Boot: a runner returning a `Future` is
   finished before the next starts; a failing runner is reported
   (`Application run failed`) and the context is closed.

Application events are published along the way (see
[Application events](#application-events)).

```dart
@Component()
@Order(1)
class Migrations implements ApplicationRunner {
  Migrations(this.db);
  final Database db;

  @override
  Future<void> run(ApplicationArguments args) => db.migrate(); // awaited
}

@Component()
@Order(2)
class Warmup implements ApplicationRunner { ... }       // starts after Migrations
```

`runApplication` returns once the synchronous part is done (the runners
then go on one after another); `await runApplicationAsync(args)`
completes after the last runner, like Spring Boot's `run`.

## Shutdown and exit codes

With `spring.main.register-shutdown-hook=true` (the property wins) or
`SpringApplication(registerShutdownHook: true)` the context is closed when
the process gets SIGINT or SIGTERM (Boot's shutdown hook): `@PreDestroy`
methods and `ContextClosedEvent` listeners run, then the process ends with
`130` / `143`. Unlike Boot it is off by default: a Dart program that
listens for signals does not end by itself, so a program that is done
would never exit. Turn it on in programs that run until stopped (scheduled
tasks, servers); the listener goes away when the context closes. It
listens through `dart:io` and does nothing on the web.

`SpringApplication.exit(context)` closes the context and returns the exit
code, like Boot's: the highest non-zero code of the `ExitCodeGenerator`
beans (and of the generators passed as the second argument), `1` when a
generator throws. A code other than `0` is also published as an
`ExitCodeEvent` before the context closes.

```dart
@Component()
class FailedJobs implements ExitCodeGenerator {
  int failed = 0;
  @override
  int getExitCode() => failed > 0 ? 2 : 0;
}

Future<void> main(List<String> args) async {
  final context = await runApplicationAsync(args);
  exit(SpringApplication.exit(context)); // dart:io
}
```

When a runner fails, `ExitCodeExceptionMapper` beans map the exception to
a code (the exception may also implement `ExitCodeGenerator` itself); the
code is published as an `ExitCodeEvent` and returned by
`SpringApplication.exitCodeOf(error)`, for `main` to pass to `exit`.

## Resources (`lib/resources/` = the classpath)

```
lib/resources/
  application.properties     (or application.yml)
  application-prod.properties
  messages/messages.properties
  templates/welcome.txt
```

The generator embeds these files into the generated code, so `classpath:`
works the same in `dart run`, AOT executables, Flutter and the web — no
asset declarations in `pubspec.yaml`. Files above 1 MB are skipped with a
warning (ship them as assets).

```dart
@Component()
class Mailer {
  Mailer(@Value('classpath:templates/welcome.txt') this.template);
  final Resource template;
}
```

`lib/resources/` rather than a top-level `resources/`: `build_runner` only
sees `lib/`, `bin/`, `test/`, ... without extra configuration.

## `@ConfigurationProperties`

```dart
@ConfigurationProperties('shop')
@Validated()
class ShopProperties {
  @NotBlank()
  String name = 'NEON Books';
  Duration deliveryTime = const Duration(days: 3);
  @Min(1)
  int maxBasketSize = 10;
}
```

Bound from `shop.max-basket-size` (or `shop.maxBasketSize`,
`--shop.max-basket-size=…`, `SHOP_MAX_BASKET_SIZE`) and converted to the
field types; with `@Validated()` the constraints are checked at startup, as
in Spring Boot. The class is a bean and introspected automatically.

Collections and nested objects bind like Boot's `Binder`:

```dart
@ConfigurationProperties('app')
class AppProperties {
  List<String> hosts = [];               // app.hosts=a,b  or  app.hosts[0]=a
  List<Server> servers = [];             // app.servers[0].name=eu-1
  Map<String, String> headers = {};      // app.headers.X-Shop=1, app.headers[x.y]=2
  Map<String, Backend> backends = {};    // app.backends.eu.url=https://...
}
```

```yaml
app:
  hosts: [a, b]          # YAML lists are indexed keys: app.hosts[0], ...
  servers:
    - name: eu-1
```

- A list comes whole from the highest-precedence source that has it (a
  comma value or indexed keys, `APP_HOSTS_0_` as an environment variable):
  `--app.hosts[0]=x` replaces a three-element list from
  `application.yml`, it does not change its first element. Indexes start
  at 0 without gaps.
- Map entries are merged across sources, the higher source winning per
  key; keys keep the form they are written in (`X-Shop`), `[x.y]` keeps
  the dots, and for scalar values the rest of the name is the key
  (`app.headers.a.b=1` → `a.b`).
- Elements, keys and values are converted through the conversion service
  (`List<Duration>`, `Map<String, int>`, enums by lenient name); a value
  that cannot be converted fails the start naming the property
  (`app.ports[0]: failed to convert to int (was "x")`).

A class whose only constructor has parameters is bound through it
(constructor binding, Boot 3's default for immutable classes), also for
nested classes:

```dart
@ConfigurationProperties('pool')
class PoolProperties {
  const PoolProperties(
    this.url, {                          // required: pool.url must be set
    @DefaultValue('10') required this.maxSize,
    this.timeout = const Duration(seconds: 5),
    this.owner,                          // nullable: null when not set
    this.replicas = const [],            // pool.replicas[0].host=...
  });
  final String url;
  final int maxSize;
  final Duration timeout;
  final String? owner;
  final List<Endpoint> replicas;
}
```

A parameter without a property takes its `@DefaultValue` (Boot's), its
Dart default value, or `null` when nullable; a required non-nullable one
without any of them fails the start (`pool.url: no value bound for the
required constructor parameter 'url' of PoolProperties ...`).
`Binder.get(environment).bind('app.hosts', ListType<String>(...))` binds
outside of a properties class.

A `Validator` (`defaultValidator`, a `BeanValidator`) and a
`methodValidationPostProcessor` (method validation of `@Validated` beans)
are auto-configured, like Boot's `ValidationAutoConfiguration`; your own
`Validator` bean replaces the default one.

`spring.main.lazy-initialization=true` makes all singletons lazy;
`spring.main.allow-bean-definition-overriding=true` lets a definition
replace another of the same name (off by default).

## JSON: the `ObjectMapper` bean

An `objectMapper` bean (the core's `ObjectMapper`) is configured from
`spring.jackson.*`, like Spring Boot's `JacksonAutoConfiguration`. It knows
every `@Introspected` class of the application and adds every
`JsonSerializer` / `JsonDeserializer` bean (Boot's `@JsonComponent`) and every
`JsonModule` bean (custom serializers). Declare your own `ObjectMapper` bean
to replace it.

```dart
@Service()
class Catalog {
  Catalog(this.mapper);
  final ObjectMapper mapper;

  String export(List<Book> books) => mapper.writeValueAsString(books);
  List<Book> import(String json) => mapper.readList<Book>(json);
}
```

| Property | Default | Meaning |
|---|---|---|
| `spring.jackson.property-naming-strategy` | `LOWER_CAMEL_CASE` | `SNAKE_CASE`, `UPPER_SNAKE_CASE`, `UPPER_CAMEL_CASE`, `KEBAB_CASE`, `LOWER_CASE`, `LOWER_DOT_CASE` |
| `spring.jackson.default-property-inclusion` | `always` | `non_null`, `non_empty` |
| `spring.jackson.deserialization.fail-on-unknown-properties` | `false` | reject JSON properties a class does not have |
| `spring.jackson.serialization.write-dates-as-timestamps` | `false` | `DateTime` / `Duration` as milliseconds |
| `spring.jackson.serialization.indent-output` | `false` | pretty-print |
| `spring.jackson.mapper.sort-properties-alphabetically` | `true` | properties sorted by JSON name, constructor parameters first (Jackson 3's / Boot 4's order); `false`: declaration order |
| `spring.jackson.time-zone` | each date in its own zone | `UTC` or a fixed offset such as `+02:00` (no named zones: Dart has no tz database) |

`objectMapperFromProperties(environment)` builds the same mapper by hand.

## Auto-configuration and starters

A library ("starter") ships auto-configuration in
`lib/spring_auto_configuration.dart` (Spring Boot's
`META-INF/spring/...AutoConfiguration.imports`):

```dart
// lib/spring_auto_configuration.dart of package `neon_cache`
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'src/cache.beans.dart';

@AutoConfigurationModule()
final BeanModule neonCacheAutoConfiguration = $neonCacheBeans;

// lib/src/cache.dart
@AutoConfiguration()
class CacheAutoConfiguration {
  @Bean()
  @ConditionalOnMissingBean(Cache)
  Cache cache() => InMemoryCache();
}
```

The generator of every application that depends on the library — directly
or transitively — finds these modules and passes them to the generated
`springApplication`; nothing is listed by hand. They are registered after
the application's beans, so `@ConditionalOnMissingBean` backs off when the
application declares its own bean. Also: `@ConditionalOnBean`,
`@ConditionalOnProperty`, `@ConditionalOnMissingBean.named('...')`.

Auto-configurations are registered in Boot's order
(`AutoConfigurationSorter`): by name, then `order`
(`@AutoConfigureOrder`), then `before` / `after` (a cycle fails the start
with `AutoConfigure cycle detected between ...`). A module is named like its
`BeanModule` (by convention the variable); an `@AutoConfiguration` class in
it can be named too:

```dart
@AutoConfigurationModule(
  order: 10,
  after: ['springBootAutoConfiguration'],   // module or @AutoConfiguration class
  before: ['neonMetricsAutoConfiguration'],
)
final BeanModule neonCacheAutoConfiguration = $neonCacheBeans;
```

Exclude auto-configurations before their conditions run: with
`@SpringBootApplication(exclude: [CacheAutoConfiguration])` (classes) or
`excludeName: ['springBootStarterCacheAutoConfiguration']` (the name of a
module or of a class), or with the property `spring.autoconfigure.exclude`
(comma-separated or a YAML list), which adds to them. Excluding a class
removes only its beans; excluding a module removes all of it. Excluding a
type that is no auto-configuration fails the start; an unknown name is
ignored. The built-in ones are `MessageSourceAutoConfiguration`,
`JacksonAutoConfiguration` and `ValidationAutoConfiguration`:

```properties
spring.autoconfigure.exclude=JacksonAutoConfiguration
```

A configuration class's conditions are evaluated once for the class and all
of its `@Bean` methods (all or nothing), like in Spring.

`spring_boot_dart` itself is a starter: `MessageSourceAutoConfiguration`
registers a `messageSource` for `classpath:<spring.messages.basename>`
(default `messages`) when the application has no bean named
`messageSource`.

Starters of this repository:

| Starter | What adding the dependency gives |
|---|---|
| [`spring_boot_starter_logging`](../spring_boot_starter_logging/README.md) | Console output with patterns, `logging.*` properties, an in-memory `LogBuffer` for an in-app log screen. |
| [`spring_boot_starter_test`](../spring_boot_starter_test/README.md) (dev) | `springBootTest` (`@SpringBootTest`), `BeanOverride` (`@MockitoBean`), `ApplicationContextRunner`, bean matchers, `captureLogs`. |

Test a starter's auto-configuration with `ApplicationContextRunner` from
`spring_boot_starter_test`.

## Writing your own starter

Any package can be a starter. An application that adds it to
`pubspec.yaml` and re-runs `build_runner` gets its beans with no code at
all — exactly how `spring_boot_starter_logging` is picked up by the
example.

**1. Declare the module** in `lib/spring_auto_configuration.dart` (the file
name is fixed): a public top-level `BeanModule` variable annotated with
`@AutoConfigurationModule`.

```dart
// lib/spring_auto_configuration.dart of package `neon_cache`
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'src/cache.beans.dart';

@AutoConfigurationModule(requires: '^0.1.0') // compatible spring_boot_dart versions
final BeanModule neonCacheAutoConfiguration = $neonCacheBeans;
```

**2. Describe the beans**, with the generator (`@AutoConfiguration` +
`@Bean` + conditions, scanned by a `@ComponentScan` in the starter) or as
hand-written `BeanDefinition`s (both starters of this repository do that):

```dart
// lib/src/cache.dart
@AutoConfiguration()
class CacheAutoConfiguration {
  @Bean()
  @ConditionalOnMissingBean(Cache)              // the application's own Cache wins
  @ConditionalOnProperty('neon.cache.enabled', matchIfMissing: true)
  Cache cache(@Value(r'${neon.cache.size:100}') int size) => InMemoryCache(size);
}
```

**3. Publish the generated code.** The generator writes files only into the
package being built (`build_to: source`), never into dependencies, so run
`dart run build_runner build` in the starter and publish its
`*.beans.dart` with the package.

**4. Test it** with `ApplicationContextRunner` (`spring_boot_starter_test`):
the starter alone, with an application bean that makes it back off, with
properties that switch it off.

How it is found: when an application with `@SpringBootApplication` is
built, the generator walks every package of its dependency graph (direct
and transitive), reads `lib/spring_auto_configuration.dart` where present
and lists the annotated modules in the generated `springApplication`
(by package name; `SpringApplication` puts them in order, see above):

```dart
// generated bin/main.beans.dart of the application
final springApplication = SpringApplication(
  [$application],
  autoConfigurations: [
    neonCacheAutoConfiguration,   // found in neon_cache
    springBootAutoConfiguration,  // spring_boot_dart
  ],
  // only where a starter sets order, before or after
  autoConfigurationMetadata: {neonCacheAutoConfiguration: AutoConfigurationModule(order: 10)},
);
```

Good to know:

- **Only with `@SpringBootApplication`.** Applications that create the
  context by hand (`AnnotationConfigApplicationContext`) list the module
  themselves.
- **Rebuild after adding the dependency.** Discovery happens at build time,
  not by scanning a classpath at startup as in Java: until `build_runner`
  runs again, the generated file does not know the new starter.
- **Incompatible versions stop the build**: if `requires` does not match
  the application's `spring_boot_dart`, the generator says which version to
  use (see below).
- **Registration order**: application beans first, then auto-configuration
  in Boot's order (see above), so `@ConditionalOnMissingBean` sees what the
  application declared.
- Keep third-party constraints of the starter wide (`dio: '>=5.0.0 <7.0.0'`)
  so applications can resolve them together with other starters.

## Logging levels

`SpringApplication` applies `logging.level.*` to the `SpringLog` facade
(Spring Boot's `LoggingApplicationListener`), with or without the logging
starter:

```properties
logging.level.root=info
logging.level.neon.checkout=debug          # and every neon.checkout.* logger
logging.group.payments=neon.card,neon.cash # a log group
logging.level.payments=trace
```

`LOGGING_LEVEL_NEON_CHECKOUT=debug` (an environment variable) works too.

## Context initializers and test properties

`SpringApplication(..., initializers: [(context) => ...])` runs callbacks
before the refresh (Spring's `ApplicationContextInitializer`), and
`run(args, properties: {...})` adds properties above every other source
(what `@SpringBootTest(properties = ...)` does). `spring_boot_starter_test`
is built on both. `SpringApplication(defaultProperties: {...})` /
`setDefaultProperties` adds the `defaultProperties` source below every
other one, config files included (Boot's `setDefaultProperties`), and
`additionalProfiles: [...]` activates profiles on top of the configured
ones (Boot's `setAdditionalProfiles`).

## Application events

Like Spring Boot, `run` / `runAsync` publish, in this order:
`ApplicationStartingEvent`, `ApplicationEnvironmentPreparedEvent`,
`ApplicationContextInitializedEvent`, `ApplicationPreparedEvent`, (the
context's `ContextRefreshedEvent`), `ApplicationStartedEvent`, the
runners, `ApplicationReadyEvent` — or `ApplicationFailedEvent` (with the
`exception`) before the failure report and the rethrow.

The early events happen before any bean exists, so their listeners are
registered on the application:

```dart
void main(List<String> args) => (springApplication
      ..addListener<ApplicationEnvironmentPreparedEvent>(
        (event) => print(event.environment.activeProfiles),
      ))
    .run(args);

// or SpringApplication([...], listeners: [ApplicationListenerAdapter.of<ApplicationStartingEvent>(...)])
```

From `ApplicationPreparedEvent` on these listeners are also listeners of
the context. `ApplicationStartedEvent`, `ApplicationReadyEvent` and the
`ApplicationFailedEvent` of a failing runner go through the context, so
`@EventListener` methods and `ApplicationListener` beans receive them:

```dart
@Component()
class Warmup {
  @EventListener()
  void onReady(ApplicationReadyEvent event) => cache.fill();
}
```

## Versions and starter compatibility

Java solves library conflicts with a BOM. pub resolves exactly one version
of every package per application, so conflicts cannot hide at runtime —
`pub get` fails and names the culprits. What remains is keeping the family
consistent and making incompatibilities readable:

- **Release train.** `spring_core_dart`, `spring_core_dart_generator`,
  `spring_boot_dart` and the `spring_boot_starter_*` packages always share
  one version and depend on each other with
  `^<version>` (`dart run tool/version.dart 0.2.0`, checked in CI).
- **Starters declare the Boot versions they support:**
  ```dart
  @AutoConfigurationModule(requires: '^0.4.0')
  final BeanModule neonCacheAutoConfiguration = $neonCacheBeans;
  ```
  The generator compares the range with `springBootVersion` and stops the
  build: *Incompatible starter: neon_cache requires spring_boot_dart ^0.4.0,
  but 0.1.0 is used. Upgrade spring_boot_dart to a version in ^0.4.0, or use
  a version of neon_cache made for spring_boot_dart 0.1.0.*
- **Starters keep third-party constraints wide** (`dio: '>=5.0.0 <7.0.0'`) so
  the solver finds a common version; CI resolves the minimum versions
  (`dart pub downgrade`) and analyzes them.
- **Escape hatch:** `dependency_overrides` in the application's
  `pubspec.yaml`, like overriding a managed version in Maven.

## Hot reload (Flutter)

A hot reload does not run `main` again, so the running context would keep
the old beans. The generator writes `springApplication` and the bean module
as getters plus a fingerprint of the generated code, and
`reloadApplication(context)` decides what to do:

- only method bodies changed (same fingerprint): the context is kept, beans
  keep their state and already run the new code;
- beans, annotations or `lib/resources/` changed (with `build_runner watch`
  running): the context is closed and started again with the same
  arguments.

Call it from `reassemble()` of the root widget's `State`, which Flutter
calls on every hot reload:

```dart
late ConfigurableApplicationContext context;

@SpringBootApplication()
Future<void> main() async {
  context = await runApplicationAsync(const []);
  runApp(const App());
}

class _AppState extends State<App> {
  @override
  void reassemble() {
    super.reassemble();
    context = reloadApplication(context); // generated next to main
  }

  @override
  Widget build(BuildContext context) => ... // look beans up here, not in initState
}
```

Objects you keep in fields (a bean fetched once in `initState`) still point
to the old context after a restart; look beans up in `build` or after
`reassemble`. A hot restart always starts from scratch.

### Runners after a restart (`runners:`)

*Runners* are beans whose code runs once, right after the application has
started — the place for "on startup" work:

```dart
@Component()
class StartupTasks implements CommandLineRunner {
  StartupTasks(this.db, this.analytics);
  final Database db;
  final Analytics analytics;

  @override
  void run(List<String> args) {
    db.migrate();                    // update the database schema
    analytics.track('app_started');  // "the app was opened"
    print('Shop is open!');
  }
}
```

When a hot reload restarts the context (beans, annotations or properties
changed), the context starts like a fresh launch, so by default the runners
run **again**:

```text
hot reload after adding a bean
  → old context closed, new one started
  → StartupTasks.run(): migrate() again, a second 'app_started' event,
    "Shop is open!" printed again
```

The app was not really opened twice, so this is often unwanted. Pass
`runners: false` to restart the beans without repeating the startup work:

```dart
@override
void reassemble() {
  super.reassemble();
  context = reloadApplication(context, runners: false);
}
```

| | `runners: true` (default) | `runners: false` |
|---|---|---|
| Beans after a restart | new | new |
| `CommandLineRunner` / `ApplicationRunner` | run again | skipped |
| Good for | runners that only prepare in-memory state the new beans need | migrations, analytics events, notifications, network calls |

Notes:

- When only method bodies changed, the context is not restarted, so
  runners never run on such a reload, whatever the flag says.
- `runApplication` / `runApplicationAsync` (a real start) always run the
  runners.
- The default matches Spring Boot DevTools, which runs the runners after
  every automatic restart.

## Flutter

`runApplicationAsync(args)` (also generated) reads the config files
asynchronously; resources from `lib/resources/` are embedded, so no asset
declarations are needed for them.

## Differences from Spring

| Spring Boot | Here | Why |
|---|---|---|
| Constructor binding passes `null` for a missing property without `@DefaultValue` | A missing non-nullable scalar fails the start; a missing collection is empty and a missing nested object is created with its own defaults (what Boot does with an empty `@DefaultValue`) | Dart's non-nullable types |
| `@ConstructorBinding` picks one of several constructors | Constructor binding only for a class whose only public generative constructor has parameters | Not implemented yet |
| YAML 1.1 (SnakeYAML) | YAML 1.2 (`package:yaml`): `on`, `off`, `yes`, `no` stay strings (converting them to `bool` still works), `0777` is 777 | The Dart team's YAML parser |
| No `spring.messages.default-locale` | `spring.messages.default-locale`: the locale tried before the system locale | Apps (Flutter) often have no meaningful system locale |
| `Started app in 0.07 seconds (process running for 0.3)` | Without the process uptime; logged only at INFO (visible with `spring_boot_starter_logging` or `logging.level.root=info`) | Dart has no process start time; no logging backend by default |
| The shutdown hook is registered by default and runs when the JVM exits | Off by default (`spring.main.register-shutdown-hook=true` turns it on); only on SIGINT / SIGTERM (then `exit(130)` / `exit(143)`); the listener keeps the process alive until the context closes | Dart has no exit hooks, and a signal listener is an open handle that would keep a finished program running |
| `@AutoConfiguration(before:, after:)` and `@AutoConfigureOrder` on the class | `before`, `after` and `order` of `@AutoConfigurationModule` (a module is the unit; classes can be named in them) | The generator discovers modules, not classes |

## Not yet

`AvailabilityChangeEvent`, test slices (`@WebMvcTest`-like),
Actuator, Web.
