# spring_core_dart: examples

**What it does:** creates the objects of your app, connects them and
configures them from settings files — you only declare what each class
needs. It is a port of Spring, the popular Java framework.

## Why use it

**1. Adding a dependency is a one-line change.**
Your `Orders` service now also needs `Analytics`. Usually you change the
constructor, then `main`, where everything is built by hand in the right
order, then every test that builds `Orders`:

```dart
// main.dart, by hand — grows with every class
final config = Config.load();
final db = Database(config.dbUrl);
final analytics = Analytics(config.analyticsKey);   // new
final orders = Orders(db, Mailer(config.smtp), analytics);  // changed
```

With the library you only change the class. Everything else follows:

```dart
@Service()
class Orders {
  Orders(this.db, this.mailer, this.analytics); // new parameter — done
  final Database db;
  final Mailer mailer;
  final Analytics analytics;
}
```

**2. Settings without parsing code.**
Values come from `application.properties`, environment variables or the
command line, already converted to the right type:

```dart
@Value(r'${shop.delivery-time}')   // "2d" in the file
late final Duration deliveryTime;  // Duration(days: 2) in the field
```

**3. Different behavior for dev, tests and production — without `if`s.**

```dart
@Service() @Profile(['dev'])
class FakePayments implements Payments { ... }   // no real money in dev

@Service() @Profile(['prod'])
class CardPayments implements Payments { ... }
```

