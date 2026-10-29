# spring_boot_dart: example

`spring_boot_dart` starts a whole
[`spring_core_dart`](https://pub.dev/packages/spring_core_dart)
application from one annotation on `main`. It reads the config files,
the environment and the command line, creates your objects (beans) and
wires them together, adds the beans of the starters you depend on, and
explains clearly what is wrong when something cannot start.

[`example.dart`](example.dart) is a small but complete application: a
`@ConfigurationProperties` class for its settings, a `@Service` that
uses them, a `CommandLineRunner` that logs a greeting at start-up, and
`@SpringBootApplication` on `main`.

## Run it

Dart has no runtime reflection, so the annotations are turned into code
at build time by **`spring_core_dart_generator`**:

```yaml
dependencies:
  spring_boot_dart: ^0.4.3      # includes spring_core_dart

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.3
```

From the `spring_boot_dart` directory:

```bash
dart run build_runner build                         # writes example/example.spring.dart
dart run example/example.dart                       # [greeting] INFO: Hello, World!
dart run example/example.dart --greeting.name=Ada   # [greeting] INFO: Hello, Ada!
GREETING_NAME=Grace dart run example/example.dart   # [greeting] INFO: Hello, Grace!
dart run example/example.dart --greeting.times=3    # three times
```

The greeting is logged after the start-up banner, by the `greeting`
logger (`@Log(topic: 'greeting')`). Without the logging starter only
warnings show, so the example sets `logging.level.greeting=info` as a
default property in `main`. The sections below walk
through what the example uses, and the next steps of a real
application.

## 1. The whole entry point

```dart
// bin/main.dart (lib/main.dart in Flutter)
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.spring.dart'; // generated next to this file

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
```

```bash
dart run build_runner build   # scans lib/ and bin/, writes main.spring.dart
dart run bin/main.dart
```

Every `@Service` and `@Component` of the package is found
automatically: there are no lists of classes and no setup code. With
the logging starter (or `logging.level.root=info`), the start is
reported:

```text
Starting my-app using Dart 3.13.5 with PID 4242
No active profile set, falling back to 1 default profile: "default"
Started my-app in 0.042 seconds
```

## 2. Configuration files

Put the files in `lib/resources/`. They are embedded into the program,
also in Flutter, without asset declarations:

```properties
# lib/resources/application.properties
spring.application.name=my-app
shop.name=NEON Books
db.password=${DB_PASSWORD:changeme}

# lib/resources/application-prod.properties  (only with the prod profile)
shop.name=NEON Books Online
```

A value can be changed without touching the files. The command line
wins over environment variables, which win over the files:

```bash
dart run bin/main.dart --shop.name=Test           # command line
SHOP_NAME=Test dart run bin/main.dart             # environment variable
dart run bin/main.dart --spring.profiles.active=prod
```

## 3. Settings as a typed object (`@ConfigurationProperties`)

All `shop.*` keys go into one class, converted to the field types and,
with `@Validated()` as in Spring Boot, checked at start-up:

```dart
@ConfigurationProperties('shop')
@Validated()
class ShopProperties {
  @NotBlank()
  String name = 'NEON Books';

  Duration deliveryTime = const Duration(days: 3);   // shop.delivery-time=2d

  @Min(1)
  int maxBasketSize = 10;                            // or SHOP_MAX_BASKET_SIZE=25
}

@Service()
class Shop {
  Shop(this.properties); // injected like any bean
  final ShopProperties properties;
}
```

An invalid value stops the start with a readable report:

```text
APPLICATION FAILED TO START

Description:

Binding to target properties under 'shop' failed:

  - shop.name: must not be blank

Action:

Update the application's configuration (lib/resources/application.properties,
command line or environment).
```

## 4. Run code after the start (`CommandLineRunner`)

```dart
// Says hello once everything is ready.
@Component()
@Log()
class Greeting implements CommandLineRunner {
  Greeting(this.properties);
  final ShopProperties properties;

  @override
  void run(List<String> args) => log.info('${properties.name} is open!');
}
```

An `ApplicationRunner` gets the arguments parsed (`--mode=batch`
options and plain values). Runners run one after another in `@Order`.

## 5. Beans only when needed (conditions)

```dart
// Only when features.recommendations is set, to anything but false.
@Service()
@ConditionalOnProperty('features.recommendations')
class Recommendations { ... }

@Configuration()
class CacheConfig {
  @Bean()
  @ConditionalOnMissingBean(Cache)   // only if the app has no Cache of its own
  Cache cache() => InMemoryCache();
}
```

## 6. Starters: add a dependency, get the feature

A starter is a package that brings ready-made beans. Add it to
`pubspec.yaml` and run `build_runner` again; no code is needed:

```yaml
dependencies:
  # in place of spring_boot_dart: it brings it, with console, log files and
  # an in-app log buffer
  spring_boot_starter_logging: ^0.4.3
dev_dependencies:
  spring_boot_starter_test: ^0.4.3      # testing the whole app
```

Anyone can write one: a `lib/spring_auto_configuration.dart` with an
`@AutoConfigurationModule()` is all it takes. See
[Writing your own starter](https://github.com/farum-azula/spring_core_dart/tree/main/spring_boot_dart#writing-your-own-starter).

## 7. Clear errors instead of stack traces

```text
APPLICATION FAILED TO START

Description:

Bean 'checkout' required a bean of type Payments that could not be found.

Action:

Declare a bean of that type (a @Component class or a @Bean method), check its
@Profile / conditions, or make the injection point nullable.
```

Two candidates without `@Primary`, a dependency cycle or a missing
`${placeholder}` get the same kind of report.

## 8. Log levels from properties

```properties
logging.level.root=info
logging.level.my_app.payments=debug   # this logger and everything below it
```

## 9. Flutter

Use the async variant, which can read config files that are Flutter
assets:

```dart
@SpringBootApplication()
Future<void> main() async {
  final context = await runApplicationAsync(const []);
  runApp(MyApp(context));
}
```

## 10. Hot reload keeps working

After a hot reload, call the generated `reloadApplication` from
`reassemble()` of your root widget. If only method bodies changed, the
running beans are kept. New or changed beans (regenerated by
`build_runner watch`) restart the context with the new code:

```dart
@override
void reassemble() {
  super.reassemble();
  context = reloadApplication(context);
}
```

A restart runs your `CommandLineRunner`s again, like a fresh launch. If
they do start-up work that must not repeat (migrations, an
`app_started` analytics event), skip them:

```dart
context = reloadApplication(context, runners: false);
```

## Further

- The package [README](https://pub.dev/packages/spring_boot_dart)
  describes every feature.
- The guides build complete applications step by step, with tests: a
  [server](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide)
  and a [Flutter app](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide).
