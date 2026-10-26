# Testing

> Tests come in two forms, both working: **functions** in `main`
> (`springBootTest(...)`, section 2) and **test classes with annotations**,
> the way Spring writes them (sections 3–11), which
> `spring_core_dart_generator` turns into the same functions (section 15).

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
| `@SpringBootTest` on a class | `@SpringBootTest()` on a class, or `springBootTest(...)` in `main` |
| `@Autowired` field in a test | `@Autowired() late Checkout checkout;`, or `app.getBean<Checkout>()` |
| `@MockitoBean`, `@TestBean` | `@TestBean()` field, or `BeanOverride` |
| `@TestPropertySource`, `@ActiveProfiles`, `@DynamicPropertySource` | the same annotations, or `properties:`, `profiles:`, `dynamicProperties:` |
| `@Test`, `@DisplayName`, `@Nested`, `@Disabled`, `@Tag` | the same annotations, or `test(...)` and `group(...)` |
| `@BeforeEach`, `@AfterEach`, `@BeforeAll`, `@AfterAll` | the same annotations, or `setUp`, `tearDown`, `setUpAll`, `tearDownAll` |
| `@DirtiesContext` | the same annotation, or `app.markDirty()` |
| `OutputCaptureExtension` | `@CapturedOutput()` field, or `captureLogs()` |
| `ApplicationContextRunner` | `ApplicationContextRunner` |
| `src/test/resources` | `test/resources/` |

## Contents

