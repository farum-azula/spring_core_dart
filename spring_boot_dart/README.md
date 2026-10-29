# spring_boot_dart

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

The part of Spring for Dart that starts an application. With
[`spring_core_dart`](../spring_core_dart) alone you have a container of
beans (your services, created and wired together), but you still write
the start-up yourself: reading configuration, creating the container,
running start-up work. `spring_boot_dart` does all of it from one
annotation on `main`:

- it reads the configuration from files, environment variables and the
  command line, with profiles such as `dev` and `prod`;
- it creates the container with every bean of your package, and adds
  the beans of the libraries ("starters") you depend on, such as a web
  server, logging or a cache;
- it binds groups of settings into typed classes and validates them;
- it runs your start-up tasks, publishes start-up events, and closes
  everything on shutdown;
- when something cannot start (a missing bean, a bad property), it
  stops with a report that says what is wrong and what to do.

Use it for any application built on `spring_core_dart`: a server, a
command-line tool, a Flutter app. It is Spring Boot for Dart. It
exports `spring_core_dart`, so one import is enough, and it depends on
nothing else.

```yaml
dependencies:
  spring_boot_dart: ^0.4.3
dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.3
```

*In the guides:* [server, 1. The application](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#1-the-application), [2. Configuration](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#2-configuration).

## The whole application entry point

```dart
// bin/main.dart (or lib/main.dart in Flutter)
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'main.spring.dart'; // generated next to this file

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
```

Dart has no runtime reflection, so `dart run build_runner build` does
the scanning at build time. It reads the whole package (`lib/` and the
directory of `main`; no `@ComponentScan`, no lists of classes) and
writes `main.spring.dart` with the beans, the files of `lib/resources/`,
the auto-configuration of the dependencies, and the `runApplication` and
`runApplicationAsync` functions.

`runApplication(args)` is Spring Boot's `SpringApplication.run`. It
goes through these steps:

1. **Sources of properties:** the command-line arguments
   (`--key=value`) and the OS environment variables.
2. **Config files:** `application.properties` or `application.yml` from
   the classpath (`lib/resources/`), then the `application-{profile}`
   files, then the files next to the program (`./`, `./config/`,
   `./config/*/`), which override the packaged ones as in Spring Boot.
   Imports and profile groups are followed. Placeholders are resolved:
   `${ENV_VAR:default}`, `${random.uuid}`, `${random.int[1,10]}`. Names
   are relaxed: `app.read-timeout` also finds `app.readTimeout`,
   `app.read_timeout` and `APP_READTIMEOUT`. Indexed keys work too
   (`spring.profiles.include[0]`, `SPRING_PROFILES_INCLUDE_0_`), and a
   list comes whole from the highest source that has it. Placeholders in
   a file's imports and on-profile guards see the command line first; an
   `optional:` import whose placeholder cannot be resolved is skipped.
3. **Log levels:** `logging.level.root=debug` and the like are applied
   to `SpringLog`.
4. **The context:** the container is created and filled, with
   `ApplicationArguments` as a bean and the `@ConfigurationProperties`
   classes bound.
5. **The report:** start-up information is logged at INFO, as in Spring
   Boot (`Starting neon-books using Dart 3.13.5 with PID 4242`,
   `The following 1 profile is active: "dev"`,
   `Started neon-books in 0.07 seconds`; `spring.main.log-startup-info=false`
   turns it off). If the start fails, an `APPLICATION FAILED TO START`
   report explains a missing bean, an ambiguity, a cycle, an unresolved
   placeholder or invalid properties. Your own `FailureAnalyzer`s, as
   beans or in `SpringApplication(failureAnalyzers:)`, are asked first.
6. **The runners:** `ApplicationRunner` and `CommandLineRunner` beans run
   one after another.

Application events are published along the way (see
[Application events](#application-events)).

### Runners: work at start-up

A runner is a bean whose `run` method is called once the application
has started: database migrations, a warm-up, a command-line task.
Runners run one after another in `@Order`, as in Spring Boot. A runner
that returns a `Future` is finished before the next one starts. A
failing runner is reported (`Application run failed`) and the context is
closed.

```dart
// The schema must be up to date before anything else touches the database.
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

`CommandLineRunner.run` gets the raw arguments; `ApplicationRunner.run`
gets them parsed (`--mode=batch` options and plain values).

`runApplication` returns once the synchronous part of the start is done;
the runners then go on one after another. `await runApplicationAsync(args)`
completes after the last runner, as Spring Boot's `run` does.

## Shutdown and exit codes

A server or a scheduler runs until it is stopped. To stop it cleanly on
`Ctrl+C` or `kill`, the context must close when the process gets
SIGINT or SIGTERM: then `@PreDestroy` methods and `ContextClosedEvent`
listeners run, and the process ends with `130` or `143`. Turn it on with
`spring.main.register-shutdown-hook=true` or
`SpringApplication(registerShutdownHook: true)`; the property wins. It
uses the context's `registerShutdownHook()`.

Unlike in Spring Boot, it is **off by default**. A Dart program that
listens for signals does not end by itself, so a program that has
finished its work would never exit. Turn it on in programs that run
until stopped (servers, scheduled tasks); the listener goes away when
the context closes. It listens through `dart:io` and does nothing on the
web.

**Exit codes.** A command-line tool often has to tell its caller how it
went. `SpringApplication.exit(context)` closes the context and returns
the exit code, as in Boot 3+. The code comes from the generators passed
as the second argument and from the `ExitCodeGenerator` beans, sorted by
order (`Ordered`, `@Order`): the first non-zero code wins. A generator
that throws gives `1`, unless a later one has a code. A code other than
`0` is also published as an `ExitCodeEvent` before the context closes.

```dart
// The job tells the shell whether some items failed.
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

When a runner fails, `ExitCodeExceptionMapper` beans map the exception
to a code; the exception may also implement `ExitCodeGenerator` itself.
The code is published as an `ExitCodeEvent` and returned by
`SpringApplication.exitCodeOf(error)`, for `main` to pass to `exit`.

## Resources (`lib/resources/` = the classpath)

Configuration files, message bundles and templates go into
`lib/resources/`, which plays the role of Java's classpath:

```
lib/resources/
  application.properties     (or application.yml)
  application-prod.properties
  messages/messages.properties
  templates/welcome.txt
```

The generator embeds these files into the generated code, so
`classpath:` works the same with `dart run`, in AOT executables, in
Flutter and on the web, with no asset declarations in `pubspec.yaml`.
Files above 1 MB are skipped with a warning: ship those as assets.

```dart
// The welcome mail's text, read from lib/resources/templates/welcome.txt.
@Component()
class Mailer {
  Mailer(@Value('classpath:templates/welcome.txt') this.template);
  final Resource template;
}
```

Why `lib/resources/` and not a top-level `resources/`: `build_runner`
only sees `lib/`, `bin/`, `test/`, ... without extra configuration.

## `@ConfigurationProperties`

Reading settings one by one with `@Value` gets tedious when a feature
has several of them. A `@ConfigurationProperties` class gathers every
property under a prefix into one typed object, converted to the field
types, and is injected like any bean:

```dart
@ConfigurationProperties('shop')
@Validated()
class ShopProperties {
  @NotBlank()
  String name = 'NEON Books';
  Duration deliveryTime = const Duration(days: 3); // shop.delivery-time=2d
  @Min(1)
  int maxBasketSize = 10;
}
```

`maxBasketSize` is bound from `shop.max-basket-size`, or
`shop.maxBasketSize`, `--shop.max-basket-size=…` or
`SHOP_MAX_BASKET_SIZE`. With `@Validated()`, the constraints are checked
at start-up, as in Spring Boot, and a violation stops the start. The
class is a bean and is introspected automatically.

### Lists, maps and nested objects

They bind as with Spring Boot's `Binder`:

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

- **A list comes whole** from the highest-precedence source that has
  it: a comma-separated value, or indexed keys (`APP_HOSTS_0_` as an
  environment variable). So `--app.hosts[0]=x` replaces a three-element
  list from `application.yml`; it does not change its first element.
  Indexes start at 0 without gaps.
- **Map entries are merged** across sources, the higher source winning
  per key. Keys keep the form they are written in (`X-Shop`), `[x.y]`
  keeps the dots, and for scalar values the rest of the name is the key
  (`app.headers.a.b=1` gives the key `a.b`).
- **Elements, keys and values are converted** through the conversion
  service (`List<Duration>`, `Map<String, int>`, enums by lenient
  name). A value that cannot be converted stops the start and names the
  property (`app.ports[0]: failed to convert to int (was "x")`).

### Immutable classes: constructor binding

A class whose only constructor has parameters is bound through that
constructor, also for nested classes. This is Boot 3's default for
immutable classes:

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

A parameter without a property takes its `@DefaultValue`, else its Dart
default value, else `null` when it is nullable. A required non-nullable
parameter without any of them stops the start (`pool.url: no value bound
for the required constructor parameter 'url' of PoolProperties ...`). A
nullable nested object none of whose own keys is set stays `null`.

### More binding

- **On a `@Bean` method**, `@ConfigurationProperties('pool')` binds the
  object the method returns, even a class of another package (the
  generator writes its introspection). `@Validated()` on the method
  validates it.
- **Another property name:** `@Name('import')` binds a field or
  constructor parameter from that name.
- **Units for plain numbers:** `@DurationUnit(ChronoUnit.seconds)` and
  `@DataSizeUnit(DataUnit.megabytes)`. `DataSize` properties read
  `10MB` or `512KB`.
- **Environment variables** bind nested objects under dashed names
  (`APP_MAIN_SERVER_HOST` gives `app.main-server.host`).
- **Strict binding:** `@ConfigurationProperties('db', ignoreUnknownFields:
  false)` stops the start for properties under the prefix that bind to
  nothing (`The elements [db.urll] were left unbound.`), which catches
  typos; OS environment variables are not checked.
  `ignoreInvalidFields: true` keeps the default of a value that cannot
  be converted instead of failing.
- **Validation:** a `Validator` bean named
  `configurationPropertiesValidator` checks every bound object it
  supports; `@Validated()` classes are checked against their
  constraints; and a properties class that is itself a `Validator`
  validates itself.
- **Without a class:** `Binder.get(environment).bind('app.hosts', const
  ListType(ClassType<String>()))` binds one property anywhere. The
  `BindResult` has `map`, `ifBound`, `orElse`, `orElseGet` and
  `orElseThrow`, and a `BindHandler` can be told about each property.

## Start-up settings

**Changing the environment before the context exists.**
`SpringApplication(environmentPostProcessors: [...])` is Boot's
`EnvironmentPostProcessor`: code that adds or changes property sources
and profiles. One ordered before
`EnvironmentPostProcessor.configDataOrder` runs before the config files
are read, so it can add imports, profiles and sources; the others run
after them.

**JSON in one variable.** `SPRING_APPLICATION_JSON` (or
`--spring.application.json`) adds its JSON as properties: `{"app":
{"hosts": ["a"]}}` is `app.hosts[0]`. It sits below the command line and
above the OS environment, as in Boot. Handy in containers, where one
variable is easier to pass than many.

**The banner** is printed at start-up: `SpringBootBanner`, a
`classpath:banner.txt` or `spring.banner.location`, or
`SpringApplication(banner:)`. `spring.main.banner-mode` (or `bannerMode:`)
is `console` (the default), `log` or `off`. With `runAsync`, a
`banner.txt` that can only be read asynchronously, such as a Flutter
asset, is printed too.

**Lazy start.** `spring.main.lazy-initialization=true` creates every
singleton on first use instead of at start-up, which shortens the start.
A `LazyInitializationExcludeFilter` bean keeps the beans it excludes
eager: `LazyInitializationExcludeFilter.forBeanTypes([CacheWarmer])`.

**Overriding.** `spring.main.allow-bean-definition-overriding=true` lets
a bean definition replace another of the same name; it is off by
default, so a duplicate name stops the start.

## Validation

Every application gets validation without setup, as with Boot's
`ValidationAutoConfiguration`:

- `defaultValidator`, a `BeanValidator` that checks constraint
  annotations such as `@NotBlank()`. Inject `Validator` to validate
  objects by hand. Your own `BeanValidator` bean replaces it; a bean
  that only implements the plain `Validator` interface does not.
- `methodValidationPostProcessor`, which checks the parameters and
  return values of the methods of `@Validated()` beans. It uses the
  single `BeanValidator` bean, or a new one when there is none or
  several. `@ConfigurationProperties` classes are left out: there,
  `@Validated()` means validation after binding.

The default validator has no message source, so a `{key}` in a
constraint message stays as it is instead of being looked up in
`messages.properties`.

## JSON: the `ObjectMapper` bean

Every application gets an `ObjectMapper` bean to read and write JSON,
set up from the `spring.jackson.*` properties as with Spring Boot's
`JacksonAutoConfiguration`. Inject it anywhere; the web starter uses the
same bean for request and response bodies. It is named
`jacksonJsonMapper` (Boot 4's name). It knows every `@Introspected`
class of the application, and adds every `JsonSerializer` and
`JsonDeserializer` bean (Boot's `@JsonComponent`) and every `JsonModule`
bean. Declare your own `ObjectMapper` bean to replace it completely.

```dart
// Exports and imports the catalog as JSON files.
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
| `spring.jackson.deserialization.fail-on-null-for-primitives` | `true` | a JSON `null` (or a missing constructor value) for a non-nullable `int`, `double`, `num` or `bool` fails, as in Jackson 3; `false` reads `0` or `false` |
| `spring.jackson.datatype.datetime.write-dates-as-timestamps` (Boot 4) or `spring.jackson.serialization.write-dates-as-timestamps` (Boot 3; the former wins) | `false` | `DateTime` as epoch seconds with the fraction (Jackson 3) |
| `spring.jackson.datatype.datetime.write-durations-as-timestamps` (or `serialization.`) | `false` | `Duration` as seconds |
| `spring.jackson.datatype.datetime.write-date-timestamps-as-nanoseconds` (or `serialization.`) | `true` | `false`: timestamps in milliseconds |
| `spring.jackson.datatype.datetime.read-date-timestamps-as-nanoseconds` (or `deserialization.`) | `true` | integer timestamps are seconds; `false`: milliseconds |
| `spring.jackson.mapper.default-view-inclusion` | `false` | properties without `@JsonView` are written with a view |
| `spring.jackson.serialization.indent-output` | `false` | pretty-print |
| `spring.jackson.mapper.sort-properties-alphabetically` | `true` | properties sorted by JSON name, constructor parameters first (Jackson 3's and Boot 4's order); `false`: declaration order |
| `spring.jackson.time-zone` | each date in its own zone | `UTC` or a fixed offset such as `+02:00` |

A boolean property that is not `true` counts as `false`, so a typo such
as `ture` silently turns a feature off. Any other `spring.jackson.*`
key (Boot binds Jackson's feature flags, `date-format`, `locale`, ...)
is logged as a warning naming the key and ignored. Dart has no time zone
database, so a named zone such as `Europe/Berlin` stops the start with a
message saying so.

To change one thing without losing the properties, declare a
`JsonMapperBuilderCustomizer` bean (Boot 4's). Customizers run after the
properties are applied, in `@Order`, so they win over them:

```dart
// Pretty JSON, whatever the properties say.
@Bean()
JsonMapperBuilderCustomizer indented() =>
    JsonMapperBuilderCustomizer.of(
      (builder) => builder.enable(SerializationFeature.indentOutput),
    );
```

`objectMapperFromProperties(environment)` builds the same mapper by
hand, for a tool without beans, a test, or a second mapper with other
settings.

## Auto-configuration and starters

A starter is a library that brings ready-made beans: add it to
`pubspec.yaml`, rebuild, and its feature is there with no code of yours.
It ships them as auto-configuration in `lib/spring_auto_configuration.dart`,
the Dart counterpart of Spring Boot's
`META-INF/spring/...AutoConfiguration.imports`:

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
  @ConditionalOnMissingBean(Cache) // the application's own Cache wins
  Cache cache() => InMemoryCache();
}
```

The generator of every application that depends on the library,
directly or through other packages, finds these modules and passes them
to the generated `springApplication`; nothing is listed by hand. They
come after the application's classes, so `@ConditionalOnMissingBean`
backs off when the application declares its own bean.

### Conditions

Conditions decide whether a bean or a configuration class is
registered at all:

| Condition | Registers when |
|---|---|
| `@ConditionalOnBean`, `@ConditionalOnMissingBean` | a bean exists, or does not. They take a type, `.named('...')`, or `.where(types:, names:, annotations:, search:)` (`ignored:` too for the missing one). Without arguments, they look for the `@Bean` method's return type. `search: SearchStrategy.current` looks at this context only, not its parents |
| `@ConditionalOnSingleCandidate` | exactly one bean of a type exists, or one is primary |
| `@ConditionalOnProperty` | a property has a value (`havingValue:`, `matchIfMissing:`, `prefix:`; several names with `.names([...])`) |
| `@ConditionalOnBooleanProperty` | a property is `true` |
| `@ConditionalOnExpression` | a SpEL expression is true (placeholders resolved first) |
| `@ConditionalOnResource` | a resource exists |
| `@ConditionalOnCloudPlatform` | the application runs on a platform: `CloudPlatform.kubernetes`, `heroku`, `cloudFoundry`, `azureAppService`, `amazonEcs`, ..., detected from environment variables as in Boot, or set with `spring.main.cloud-platform` |

Bean conditions (`@ConditionalOnBean`, `@ConditionalOnMissingBean`,
`@ConditionalOnSingleCandidate`) depend on what was registered before
them, so their timing matters. As with Boot's `OnBeanCondition`, they
are decided when the configuration class is read (Spring's
`registerBean` phase), class by class. A scanned `@Component` and an
`@Import`ed class count as classes too, at their place in that order. By
then every earlier class has registered its `@Bean` methods and run its
`@Import`ed `BeanRegistrar` or `ImportBeanDefinitionRegistrar`, so a
bean registered in any of those ways counts. A component declared
before the class whose bean it looks for is decided first, as in
Spring.

On a class, a condition decides the class, its `@Bean` methods and its
imports at once, all or nothing, as in Spring. A skipped class runs no
registrar, and what it selects is not registered. A class whose
condition looks for the bean its own imported class defines stays
registered (Boot's `PooledDataSourceConfiguration` pattern). Its
`@PropertySource`s load anyway, because they are read while parsing, as
in Spring.

Like Boot 3.4+, beans declared with `autowireCandidate: false` or
`defaultCandidate: false` count for neither `@ConditionalOnBean` nor
`@ConditionalOnMissingBean`.

To see why a bean is there or not, start with `--debug` (or
`debug=true`): the condition evaluation report (`ConditionEvaluationReport`,
with the positive and negative matches) is logged at INFO after the
refresh or a failed start.

### Order

Auto-configurations are registered in Boot's order
(`AutoConfigurationSorter`): by `order` (`@AutoConfigureOrder` in Boot;
`0` by default), modules with the same order by name, then `before` and
`after` move them. A cycle stops the start with `AutoConfigure cycle
detected between ...`. A module is named like its `BeanModule` (by
convention, the variable); an `@AutoConfiguration` class in it can be
named too, by its short name only:

```dart
@AutoConfigurationModule(
  order: 10,
  after: ['springBootAutoConfiguration'],   // a module or an @AutoConfiguration class
  before: ['neonMetricsAutoConfiguration'],
)
final BeanModule neonCacheAutoConfiguration = $neonCacheBeans;
```

### Excluding auto-configuration

When a starter's beans are not wanted, exclude them before their
conditions run:

- `@SpringBootApplication(exclude: [CacheAutoConfiguration])` takes
  classes. A `Type` is compared by its simple name, so classes of the
  same name in different libraries are excluded together.
- `@SpringBootApplication(excludeName: ['springBootStarterCacheAutoConfiguration'])`
  takes the name of a module or of a class (short, or
  `package:x/src/y.dart#CacheAutoConfiguration`).
- The property `spring.autoconfigure.exclude` (comma-separated, or a
  YAML list) adds to them.

Excluding a class removes its beans, its imported registrars and
selectors, and its conditional `@PropertySource`s; configuration classes
it `@Import`s stay. Excluding a module removes all of it. Excluding a type that is no auto-configuration stops
the start; an unknown name is ignored. The built-in ones are
`MessageSourceAutoConfiguration`, `JacksonAutoConfiguration` and
`ValidationAutoConfiguration`:

```properties
spring.autoconfigure.exclude=JacksonAutoConfiguration
```

### What `spring_boot_dart` configures itself

`spring_boot_dart` is a starter too (`springBootAutoConfiguration`): the
`ObjectMapper` and validation beans above, and
`MessageSourceAutoConfiguration`. That one registers a `messageSource`
for `classpath:<spring.messages.basename>` (`messages` by default) when
the context, not counting a parent, has no bean named `messageSource`.
It reads `spring.messages.encoding`, `use-code-as-default-message`,
`always-use-message-format`, `common-messages`,
`fallback-to-system-locale` and `cache-duration`.

### Starters of this repository

| Starter | What adding the dependency gives |
|---|---|
| [`spring_boot_starter_logging`](../spring_boot_starter_logging/README.md) | Console output with patterns, log files with rollover, `logging.*` properties, an in-memory `LogBuffer` for an in-app log screen. |
| [`spring_boot_starter_web`](../spring_boot_starter_web/README.md) | A web server: `@RestController` classes, JSON bodies, `@Valid`, `ProblemDetail` errors, server-sent events, filters, CORS. |
| [`spring_boot_starter_security`](../spring_boot_starter_security/README.md) | Security for the web starter: a filter chain configured with `HttpSecurity`, HTTP Basic, form login, sessions, CSRF, JWT resource servers. |
| [`spring_boot_starter_feign`](../spring_boot_starter_feign/README.md) | HTTP clients from annotated interfaces (`@FeignClient`), with interceptors, retries and fallbacks. |
| [`spring_boot_starter_websocket`](../spring_boot_starter_websocket/README.md) | WebSocket clients from annotated interfaces (`@WebSocketClient`), and endpoints with the web starter. |
| [`spring_boot_starter_cache`](../spring_boot_starter_cache/README.md) | `@Cacheable`, `@CachePut`, `@CacheEvict` on bean methods, a `CacheManager` with TTL and size limits. |
| [`spring_boot_starter_scheduling`](../spring_boot_starter_scheduling/README.md) | `@Scheduled` methods (fixed rate, fixed delay, cron) and a `TaskScheduler` bean. |
| [`spring_boot_starter_flutter`](../spring_boot_starter_flutter/README.md) | Flutter apps: `SpringApplicationWidget`, beans in widgets, the app lifecycle, platform profiles. |
| [`spring_boot_starter_test`](../spring_boot_starter_test/README.md) (dev) | `springBootTest` (`@SpringBootTest`), `BeanOverride` (`@MockitoBean`), `ApplicationContextRunner`, bean matchers, `captureLogs`. |

Test a starter's auto-configuration with `ApplicationContextRunner` from
`spring_boot_starter_test`.

## Writing your own starter

Any package can be a starter. An application that adds it to
`pubspec.yaml` and runs `build_runner` again gets its beans with no code
at all; this is how `spring_boot_starter_logging` is picked up.

**1. Declare the module** in `lib/spring_auto_configuration.dart` (the
file name is fixed): a public top-level `BeanModule` variable annotated
with `@AutoConfigurationModule`.

```dart
// lib/spring_auto_configuration.dart of package `neon_cache`
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'src/cache.spring.dart';

@AutoConfigurationModule(requires: '^0.1.0') // compatible spring_boot_dart versions
final BeanModule neonCacheAutoConfiguration = $neonCacheBeans;
```

**2. Describe the beans**, either with the generator (`@AutoConfiguration`,
`@Bean` and conditions, scanned by a `@ComponentScan` in the starter) or
as hand-written `BeanDefinition`s, as the starters of this repository
do:

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

**3. Publish the generated code.** The generator writes files only into
the package being built (`build_to: source`), never into dependencies.
So run `dart run build_runner build` in the starter and publish its
`*.spring.dart` files with the package.

**4. Test it** with `ApplicationContextRunner` (`spring_boot_starter_test`):
the starter alone, with an application bean that makes it back off, and
with properties that switch it off.

**How it is found.** When an application with `@SpringBootApplication`
is built, the generator walks every package of its dependency graph,
direct and transitive, reads `lib/spring_auto_configuration.dart` where
there is one, and lists the annotated modules in the generated
`springApplication` (by package name; `SpringApplication` puts them in
order, see [Order](#order)):

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
- **Rebuild after adding the dependency.** Discovery happens at build
  time, not by scanning a classpath at start-up as in Java: until
  `build_runner` runs again, the generated file does not know the new
  starter.
- **Incompatible versions stop the build.** If `requires` does not match
  the application's `spring_boot_dart`, the generator says which version
  to use (see [Versions](#versions-and-starter-compatibility)).
- **Registration order:** application classes first, then
  auto-configuration in Boot's order. Bean conditions are decided class
  by class in that order, so `@ConditionalOnMissingBean` sees what the
  application declared, including the beans of its `@Import`ed
  registrars. A hand-written auto-configuration bean needs a `source`
  (its class, `library#Class`, as the generator sets it) or a
  `factoryMethodName` (a `@Bean` method) for its bean conditions to be
  decided in that order too; a definition with neither is decided at
  once.
- Keep the starter's third-party constraints wide (`dio: '>=5.0.0 <7.0.0'`)
  so applications can resolve them together with other starters.

## Logging levels

`SpringApplication` applies the `logging.level.*` properties to the
`SpringLog` facade, with or without the logging starter. It is Spring
Boot's `LoggingApplicationListener`:

```properties
logging.level.root=info
logging.level.neon.checkout=debug          # and every neon.checkout.* logger
logging.group.payments=neon.card,neon.cash # a log group (or a YAML list)
logging.level.payments=trace
```

`LOGGING_LEVEL_NEON_CHECKOUT=debug` as an environment variable works
too. A value that is not a level (`trace`, `debug`, `info`, `warn`,
`error`, `fatal`, `off`) stops the start, as Boot's binding does.

## Context initializers and test properties

These hooks change the context before it is filled; tests use them most.

- `SpringApplication(..., initializers: [...])` runs
  `ApplicationContextInitializer`s before the refresh, sorted by
  `Ordered`: a class implementing `initialize`, or
  `ApplicationContextInitializer.of((context) => ...)`.
- `run(args, properties: {...})` adds properties above every other
  source, which is what `@SpringBootTest(properties = ...)` does.
  `spring_boot_starter_test` is built on these two.
- `SpringApplication(defaultProperties: {...})` or
  `setDefaultProperties` adds the `defaultProperties` source below every
  other one, config files included (Boot's `setDefaultProperties`).
- `additionalProfiles: [...]` activates profiles on top of the
  configured ones (Boot's `setAdditionalProfiles`).

## Application events

Some code has to act at a precise moment of the start: once the
properties are known, or once the application is ready to serve. As in
Spring Boot, `run` and `runAsync` publish, in this order:

1. `ApplicationStartingEvent`: the run has begun;
2. `ApplicationEnvironmentPreparedEvent`: properties and profiles are
   known;
3. `ApplicationContextInitializedEvent` and `ApplicationPreparedEvent`:
   the context exists, no bean is created yet;
4. the context's own `ContextRefreshedEvent`: every bean is created;
5. `ApplicationStartedEvent`, then the runners;
6. `ApplicationReadyEvent`.

If the start or a runner fails, `ApplicationFailedEvent` (with the
`exception`) is published instead, before the failure report and the
rethrow.

The early events happen before any bean exists, so their listeners are
registered on the application itself:

```dart
// The active profiles, before any bean is created.
void main(List<String> args) => (springApplication
      ..addListener<ApplicationEnvironmentPreparedEvent>(
        (event) => log.info(event.environment.activeProfiles),
      ))
    .run(args);

// or SpringApplication([...], listeners: [ApplicationListenerAdapter.of<ApplicationStartingEvent>(...)])
```

From `ApplicationPreparedEvent` on, these listeners are also listeners
of the context. `ApplicationStartedEvent`, `ApplicationReadyEvent` and
the `ApplicationFailedEvent` of a failing runner go through the context,
so `@EventListener` methods and `ApplicationListener` beans receive
them. Most applications only need `ApplicationReadyEvent`, in a bean:

```dart
// Fill the cache once the application is up, without delaying the start.
@Component()
class Warmup {
  @EventListener()
  void onReady(ApplicationReadyEvent event) => cache.fill();
}
```

## Versions and starter compatibility

Java solves library conflicts with a BOM. pub resolves exactly one
version of every package per application, so conflicts cannot hide at
runtime: `pub get` fails and names the culprits. What remains is keeping
the family consistent and making incompatibilities readable:

- **Release train.** `spring_core_dart`, `spring_core_dart_generator`,
  `spring_boot_dart` and the `spring_boot_starter_*` packages always
  share one version and depend on each other with `^<version>`
  (`dart run tool/version.dart 0.2.0`, checked in CI).
- **Starters declare the `spring_boot_dart` versions they support:**
  ```dart
  @AutoConfigurationModule(requires: '^0.4.0')
  final BeanModule neonCacheAutoConfiguration = $neonCacheBeans;
  ```
  The generator compares the range with `springBootVersion` and stops
  the build: *Incompatible starter: neon_cache requires spring_boot_dart
  ^0.4.0, but 0.1.0 is used. Upgrade spring_boot_dart to a version in
  ^0.4.0, or use a version of neon_cache made for spring_boot_dart
  0.1.0.*
- **Starters keep third-party constraints wide** (`dio: '>=5.0.0 <7.0.0'`)
  so the solver finds a common version; CI resolves the minimum versions
  (`dart pub downgrade`) and analyzes them.
- **Escape hatch:** `dependency_overrides` in the application's
  `pubspec.yaml`, like overriding a managed version in Maven.

## Build-time values (`--dart-define`)

A Flutter app has no command line, and on phones and in browsers no
useful environment variables. Values chosen when the app is built come
in as `--dart-define`s instead (`-DKEY=value` for `dart run` and
`dart compile`). They become a property source right below the
command-line arguments, above the OS environment and the config files:

```sh
flutter build apk --dart-define=SPRING_PROFILES_ACTIVE=prod \
  --dart-define=API_URL=https://api.neon.books
# or --dart-define-from-file=config/prod.json
```

```dart
@Value(r'${API_URL}') String apiUrl            // https://api.neon.books
@Value(r'${api.url}') String sameUrl           // relaxed, like env variables
```

`SPRING_PROFILES_ACTIVE` activates `application-prod.properties`, so
Spring profiles can replace build flavors. Names are relaxed as for
environment variables (`API_URL` answers `api.url`,
`SHOP_MAXBASKETSIZE` binds `shop.max-basket-size`).

On the web and in AOT builds, `String.fromEnvironment` works only as a
`const` with a literal key, so a define must be known at build time. The
generator therefore lists every key the application can read, each also
in its environment form (`SPRING_PROFILES_ACTIVE`), as
`SpringApplication(dartDefines: ...)`:

- the `${...}` placeholders of annotations;
- the `@ConditionalOnProperty` names;
- the fields of `@ConfigurationProperties` classes;
- the keys and placeholders of the `application*` config files;
- `spring.profiles.active`.

A key read only in code (`environment.getProperty('x')`) is not listed:
put it in `application.properties` (even empty), or pass it to
`SpringApplication(dartDefines: {...})` yourself.

Defines are compiled into the program and can be read from an APK, an
IPA or `main.dart.js`. Never pass passwords or private keys this way; a
client app gets tokens from a server instead.

Spring has no counterpart; the closest is passing `-Dkey=value` system
properties to the JVM.

## Hot reload (Flutter)

A hot reload does not run `main` again, so the running context would
keep the old beans. The generator writes `springApplication` and the
bean module as getters, plus a fingerprint of the generated code, and
the generated `reloadApplication(context)` decides what to do:

- only method bodies changed (same fingerprint): the context is kept;
  the beans keep their state and already run the new code;
- beans, annotations or `lib/resources/` changed (with
  `build_runner watch` running): the context is closed and started
  again with the same arguments.

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

Objects you keep in fields (a bean fetched once in `initState`) still
point to the old context after a restart; look beans up in `build` or
after `reassemble`. A hot restart always starts from scratch.

### Runners after a restart (`runners:`)

Runners are the place for "on start-up" work:

```dart
@Component()
@Log()
class StartupTasks implements CommandLineRunner {
  StartupTasks(this.db, this.analytics);
  final Database db;
  final Analytics analytics;

  @override
  void run(List<String> args) {
    db.migrate();                    // update the database schema
    analytics.track('app_started');  // "the app was opened"
    log.info('Shop is open!');
  }
}
```

When a hot reload restarts the context (beans, annotations or
properties changed), the context starts like a fresh launch, so by
default the runners run **again**:

```text
hot reload after adding a bean
  → old context closed, new one started
  → StartupTasks.run(): migrate() again, a second 'app_started' event,
    "Shop is open!" printed again
```

The app was not really opened twice, so this is often unwanted. Pass
`runners: false` to restart the beans without repeating the start-up
work:

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
- `runApplication` and `runApplicationAsync` (a real start) always run
  the runners.
- The default matches Spring Boot DevTools, which runs the runners after
  every automatic restart.

## Hot reload (Dart VM: servers, CLIs)

A program on the Dart VM, such as a server of `spring_boot_starter_web`
or a command-line tool, hot reloads too, like Spring Boot DevTools'
restart. The generated `runApplication` registers the context. After the
VM has reloaded the code (`reloadSources`, called by a tool), the tool
calls the service extension `ext.spring_boot.reload`
(`SpringHotReload.extensionName`):

- only method bodies changed: the context keeps running, with the new
  code;
- the generated code changed (beans, annotations, `lib/resources/`; for
  example a new `@GetMapping` or another `server.port`): the context is
  closed and starts again with the same arguments, so the web server
  stops and listens again.

The `dart run: <file>` tasks of the Flutter tools Zed extension do this
on save: they run the program with the VM service on, reload it when a
`.dart` file of the package changes (generated ones included:
`build_runner watch` rewrites `*.spring.dart`) or a config file changes,
then call the extension. Any tool can do the same with the VM service
protocol.

`spring.devtools.restart.enabled=false` keeps the context (the server,
its connections, the beans' state) running whatever changed; new beans
and config then take effect when the program restarts. Hot reload is not
available in AOT or product builds, on the web, nor in Flutter (there,
the root widget restarts the context, see above).

## Flutter

`runApplicationAsync(args)` (also generated) reads the config files
asynchronously. Resources from `lib/resources/` are embedded, so they
need no asset declarations. Other assets plug in as a `ProtocolResolver`
on the context's resource loader (for `asset:` or `package:` locations);
config imports and `@PropertySource` files from it are read
asynchronously too. The
[`spring_boot_starter_flutter`](../spring_boot_starter_flutter/README.md)
starter does this for you and starts the application from a widget.

## Differences from Spring

| Spring Boot | Here | Why |
|---|---|---|
| Constructor binding passes `null` for a missing property without `@DefaultValue` | A missing non-nullable scalar stops the start; a missing collection is empty and a missing nested object is created with its own defaults (what Boot does with an empty `@DefaultValue`) | Dart's non-nullable types |
| `@ConstructorBinding` picks one of several constructors | Constructor binding only for a class whose only public generative constructor has parameters | Not implemented yet |
| `.properties` config files are read as ISO-8859-1 | UTF-8 (pass `PropertiesPropertySourceLoader(encoding: latin1)` to `ConfigDataEnvironment` for ISO-8859-1) | Dart files are UTF-8 |
| YAML 1.1 (SnakeYAML) | YAML 1.2 (`package:yaml`): `on`, `off`, `yes`, `no` stay strings (converting them to `bool` still works), `0777` is 777 | The Dart team's YAML parser |
| No `spring.messages.default-locale` | `spring.messages.default-locale`: the locale tried before the system locale | Apps (Flutter) often have no meaningful system locale |
| `Started app in 0.07 seconds (process running for 0.3)` | Without the process uptime; logged only at INFO (visible with `spring_boot_starter_logging` or `logging.level.root=info`) | Dart has no process start time; no logging backend by default |
| The shutdown hook is registered by default and runs when the JVM exits | Off by default (`spring.main.register-shutdown-hook=true` turns it on); only on SIGINT and SIGTERM (then `exit(130)` or `exit(143)`); the listener keeps the process alive until the context closes | Dart has no exit hooks, and a signal listener is an open handle that would keep a finished program running |
| `EnvironmentPostProcessor`s listed in `META-INF/spring.factories` | `SpringApplication(environmentPostProcessors: [...])`, ordered by `Ordered` around config data (`EnvironmentPostProcessor.configDataOrder`) | No class path to scan |
| `@DurationUnit(ChronoUnit.X)`, `@DataSizeUnit(DataUnit.X)` | The same with Dart enums (`ChronoUnit.seconds`, `DataUnit.megabytes`; no months or years) | Dart naming; `Duration` has no calendar units |
| `BindHandler.onFailure` returns a replacement value or rethrows | `onFailure(name, error)` returns whether the failure counts (`false` leaves the property unbound) | Errors are collected and reported together |
| `JsonMapperBuilderCustomizer` gets Jackson's `JsonMapper.Builder` | It gets the core `JsonMapperBuilder` (naming, inclusion, time zone, features, serializers, modules); Jackson's other builder methods are missing | Only what the Dart mapper supports |
| A `spring.jackson.*` boolean that is not `true` or `false` fails the binding | It counts as `false`, silently | Not checked yet |
| The condition evaluation report explains each outcome (`found bean 'x'`, `@ConditionalOnProperty (a=b) matched`) | It names each condition and whether it matched; a configuration class's conditions are listed under its key | Conditions are plain Dart objects |
| The banner is printed to `System.out`; `banner.txt` may use `${application.version}`, `${AnsiColor.*}` | `print` (`spring.main.banner-mode=log` logs it); `banner.txt` gets `${spring-boot.version}`, `${spring-boot.formatted-version}` and environment placeholders | Dart has no manifest version or ANSI property source |
| `@AutoConfiguration(before:, after:)` and `@AutoConfigureOrder` on the class | `before`, `after` and `order` of `@AutoConfigurationModule` (a module is the unit; classes can be named in them, by short name) | The generator discovers modules, not classes |
| `exclude` compares classes | A `Type` in `exclude` is compared by its simple name | A `Type` gives only its name at runtime |
| `spring.main.allow-circular-references=true` allows circular references | Not supported: a cycle is always an error (mark an injection point `@Lazy()` or inject an `ObjectProvider`) | No early singleton references |
| `@ConditionalOnBean(annotation = Service.class)` also finds meta-annotated beans | `annotations: [Service]` matches that exact annotation class | Annotations are plain objects at runtime |

## Not yet

`AvailabilityChangeEvent`, test slices (`@WebMvcTest`-like), Actuator.