**4. Easy tests.** Replace one service with a fake and test the rest of
the app as it really runs (see
[`spring_boot_starter_test`](https://pub.dev/packages/spring_boot_starter_test)).

**5. Logging, timing, retries, caching without touching the methods**
(AOP, block 9 below).

**6. Familiar structure.** Anyone who knows Spring from Java or Kotlin
reads the code immediately.

## Setup (the generator is required)

Dart has no runtime reflection (it is not available in Flutter), so the
annotations are turned into plain Dart code by
**`spring_core_dart_generator`** at build time. You always need both
packages:

```yaml
dependencies:
  spring_core_dart: ^0.1.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.1.0
```

One file tells the generator what to scan (everything under `lib/src/`):

```dart
// lib/src/app.dart
import 'package:spring_core_dart/spring_core_dart.dart';
import 'app.beans.dart'; // will be generated

@ComponentScan()
final BeanModule appBeans = $appBeans;
```

Generate the code (again after changing annotations), then run:

```bash
dart run build_runner build   # or: dart run build_runner watch
```

```dart
// bin/main.dart
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:my_app/src/app.dart';

void main() {
  final context = ApplicationContext.run([appBeans]);
  context.getBean<Orders>().place('book');
  context.close();
}
```

> With [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) the
> whole `main` is one line: `@SpringBootApplication() void main(args) => runApplication(args);`

## 1. Objects that are created for you

Mark a class with `@Service()` (or `@Component()`). Whatever it needs in its
constructor is created first and passed in.

```dart
@Service()
class Mailer {
  void send(String text) => print('mail: $text');
}

@Service()
class Orders {
  Orders(this.mailer); // Mailer is created and passed in
  final Mailer mailer;

  void place(String item) => mailer.send('ordered $item');
}
```

Every object is created once and shared (a *singleton*), so all classes get
the same `Mailer`.

## 2. Depend on an interface, pick the implementation

Ask for the interface; the library finds the class that implements it.

```dart
abstract interface class Payments {
  String pay(double amount);
}

@Service()
class CardPayments implements Payments {
  @override
  String pay(double amount) => 'card: $amount';
}

@Service()
class Checkout {
  Checkout(this.payments); // gets CardPayments
  final Payments payments;
}
```

Several implementations? Choose one:

```dart
@Service() @Primary()            // the default choice
class CardPayments implements Payments { ... }

@Service('cash')                 // a named one
class CashPayments implements Payments { ... }

@Service()
class Refunds {
  Refunds(@Qualifier('cash') this.payments); // asks by name
  final Payments payments;
}

@Service()
class Reports {
  Reports(this.all);              // all implementations, in @Order
  final List<Payments> all;
}
```

## 3. Settings from a properties file

Put settings in `lib/resources/application.properties` (embedded into the
app by the generator, no asset setup):

```properties
shop.name=NEON Books
shop.delivery=2d
db.password=${DB_PASSWORD:changeme}
```

Read them with `@Value`. Text is converted to the field type (`int`,
`Duration`, `List`, enums...). `${DB_PASSWORD:changeme}` reads an
environment variable with a default.

```dart
@Service()
class Shop {
  Shop(@Value(r'${shop.name}') this.name);
  final String name;

  @Value(r'${shop.delivery}')
  late final Duration delivery; // 2 days

  @Value(r'${shop.motto}')
  String? motto; // optional: null when missing
}
```

> Write placeholders in **raw strings** `r'${...}'`: in a normal Dart string
> `${...}` is string interpolation.

Load the files before starting the context:

```dart
final environment = StandardEnvironment();
ConfigDataEnvironment(environment).processAndApplySync();
final context = ApplicationContext.run([appBeans], environment: environment);
```

## 4. Different settings for dev and prod (profiles)

```properties
# lib/resources/application.properties
spring.profiles.active=dev

# lib/resources/application-prod.properties   (used only with the prod profile)
db.url=postgres://prod
```

Classes can exist only in some profiles:

```dart
@Service() @Profile(['dev'])
class FakePayments implements Payments { ... }

@Service() @Profile(['prod'])
class CardPayments implements Payments { ... }
```

Switch at start: `dart run bin/main.dart --spring.profiles.active=prod`
(add a `SimpleCommandLinePropertySource(args)` to the environment).

## 5. Objects from other libraries (`@Bean`)

You cannot annotate `http.Client`, so create it in a method:

```dart
@Configuration()
class HttpConfig {
  @Bean()
  http.Client client() => http.Client(); // now injectable anywhere
}
```

`close()` / `dispose()` of such objects is called when the context closes.

## 6. Run code after creation and before shutdown

```dart
@Service()
class Cache {
  @PostConstruct()
  void warmUp() => print('loading cache');   // after dependencies are set

  @PreDestroy()
  void flush() => print('saving cache');     // on context.close()
}
```

## 7. Events between classes that do not know each other

```dart
class OrderPlaced {
  OrderPlaced(this.id);
  final int id;
}

@Service()
class Orders {
  Orders(this.events);
  final ApplicationEventPublisher events;

  void place(int id) => events.publishEvent(OrderPlaced(id));
}

@Service()
class Emails {
  @EventListener()
  void onOrder(OrderPlaced order) => print('email for order ${order.id}');
}
```

## 8. Create objects later or many times

```dart
@Service() @Lazy()                 // created on first use, not at start
class HeavyReport { ... }

@Component() @Scope('prototype')   // a new object every time it is requested
class Basket { ... }

@Service()
class Shop {
  Shop(this.baskets);
  final ObjectProvider<Basket> baskets; // ask when needed
  Basket newBasket() => baskets.getObject();
}
```

## 9. Add behavior to methods without touching them (AOP)

Time every method marked `@Timed()`:

```dart
class Timed {
  const Timed();
}

@Aspect() @Component()
class TimingAspect {
  @Around('@annotation(Timed)')
  Object? time(ProceedingJoinPoint call) {
    final watch = Stopwatch()..start();
    try {
      return call.proceed();                    // the real method
    } finally {
      print('${call.signature.name}: ${watch.elapsedMilliseconds} ms');
    }
  }
}

@Service()
class Search {
  @Timed()
  List<String> find(String text) => [...];      // now timed
}
```

A call through `this` inside the class is not intercepted. To call
yourself through the aspect, inject yourself lazily:
`Search(@Lazy() this.self)`.

All kinds of advice (`@Before`, `@After`, `@AfterReturning`,
`@AfterThrowing`, `@Around`), the pointcut syntax with a table of
examples, and advice order: [AOP guide](https://pub.dev/packages/spring_core_dart#aop).

## 10. Validate forms and input

```dart
@Introspected()
class SignUp {
  @NotBlank()
  String name = '';

  @Email()
  String? email;

  @Min(18)
  int age = 0;
}

final binder = DataBinder(SignUp(), introspector: introspector)
  ..validators.add(BeanValidator(introspector: introspector))
  ..bind({'name': '', 'email': 'ada@example.com', 'age': 'old'}) // e.g. form data
  ..validate();

for (final error in binder.bindingResult.allErrors) {
  print(context.getMessageFromResolvable(error)); // e.g. "must not be blank"
}
```

`introspector` is `context.getBean<BeanIntrospector>()`. Messages can be
translated with `messages.properties` (next block).

## 11. Translations

```properties
# lib/resources/messages.properties
greeting=Welcome to {0}!
# lib/resources/messages_ru.properties
greeting=Добро пожаловать в {0}!
```

```dart
@Configuration()
class MessagesConfig {
  @Bean()
  MessageSource messageSource() =>
      ReloadableResourceBundleMessageSource(basenames: ['classpath:messages']);
}

context.getMessage('greeting', args: ['NEON'], locale: 'ru');
// Добро пожаловать в NEON!
```

## 12. Expressions in settings (SpEL)

```dart
@Value('#{2 * 60}')                            // 120
late final int seconds;

@Value(r"#{'${shop.name}'.toUpperCase()}")     // NEON BOOKS
late final String title;

@Value('#{appInfo.name}')                      // a property of the bean appInfo
late final String appName;                     // (its class needs @Introspected())
```

## 13. Files from `lib/resources/`

```dart
@Service()
class WelcomeLetter {
  WelcomeLetter(@Value('classpath:templates/welcome.txt') this.template);
  final Resource template;

  String text() => template.readAsStringSync();
}
```

## 14. Hook into object creation (`BeanPostProcessor`)

Runs for every object the library creates — for logging, wrapping,
registration:

```dart
@Component()
class Audit extends BeanPostProcessor {
  @override
  Object postProcessAfterInitialization(Object bean, String name) {
    print('created $name');
    return bean; // or a wrapper around it
  }
}
```

## More

- A runnable app that uses every feature (with tests):
  [example/ in the repository](https://github.com/farum-azula/spring_core_dart/tree/main/example)
  — `dart run bin/main.dart` prints what each feature does.
- [`main.dart`](main.dart) next to this file: the same ideas written without
  the generator (bean definitions by hand), runnable with
  `dart run example/main.dart`.
- [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart): starts
  everything above from one annotation.
