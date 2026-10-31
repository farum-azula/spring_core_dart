# spring_boot_starter_test: examples

These examples test a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) application
the way it really runs: with its config files and profiles, and with all
its objects wired together. Where a real service cannot run in a test
(payments, the network, a database), the test swaps it for a fake. They
work with `package:test` and `flutter_test`.

A complete, runnable test suite that uses every part shown here is the one
of the server guide,
[example/server_guide/test](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide/test).
To run it from a clone of the repository:

```bash
cd example/server_guide
dart run build_runner build          # writes the generated *.spring.dart files
dart test                            # every test
dart test --exclude-tags integration # without the tests that open real sockets
```

## Setup

```yaml
dev_dependencies:
  spring_boot_starter_test: ^0.5.0
  test: ^1.25.0          # or flutter_test
```

The application is built with `spring_core_dart_generator`, which writes
the `springApplication` the tests start. Run `dart run build_runner build`
before the tests, and again after changing beans.

## 1. Start the whole application in a test

```dart
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/main.spring.dart'; // generated: springApplication

void main() {
  final app = springBootTest(springApplication);

  test('the shop has a name', () {
    // A real bean, with its properties bound from the config files.
    expect(app.getBean<ShopProperties>().name, 'NEON Books');
  });
}
```

The application starts once, before the first test of the file, and stops
after the last one. Every test of the file shares it.

## 2. Replace a real service with a fake

```dart
class FakePayments implements Payments {
  final paid = <double>[];

  @override
  String pay(double amount) {
    paid.add(amount);
    return 'ok';
  }
}

void main() {
  final payments = FakePayments();
  final app = springBootTest(
    springApplication,
    // The real Payments is never created; Checkout gets the fake.
    overrides: [BeanOverride<Payments>(payments)],
  );

  test('checkout pays once', () {
    app.getBean<Checkout>().buy('book');
    expect(payments.paid, [9.99]);
  });
}
```

Mocks from a library such as `mocktail` work the same way. Nothing is
reset between tests, so reset a shared fake in `setUp`.

## 3. Test settings

Settings for the tests only go to `test/resources/`, which is read before
`lib/resources/` during the tests and never shipped with the application:

```text
lib/resources/application.properties          # the application's settings
test/resources/application-test.properties    # only for tests
```

```dart
final app = springBootTest(
  springApplication,
  profiles: ['test'],                         // also reads application-test.properties
  properties: {'shop.name': 'Test Books'},    // wins over every other source
  systemEnvironment: {'DB_PASSWORD': 'x'},    // instead of the machine's variables
);
```

Test data files work too: `test/resources/books.json` is
`classpath:books.json` in the tests.

## 4. A fresh application after a test that changes state

```dart
test('clears the basket', () {
  app.getBean<Basket>().clear();
  // The basket bean is now empty: the next test gets a newly started app.
  app.markDirty();
});
```

## 5. Call the controllers without a server

With `spring_boot_starter_web`, `app.mockMvc` sends requests through the
real web layer in memory: filters, validation and error answers included.

```dart
test('an unknown book is a 404', () async {
  await app.mockMvc
      .get('/api/books/9780000000000')
      .andExpect(status: 404, contentType: MediaType.applicationProblemJson);
});
```

Always `await` the chain: a check that is not awaited never fails the
test.

## 6. Check what was logged

```dart
final logs = captureLogs();

test('logs the payment', () {
  app.getBean<Checkout>().buy('book');
  expect(logs.messages, contains('paid 9.99'));
});
```

The capture is emptied before every test.

## 7. The same test as a class

The generator turns a class like this into the functions above; the test
file keeps a one-line `main`:

```dart
import 'spring/checkout.test.spring.dart'; // generated next to the test

@SpringBootTest()
@ActiveProfiles(['test'])
class CheckoutTest {
  @TestBean()
  final Payments payments = FakePayments(); // replaces the only Payments

  @Autowired()
  late Checkout checkout;

  @Test()
  void checkoutPaysOnce() {
    checkout.buy('book');
    expect((payments as FakePayments).paid, [9.99]);
  }
}

void main() => runSpringTests();
```

## 8. Testing your own starter

`ApplicationContextRunner` starts a small context per test, with just your
auto-configuration and the properties of the test:

```dart
final runner = const ApplicationContextRunner()
    .withAutoConfiguration(myCacheAutoConfiguration);

test('provides a cache', () {
  runner.run((context) => expect(context, hasSingleBean<Cache>()));
});

test('steps aside when the app has its own cache', () {
  // Registered before the auto-configuration, as an application's bean
  // would be: without @ConditionalOnMissingBean there would be two caches.
  runner.withBean<Cache>(AppCache.new).run((context) {
    expect(context, hasSingleBean<Cache>());
    expect(context.getBean<Cache>(), isA<AppCache>());
  });
});

test('can be switched off', () {
  runner.withPropertyValues(['my.cache.enabled=false']).run((context) {
    expect(context, doesNotHaveBean<Cache>());
  });
});
```

Matchers: `hasSingleBean<T>()`, `hasBean<T>()`, `doesNotHaveBean<T>()`,
`hasBeanNamed('x')`, `hasFailed()`.

## Where each part is used in the server guide

| Part | File in `example/server_guide/test/` |
|---|---|
| `springBootTest` with the `test` profile | `support/app.dart`, used by every test |
| a test class with `@TestBean`, `@Autowired`, `@Value`, `@CapturedOutput`, `@Nested` | `shop_class_test.dart` |
| `MockMvc`, with a logged-in user and a CSRF token | `web_test.dart`, `security_test.dart` |
| a real server on a free port | `server_integration_test.dart` |
| `BeanOverride` | `supplier_test.dart`, `cache_scheduling_test.dart`, `data_access_test.dart` |
| `ApplicationContextRunner` | `configuration_test.dart` |
| `captureLogs` | `events_aop_test.dart`, `security_test.dart` |
