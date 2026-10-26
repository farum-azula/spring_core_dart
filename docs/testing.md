# Testing

> **Status.** Sections 1–2 and 12–14 describe what works today
> (`spring_boot_starter_test`: `springBootTest`, `ApplicationContextRunner`,
> the matchers, `captureLogs`). Sections 3–11, 15 and 16 describe **test
> classes with annotations**, the way Spring writes tests; they are
> **planned** ([roadmap](../roadmap/spring_boot_starter_test.md)) and this
> page is their specification: the code shows the intended API and may
> still change.

Spring tests start the application (or a slice of it) once, inject beans
into the test, replace some beans with fakes and set properties for the
test. `spring_boot_starter_test` does the same for Dart, on top of
`package:test`.

**Flutter** apps have their own starter, `spring_boot_starter_flutter_test`
([Flutter testing](flutter-testing.md)): it is built on this one, so
everything on this page works there too, and adds widget tests, pumping
widgets with the test's beans, themes and platforms.

| Spring (Java) | Here |
|---|---|
| `@SpringBootTest` on a class | `@SpringBootTest()` on a class (planned), or `springBootTest(...)` in `main` (today) |
| `@Autowired` field in a test | `@Autowired() late Checkout checkout;` (planned), or `app.getBean<Checkout>()` (today) |
| `@MockitoBean`, `@TestBean` | `@TestBean()` field (planned), or `BeanOverride` (today) |
| `@TestPropertySource`, `@ActiveProfiles`, `@DynamicPropertySource` | the same annotations (planned), or `properties:`, `profiles:`, `dynamicProperties:` (today) |
| `@Test`, `@DisplayName`, `@Nested` | the same annotations (planned), or `test(...)` and `group(...)` (today) |
| `@BeforeEach`, `@AfterEach`, `@BeforeAll`, `@AfterAll` | the same annotations (planned), or `setUp`, `tearDown`, `setUpAll`, `tearDownAll` (today) |
| `@DirtiesContext` | the same annotation (planned), or `app.markDirty()` (today) |
| `OutputCaptureExtension` | `@CapturedOutput()` field (planned), or `captureLogs()` (today) |
| `ApplicationContextRunner` | `ApplicationContextRunner` |
| `src/test/resources` | `test/resources/` |

## Contents

