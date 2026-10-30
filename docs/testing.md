# Testing

`spring_boot_starter_test` lets a test start the real application, get its
beans, replace some of them with fakes, set properties for the test, and
call the controllers without a server. It runs on top of `package:test`.

Why start the application at all? A unit test that creates its objects by
hand cannot show that the config files bind, that the beans find each
other, or that a controller answers as a client expects. A test that
starts the application can, and it stays fast because the application
starts once for many tests.

Tests come in two forms, and both work the same way:

- **functions** in `main`: `springBootTest(...)`, `test(...)`, `setUp(...)`
  ([section 2](#2-tests-as-functions));
- **test classes with annotations**, the way Spring writes tests
  (sections 3 to 11). `spring_core_dart_generator` turns each class into
  the same functions ([section 15](#15-what-the-generator-writes)).

**Flutter** apps have their own starter, `spring_boot_starter_flutter_test`
([Flutter testing](flutter-testing.md)). It is built on this one, so
everything on this page works there too; it adds widget tests that pump
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
| `@SpringBootTest(webEnvironment = RANDOM_PORT)`, `@LocalServerPort` | `@SpringBootTest(webEnvironment: WebEnvironment.randomPort)`, `@LocalServerPort()` field, or `webEnvironment:` and `app.localServerPort` |
| `@AutoConfigureMockMvc`, `MockMvc` | `@Autowired() late MockMvc mvc;`, or `app.mockMvc` |
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
17. [Web tests: `MockMvc`](#17-web-tests-mockmvc)
18. [Differences from Spring](#18-differences-from-spring)

## 1. Setup

```yaml
# pubspec.yaml
dev_dependencies:
  spring_boot_starter_test: ^0.4.3
  test: ^1.25.0
  build_runner: ^2.17.0   # already there for the application
```

Configuration and data for the tests go to `test/resources/`. During the
tests it comes first on the classpath, before `lib/resources/`, and it is
never shipped with the application (see
[Configuration, section 20](configuration.md#20-tests)):

```
test/
  resources/
    application-test.yml   # read with the 'test' profile
  checkout_test.dart
```

Test classes need `spring_core_dart_generator`, which the application
already has as a dev dependency, and `build_runner`. The generator runs
over `test/` by default with `dart run build_runner build` or `watch`.

## 2. Tests as functions

Here the whole application starts once for the test file, with a fake
payment gateway in place of the real one:

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
    // The dev profile has several gateways; 'sandbox' is the one Checkout uses.
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

`springBootTest` registers a `setUpAll` that starts the context, a
`tearDownAll` that closes it with `closeAsync()`, and a `tearDown` that
closes it after a test that called `app.markDirty()`, so the next test
starts a new one. It returns at once: use `app` inside tests, `setUp`, or
a `setUpAll` declared after the call. Every option is listed in
[section 3](#3-a-test-class), next to its annotation.

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

- **The class** holds the test's beans and its test methods. The
  annotations above it say how the application starts.
- **`main` stays.** `dart test` runs a file's `main`, and the generator
  cannot write into your file. `runSpringTests()` comes from the generated
  `test/spring/checkout.test.spring.dart` and runs every test class of the
  file.
- **Plain tests** that need no context can sit next to it in `main`:

  ```dart
  void main() {
    runSpringTests();

    test('a basket starts empty', () => expect(Basket().items, isEmpty));
  }
  ```

Spring (Java):

```java
@SpringBootTest(args = "--shop.name=Night Books")
@ActiveProfiles({"dev", "test"})
class CheckoutTest {
  @Autowired ShopProperties properties;
  @Autowired Checkout checkout;
  @TestBean(name = "sandbox") PaymentGateway gateway;

  static PaymentGateway gateway() { return new FakeGateway(); }

  @Test
  void pays() { ... }
}
```

### `@SpringBootTest` options

| Option | Type | Default | `springBootTest` parameter | Spring |
|---|---|---|---|---|
| `application` | `String` | the package's only application ([section 4](#4-which-application)) | the first argument | `classes` |
| `args` | `List<String>` | `[]` | `args:` | `args` |
| `properties` | `Map<String, Object?>` | `{}` | `properties:` | `properties` |
| `resourceDirectories` | `List<String>` | `['test/resources']` | `resourceDirectories:` | the test classpath |
| `webEnvironment` | `WebEnvironment` | `WebEnvironment.mock` | `webEnvironment:` | `webEnvironment` ([section 17](#17-web-tests-mockmvc)) |

The other options have annotations of their own, so that a test reads like
Spring's:

| Annotation | On | `springBootTest` parameter | Spring |
|---|---|---|---|
| `@ActiveProfiles(['dev', 'test'])` | class | `profiles:` | `@ActiveProfiles` |
| `@TestPropertySource(properties: {...}, locations: [...])` | class | `properties:`, `propertyFiles:` | `@TestPropertySource` |
| `@TestEnvironment({'NAME': 'value'})` | class | `systemEnvironment:` | none ([section 18](#18-differences-from-spring)) |
| `@DynamicPropertySource()` | static method | `dynamicProperties:` | `@DynamicPropertySource` |
| `@ContextInitializer()` | static method | `initializers:` | `@ContextConfiguration(initializers = ...)` |
| `@TestBean()` | field | `overrides:` | `@TestBean`, `@MockitoBean` |
| `@DirtiesContext()` | class, method or `@Nested` field | `app.markDirty()` | `@DirtiesContext` |

## 4. Which application

A test class starts the application of its own package: the one generated
into `bin/<name>.spring.dart` or `lib/main.spring.dart`. With one
application in the package, nothing needs saying. With several (two
executables in `bin/`, say), name the entry point:

```dart
@SpringBootTest(application: 'bin/admin.dart')
class AdminTest { ... }
```

Spring names the application's class (`@SpringBootTest(classes =
AdminApplication.class)`). Here it is a path, because an annotation's
arguments must be constants and the generated `springApplication` is not
one. The generator checks that the path is an entry point with
`@SpringBootApplication` ([section 16](#16-build-errors)).

## 5. Injecting beans

An `@Autowired()` field receives a bean of the application. It is set
before every test, so after a restart
([section 10](#10-a-fresh-context-dirtiescontext)) it holds the new
context's bean.

```dart
@SpringBootTest()
class OrdersTest {
  @Autowired()
  late Orders orders;                     // by type

  @Autowired()
  @Qualifier('express')
  late Shipping shipping;                 // one of several, by qualifier

  @Autowired()
  late List<PaymentGateway> gateways;     // every bean of the type, by @Order

  @Autowired()
  late ApplicationContext context;        // the context itself

  @Autowired()
  late SpringBootTestContext app;         // output, markDirty(), getBean

  @Value(r'${shop.max-basket-size}')
  late int maxBasketSize;                 // a property, converted

  @Autowired()
  late Environment environment;

  @Autowired()
  late MockMvc mvc;                       // the controllers in memory (web starter)
}
```

With the web starter, a `@LocalServerPort() late int port;` field gets
the port of the real server (`webEnvironment: WebEnvironment.randomPort`,
see [section 17](#17-web-tests-mockmvc)).

- A field must be `late`, public and not `final`: the generated code sets
  it from outside the class.
- The types are those of constructor injection. A nullable field is
  optional (`late Mailer? mailer;` stays `null` without a bean).
  `List<T>`, `Iterable<T>`, `Set<T>`, `Map<String, T>` (by bean name) and
  `ObjectProvider<T>` work too. `ApplicationContext`,
  `ConfigurableApplicationContext`, `Environment`,
  `ConfigurableEnvironment`, `SpringBootTestContext` and `MockMvc` are
  recognised by name.
- Spring also allows constructor injection in tests; here fields are the
  only way. The generated code creates the class with `Name()`, so it
  must be public, not abstract, and have an unnamed constructor without
  required parameters.
- **Superclasses:** annotated members of a superclass declared in the same
  file count, for a base class of shared beans, tests and set-up. A
  superclass in another file is not seen (the generator reads the test
  file as written), and the build warns about it.

## 6. Replacing beans

A bean that talks to something a test cannot use (a payment provider, the
wall clock, a mail server) is replaced with a field's value. Put
`@TestBean()` on a field with a value: the value replaces the
application's bean before the context starts. The real bean's definition
is removed first, so the real object is never built, and every bean that
injects it gets the value.

```dart
@SpringBootTest()
@ActiveProfiles(['dev'])
class PaymentTest {
  @TestBean(name: 'sandbox')            // replaces the bean named sandbox
  final gateway = FakeGateway();

  @TestBean()                           // replaces the only Clock
  final Clock clock = FixedClock(DateTime(2026, 1, 1));

  @TestBean()                           // no Mailer bean: adds one
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

Which bean is replaced, and what the generator writes for it:

| Given | Replaces | Generated |
|---|---|---|
| `name` only | the bean (or alias) with that name. The value is registered under the field's type, as in Spring (unless it is `Object`), under its runtime class, and under more types. A value created with a constructor (`FakeGateway()`, also `new` or `const`, a named constructor, a private class, an import prefix, in parentheses or followed by a cascade `..`) adds that class and all its public supertypes, as the generator registers a bean of that class, whatever the field's declared type (`types: [FakeGateway, PaymentGateway]`; a `SubGateway extends RealGateway` also stays a `RealGateway` with every interface of it; a fake `HttpClient` stays an `HttpClient`, written through `dart:io`; a private class is not written, its runtime class is added anyway). A type with a private class as a type argument cannot be written in the generated file and counts in its raw form only (`FakeRepo<_Draft>()` gives `types: [FakeRepo<dynamic>, Repo<dynamic>]`). The generator reads them from the resolved test file. Any other value (a function or static method call such as `Fakes.gateway()`, which may return any subclass, a variable), a class that cannot be resolved, or another type that cannot be written in the generated file (a function or record type argument) adds the types the replaced bean was registered under instead, except its own class (unless the field has that type); a fake that implements only some of those types fails where another is injected (create it with a constructor, or write the override with `BeanOverride.named(value, name: ..., types: [...])`, the fake's own types). | `BeanOverride.named(value, name: ...)` (`types: [...]` for a value created with a constructor), in a function that keeps the field's type as its type argument |
| `type` (with or without `name`) | the bean called `name` if given; else the only bean of `type`, or the `@Primary` one among several. The value is registered under `type` only | `BeanOverride<Type>(value)` |
| neither | the only (or `@Primary`) bean of the field's declared type. The type must be written (`final Clock clock = ...`), or the build fails | `BeanOverride<Clock>(value)` |

Without such a bean, the value is added as a new bean. Several beans of the
type and no single `@Primary` one fail the start with a `StateError` that
lists them: give a `name`.

- The field is a normal field, so the test reads its fake directly
  (`gateway.charged`), with the fake's own class.
- The value is created once, with the test class. When it holds state
  between tests, reset it in `@BeforeEach` or use `@DirtiesContext`.
- Mocks from `package:mocktail` work as values; the starter has no mocking
  library of its own (Spring ships Mockito).
- As a function: `overrides: [BeanOverride.named(gateway, name:
  'sandbox')]`, or `BeanOverride<PaymentGateway>(gateway)`.

Behaviour to know, as the code is today:

- **A misspelt `name` does not fail.** When no bean has that name, the
  value is added under it and the real bean stays. The usual symptom is
  that the real bean is still used, or that two beans of the type now
  compete.
- **With `type` (or none given), the replacement is registered under that
  one type.** If the original bean was also found under another interface,
  that interface no longer finds it.
- **Without `name` and without a bean of the type,** the value is
  registered under the type's default bean name (`Mailer` → `mailer`). If
  an unrelated bean already has that name, it is removed.

## 7. Properties and profiles

Where the test's properties come from, highest first:

1. `@DynamicPropertySource` values;
2. `@TestPropertySource(properties:)` and `@SpringBootTest(properties:)`
   (merged; on the same key, `@TestPropertySource` wins);
3. `@TestPropertySource(locations:)` files; when two files set a key, the
   later file wins;
4. command-line `args`;
5. `@TestEnvironment`, which stands in for the OS environment;
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

  // The fake server's URL exists only once it runs.
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
  profiles of the config files, as in Spring. List the application's own
  profiles too when the tests need them.
- **`@TestEnvironment`** replaces the OS environment completely, so tests
  do not depend on the machine's variables. Without it the environment is
  empty.
- **`@DynamicPropertySource`** must be a static method, because it runs
  before the test class is created. It is called at every start of the
  context, and each value supplier each time the property is read, so a
  server started in `@BeforeAll` can hand over its port. A class may have
  several; all are called.
- **`@TestPropertySource(locations:)`**: a file that does not exist fails
  the start with a `StateError`.
- In `test/resources/`, an `application.yml` replaces the one in
  `lib/resources/` entirely (same path); an `application-test.yml` read
  with the `test` profile only adds to it.

## 8. Test methods

Every method with `@Test()` is a test. A method that returns a `Future` is
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
  @DisplayName('checkout sends an email')       // JUnit's spelling
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
| `@DisplayName(name)` | the test's name, the same as `@Test(name)`; it wins when both are given |
| `@Disabled([reason])` | skips the test (on the class or a `@Nested` field: every test of it), shown as skipped with the reason |
| `@Tag(name)` | a tag for `dart test --tags` / `--exclude-tags`; several allowed; on the class or a `@Nested` field for every test of it |
| `@TestOptions(timeout:, retry:, testOn:, onPlatform:)` | the other options of `test()`; on the class or a `@Nested` field for every test of it |

`package:test`'s own `@Skip`, `@Timeout`, `@Tags`, `@Retry`, `@TestOn` and
`@OnPlatform` can only annotate a whole library (`@TestOn('vm') library;`
at the top of the file still works). `@Disabled`, `@Tag` and
`@TestOptions` bring them to a single test.

Tests run in the order of the methods in the class. A test method takes
no parameters and is not static.

## 9. Before and after

```dart
@SpringBootTest()
class OrdersTest {
  @Autowired()
  late Orders orders;

  @BeforeAll()
  static Future<void> startDatabase() async { ... } // before the context starts

  @BeforeEach()
  void clear() => orders.clear();                 // the beans are injected by now

  @AfterEach()
  Future<void> report() async { ... }

  @AfterAll()
  static void stopDatabase() { ... }              // after the context closed
}
```

| Annotation | Runs | As a function |
|---|---|---|
| `@BeforeAll()` | once, before the context starts; a static method | `setUpAll` registered before `springBootTest(...)` |
| `@BeforeEach()` | before every test, after the fields were injected | `setUp` |
| `@AfterEach()` | after every test, before a `@DirtiesContext` restart | `tearDown` |
| `@AfterAll()` | once, after the context is closed; a static method | `tearDownAll` registered before `springBootTest(...)` |

Several methods with the same annotation run in the order of the class.
`@BeforeAll` and `@AfterAll` methods belong to the `@SpringBootTest`
class, not to a `@Nested` one. A returned `Future` is awaited.

## 10. A fresh context: `@DirtiesContext`

One context serves all the tests of a class, which keeps them fast. A test
that leaves beans in a state the next tests must not see (a counter, an
in-memory store, a cache) marks the context dirty. The context is closed
after that test, a new one starts before the next, and the `@Autowired`
fields are injected again.

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

On a `@Nested` field it applies to every test of the group. As a
function: `app.markDirty()` in the test, or `setUp(app.markDirty)` for
every test.

On a class it restarts the context after each test, which Spring writes
`@DirtiesContext(classMode = AFTER_EACH_TEST_METHOD)`. Spring's default
for a class (`AFTER_CLASS`: a new context for the next class) is what
every class gets here anyway, as each class starts its own context.

## 11. Groups: `@Nested`

A field with `@Nested()` holds a class of tests that run as a `group`
inside the outer class, with the same context and beans. Use it to group
tests that share a setup, such as "with one book in the basket". The
nested class's `@BeforeEach` methods run after the outer ones.

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
  late Basket basket;               // the same bean as in the outer class

  @BeforeEach()
  void addBook() => basket.add('Dune', 10);

  @Test()
  void costsItsPrice() => expect(basket.total, 10);
}
```

Spring nests inner classes (`@Nested class WithOneBook`). Dart has no
inner classes, so the group is a field holding an instance of its own
class.

- `@Disabled`, `@Tag`, `@TestOptions` and `@DirtiesContext` on the field
  (or on the nested class) apply to the whole group.
- The nested class must be declared in the test file. It may have
  `@Autowired`, `@Value` and `@CapturedOutput` fields, `@BeforeEach` and
  `@AfterEach` methods, tests and further `@Nested` fields.
- It may not have `@TestBean` fields or `@BeforeAll`, `@AfterAll`,
  `@DynamicPropertySource` and `@ContextInitializer` methods: they belong
  to the outer class, which owns the context.

## 12. Logs and console output

To check what the code logged, `captureLogs()` records what goes through
`SpringLog` during each test. Call it once in `main` or a `group`, outside
the tests; the capture is emptied before every test.

```dart
void main() {
  final logs = captureLogs();
  final app = springBootTest(springApplication);

  test('paying is logged', () {
    app.getBean<Checkout>().pay(3);
    expect(logs.messages, ['paid 3.0', 'gateway answered: fake charged 3.0']);
  });
}
```

In a test class, a `@CapturedOutput()` field does the same:

```dart
@SpringBootTest()
class CheckoutLogTest {
  @CapturedOutput()
  late CapturedLogs logs;                      // emptied before every test

  @Autowired()
  late Checkout checkout;

  @Test()
  void payingIsLogged() {
    checkout.pay(3);
    expect(logs.messages, contains('paid 3.0'));
  }
}
```

`CapturedLogs` has `records` (`SpringLogRecord`s with level, logger and
message), `messages`, `text` (one `LEVEL [logger] message` line per
record), `atLevel(level)` (exactly that level) and `ofLogger(name)` (that
logger and the loggers below it). Records are captured after the loggers'
levels filtered them; `captureLogs(level: SpringLogLevel.debug)` sets the
global level during each test and restores it afterwards.

`app.output` is something else: the lines the application printed, such
as the failure report of a context that did not start, or the banner when
it is on. Each line is also shown when a test fails.

## 13. Auto-configuration: `ApplicationContextRunner`

A starter's auto-configuration must react to its surroundings: create a
bean by default, back off when the application declares its own, change
with a property, fail on a bad value. `ApplicationContextRunner` starts a
small context per test to check each case. There is no application and no
config file, only the modules and properties the test gives. It is used as
a function, as in Spring.

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
    // Registered before the auto-configuration, as the application's would be.
    runner.withBean<CacheManager>(() => own).run((context) {
      expect(context.getBean<CacheManager>(), same(own));
    });
  });
}
```

The runner is immutable: each `with...` method returns a new one. The
methods are `withAutoConfiguration`, `withUserConfiguration`, `withBean`,
`withBeanOverride`, `withPropertyValues`, `withSystemEnvironment`,
`withInitializer` and `withParent`; the package README
([`ApplicationContextRunner`](../spring_boot_starter_test/README.md#testing-auto-configuration-applicationcontextrunner))
describes each. Initializers run in the order they were added; their
`order` is not used.

`run` (or `runAsync` for a body that awaits) passes an
`AssertableApplicationContext`. A context that failed to start is passed
too, instead of throwing: `expect(context, hasFailed())`, or read
`startupFailure`.

## 14. Matchers

| Matcher | Passes when the context has |
|---|---|
| `hasSingleBean<T>()` | exactly one bean of type `T` |
| `hasBean<T>()` | at least one |
| `doesNotHaveBean<T>()` | none |
| `hasBeanNamed(name)` | a bean with that name or alias |
| `hasFailed([matcher])` | failed to start (`ApplicationContextRunner` only); with a matcher, the error must match it |

They take a `SpringBootTestContext`, an `AssertableApplicationContext`, or
any `ListableBeanFactory` such as an `ApplicationContext`. Beans of parent
contexts count too. On failure they list the beans found, or the reason
the context did not start.

## 15. What the generator writes

The generated files go to their own folder, `test/spring/`, which mirrors
the structure of `test/`:

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
file as a test of its own. Each test file gets its own generated file:
`dart test` compiles every test file separately, and a shared file would
make each of them compile all the tests (and an error in one would break
them all).

The generated file of `test/checkout_test.dart` holds `runSpringTests()`,
which writes the class out with the functions of
[section 2](#2-tests-as-functions). For the class of section 3:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated by spring_core_dart_generator from the @SpringBootTest classes of checkout_test.dart.

// ignore_for_file: type=lint, unused_import, unused_shown_name, duplicate_import

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';
import '../checkout_test.dart';
import 'package:spring_boot_starter_test/generated.dart' as _sbt;
import '../../bin/shop.spring.dart' as _app0;

/// Declares the tests of the `@SpringBootTest` classes of `checkout_test.dart`.
void runSpringTests() {
  _sbt.group('CheckoutTest', () {
    final $instance = CheckoutTest();
    final $app = _sbt.springBootTest(
      _app0.springApplication,
      args: ['--shop.name=Night Books'],
      profiles: ['dev', 'test'],
      systemEnvironment: {'SHOP_MAX_BASKET_SIZE': '25'},
      overrides: [
        _$named(_sbt.BeanOverride.named($instance.gateway, name: 'sandbox')),
      ],
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

// The override of a @TestBean field, typed by the field: in the overrides
// list, BeanOverride.named (or BeanOverride) alone infers Object.
_sbt.BeanOverride<Object> _$named<T extends Object>(
  _sbt.BeanOverride<T> override,
) => override;
```

- **The test file is read as written**: it is resolved only for the
  class of a `@TestBean(name:)` value created with a call, and for the
  nullability of a `@TestBean` field whose type the text does not tell
  (below). The
  generated file imports what the test file imports (same prefixes,
  `show` and `hide`) plus the test file itself; relative imports, conditional ones included,
  are re-pointed from `test/spring/`. So every type and constant in the
  annotations means the same there. A static constant of the class used in
  a member's annotation (`@Tag(slow)`) is written `ShopTest.slow`, and a
  private name fails the build, since another library cannot reach it.
  Annotations are recognised by name (`@Test`, also `@spring.Test` with a
  prefix). The generated names start with `$` (`$instance`, `$app`) or
  are private to the generated file (`_$named`), so they never hide one
  of the test file's.
- **Bean types are not repeated**: `$instance.checkout = $app.getBean();`
  takes `Checkout` from the field. A nullable field uses `findBean()`, a
  `List` field `getBeans()`, a `@Value` field `value(...)`.
- **`@TestBean(name:)`** becomes `BeanOverride.named`, passed through
  `_$named`: in the `overrides:` list, `BeanOverride.named` alone would
  get `Object` as its type argument, while through `_$named` it gets the
  field's type, which the replacement is registered under (as in Spring;
  not `Object`). A value created with a constructor (`= FakeGateway()`,
  `= f.FakeGateway.sandbox()`, `= _Fake()`, `= (FakeGateway()..reset())`,
  whatever the field's declared type) generates a `types:` list: that
  class and all its public supertypes, read from the resolved test file,
  as the generator registers a bean of that class (a supertype of an
  internal SDK library is written through the public one that exports
  it, `HttpClient` through `dart:io`; a private class is left out, its
  runtime class is added anyway; a type with a private class as a type
  argument is written in its raw form, `Repo<dynamic>` for
  `Repo<_Draft>`). Only a test file with such a value, or with a
  `@TestBean` field of an inferred type or of a named type without `?`
  that the file does not declare as a class (it may be a type alias), is
  resolved; the builder reads the others as syntax.
  Any other value (`= Fakes.gateway()`, a function's or static method's,
  which may return any subclass), a class that cannot be resolved or
  another type that cannot be written in the generated file gets no
  list: the replacement keeps the types of the bean it replaces except
  its own class (unless the field has that type), and adds the fake's
  class (a `FakeGateway` field replacing the `SandboxGateway` called
  `sandbox`: `getBean<SandboxGateway>()` then finds nothing). The fake
  must implement every other type of that bean then (Dart cannot check
  it at run time). A nullable `@TestBean`
  field is passed as `value ?? throw StateError(...)`: `null` fails the
  test file. That includes a field of a nullable type alias
  (`typedef MaybeMailer = Mailer?;`, from any library), read from the
  resolved file; without `name:` or `type:` such a field's override is
  `_$named(BeanOverride(...))`, typed by the value (`Mailer`), as the
  alias cannot be written without its `?`. A field of an inferred type
  (`final mailer = Fakes.maybeMailer();`) needs `name:` or `type:`,
  nullable or not (with one, an inferred nullable type is read from the
  resolved file and checked the same way); without either the build fails
  with "@TestBean field 'mailer' needs the type of the bean it replaces".
- **The application** is the package's `@SpringBootApplication` entry
  point in `bin/` or `lib/`, through its generated `springApplication`.
- **Order**: `@BeforeAll` and `@AfterAll` are declared before
  `springBootTest`, so they run before the context starts and after it
  closes. The fields are injected in a `setUp` before every test (new
  beans after a restart), then the `@BeforeEach` methods run.
- The test file and the generated file import each other, which Dart
  allows. No `part` is needed; the generated code uses only public
  members.
- Each test class becomes a `group` named after it, so
  `dart test --name` and the editor's run buttons find its tests.
- The generated file is plain code: open it to see what a test does, and
  set breakpoints in it.
- Keep `build_runner watch` running (or run `build`) before `dart test`,
  as for the application: a stale generated file runs the old tests.

## 16. Build errors

When a test class cannot be generated, the build stops with a message that
starts with the place (`test/checkout_test.dart:12:3: ...`):

| Message | Fix |
|---|---|
| `@Autowired field 'checkout' must be late and not final or static` | `@Autowired() late Checkout checkout;` (also `@Value`, `@CapturedOutput`, `@LocalServerPort`) |
| `@Autowired field 'checkout' needs its type written` | `late Checkout checkout;`, not `late var checkout;` |
| `'_checkout' is private; the generated test cannot reach it` | make it public |
| `@TestBean field 'gateway' needs a value` | `final gateway = FakeGateway();` (a static field does not count) |
| `@TestBean field 'gateway' needs the type of the bean it replaces` | `final PaymentGateway gateway = ...`, `@TestBean(type: PaymentGateway)` or `@TestBean(name: 'sandbox')` |
| `@TestBean field 'gateway' in a @Nested class` | move it to the `@SpringBootTest` class (one context) |
| `@BeforeAll method start must be static` | `static Future<void> start() ...` (also `@AfterAll`, `@DynamicPropertySource`, `@ContextInitializer`) |
| `@BeforeAll in a @Nested class: it belongs to the @SpringBootTest class` | move it to the outer class (also `@AfterAll`, `@DynamicPropertySource`, `@ContextInitializer`) |
| `@BeforeEach method before must not be static` | an instance method (also `@AfterEach`, `@Test`) |
| `@Test method pays has parameters` | test methods take none (widget tests with a `WidgetTester`: [Flutter testing](flutter-testing.md)) |
| `@ActiveProfiles on a method: it belongs to the class` | move it to the class, or write a second class (also `@SpringBootTest`, `@TestPropertySource`, `@TestEnvironment`) |
| `@Disabled on helper, which is not a @Test method` | add `@Test()` (also `@DisplayName`, `@Tag`, `@TestOptions`) |
| `@Disabled on the field x, which is not @Nested` | `@Disabled`, `@Tag`, `@TestOptions` and `@DirtiesContext` go on `@Test` methods, classes and `@Nested` fields |
| `@Nested field 'inner' needs a value` | `final inner = Inner();` |
| `@Nested field 'inner' must be created with a class of this file` | declare the class in the test file |
| `'CheckoutTest' needs a constructor without required parameters` | remove the constructor's required parameters |
| `'CheckoutTest' has no unnamed constructor` | add `CheckoutTest();` (the generated code calls it) |
| `'CheckoutTest' is abstract` | make it a concrete class |
| `'_CheckoutTest' is private` | make the class public (also a `@Nested` class) |
| `'_env' is private to the test file` | a constant used in an annotation must be public |
| `No application in this package` | a `@SpringBootApplication` entry point in `bin/` or `lib/` |
| `Several applications in this package (...)` | `@SpringBootTest(application: 'bin/shop.dart')` |
| `'bin/x.dart' is not an entry point with @SpringBootApplication` | the path of an entry point |
| `test/checkout_test.dart does not import 'spring/checkout.test.spring.dart'` (a warning) | add the import and `void main() => runSpringTests();` |

A missing bean is not a build error: the test fails when the context
starts, with the same report as the application (`No bean of type
Mailer`).

## 17. Web tests: `MockMvc`

With `spring_boot_starter_web`, a test calls the controllers in one of two
ways:

- **in memory, through `MockMvc`** (the default: no server starts).
  `MockMvc` runs the same handler as the server: filters, mapping,
  binding, `@Valid`, exception handlers and the `ProblemDetail` answers,
  only without the socket. It is fast and needs no free port;
- **over a real socket** on a free port, for clients that need one
  ([below](#a-real-server-webenvironment)).

As a class:

```dart
@SpringBootTest()
@AutoConfigureMockMvc()                  // optional: states the intent, as in Spring
class BookControllerTest {
  @Autowired()
  late MockMvc mvc;

  @Test()
  Future<void> findsABook() async {
    await mvc.get('/api/books/1111').andExpect(
      status: 200,
      contentType: MediaType.applicationJson,
      json: {'isbn': '1111', 'title': 'Dune'},
    );
  }

  @Test()
  Future<void> rejectsAnInvalidBook() async {
    // Empty fields fail @Valid: a 400 with a ProblemDetail body.
    await mvc
        .post('/api/books', json: {'isbn': '', 'title': ''})
        .andExpect(status: 400, contentType: MediaType.applicationProblemJson);
  }
}

void main() => runSpringTests();
```

As functions:

```dart
void main() {
  final app = springBootTest(springApplication);

  test('finds a book', () async {
    await app.mockMvc.get('/api/books/1111').andExpect(status: 200, json: containsPair('title', 'Dune'));
  });
}
```

Spring (Java):

```java
@SpringBootTest
@AutoConfigureMockMvc
class BookControllerTest {
  @Autowired MockMvc mvc;

  @Test
  void findsABook() throws Exception {
    mvc.perform(get("/api/books/1111"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.title").value("Dune"));
  }
}
```

Each call returns a `ResultActions`, which is a `Future`. Always `await`
it: a chain that is not awaited never reports a failed expectation.

### Requests and expectations

| Call | Request |
|---|---|
| `mvc.get(path, headers:, params:)` | `GET`; `params: {'q': 'dune', 'id': [1, 2]}` adds query parameters, a list sends the parameter once per element |
| `mvc.post(path, json:, body:, headers:)`, `put`, `patch` | a JSON body (`Content-Type: application/json`), or `body` (a `String` or bytes, sent as is, no content type added); `json` wins when both are given |
| `mvc.delete(path, headers:)` | `DELETE` |
| `mvc.multipart(path, files: [...], params: {...}, headers:, method:)` | a `multipart/form-data` upload, a `POST` unless `method` says otherwise, like `MockMvcRequestBuilders.multipart`; see below |
| `mvc.perform(MockRequestBuilder(HttpMethod.get, '/api/books/{isbn}', ['978-0']))` | anything else. The builder has `headers`, `params`, `cookies`, `principal`, `content(...)`, `json(...)` and `with_(postProcessor)`; each `{name}` is filled from the list, URL-encoded |
| `mvc.webSocket(path, headers:, postProcessors:)` | a WebSocket handshake in memory (see below) |

| On the result | Spring |
|---|---|
| `.andExpect(status: 201, contentType: ..., headers: {...}, body: ..., json: ...)` | `andExpect(status().isCreated())`, `content().contentType(...)`, `header().string(...)`, `content().string(...)`, `content().json(...)`; `body` and `json` take a value or a matcher (`hasLength(1)`, `containsPair(...)`) |
| `.andDo((result) => log.info(result.response.bodyText))` | `andDo(print())` |
| `await ....andReturn()` → `MvcResult` (`request`, `response`) | `andReturn()` |

`andExpect` checks only what is given. `status` must be equal; `contentType`
must be compatible (`application/json` matches
`application/json;charset=utf-8`); each header in `headers` must have
exactly that value. A failed expectation is a test failure that names the
request and shows the response (`GET http://localhost/api/books/1111:
expected status 404, got 200`). A `json:` check on a body that is not JSON
throws a `FormatException` instead.

The response is a `MockServerHttpResponse`: `statusCode`, `headers`,
`cookies`, `bodyText`, `bodyBytes`, `json`.

### Files: uploads and downloads

`mvc.multipart` sends `MockMultipartFile`s (field name, original file
name, content type, bytes, as in Spring) and text fields (`params`) as one
`multipart/form-data` body. It goes through the same multipart parsing
and limits as on the server. A `MockMultipartFile` without a file name is
a plain part; with `application/json` it fills a `@RequestPart` object:

```dart
test('uploads a cover', () async {
  await app.mockMvc.multipart('/api/books', files: [
    MockMultipartFile('cover', 'dune.png', 'image/png', pngBytes),
    MockMultipartFile('book', null, 'application/json',
        utf8.encode(jsonEncode({'isbn': '9780441013593', 'title': 'Dune'}))),
  ], params: {'note': 'first edition'}).andExpect(status: 200);
});

test('a missing part, a file too large', () async {
  await app.mockMvc
      .multipart('/api/books', params: {'note': 'x'})
      .andExpect(status: 400, json: containsPair('detail', "Required part 'book' is not present."));
  await app.mockMvc.multipart('/api/books', files: [
    MockMultipartFile('cover', 'big.png', 'image/png', List.filled(2 * 1024 * 1024, 0)),
  ]).andExpect(status: 413);                    // above max-file-size (1MB)
});
```

`MockMultipartFile` comes with `spring_boot_starter_test`. Set the limits
for a test with `properties: {'spring.servlet.multipart.max-file-size':
'64KB'}`.

A download (a `Resource`, a byte stream, a `StreamingResponseBody`) is
read from `response.bodyBytes` (or `bodyText`). Headers such as `Range`
and `If-Modified-Since` are sent like any other:

```dart
test('downloads part of a cover', () async {
  final result = await app.mockMvc
      .get('/api/books/9780441013593/cover', headers: {'Range': 'bytes=0-99'})
      .andExpect(status: 206, contentType: 'image/png', headers: {'Accept-Ranges': 'bytes'})
      .andReturn();
  expect(result.response.bodyBytes, hasLength(100));

  // Asked again with the date it got: nothing changed, so no body.
  final modified = result.response.headers['Last-Modified']!;
  await app.mockMvc
      .get('/api/books/9780441013593/cover', headers: {'If-Modified-Since': modified})
      .andExpect(status: 304, body: '');
});
```

Over a real server (`WebEnvironment.randomPort`), a Feign client sends
files as described in the Feign starter's
[Files and multipart](../spring_boot_starter_feign/README.md#files-and-multipart).

### Server-sent events

A stream answers before it ends, so `andReturn()` completes as soon as
the headers are out. Read the events as they come, and end the stream from
the client's side:

```dart
test('streams changes', () async {
  final result = await app.mockMvc.get('/api/books/changes').andReturn();
  expect(result.response.headers.contentType, startsWith('text/event-stream'));
  final next = result.response.eventStream.firstWhere((e) => e.data != null);

  await app.mockMvc.post('/api/books', json: {'isbn': '5555', 'title': 'Vurt'});

  final event = await next;
  expect(event.id, '5555');
  expect(event.data, contains('Vurt'));         // the data as sent (JSON text)
  await result.cancel();                        // the client goes away
});
```

`response.events` holds the events written so far, `response.chunks` the
raw body from now on, and `result.completion` completes when the
application has finished the response. `SseEmitter`s and
`application/x-ndjson` streams are read the same way.

### WebSocket endpoints

With `spring_boot_starter_websocket`, `mvc.webSocket(path)` performs the
handshake in memory, through the filters, the origin check and the
handshake interceptors. It returns the client's end of the connection;
the endpoint gets the other end:

```dart
test('echoes', () async {
  final session = await app.mockMvc.webSocket('/ws/echo/bob');
  final replies = StreamIterator(session.messages);
  session.sendMessage('hey');
  expect(await replies.moveNext(), isTrue);
  expect(jsonDecode(replies.current as String), {'text': 'bob: HEY'});
  await session.close();
});
```

A refused handshake throws a `WebSocketException` with the status and
body of the answer.

### A real server: `webEnvironment`

Some clients need a real socket: a Feign client, `dart:io`'s
`HttpClient`, a WebSocket client. For them the test starts the server on a
free port.

| `webEnvironment` | Spring | What starts |
|---|---|---|
| `WebEnvironment.mock` (default) | `MOCK` | no server; `MockMvc` |
| `WebEnvironment.randomPort` | `RANDOM_PORT` | the server on a free port; the context counts as started once it listens |
| `WebEnvironment.definedPort` | `DEFINED_PORT` | the server on `server.port`; the start fails when the port is taken |
| `WebEnvironment.none` | `NONE` | no server; `MockMvc` still works |

```dart
import 'dart:io' as io;

@SpringBootTest(webEnvironment: WebEnvironment.randomPort)
class ServerTest {
  @LocalServerPort()
  late int port;                          // also app.localServerPort

  @Test()
  Future<void> answersOverHttp() async {
    final client = io.HttpClient();
    final request = await client.getUrl(Uri.parse('http://localhost:$port/api/books/1111'));
    final response = await request.close();
    expect(response.statusCode, 200);
    client.close();
  }
}
```

`app.localServerPort` (and a `@LocalServerPort()` field) reads the
`local.server.port` property; without a running server it throws a
`StateError`. A server that cannot start fails the context with Spring
Boot's report. `MockMvc` works in every web environment; without the web
starter it throws a `StateError`.

### Changing every request: `RequestPostProcessor`

A `RequestPostProcessor` changes a request just before it is sent, as in
Spring. `spring_boot_starter_security/testing.dart` provides the security
ones: `user(...)`, `jwt()`, `csrf()`, `httpBasic(...)` and others. Write
your own for anything else, such as a header every request needs:

```dart
// Every request arrives as if through the HTTPS proxy of production.
final viaProxy = FunctionRequestPostProcessor(
  (request) => request..headers.set('X-Forwarded-Proto', 'https'),
);

await app.mockMvc.perform(
  MockRequestBuilder(HttpMethod.delete, '/api/books/1111')..with_(viaProxy),
).andExpect(status: 204);

// For every request of a MockMvc (DispatcherHandler comes from spring_boot_starter_web):
final mvc = MockMvc(app.getBean<DispatcherHandler>(), defaultPostProcessors: [viaProxy]);
```

The `defaultPostProcessors` run before those of the request itself.

### `ApplicationContextRunner`

The runner starts no server either: it sets
`spring.test.web-environment=mock`, so auto-configuration tests of a web
application never open a port. For a real server in a runner, add
`.withPropertyValues(['spring.test.web-environment=random-port'])`, then
`await context.getBean<WebServerStartStopLifecycle>().started` gives the
`WebServer` and its port.

## 18. Differences from Spring

- **`main` stays.** `dart test` runs `main`; a test file keeps one line,
  `void main() => runSpringTests();`.
- **Fields, not constructors**, for injection into tests, and they are
  `late`.
- **`@TestBean` takes a value**, not a factory method name or a Mockito
  mock; any object (a fake, a `mocktail` mock) works. Nothing is reset
  between tests.
- **`@TestEnvironment`** does not exist in Spring: Java tests cannot
  replace environment variables. Here a test's environment is empty unless
  given, so tests do not depend on the machine.
- **`@SpringBootTest(application:)`** is a path to the entry point, not a
  class, because annotation arguments must be constants.
- **`@Nested`** is a field holding another class: Dart has no inner
  classes.
- **One context per class**, not shared between classes with the same
  configuration (Spring's context cache). Each class starts its own;
  starting is fast, since nothing is scanned at run time: everything is
  generated.
- **Web tests** ([section 17](#17-web-tests-mockmvc)): `MockMvc` needs no
  `@AutoConfigureMockMvc` (an `@Autowired MockMvc` field or `app.mockMvc`
  always works with the web starter). Its expectations are named
  parameters with matchers instead of `status().isOk()` and
  `jsonPath(...)`. There is no `WebTestClient` or `TestRestTemplate`: use
  a Feign client or `HttpClient` against `localServerPort`.
- **No test slices** (`@WebMvcTest`, `@DataJpaTest`) yet; use
  `ApplicationContextRunner` for a part of the configuration.
