# spring_core_dart_generator: examples

**What it does:** it reads the annotations of
[`spring_core_dart`](https://pub.dev/packages/spring_core_dart)
(`@Service`, `@Value`, `@Bean`, `@Aspect`...) and writes plain Dart code
that creates and connects your objects. Dart has no runtime reflection in
Flutter, AOT executables or on the web, so this step happens at build
time. It is required: without it the annotations do nothing.

This page walks through one small app: the setup, the command to run,
the file the generator writes, and the errors it reports.

## Setup

```yaml
dependencies:
  spring_core_dart: ^0.5.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.5.0
```

Mark the scan root. Every class in this file's directory and below (here
`lib/src/`) is scanned:

```dart
// lib/src/app.dart
import 'package:spring_core_dart/spring_core_dart.dart';
import 'app.spring.dart'; // created by the generator

@ComponentScan()
final BeanModule appBeans = $appBeans;
```

A bean to scan:

```dart
// lib/src/greeter.dart
import 'package:spring_core_dart/spring_core_dart.dart';

@Service()
class Greeter {
  Greeter(@Value(r'${greeting.suffix:!}') this.suffix);
  final String suffix;

  String greet(String name) => 'Hello, $name$suffix';
}
```

And `main`, which starts the container with the generated module:

```dart
// bin/main.dart
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:my_app/src/app.dart';
import 'package:my_app/src/greeter.dart';

const log = SpringLog('app'); // a logger by name, for code outside beans

void main() {
  SpringLog.level = SpringLogLevel.info; // by default only warnings show
  final context = ApplicationContext.run([appBeans]);
  log.info(context.getBean<Greeter>().greet('Ada')); // Hello, Ada!
  context.close();
}
```

With [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) you
skip `app.dart` and write `@SpringBootApplication()` on `main` instead;
the generator then scans `lib/` and the directory of `main`.

## Run it

```bash
dart run build_runner build   # once
dart run build_runner watch   # regenerate on every save
dart run bin/main.dart
```

The generator writes `app.spring.dart` next to `app.dart`. Commit the
generated files: then the app builds without running the generator first
(in CI, for other developers).

## What it writes

For `Greeter` above it generates (simplified; the real file uses import
prefixes such as `_i1.`):

```dart
BeanModule get $appBeans => BeanModule(r'appBeans', [
  BeanDefinition<Greeter>(
    name: r'greeter',
    types: const [Greeter],
    dependencies: const [Dependency.value(r'${greeting.suffix:!}')],
    create: (r) => Greeter(r.value<String>(r'${greeting.suffix:!}')),
  ),
]);
```

`create` is a plain constructor call: fast, available in AOT, Flutter and
on the web, and unaffected by minification. The container calls it with a
resolver `r` that hands out the dependencies and settings.

## Mistakes are build errors, not crashes

The generator checks what it can before the app ever runs:

```dart
@Service()
class Report {
  @Autowired()
  final Clock clock;
  // ✗ Injected field clock must be settable: declare it `late final` or non-final.
}

@Service()
class Inbox {
  @Autowired()
  late final Mailer _mailer;
  // ✗ Injected field _mailer must be public: the generated code is another
  //   library and cannot reach a private member; ...
}

@Service()
class Shop {
  Shop(@Lazy() this.repo);
  final Repository? repo;
  // ✗ @Lazy on repo: a lazy dependency cannot be nullable; use
  //   ObjectProvider<Repository> for an optional lazy bean.
}
```

Missing or ambiguous beans and dependency cycles depend on the whole
application, so they are reported when the context starts, before any of
your objects is created.

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

`aop_proxies` controls the proxy classes that `@Aspect` advice needs.
`interfaces` generates proxies only through a bean's abstract supertypes
(less code; a bean without one cannot be advised), `none` generates no
proxies, so AOP cannot advise the beans. The second option, `aop_prune`,
is described in the
[package README](https://pub.dev/packages/spring_core_dart_generator#options).

## Resources

Files in `lib/resources/` are embedded into the generated code, so
`classpath:application.properties` and `@Value('classpath:logo.png')`
work everywhere without declaring Flutter assets.

## More

- What every annotation means:
  [spring_core_dart example](https://pub.dev/packages/spring_core_dart/example).
- Full apps and their generated code:
  [example/ in the repository](https://github.com/farum-azula/spring_core_dart/tree/main/example)
  (`server_guide/lib/src/app.spring.dart` from a `@ComponentScan`,
  `server_guide/bin/main.spring.dart` from a `@SpringBootApplication`).