1. [Setup](#1-setup)
2. [A test today](#2-a-test-today)
3. [A test class](#3-a-test-class)
4. [Which application](#4-which-application)
5. [Injecting beans](#5-injecting-beans)
6. [Replacing beans](#6-replacing-beans)
7. [Properties and profiles](#7-properties-and-profiles)
8. [Test methods](#8-test-methods)
9. [Before and after](#9-before-and-after)
10. [A fresh context: `@DirtiesContext`](#10-a-fresh-context-dirtiescontext)
11. [Groups: `@Nested`](#11-groups-nested)
12. [Logs and console output](#12-logs-and-console-output)
13. [Auto-configuration: `ApplicationContextRunner`](#13-auto-configuration-applicationcontextrunner)
14. [Matchers](#14-matchers)
15. [What the generator writes](#15-what-the-generator-writes)
16. [Build errors](#16-build-errors)
17. [Differences from Spring](#17-differences-from-spring)

## 1. Setup

```yaml
# pubspec.yaml
dev_dependencies:
  spring_boot_starter_test: ^0.3.0
  test: ^1.25.0
  build_runner: ^2.4.0   # already there for the application
```

Test configuration goes to `test/resources/`, which comes first on the
classpath during tests, like `src/test/resources` (see
[Configuration, section 18](configuration.md#18-tests)):

```
test/
  resources/
    application-test.yml   # read with the 'test' profile
  checkout_test.dart
```

Test classes (planned) need the generator to run over `test/` too; it does
by default with `dart run build_runner build` or `watch`.

## 2. A test today

The whole application, once for the test file, with a fake gateway:

```dart
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/shop.spring.dart'; // springApplication

class FakeGateway implements PaymentGateway {
  final charged = <double>[];

  @override
  String charge(double amount) {
    charged.add(amount);
    return 'fake charged $amount';
  }
}

void main() {
  final gateway = FakeGateway();
  final app = springBootTest(
    springApplication,
    args: ['--shop.name=Night Books'],
    profiles: ['dev', 'test'],
    systemEnvironment: {'SHOP_MAX_BASKET_SIZE': '25'},
    overrides: [BeanOverride<PaymentGateway>(gateway, name: 'sandbox')],
  );

  test('properties from the command line and the environment', () {
    final properties = app.getBean<ShopProperties>();
    expect(properties.name, 'Night Books');
    expect(properties.maxBasketSize, 25);
  });

  test('checkout pays through the fake', () {
    app.getBean<Checkout>().pay(3);
    expect(gateway.charged, [3]);
  });
}
```

`springBootTest` registers `setUpAll` (start the context), `tearDownAll`
(close it) and `tearDown` (restart after `app.markDirty()`). Every option
is listed in [section 3](#3-a-test-class), next to its annotation.

## 3. A test class

*Planned.* The same test as a class:

```dart
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'checkout.test.spring.dart'; // generated next to this file

@SpringBootTest(args: ['--shop.name=Night Books'])
@ActiveProfiles(['dev', 'test'])
@TestEnvironment({'SHOP_MAX_BASKET_SIZE': '25'})
class CheckoutTest {
  @Autowired()
  late ShopProperties properties;

  @Autowired()
  late Checkout checkout;

  @TestBean(name: 'sandbox')
  final gateway = FakeGateway();

  @Test()
  void propertiesFromTheCommandLineAndTheEnvironment() {
    expect(properties.name, 'Night Books');
    expect(properties.maxBasketSize, 25);
  }

  @Test('checkout pays through the fake')
  void pays() {
    checkout.pay(3);
    expect(gateway.charged, [3]);
  }
}

void main() => runSpringTests();
```

- **The class** holds the test's beans and its test methods; the
  annotations above it say how the application starts.
- **`main`** stays: `dart test` runs a file's `main`, and the generator
  cannot write into your file. `runSpringTests()` comes from the generated
  `checkout.test.spring.dart` and runs every test class of the file.
- **Plain tests** can sit next to it in `main`, for what needs no context:

  ```dart
  void main() {
    runSpringTests();

    test('a basket starts empty', () => expect(Basket().items, isEmpty));
  }
  ```

### `@SpringBootTest` options

| Option | Type | Default | Today's parameter | Spring |
|---|---|---|---|---|
| `application` | `String` | the package's only application ([section 4](#4-which-application)) | the first argument | `classes` |
| `args` | `List<String>` | `[]` | `args:` | `args` |
| `properties` | `Map<String, Object?>` | `{}` | `properties:` | `properties` |
| `resourceDirectories` | `List<String>` | `['test/resources']` | `resourceDirectories:` | (the test classpath) |

The other options are their own annotations, so that a test reads like
Spring's:

| Annotation | On | Today's parameter | Spring |
|---|---|---|---|
| `@ActiveProfiles(['dev', 'test'])` | class | `profiles:` | `@ActiveProfiles` |
| `@TestPropertySource(properties: {...}, locations: [...])` | class | `properties:`, `propertyFiles:` | `@TestPropertySource` |
| `@TestEnvironment({'NAME': 'value'})` | class | `systemEnvironment:` | none ([section 17](#17-differences-from-spring)) |
| `@DynamicPropertySource()` | static method | `dynamicProperties:` | `@DynamicPropertySource` |
| `@ContextInitializer()` | static method | `initializers:` | `@ContextConfiguration(initializers = ...)` |
| `@TestBean()` | field | `overrides:` | `@TestBean`, `@MockitoBean` |
| `@DirtiesContext()` | class or method | `app.markDirty()` | `@DirtiesContext` |

## 4. Which application

A test class starts the application of its package, the one generated
into `bin/<name>.spring.dart` or `lib/main.spring.dart`. With one
application in the package, nothing needs saying. With several (two
executables in `bin/`), name the entry point:

```dart
@SpringBootTest(application: 'bin/admin.dart')
class AdminTest { ... }
```

Spring names the application's class (`@SpringBootTest(classes =
AdminApplication.class)`). Here it is a path because an annotation's
arguments must be constants, and the generated `springApplication` is not
one; the generator checks that the path is an entry point of the package
([section 16](#16-build-errors)).

## 5. Injecting beans

`@Autowired()` on a `late` field: the field is set from the context before
the first test of the class, and again after a restart
([section 10](#10-a-fresh-context-dirtiescontext)).

```dart
@SpringBootTest()
class OrdersTest {
  @Autowired()
  late Orders orders;                     // by type

  @Autowired()
  @Qualifier('express')
  late Shipping shipping;                 // by name

  @Autowired()
  late List<PaymentGateway> gateways;     // every bean of the type

  @Autowired()
  late ApplicationContext context;        // the context itself

  @Autowired()
  late SpringBootTestContext app;         // output(), markDirty(), getBean

  @Value('${shop.max-basket-size}')
  late int maxBasketSize;                 // a property, converted

  @Autowired()
  late Environment environment;
}
```

- A field must be `late`, public and not `final` (the generated code sets
  it from outside the class).
- The types and qualifiers are the ones of constructor injection: an
  optional bean is a nullable field (`late Mailer? mailer;`).
- Spring Java allows constructor injection in tests too; here the fields
  are the only way, the test class is created by the generated code with
  its default constructor.

## 6. Replacing beans

`@TestBean()` on a field with a value: the value replaces the application's
bean of the field's type before the context starts, like `@TestBean` and
`@MockitoBean` in Spring.

```dart
@SpringBootTest()
@ActiveProfiles(['dev'])
class PaymentTest {
  @TestBean(name: 'sandbox')            // replaces the bean named sandbox
  final gateway = FakeGateway();

  @TestBean()                           // replaces the only Clock
  final Clock clock = FixedClock(DateTime(2026, 1, 1));

  @TestBean()                           // adds a bean that did not exist
  final Mailer mailer = RecordingMailer();

  @Autowired()
  late Checkout checkout;

  @Test()
  void paysThroughTheFake() {
    checkout.pay(12.5);
    expect(gateway.charged, [12.5]);
  }
}
```

| Option | Default | Meaning |
|---|---|---|
| `name` | the only bean of the type | which bean to replace |
| `type` | the field's declared type | replace a bean of another type than the field's (`@TestBean(type: PaymentGateway) final fake = FakeGateway();`) |

- The field is a normal field, so the test reads its fake directly
  (`gateway.charged`), with its own type, not the bean's interface.
- The value is created once with the test class. When it holds state
  between tests, reset it in `@BeforeEach` or use `@DirtiesContext`.
- Mocks from `package:mocktail` work as values; the starter has no mocking
  library of its own (Spring ships Mockito).
- Today: `overrides: [BeanOverride<PaymentGateway>(gateway, name:
  'sandbox')]`.

## 7. Properties and profiles

Where test properties come from, highest first:

1. `@DynamicPropertySource` values;
2. `@TestPropertySource(properties:)` and `@SpringBootTest(properties:)`;
3. `@TestPropertySource(locations:)` files, later files first;
4. command-line `args`;
5. `@TestEnvironment`, in place of the OS environment;
6. the config files: `test/resources/` first, then `lib/resources/`.

```dart
@SpringBootTest(properties: {'shop.name': 'Test Books'})
@ActiveProfiles(['test'])                       // application-test.yml
@TestPropertySource(
  locations: ['test/resources/big-shop.properties'],
  properties: {'shop.max-basket-size': 100},
)
@TestEnvironment({'SHOP_CURRENCY': 'EUR'})
class ShopPropertiesTest {
  static final server = FakeServer();

  @DynamicPropertySource()
  static void serverUrl(DynamicPropertyRegistry registry) {
    registry.add('shop.payments.url', () => server.url); // read when used
  }

  @BeforeAll()
  static Future<void> startServer() => server.start();

  @AfterAll()
  static Future<void> stopServer() => server.stop();

  @Autowired()
  late ShopProperties shop;

  @Test()
  void readsEverySource() {
    expect(shop.name, 'Test Books');
    expect(shop.maxBasketSize, 100);
    expect(shop.currency, 'EUR');
    expect(shop.payments.url, server.url);
  }
}
```

- **`@ActiveProfiles`** sets `spring.profiles.active`, replacing the
  profiles of the config files, as in Spring.
- **`@TestEnvironment`** replaces the OS environment completely: tests do
  not depend on the machine's variables. Without it the environment is
  empty.
- **`@DynamicPropertySource`** must be a static method (it runs before the
  test class is created). The value supplier is called each time the
  property is read, so a server started in `@BeforeAll` can give its port.
- In `test/resources/`, `application.yml` replaces the one in
  `lib/resources/` entirely (same path); `application-test.yml` with the
  `test` profile only adds to it.

## 8. Test methods

Every method with `@Test()` is a test. A method returning `Future` is
awaited.

```dart
@SpringBootTest()
class BasketTest {
  @Autowired()
  late Basket basket;

  @Test()                                       // name: "adds a book"
  void addsABook() => ...;

  @Test('an empty basket costs nothing')        // name given
  void emptyBasket() => ...;

  @Test()
  @DisplayName('checkout sends an email')       // Spring's spelling
  Future<void> checkoutSendsAnEmail() async => ...;

  @Test()
  @Skip('the payment sandbox is down')          // package:test's annotations
  @Timeout(Duration(seconds: 5))
  @Tags(['slow'])
  void paysOnline() => ...;
}
```

| Annotation | Meaning |
|---|---|
| `@Test([name])` | a test; without a name, the method name split into words (`addsABook` → `adds a book`) |
| `@DisplayName(name)` | the test's name, the same as `@Test(name)` |
| `@Skip([reason])`, `@Timeout(...)`, `@Tags([...])`, `@Retry(n)`, `@OnPlatform({...})`, `@TestOn(...)` | `package:test`'s own annotations; on a method they apply to that test, on the class to all of them |

The order of the tests is the order of the methods in the class.

## 9. Before and after

```dart
@SpringBootTest()
class OrdersTest {
  @Autowired()
  late Orders orders;

  @BeforeAll()
  static Future<void> startDatabase() async { ... } // before the context

  @BeforeEach()
  void clear() => orders.clear();                 // beans are injected here

  @AfterEach()
  Future<void> report() async { ... }

  @AfterAll()
  static void stopDatabase() { ... }              // after the context closed
}
```

| Annotation | Runs | Today |
|---|---|---|
| `@BeforeAll()` | once, before the context starts; a static method | `setUpAll` registered before `springBootTest(...)` |
| `@BeforeEach()` | before every test, with the beans injected | `setUp` |
| `@AfterEach()` | after every test, before a `@DirtiesContext` restart | `tearDown` |
| `@AfterAll()` | once, after the context is closed; a static method | `tearDownAll` |

Several methods with the same annotation run in the order of the class.

## 10. A fresh context: `@DirtiesContext`

One context serves all tests of a class. A test that leaves beans in a
state the next tests should not see marks the context dirty; it is closed
after the test and a new one starts before the next, with the
`@Autowired` fields injected again.

```dart
@SpringBootTest()
class CounterTest {
  @Autowired()
  late Counter counter;

  @Test()
  @DirtiesContext()                 // a new context after this test
  void counts() {
    counter.increment();
    expect(counter.value, 1);
  }

  @Test()
  void startsAtZero() => expect(counter.value, 0);
}

@SpringBootTest()
@DirtiesContext()                   // a new context after every test
class FreshCounterTest { ... }
```

Today: `app.markDirty()` in the test, or `setUp(app.markDirty)` for every
test.

## 11. Groups: `@Nested`

A field with `@Nested()` holds a class of tests run as a `group` with the
outer class's context and beans. Its own `@BeforeEach` methods run after
the outer ones.

```dart
@SpringBootTest()
class BasketTest {
  @Autowired()
  late Basket basket;

  @Nested('with one book')
  final withOneBook = WithOneBook();
}

class WithOneBook {
  @Autowired()
  late Basket basket;               // the same bean as the outer class

  @BeforeEach()
  void addBook() => basket.add('Dune', 10);

  @Test()
  void costsItsPrice() => expect(basket.total, 10);
}
```

Spring nests inner classes (`@Nested class WithOneBook`); Dart has none, so
the group is a field of its own class.

## 12. Logs and console output

*Today.* `captureLogs()` records what is logged through `SpringLog` in
each test; `app.output` is what the application printed (the failure
report of a context that did not start, the banner when on).

```dart
void main() {
  final logs = captureLogs();                  // before springBootTest
  final app = springBootTest(springApplication);

  test('paying is logged', () {
    app.getBean<Checkout>().pay(3);
    expect(logs.messages, ['paid 3.0', 'gateway answered: fake charged 3.0']);
  });
}
```

*Planned.* A `@CapturedOutput()` field:

```dart
@SpringBootTest()
class CheckoutLogTest {
  @CapturedOutput()
  late CapturedLogs logs;                      // cleared before every test

  @Autowired()
  late Checkout checkout;

  @Test()
  void payingIsLogged() {
    checkout.pay(3);
    expect(logs.messages, contains('paid 3.0'));
  }
}
```

`CapturedLogs`: `records` (`SpringLogRecord`s), `messages`, `text`. `captureLogs(level: SpringLogLevel.debug)` records from
that level.

## 13. Auto-configuration: `ApplicationContextRunner`

*Today, and it stays a function, as in Spring.* A small context per test,
to check what an auto-configuration creates under which properties. No
application, no config files.

```dart
void main() {
  final runner = const ApplicationContextRunner()
      .withAutoConfiguration(springBootStarterCacheAutoConfiguration);

  test('a cache manager by default', () {
    runner.run((context) {
      expect(context, hasSingleBean<CacheManager>());
      expect(context.getBean<CacheManager>(), isA<InMemoryCacheManager>());
    });
  });

  test('spring.cache.type=none caches nothing', () {
    runner.withPropertyValues(['spring.cache.type=none']).run((context) {
      expect(context.getBean<CacheManager>(), isA<NoOpCacheManager>());
    });
  });

  test('backs off when the application declares a CacheManager', () {
    final own = InMemoryCacheManager(cacheNames: ['books']);
    runner.withBean<CacheManager>(() => own).run((context) {
      expect(context.getBean<CacheManager>(), same(own));
    });
  });
}
```

`withAutoConfiguration`, `withUserConfiguration`, `withBean`,
`withBeanOverride`, `withPropertyValues`, `withSystemEnvironment`,
`withInitializer`, `withParent`; `run` (or `runAsync`) gives an
`AssertableApplicationContext`, with `hasFailed` and `startupFailure` when
the context did not start (`expect(context, hasFailed())`).

## 14. Matchers

| Matcher | Passes when |
|---|---|
| `hasSingleBean<T>()` | the context has exactly one bean of type `T` |
| `hasBean<T>()` | at least one |
| `doesNotHaveBean<T>()` | none |
| `hasBeanNamed(name)` | a bean with that name |
| `hasFailed()` | the context did not start (`ApplicationContextRunner`) |

They take a `SpringBootTestContext`, an `ApplicationContext` or an
`AssertableApplicationContext`.

## 15. What the generator writes

*Planned.* For `test/checkout_test.dart` the generator writes
`test/checkout.test.spring.dart` (the `_test` suffix becomes `.test`, so
`dart test` does not run the generated file as a test of its own). It
holds `runSpringTests()`, which writes the class out with today's
functions:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/shop.spring.dart';
import 'checkout_test.dart';

void runSpringTests() {
  group('CheckoutTest', () {
    final instance = CheckoutTest();
    final app = springBootTest(
      springApplication,
      args: ['--shop.name=Night Books'],
      profiles: ['dev', 'test'],
      systemEnvironment: {'SHOP_MAX_BASKET_SIZE': '25'},
      overrides: [
        BeanOverride<PaymentGateway>(instance.gateway, name: 'sandbox'),
      ],
    );
    void inject() => instance
      ..properties = app.getBean<ShopProperties>()
      ..checkout = app.getBean<Checkout>();

    setUp(inject); // after a restart too
    test('properties from the command line and the environment',
        () => instance.propertiesFromTheCommandLineAndTheEnvironment());
    test('checkout pays through the fake', () => instance.pays());
  });
}
```

- The test file and the generated file import each other, which Dart
  allows; no `part` is needed, the generated code uses only public members.
- The generator for test classes is open to other starters:
  `spring_boot_starter_flutter_test` adds its own method annotations
  (`@WidgetTest`) to the same generated file.
- Each test class becomes a `group` named after it, so `dart test --name`
  and the editor's run buttons find its tests.
- The generated file is plain code: open it to see what a test does, and
  break on it in the debugger.
- Keep `build_runner watch` running (or run `build`) before `dart test`, as
  for the application: a stale generated file runs the old tests.

## 16. Build errors

*Planned.* The generator stops the build with a message pointing at the
member:

| Message | Fix |
|---|---|
| `@Autowired field 'checkout' must be late and not final` | `@Autowired() late Checkout checkout;` |
| `'_checkout' is private; the generated test cannot set it` | make it public |
| `@TestBean field 'gateway' needs a value` | `final gateway = FakeGateway();` |
| `@BeforeAll method 'start' must be static` | `static Future<void> start() ...` (it runs before the class is created) |
| `@Test method 'pays' has parameters` | test methods take none (widget tests with a `WidgetTester`: [Flutter testing](flutter-testing.md)) |
| `@ActiveProfiles on a method: profiles belong to the class` | move it to the class, or a second class |
| `No application in this package` / `Several applications: name one` | `@SpringBootTest(application: 'bin/shop.dart')` |
| `@SpringBootTest class 'CheckoutTest' needs a default constructor` | remove the constructor's parameters |
| `checkout_test.dart does not import checkout.test.spring.dart` (a warning) | add the import and `void main() => runSpringTests();` |

A missing bean is not a build error: the test fails when the context
starts, with the same report as the application (`No bean of type
Mailer`).

## 17. Differences from Spring

- **`main` stays.** `dart test` runs `main`; a test file keeps one line,
  `void main() => runSpringTests();`.
- **Fields, not constructors**, for injection into tests, and they are
  `late`.
- **`@TestBean` takes a value**, not a factory method name or a Mockito
  mock; any object (a fake, a `mocktail` mock) works.
- **`@TestEnvironment`** does not exist in Spring: Java tests cannot
  replace environment variables. Here the environment of a test is empty
  unless given, so tests do not depend on the machine.
- **`@SpringBootTest(application:)`** is a path to the entry point, not a
  class, because annotation arguments must be constants.
- **`@Nested`** is a field holding another class: Dart has no inner
  classes.
- **One context per class**, not shared between classes with the same
  configuration (Spring's context cache). Each class starts its own;
  starting is fast (no classpath scanning: everything is generated).
- **No web environment** (`webEnvironment = RANDOM_PORT`, `MockMvc`): there
  is no web server yet ([roadmap](../roadmap/spring_boot_starter_web.md)).
- **No test slices** (`@WebMvcTest`, `@DataJpaTest`) yet; use
  `ApplicationContextRunner` for a part of the configuration.
