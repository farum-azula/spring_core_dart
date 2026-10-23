# spring_boot_dart: examples

**What it does:** starts a whole
[`spring_core_dart`](https://pub.dev/packages/spring_core_dart) application
from one annotation on `main`: reads the config files, the environment and
the command line, creates your objects, plugs in installed starters and
explains clearly what is wrong when something cannot start.

## Setup (the generator is required)

Dart has no runtime reflection, so annotations are turned into code by
**`spring_core_dart_generator`** at build time:

```yaml
dependencies:
  spring_boot_dart: ^0.1.0      # includes spring_core_dart

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.1.0
```

## 1. The whole entry point

```dart
// bin/main.dart (lib/main.dart in Flutter)
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.beans.dart'; // generated next to this file

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
```

```bash
dart run build_runner build   # scans lib/ and bin/, writes main.beans.dart
dart run bin/main.dart
```

```text
Starting my-app using Dart 3.9.0 with PID 4242
No active profile set, falling back to 1 default profile: "default"
Started my-app in 0.042 seconds
```

(INFO lines through `SpringLog`: shown with `spring_boot_starter_logging`
or `logging.level.root=info`.)

Every `@Service` / `@Component` in `lib/` is found automatically — no lists
of classes, no setup code.

## 2. Configuration files

Put files in `lib/resources/` (they are embedded into the app, also in
Flutter, without asset declarations):

```properties
# lib/resources/application.properties
spring.application.name=my-app
shop.name=NEON Books
db.password=${DB_PASSWORD:changeme}

# lib/resources/application-prod.properties  (only with the prod profile)
shop.name=NEON Books Online
```

Values can be overridden without touching the files — later wins:

```bash
dart run bin/main.dart --shop.name=Test           # command line
SHOP_NAME=Test dart run bin/main.dart             # environment variable
dart run bin/main.dart --spring.profiles.active=prod
```

## 3. Settings as a typed object (`@ConfigurationProperties`)

All `shop.*` keys go into one class, converted and (with `@Validated()`,
as in Spring Boot) validated at start:

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
  Shop(this.properties); // inject it like any object
  final ShopProperties properties;
}
```

Invalid values stop the start with a readable report:

```text
APPLICATION FAILED TO START

Description:

Binding to target properties under 'shop' failed:

  - shop.name: must not be blank

Action:

Update the application's configuration (lib/resources/application.properties,
command line or environment).
```

## 4. Run code after start (`CommandLineRunner`)

```dart
@Component()
class Greeting implements CommandLineRunner {
  Greeting(this.properties);
  final ShopProperties properties;

  @override
  void run(List<String> args) => print('${properties.name} is open!');
}
```

`ApplicationRunner` gets parsed arguments (`--mode=batch`, plain values).
Runners run in `@Order`.

## 5. Beans only when needed (conditions)

```dart
@Service()
@ConditionalOnProperty('features.recommendations')  // only if =true
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
`pubspec.yaml`, run `build_runner` again — no code:

```yaml
dependencies:
  spring_boot_starter_logging: ^0.1.0   # console, log files, in-app log buffer
dev_dependencies:
  spring_boot_starter_test: ^0.1.0      # testing the whole app
```

Anyone can write one: a `lib/spring_auto_configuration.dart` with an
`@AutoConfigurationModule()` is all it takes — see
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

The same for two candidates without `@Primary`, a dependency cycle or a
missing `${placeholder}`.

## 8. Log levels from properties

```properties
logging.level.root=info
logging.level.my_app.payments=debug   # this logger and everything below it
```

## 9. Flutter

Use the async variant (config files may be Flutter assets):

```dart
@SpringBootApplication()
Future<void> main() async {
  final context = await runApplicationAsync(const []);
  runApp(MyApp(context));
}
```

## 10. Hot reload keeps working

After a hot reload, call the generated `reloadApplication` from
`reassemble()` of your root widget. Changed method bodies keep the running
beans; new or changed beans (regenerated by `build_runner watch`) restart
the context with the new code:

```dart
@override
void reassemble() {
  super.reassemble();
  context = reloadApplication(context);
}
```

A restart runs your `CommandLineRunner`s again, like a fresh launch. If
they do "on startup" work that must not repeat (migrations, an
`app_started` analytics event), skip them:

```dart
context = reloadApplication(context, runners: false);
```

## Try it

[`example.dart`](example.dart) next to this file runs without the generator
(bean definitions written by hand):
`dart run example/example.dart --greeting.name=Ada` → `Hello, Ada!`

A full Spring Boot app with tests:
[example/ in the repository](https://github.com/farum-azula/spring_core_dart/tree/main/example)
(`dart run bin/shop.dart`).
