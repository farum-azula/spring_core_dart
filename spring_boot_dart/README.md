# spring_boot_dart

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Spring Boot for Dart, on top of [`spring_core_dart`](../spring_core_dart)
(re-exported: one import is enough). A separate package so it can live in its
own repository later; it depends only on `spring_core_dart`.

```yaml
dependencies:
  spring_boot_dart: ^0.4.0
dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.0
```

## The whole application entry point

```dart
// bin/main.dart (or lib/main.dart in Flutter)
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'main.spring.dart'; // generated next to this file

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
```

`dart run build_runner build` scans the whole package (`lib/` and the
directory of `main`) — no `@ComponentScan`, no module variables — and writes
`main.spring.dart` with the beans, the `lib/resources/` files, the
auto-configuration of the dependencies and `runApplication` /
`runApplicationAsync`.

`runApplication(args)` (`SpringApplication.run`):

1. command-line arguments (`--key=value`) and OS environment variables;
2. config data: `classpath:application.properties` / `application.yml`
   (= `lib/resources/`), `application-{profile}` files, then the external
   group `./`, `./config/`, `./config/*/` overriding the packaged files
   (Boot's location groups), imports, profile groups,
   `${ENV_VAR:default}` and `${random.uuid}` / `${random.int[1,10]}`
   placeholders; relaxed names (`app.read-timeout` also finds
   `app.readTimeout`, `app.read_timeout`, `APP_READTIMEOUT`) and indexed
   keys (`spring.profiles.include[0]`, `SPRING_PROFILES_INCLUDE_0_`; a list
   comes whole from the highest source). Placeholders in a file's imports
   and on-profile guards see the command line first; an `optional:` import
   with an unresolvable placeholder is skipped;
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
the process gets SIGINT or SIGTERM (Boot's shutdown hook, through the
context's `registerShutdownHook()`): `@PreDestroy`
methods and `ContextClosedEvent` listeners run, then the process ends with
`130` / `143`. Unlike Boot it is off by default: a Dart program that
listens for signals does not end by itself, so a program that is done
would never exit. Turn it on in programs that run until stopped (scheduled
tasks, servers); the listener goes away when the context closes. It
listens through `dart:io` and does nothing on the web.

`SpringApplication.exit(context)` closes the context and returns the exit
code, like Boot 3+: the generators passed as the second argument and the
`ExitCodeGenerator` beans, sorted by order (`Ordered`, `@Order`), give the
first non-zero code; a generator that throws gives `1` unless a later one
has a code. A code other than `0` is also published as an
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
required constructor parameter 'url' of PoolProperties ...`). A nullable
nested value object none of whose own keys is set stays `null`.
`Binder.get(environment).bind('app.hosts', ListType<String>(...))` binds
outside of a properties class (`BindResult.map` / `ifBound` / `orElseGet` /
`orElseThrow`, and a `BindHandler` told about each property).

More of Boot's binding:

- `@ConfigurationProperties('pool')` on a `@Bean` method binds the object
  it returns, also a class of another package (the generator writes its
  introspection); `@Validated()` on the method validates it.
- `@Name('import')` binds a field or constructor parameter from another
  property name; `@DurationUnit(ChronoUnit.seconds)` /
  `@DataSizeUnit(DataUnit.megabytes)` give plain numbers a unit (`DataSize`
  properties read `10MB`, `512KB`).
- Environment variables bind nested objects under dashed names
  (`APP_MAIN_SERVER_HOST` → `app.main-server.host`).
- `@ConfigurationProperties('db', ignoreUnknownFields: false)` fails the
  start for properties under the prefix that bind to nothing (`The
  elements [db.urll] were left unbound.`; OS environment variables are not
  checked); `ignoreInvalidFields: true` keeps the default of a value that
  cannot be converted.
- Validation: a `Validator` bean named `configurationPropertiesValidator`
  checks every bound object it supports, `@Validated()` classes are checked
  against their constraints, and a properties class that is itself a
  `Validator` validates itself.

`SpringApplication(environmentPostProcessors: [...])` customizes the
environment before the context exists (Boot's `EnvironmentPostProcessor`):
one ordered before `EnvironmentPostProcessor.configDataOrder` runs before
the config files are read (it can add imports, profiles, sources), the
others after them. `SPRING_APPLICATION_JSON` (or
`--spring.application.json`) adds its JSON as properties (`{"app":
{"hosts": ["a"]}}` is `app.hosts[0]`), below the command line and above
the OS environment, like Boot's.

A banner is printed at startup (`SpringBootBanner`, a `classpath:banner.txt`
or `spring.banner.location`, or `SpringApplication(banner:)`);
`spring.main.banner-mode` / `bannerMode:` is `console` (default), `log` or
`off`. With `runAsync` a `banner.txt` that can only be read asynchronously
(a Flutter asset) is printed too.

A `Validator` (`defaultValidator`, a `BeanValidator`) and a
`methodValidationPostProcessor` (method validation of `@Validated` beans,
with the unique `BeanValidator`) are auto-configured, like Boot's
`ValidationAutoConfiguration`; your own `BeanValidator` bean replaces the
default one (plain form `Validator` beans do not).

`spring.main.lazy-initialization=true` makes all singletons lazy (a
`LazyInitializationExcludeFilter` bean keeps the beans it excludes eager,
`LazyInitializationExcludeFilter.forBeanTypes([CacheWarmer])`);
`spring.main.allow-bean-definition-overriding=true` lets a definition
replace another of the same name (off by default).

## JSON: the `ObjectMapper` bean

A `jacksonJsonMapper` bean (Boot 4's name; the core's `ObjectMapper`) is configured from
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
| `spring.jackson.default-property-inclusion` | `always` | `non_null`, `non_absent`, `non_empty`, `non_default` |
| `spring.jackson.deserialization.fail-on-unknown-properties` | `false` | reject JSON properties a class does not have |
| `spring.jackson.deserialization.accept-float-as-int` | `true` | `1.5` into an `int` truncates; `false` rejects it |
| `spring.jackson.deserialization.fail-on-null-for-primitives` | `true` | a JSON `null` (or missing constructor value) for a non-nullable `int`, `double`, `num` or `bool` fails, like Jackson 3; `false` reads `0` / `false` |
| `spring.jackson.datatype.datetime.write-dates-as-timestamps` (Boot 4) or `spring.jackson.serialization.write-dates-as-timestamps` (Boot 3; the former wins) | `false` | `DateTime` as epoch seconds with the fraction (Jackson 3) |
| `spring.jackson.datatype.datetime.write-durations-as-timestamps` (or `serialization.`) | `false` | `Duration` as seconds |
| `spring.jackson.datatype.datetime.write-date-timestamps-as-nanoseconds` (or `serialization.`) | `true` | `false`: timestamps in milliseconds |
| `spring.jackson.datatype.datetime.read-date-timestamps-as-nanoseconds` (or `deserialization.`) | `true` | integer timestamps are seconds; `false`: milliseconds |
| `spring.jackson.mapper.default-view-inclusion` | `false` | properties without `@JsonView` are written with a view |
| `spring.jackson.serialization.indent-output` | `false` | pretty-print |
| `spring.jackson.mapper.sort-properties-alphabetically` | `true` | properties sorted by JSON name, constructor parameters first (Jackson 3's / Boot 4's order); `false`: declaration order |
| `spring.jackson.time-zone` | each date in its own zone | `UTC` or a fixed offset such as `+02:00` (no named zones: Dart has no tz database) |

Any other `spring.jackson.*` key (Boot binds Jackson's feature flags,
`date-format`, `locale`, ...) is logged as a warning naming the key and
ignored. Time zones are `UTC` / `Z` or a fixed offset: Dart has no time zone
database, so a named zone such as `Europe/Berlin` fails the startup with a
message saying so.

`JsonMapperBuilderCustomizer` beans (Boot 4's) change the builder after
the properties are applied:

```dart
@Bean()
JsonMapperBuilderCustomizer indented() =>
    JsonMapperBuilderCustomizer.of(
      (builder) => builder.enable(SerializationFeature.indentOutput),
    );
```

`objectMapperFromProperties(environment)` builds the same mapper by hand.

## Auto-configuration and starters

A library ("starter") ships auto-configuration in
`lib/spring_auto_configuration.dart` (Spring Boot's
`META-INF/spring/...AutoConfiguration.imports`):

```dart
// lib/spring_auto_configuration.dart of package `neon_cache`
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'src/cache.spring.dart';

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
`springApplication`; nothing is listed by hand. They come after the
application's classes, so `@ConditionalOnMissingBean` backs off when the
application declares its own bean. Like Boot's `OnBeanCondition`,
`@ConditionalOnBean`, `@ConditionalOnMissingBean` and
`@ConditionalOnSingleCandidate` are decided when the configuration class
is read (Spring's `registerBean` phase), class by class — a scanned
`@Component` and an `@Import`ed class count as classes too, at their place
in that order: by then every earlier class has registered its `@Bean`
methods and run its `@Import`ed `BeanRegistrar` /
`ImportBeanDefinitionRegistrar`, so a bean registered any of those ways
counts (a component declared before the class whose bean it looks for is
decided first, as in Spring). On a class, the condition decides the class,
its `@Bean` methods and its imports once: a skipped class runs no
registrar and what it selects is not registered; a class whose condition
looks for the bean its imported class defines stays registered (Boot's
`PooledDataSourceConfiguration` pattern); its `@PropertySource`s load
anyway (they are read while parsing, as in Spring). `@ConditionalOnBean` /
`@ConditionalOnMissingBean` take a type, `.named('...')`, or
`.where(types:, names:, annotations:, search:)` (`ignored:` too for the
missing one); without arguments they check the `@Bean` method's return
type, and `search: SearchStrategy.current` looks at this context only
(Boot's `SearchStrategy`). Also: `@ConditionalOnSingleCandidate`,
`@ConditionalOnProperty` (with `prefix:`, several names with
`.names([...])`), `@ConditionalOnBooleanProperty`,
`@ConditionalOnExpression` (SpEL, placeholders resolved first),
`@ConditionalOnResource` and `@ConditionalOnCloudPlatform`
(`CloudPlatform.kubernetes`, `heroku`, `cloudFoundry`, `azureAppService`,
`amazonEcs`, ..., detected from environment variables like Boot's, or set
with `spring.main.cloud-platform`). Like Boot 3.4+, beans declared with
`autowireCandidate: false` or `defaultCandidate: false` count for neither
`@ConditionalOnBean` nor `@ConditionalOnMissingBean`. With `--debug` (or
`debug=true`) the condition evaluation report (positive and negative
matches, `ConditionEvaluationReport`) is logged at INFO after the refresh
or a failed start.

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
(default `messages`) when the context (not a parent) has no bean named
`messageSource`, with `spring.messages.encoding`,
`use-code-as-default-message`, `always-use-message-format`,
`common-messages`, `fallback-to-system-locale` and `cache-duration`.

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
import 'src/cache.spring.dart';

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
`*.spring.dart` with the package.

**4. Test it** with `ApplicationContextRunner` (`spring_boot_starter_test`):
the starter alone, with an application bean that makes it back off, with
properties that switch it off.

How it is found: when an application with `@SpringBootApplication` is
built, the generator walks every package of its dependency graph (direct
and transitive), reads `lib/spring_auto_configuration.dart` where present
and lists the annotated modules in the generated `springApplication`
(by package name; `SpringApplication` puts them in order, see above):

```dart
// generated bin/main.spring.dart of the application
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
- **Registration order**: application classes first, then
  auto-configuration in Boot's order (see above); bean conditions are
  decided class by class in that order, so `@ConditionalOnMissingBean`
  sees what the application declared, including the beans of its
  `@Import`ed registrars. A hand-written auto-configuration bean needs a
  `source` (its class, `library#Class`, as the generator sets it) or a
  `factoryMethodName` (a `@Bean` method) for its bean conditions to be
  decided in that order too; a definition with neither is decided at once.
- Keep third-party constraints of the starter wide (`dio: '>=5.0.0 <7.0.0'`)
  so applications can resolve them together with other starters.

## Logging levels

`SpringApplication` applies `logging.level.*` to the `SpringLog` facade
(Spring Boot's `LoggingApplicationListener`), with or without the logging
starter:

```properties
logging.level.root=info
logging.level.neon.checkout=debug          # and every neon.checkout.* logger
logging.group.payments=neon.card,neon.cash # a log group (or a YAML list)
logging.level.payments=trace
```

`LOGGING_LEVEL_NEON_CHECKOUT=debug` (an environment variable) works too. A
value that is no level (`trace`, `debug`, `info`, `warn`, `error`, `fatal`,
`off`) fails the start, like Boot's binding.

## Context initializers and test properties

`SpringApplication(..., initializers: [...])` runs `ApplicationContextInitializer`s
before the refresh, sorted by `Ordered` (a class implementing `initialize`,
or `ApplicationContextInitializer.of((context) => ...)`), and
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

## Build-time values (`--dart-define`)

A Flutter app has no command line, and on phones and in browsers no
useful environment variables, so values chosen when the app is built come
in as `--dart-define`s (`-DKEY=value` for `dart run` and `dart compile`).
They become a property source right below the command-line arguments,
above the OS environment and the config files:

```sh
flutter build apk --dart-define=SPRING_PROFILES_ACTIVE=prod \
  --dart-define=API_URL=https://api.neon.books
# or --dart-define-from-file=config/prod.json
```

```dart
@Value(r'${API_URL}') String apiUrl            // https://api.neon.books
@Value(r'${api.url}') String sameUrl           // relaxed, like env variables
```

`SPRING_PROFILES_ACTIVE` activates `application-prod.properties`, so Spring
profiles replace flavors. Names are relaxed like environment variables
(`API_URL` answers `api.url`, `SHOP_MAXBASKETSIZE` binds
`shop.max-basket-size`).

On the web and in AOT builds `String.fromEnvironment` works only as a
`const` with a literal key, so a define must be known at build time: the
generator lists every key the application can read — the `${...}`
placeholders of annotations, `@ConditionalOnProperty` names, the fields of
`@ConfigurationProperties` classes, the keys and placeholders of the
`application*` config files, and `spring.profiles.active` — each also in
its environment form (`SPRING_PROFILES_ACTIVE`), as
`SpringApplication(dartDefines: ...)`. A key read only in code
(`environment.getProperty('x')`) is not listed: put it in
`application.properties` (even empty) or pass it to
`SpringApplication(dartDefines: {...})` yourself.

Defines are compiled into the program and can be read from an APK, an IPA
or `main.dart.js`: never pass passwords or private keys this way; a client
app gets tokens from a server instead.

Spring has no counterpart; the closest is passing `-Dkey=value` system
properties to the JVM.

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

## Hot reload (Dart VM: servers, CLIs)

A program on the Dart VM (a server of `spring_boot_starter_web`, a CLI) hot
reloads too, like Spring Boot DevTools' restart: the generated
`runApplication` registers the context, and after the VM reloaded the code
(`reloadSources`, from a tool) the tool calls the service extension
`ext.spring_boot.reload` (`SpringHotReload.extensionName`):

- only method bodies changed: the context keeps running, with the new code;
- the generated code changed (beans, annotations, `lib/resources/`, such as
  a new `@GetMapping` or another `server.port`): the context is closed and
  starts again with the same arguments (the web server stops and listens
  again).

The `dart run: <file>` tasks of the Flutter tools Zed extension do it on
save: they run the program with the VM service on, reload it when a `.dart`
file of the package (generated ones included: `build_runner watch` rewrites
`*.spring.dart`) or a config file changes, then call the extension. Any tool
can do the same with the VM service protocol.
`spring.devtools.restart.enabled=false` keeps the context (the server, its
connections, the beans' state) running whatever changed; new beans and
config then take effect when the program restarts. Not in AOT or product builds,
on the web, nor in Flutter (above: the root widget restarts the context).


## Flutter

`runApplicationAsync(args)` (also generated) reads the config files
asynchronously; resources from `lib/resources/` are embedded, so no asset
declarations are needed for them. Other assets plug in as a
`ProtocolResolver` on the context's resource loader (for `asset:` or
`package:` locations); config imports and `@PropertySource` files from it
are read asynchronously too.

## Differences from Spring

| Spring Boot | Here | Why |
|---|---|---|
| Constructor binding passes `null` for a missing property without `@DefaultValue` | A missing non-nullable scalar fails the start; a missing collection is empty and a missing nested object is created with its own defaults (what Boot does with an empty `@DefaultValue`) | Dart's non-nullable types |
| `@ConstructorBinding` picks one of several constructors | Constructor binding only for a class whose only public generative constructor has parameters | Not implemented yet |
| `.properties` config files are read as ISO-8859-1 | UTF-8 (pass `PropertiesPropertySourceLoader(encoding: latin1)` to `ConfigDataEnvironment` for ISO-8859-1) | Dart files are UTF-8 |
| YAML 1.1 (SnakeYAML) | YAML 1.2 (`package:yaml`): `on`, `off`, `yes`, `no` stay strings (converting them to `bool` still works), `0777` is 777 | The Dart team's YAML parser |
| No `spring.messages.default-locale` | `spring.messages.default-locale`: the locale tried before the system locale | Apps (Flutter) often have no meaningful system locale |
| `Started app in 0.07 seconds (process running for 0.3)` | Without the process uptime; logged only at INFO (visible with `spring_boot_starter_logging` or `logging.level.root=info`) | Dart has no process start time; no logging backend by default |
| The shutdown hook is registered by default and runs when the JVM exits | Off by default (`spring.main.register-shutdown-hook=true` turns it on); only on SIGINT / SIGTERM (then `exit(130)` / `exit(143)`); the listener keeps the process alive until the context closes | Dart has no exit hooks, and a signal listener is an open handle that would keep a finished program running |
| `EnvironmentPostProcessor`s listed in `META-INF/spring.factories` | `SpringApplication(environmentPostProcessors: [...])`; ordered by `Ordered` around config data (`EnvironmentPostProcessor.configDataOrder`) | No class path to scan |
| `@DurationUnit(ChronoUnit.X)`, `@DataSizeUnit(DataUnit.X)` | The same with Dart enums (`ChronoUnit.seconds`, `DataUnit.megabytes`; no months / years) | Dart naming; `Duration` has no calendar units |
| `BindHandler.onFailure` returns a replacement value or rethrows | `onFailure(name, error)` returns whether the failure counts (`false` leaves the property unbound) | Errors are collected and reported together |
| `JsonMapperBuilderCustomizer` gets Jackson's `JsonMapper.Builder` | It gets the core `JsonMapperBuilder` (naming, inclusion, time zone, features, serializers, modules); Jackson's other builder methods are missing | Only what the Dart mapper supports |
| The condition evaluation report explains each outcome (`found bean 'x'`, `@ConditionalOnProperty (a=b) matched`) | It names each condition and whether it matched; a configuration class's conditions are listed under its key | Conditions are plain Dart objects |
| The banner is printed to `System.out`; `banner.txt` may use `${application.version}`, `${AnsiColor.*}` | `print` (`spring.main.banner-mode=log` logs it); `banner.txt` gets `${spring-boot.version}`, `${spring-boot.formatted-version}` and environment placeholders | Dart has no manifest version or ANSI property source |
| `@AutoConfiguration(before:, after:)` and `@AutoConfigureOrder` on the class | `before`, `after` and `order` of `@AutoConfigurationModule` (a module is the unit; classes can be named in them) | The generator discovers modules, not classes |
| `spring.main.allow-circular-references=true` allows circular references | Not supported: a cycle is always an error (mark an injection point `@Lazy()` or inject an `ObjectProvider`) | No early singleton references |
| `@ConditionalOnBean(annotation = Service.class)` also finds meta-annotated beans | `annotations: [Service]` matches that exact annotation class | Annotations are plain objects at runtime |

## Not yet

`AvailabilityChangeEvent`, test slices (`@WebMvcTest`-like),
Actuator, Web.
