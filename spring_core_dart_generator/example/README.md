# spring_core_dart_generator: examples

**What it does:** reads the annotations of
[`spring_core_dart`](https://pub.dev/packages/spring_core_dart)
(`@Service`, `@Value`, `@Bean`, `@Aspect`...) and writes plain Dart code
that creates and connects your objects. Dart has no runtime reflection
(and Flutter forbids it), so this step happens at build time. It is
required: without it the annotations do nothing.

## Setup

```yaml
dependencies:
  spring_core_dart: ^0.2.1

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.2.1
```

Mark the scan root — every class under `lib/src/` is scanned:

```dart
// lib/src/app.dart
import 'package:spring_core_dart/spring_core_dart.dart';
import 'app.spring.dart'; // created by the generator

@ComponentScan()
final BeanModule appBeans = $appBeans;
```

With [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) you
skip this file: put `@SpringBootApplication()` on `main` instead.

## Run it

```bash
dart run build_runner build   # once
dart run build_runner watch   # regenerate on every save
```

It writes `app.spring.dart` next to `app.dart`. Commit generated files:
then the app builds without running the generator first (CI, other
developers).

## What it writes

You write:

```dart
@Service()
class Greeter {
  Greeter(@Value(r'${greeting.suffix:!}') this.suffix, this.clock);
  final String suffix;
  final Clock clock;
}
```

It generates (simplified):

```dart
final BeanModule $appBeans = BeanModule('appBeans', [
  BeanDefinition<Greeter>(
    name: 'greeter',
    dependencies: const [
      Dependency.value(r'${greeting.suffix:!}'),
      Dependency(Clock, name: r'clock'),
    ],
    create: (r) => Greeter(
      r.value<String>(r'${greeting.suffix:!}'),
      r.dependency<Clock>(name: r'clock'),
    ),
  ),
]);
```

Plain constructor calls and closures: fast, works in AOT, Flutter and on
the web, and survives minification.

## Mistakes are build errors, not crashes

The generator checks what it can before the app ever runs:

```dart
@Service()
class Report {
  @Autowired()
  final Clock clock;   // ✗ "Injected field clock must be settable: declare it late final or non-final."
}

@Service()
class Inbox {
  @Autowired()
  late final Mailer _mailer;   // ✗ "Injected field _mailer must be public."
}

@Service()
class Shop {
  Shop(@Lazy() this.repo);
  final Repository<Book>? repo;  // ✗ "a lazy dependency cannot be nullable; use ObjectProvider<...>"
}
```

Missing or ambiguous beans and dependency cycles are reported when the
context starts — before any of your objects is created.

## Options

```yaml
# build.yaml of your package
targets:
  $default:
    builders:
      spring_core_dart_generator:spring_core_dart:
        options:
          aop_proxies: all   # all (default) | interfaces | none
```

`aop_proxies` controls the generated proxies used by `@Aspect` advice:
`interfaces` proxies only interfaces (smaller code), `none` turns AOP off.

## Resources

Files in `lib/resources/` are embedded into the generated code, so
`classpath:application.properties` and `@Value('classpath:logo.png')` work
everywhere without declaring Flutter assets.

## More

- What every annotation means:
  [spring_core_dart example](https://pub.dev/packages/spring_core_dart/example).
- A full app and its generated code:
  [example/ in the repository](https://github.com/farum-azula/spring_core_dart/tree/main/example)
  (`lib/src/app.spring.dart`, `bin/shop.spring.dart`).
