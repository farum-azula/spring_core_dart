# spring_boot_starter_test: examples

**What it does:** tests a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) app the way
it really runs — config files, profiles, all objects wired together — and
lets you swap real services (payments, network, database) for fakes.
Works with `package:test` and `flutter_test`.

## Setup

```yaml
dev_dependencies:
  spring_boot_starter_test: ^0.3.2
  test: ^1.25.0          # or flutter_test
```

Your app is built with `spring_core_dart_generator` (it creates the
`springApplication` used below), so run `dart run build_runner build` first.

## 1. Start the whole app in a test

```dart
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/main.spring.dart'; // generated: springApplication

void main() {
  final app = springBootTest(springApplication);

  test('the shop has a name', () {
    expect(app.getBean<ShopProperties>().name, 'NEON Books');
  });
}
```

The app starts once before the tests of the file and stops after them.

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
    overrides: [BeanOverride<Payments>(payments)],
  );

  test('checkout pays once', () {
    app.getBean<Checkout>().buy('book');
    expect(payments.paid, [9.99]);
  });
}
```

The real `Payments` is never created. Mocks from `mocktail` work the same.

## 3. Test settings

```text
lib/resources/application.properties          # the app's settings
test/resources/application-test.properties    # only for tests, not shipped
```

```dart
final app = springBootTest(
  springApplication,
  profiles: ['test'],                         // loads application-test.properties
  properties: {'shop.name': 'Test Books'},    // wins over everything
  systemEnvironment: {'DB_PASSWORD': 'x'},    // instead of the real environment
);
```

Test data files work too: `test/resources/books.json` is
`classpath:books.json` in tests.

## 4. A fresh app after a test that changes state

```dart
test('clears the basket', () {
  app.getBean<Basket>().clear();
  app.markDirty(); // the next test gets a newly started app
});
```

## 5. Check what was logged

```dart
final logs = captureLogs();

test('logs the payment', () {
  app.getBean<Checkout>().buy('book');
  expect(logs.messages, contains('paid 9.99'));
});
```

## 6. Testing your own starter

`ApplicationContextRunner` starts small contexts with just your
auto-configuration:

```dart
final runner = const ApplicationContextRunner()
    .withAutoConfiguration(myCacheAutoConfiguration);

test('provides a cache', () {
  runner.run((context) => expect(context, hasSingleBean<Cache>()));
});

test('steps aside when the app has its own cache', () {
  // Registered before the auto-configuration, like Boot's withBean:
  // a missing @ConditionalOnMissingBean would give two caches.
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

## More

A real test suite using all of this:
[example/test/boot_test.dart](https://github.com/farum-azula/spring_core_dart/blob/main/example/test/boot_test.dart).