1. [Setup](#1-setup)
2. [Tests as functions](#2-tests-as-functions)
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
  build_runner: ^2.17.0   # already there for the application
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

Test classes need `spring_core_dart_generator` (already a dev dependency
of the application) and `build_runner`; it runs over `test/` by default
with `dart run build_runner build` or `watch`.

## 2. Tests as functions

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

The same test as a class:

```dart
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'spring/checkout.test.spring.dart'; // generated, in test/spring/

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
  `test/spring/checkout.test.spring.dart` and runs every test class of the
  file.
- **Plain tests** can sit next to it in `main`, for what needs no context:

  ```dart
  void main() {
    runSpringTests();

    test('a basket starts empty', () => expect(Basket().items, isEmpty));
  }
  ```

### `@SpringBootTest` options

| Option | Type | Default | `springBootTest` parameter | Spring |
|---|---|---|---|---|
| `application` | `String` | the package's only application ([section 4](#4-which-application)) | the first argument | `classes` |
| `args` | `List<String>` | `[]` | `args:` | `args` |
| `properties` | `Map<String, Object?>` | `{}` | `properties:` | `properties` |
| `resourceDirectories` | `List<String>` | `['test/resources']` | `resourceDirectories:` | (the test classpath) |

The other options are their own annotations, so that a test reads like
Spring's:

| Annotation | On | `springBootTest` parameter | Spring |
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
  late SpringBootTestContext app;         // output, markDirty(), getBean

  @Value(r'${shop.max-basket-size}')
  late int maxBasketSize;                 // a property, converted

  @Autowired()
  late Environment environment;
}
```

- A field must be `late`, public and not `final` (the generated code sets
  it from outside the class).
- The types and qualifiers are the ones of constructor injection: an
  optional bean is a nullable field (`late Mailer? mailer;`), and
  `List<T>` / `Iterable<T>` / `Set<T>`, `Map<String, T>` (by name) and
  `ObjectProvider<T>` work too.
- Spring Java allows constructor injection in tests too; here the fields
  are the only way: the generated code creates the class with `Name()`,
  so it must be public with an unnamed constructor without required
  parameters.
- **Superclasses:** annotated members of a superclass declared in the same
  file count (a base class of shared beans, tests and set-up). One in
  another file is not seen (the test file is read as written) and the
  build warns.

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

Which bean is replaced:

| Given | Replaces | Generated |
|---|---|---|
| `name` | the bean (or alias) with that name, keeping the types it is registered under; without one, adds the value under that name | `BeanOverride.named(value, name: ...)` |
| `type` (with or without `name`) | the only (or `@Primary`, or named) bean of `type` | `BeanOverride<Type>(value)` |
| neither | the only bean of the field's declared type; the type must be written (`final Clock clock = ...`), else the build fails | `BeanOverride<Clock>(value)` |

Without such a bean, the value is added as a new bean.

- The field is a normal field, so the test reads its fake directly
  (`gateway.charged`), with its own type, not the bean's interface.
- The value is created once with the test class. When it holds state
  between tests, reset it in `@BeforeEach` or use `@DirtiesContext`.
- Mocks from `package:mocktail` work as values; the starter has no mocking
  library of its own (Spring ships Mockito).
- As a function: `overrides: [BeanOverride.named(gateway, name:
  'sandbox')]`, or `BeanOverride<PaymentGateway>(gateway)`.

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
  locations: ['classpath:big-shop.properties'],    // test/resources/
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
  @Disabled('the payment sandbox is down')      // skipped, with the reason
  @Tag('slow')                                  // dart test --tags slow
  @TestOptions(timeout: Timeout(Duration(seconds: 5)), retry: 2)
  Future<void> paysOnline() async => ...;
}
```

| Annotation | Meaning |
|---|---|
| `@Test([name])` | a test; without a name, the method name split into words (`addsABook` → `adds a book`) |
| `@DisplayName(name)` | the test's name, the same as `@Test(name)` |
| `@Disabled([reason])` | skips the test (on the class: every test), like JUnit's `@Disabled` |
| `@Tag(name)` | a tag for `dart test --tags` / `--exclude-tags`; several allowed; on the class for every test |
| `@TestOptions(timeout:, retry:, testOn:, onPlatform:)` | `test()`'s other options; on the class for every test |

`package:test`'s own `@Skip`, `@Timeout`, `@Tags`, `@Retry`, `@TestOn` and
`@OnPlatform` can only annotate a library (`@TestOn('vm') library;` at the
top of the file still works); `@Disabled`, `@Tag` and `@TestOptions` are
their per-test counterparts.

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

| Annotation | Runs | As a function |
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

As a function: `app.markDirty()` in the test, or `setUp(app.markDirty)` for every
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

`@Disabled`, `@Tag`, `@TestOptions` and `@DirtiesContext` on the field (or
on the nested class) apply to the whole group. The nested class must be
declared in the test file; it may have `@CapturedOutput` fields.

## 12. Logs and console output

As a function, `captureLogs()` records what is logged through `SpringLog` in
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

In a test class, a `@CapturedOutput()` field:

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

A function, as in Spring: a small context per test,
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

The generated files go to their own folder, `test/spring/`, with the
same structure as `test/`:

```
test/
  checkout_test.dart
  orders/
    basket_test.dart
  spring/                              generated, do not edit
    checkout.test.spring.dart
    orders/basket.test.spring.dart
```

The `_test` suffix becomes `.test`, so `dart test` never runs a generated
file as a test of its own. Each test file has its own generated file, not
one for all: `dart test` compiles every test file separately, and a shared
file would make each of them compile all the tests (and an error in one
break them all). The generated file of `test/checkout_test.dart`
holds `runSpringTests()`, which writes the class out with the functions of
[section 2](#2-tests-as-functions). For the class of section 3:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../checkout_test.dart';

import 'package:spring_boot_starter_test/generated.dart' as _sbt;

import '../../bin/shop.spring.dart' as _app0;

void runSpringTests() {
  _sbt.group('CheckoutTest', () {
    final $instance = CheckoutTest();
    final $app = _sbt.springBootTest(
      _app0.springApplication,
      args: ['--shop.name=Night Books'],
      profiles: ['dev', 'test'],
      systemEnvironment: {'SHOP_MAX_BASKET_SIZE': '25'},
      overrides: [_sbt.BeanOverride.named($instance.gateway, name: 'sandbox')],
    );
    _sbt.setUp(() {
      $instance.properties = $app.getBean();
      $instance.checkout = $app.getBean();
    });
    _sbt.test(
      'properties from the command line and the environment',
      () => $instance.propertiesFromTheCommandLineAndTheEnvironment(),
    );
    _sbt.test('checkout pays through the fake', () => $instance.pays());
  });
}
```

- **The test file is read as written**, not resolved: the generated file
  imports what the test file imports (same prefixes, `show` and `hide`)
  plus the test file itself (relative imports, conditional ones included,
  re-pointed from `test/spring/`), so every type and constant in the
  annotations means the same there; a static constant of the class used in
  a member's annotation (`@Tag(slow)`) is written `ShopTest.slow`, and a
  private name fails the build (another library cannot reach it).
  Annotations are recognized by name (`@Test`, also `@spring.Test` with a
  prefix). The generated names start with `$` (`$instance`, `$app`) so
  they never hide one of the test file's.
- **Bean types are not repeated**: `$instance.checkout = $app.getBean();`
  takes `Checkout` from the field. A nullable field uses `findBean()`, a
  `List` field `getBeans()`, a `@Value` field `value(...)`.
- **`@TestBean(name:)`** becomes `BeanOverride.named`, which keeps the
  types of the bean it replaces but its own class, and adds the fake's:
  a `FakeGateway` field replaces the `PaymentGateway` called `sandbox`;
  `getBean<SandboxGateway>()` then finds nothing.
- **The application** is the package's `@SpringBootApplication` entry point
  in `bin/` or `lib/` (its generated `springApplication`).
- **Order**: `@BeforeAll` and `@AfterAll` are declared before
  `springBootTest`, so they run before the context starts and after it
  closes; the fields are injected in a `setUp` before every test (new beans
  after a restart), then the `@BeforeEach` methods run.
- The test file and the generated file import each other, which Dart
  allows; no `part` is needed, the generated code uses only public members.
- Each test class becomes a `group` named after it, so `dart test --name`
  and the editor's run buttons find its tests.
- The generated file is plain code: open it to see what a test does, and
  break on it in the debugger.
- Keep `build_runner watch` running (or run `build`) before `dart test`, as
  for the application: a stale generated file runs the old tests.

## 16. Build errors

The generator stops the build with a message pointing at the
member:

| Message | Fix |
|---|---|
| `@Autowired field 'checkout' must be late and not final or static` | `@Autowired() late Checkout checkout;` (also `@Value`, `@CapturedOutput`) |
| `@Autowired field 'checkout' needs its type written` | `late Checkout checkout;`, not `late var checkout;` |
| `'_checkout' is private; the generated test cannot reach it` | make it public |
| `@TestBean field 'gateway' needs a value` | `final gateway = FakeGateway();` |
| `@TestBean field 'gateway' needs the type of the bean it replaces` | `final PaymentGateway gateway = ...`, `@TestBean(type: PaymentGateway)` or `@TestBean(name: 'sandbox')` |
| `@TestBean field 'gateway' in a @Nested class` | move it to the `@SpringBootTest` class (one context) |
| `@BeforeAll method start must be static` | `static Future<void> start() ...` (also `@AfterAll`, `@DynamicPropertySource`, `@ContextInitializer`) |
| `@BeforeEach method before must not be static` | an instance method (also `@AfterEach`, `@Test`) |
| `@Test method pays has parameters` | test methods take none (widget tests with a `WidgetTester`: [Flutter testing](flutter-testing.md)) |
| `@ActiveProfiles on a method: it belongs to the class` | move it to the class, or a second class (also `@SpringBootTest`, `@TestPropertySource`, `@TestEnvironment`) |
| `@Disabled on helper, which is not a @Test method` | add `@Test()` (also `@DisplayName`, `@Tag`, `@TestOptions`) |
| `@Nested field 'inner' must be created with a class of this file` | declare the class in the test file: `final inner = Inner();` |
| `'CheckoutTest' needs a constructor without required parameters` | remove the constructor's parameters |
| `'CheckoutTest' has no unnamed constructor` | add `CheckoutTest();` (the generated code calls it) |
| `'_CheckoutTest' is private` | make the class public (also a `@Nested` class) |
| `'_env' is private to the test file` | a constant used in an annotation must be public |
| `@Disabled on the field x, which is not @Nested` | `@Disabled`, `@Tag`, `@TestOptions`, `@DirtiesContext` go on `@Test` methods, classes and `@Nested` fields |
| `No application in this package` | a `@SpringBootApplication` entry point in `bin/` or `lib/` |
| `Several applications in this package (...)` | `@SpringBootTest(application: 'bin/shop.dart')` |
| `'bin/x.dart' is not an entry point with @SpringBootApplication` | the path of an entry point |
| `test/checkout_test.dart does not import 'spring/checkout.test.spring.dart'` (a warning) | add the import and `void main() => runSpringTests();` |

Each message starts with the place: `test/checkout_test.dart:12:3: ...`.

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
