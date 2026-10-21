# spring_boot_starter_test

Testing support for [`spring_boot_dart`](../spring_boot_dart) applications
and starters, like `spring-boot-starter-test`. Built on `test_api` and
`matcher` (not `package:test` itself), so it works with both `package:test`
and `flutter_test`.

```yaml
dev_dependencies:
  spring_boot_starter_test: ^0.1.0
  test: ^1.25.0          # or flutter_test
```

## `springBootTest`: the whole application (`@SpringBootTest`)

```dart
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/shop.beans.dart'; // generated springApplication

void main() {
  final gateway = FakeGateway();

  final app = springBootTest(
    springApplication,
    args: ['--shop.name=Night Books'],
    properties: {'logging.console.enabled': false}, // @SpringBootTest(properties)
    profiles: ['test'],                             // @ActiveProfiles
    systemEnvironment: {'SHOP_MAX_BASKET_SIZE': '25'},
    overrides: [BeanOverride<PaymentGateway>(gateway)], // @MockitoBean
  );

  test('pays through the fake', () {
    app.getBean<Checkout>().pay(10);
    expect(gateway.charged, [10]);
  });

  test('changes shared state', () {
    app.getBean<Basket>().add(book);
    app.markDirty(); // @DirtiesContext: the next test gets a fresh context
  });
}
```

- Test config lives in `test/resources/` (see below).
- The context starts once before the first test of the `main` / `group`
  (config files, auto-configuration, runners: all of `runApplication`) and
  closes after the last one.
- `properties` win over every other source, the command line included.
- `systemEnvironment` is empty by default, so tests do not depend on the
  machine.
- `SpringLog` levels and handler are restored afterwards.
- `app.output` holds what the application printed (startup line, failure
  report); it is also printed when a test fails.

## `test/resources/`: config and data for tests only

Like `src/test/resources` in Spring, `test/resources/` comes first on the
classpath while `springBootTest` runs, and is never embedded into the
application (the generator embeds only `lib/resources/`):

```text
lib/resources/application.properties          # the application's config
test/resources/application-test.properties    # test-only settings
test/resources/fixtures/books.json            # classpath:fixtures/books.json in tests
```

```dart
final app = springBootTest(
  springApplication,
  profiles: ['test'],                                // + application-test.properties
  propertyFiles: ['classpath:payments-test.properties'], // @TestPropertySource(locations)
);
```

- Prefer `application-test.properties` with `profiles: ['test']`: its keys
  are added on top of `application.properties`. A file with the same path
  as a `lib/resources/` file replaces it entirely (as in Spring), so a
  `test/resources/application.properties` hides the real one.
- `profiles` replaces `spring.profiles.active` (like `@ActiveProfiles`):
  list the application's profiles too if you need them
  (`profiles: ['dev', 'test']`).
- Precedence: `properties` > `propertyFiles` (later files win) > command
  line `args` > environment > config files.
- Relative directories are resolved against the package of the test file
  (the nearest `pubspec.yaml`), so it does not matter whether the tests run
  from the package, a workspace root or an IDE.
- Other directories: `resourceDirectories: ['test/fixtures', 'test/resources']`
  (the first listed comes first). In browser tests there is no file system,
  so the directories are simply not found.

## `BeanOverride`: fakes and mocks (`@MockitoBean`, `@TestBean`)

```dart
BeanOverride<PaymentGateway>(FakeGateway())                 // the only bean of the type
BeanOverride<PaymentGateway>(MockGateway(), name: 'sandbox') // one of several
```

The original definition is removed before any bean is created, so the real
object is never built. The replacement keeps the name, aliases, qualifiers
and `@Primary` / `@Fallback`, so `@Qualifier` injection points still get it.
Use any fake or mock library (e.g. `mocktail`). Overriding a type with
several beans without `name:` fails and lists them.

## `ApplicationContextRunner`: testing auto-configuration

The tool for starter authors (Spring Boot's `ApplicationContextRunner`).
Immutable; no config files; empty environment unless set.

```dart
final runner = const ApplicationContextRunner()
    .withAutoConfiguration(neonCacheAutoConfiguration);

test('default cache', () {
  runner.run((context) {
    expect(context, hasSingleBean<Cache>());
  });
});

test('backs off for the application cache', () {
  runner.withBean<Cache>(AppCache()).run((context) {
    expect(context.getBean<Cache>(), isA<AppCache>());
  });
});

test('needs a size', () {
  runner.withPropertyValues(['neon.cache.size=-1']).run((context) {
    expect(context, hasFailed(isA<BeanCreationException>()));
  });
});
```

Also `withUserConfiguration(module)` (registered before the
auto-configuration), `withSystemEnvironment`, `withInitializer`.

## Matchers

`hasSingleBean<T>()`, `hasBean<T>()`, `doesNotHaveBean<T>()`,
`hasBeanNamed('name')`, `hasFailed([matcher])`. They accept an
`AssertableApplicationContext`, a `springBootTest` context or any
`ListableBeanFactory`, and say which beans were found when they fail.

## `captureLogs`

```dart
final logs = captureLogs(level: SpringLogLevel.debug);

test('warns about slow payments', () {
  checkout.pay(slowOrder);
  expect(logs.messages, contains('slow payment'));
  expect(logs.atLevel(SpringLogLevel.warning), hasLength(1));
  expect(logs.ofLogger('neon.checkout'), isNotEmpty);
});
```

Every test starts with an empty capture.

## Name clash

`package:test` (via `matcher`) and `spring_core_dart` both define
`Description` (Spring's `@Description`). It only matters if a test uses it:
`import 'package:test/test.dart' hide Description;`.
