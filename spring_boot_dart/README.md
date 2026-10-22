# spring_boot_dart

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
2. config data: `classpath:application.properties` (= `lib/resources/`),
   `application-{profile}.properties`, `./config/` overrides, imports,
   profile groups, `${ENV_VAR:default}` placeholders;
3. `logging.level.root=debug` → `SpringLog`;
4. the context, with `ApplicationArguments` as a bean and
   `@ConfigurationProperties` binding;
5. `ApplicationRunner` / `CommandLineRunner` beans;
6. `Started neon-books in 70 ms (profiles: dev)` — or an
   `APPLICATION FAILED TO START` report explaining a missing bean, an
   ambiguity, a cycle, an unresolved placeholder or invalid properties.

## Resources (`lib/resources/` = the classpath)

```
lib/resources/
  application.properties
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
class ShopProperties {
  @NotBlank()
  String name = 'NEON Books';
  Duration deliveryTime = const Duration(days: 3);
  @Min(1)
  int maxBasketSize = 10;
}
```

Bound from `shop.max-basket-size` (or `shop.maxBasketSize`,
`--shop.max-basket-size=…`, `SHOP_MAX_BASKET_SIZE`), converted to the field
types and validated at startup. The class is a bean and introspected
automatically.

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
(sorted by `order`, then package name):

```dart
// generated bin/main.beans.dart of the application
final springApplication = SpringApplication(
  [$application],
  autoConfigurations: [
    springBootAutoConfiguration,  // spring_boot_dart
    neonCacheAutoConfiguration,   // found in neon_cache
  ],
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
- **Registration order**: application beans first, then auto-configuration,
  so `@ConditionalOnMissingBean` sees what the application declared.
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
is built on both.

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

## Not yet

`@AutoConfigureAfter` / `@AutoConfigureBefore` (only
`AutoConfigurationModule(order:)`), test slices (`@WebMvcTest`-like),
Actuator, Web.
