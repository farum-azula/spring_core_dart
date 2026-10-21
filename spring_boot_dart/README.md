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

## Versions and starter compatibility

Java solves library conflicts with a BOM. pub resolves exactly one version
of every package per application, so conflicts cannot hide at runtime —
`pub get` fails and names the culprits. What remains is keeping the family
consistent and making incompatibilities readable:

- **Release train.** `spring_core_dart`, `spring_core_dart_generator` and
  `spring_boot_dart` always share one version and depend on each other with
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

## Flutter

`runApplicationAsync(args)` (also generated) reads the config files
asynchronously; resources from `lib/resources/` are embedded, so no asset
declarations are needed for them.

## Not yet

`@SpringBootTest`-style test support (next), `@AutoConfigureAfter` /
`@AutoConfigureBefore` (only `AutoConfigurationModule(order:)`), Actuator,
Web.
