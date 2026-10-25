# spring_boot_starter_test

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Testing support for [`spring_boot_dart`](../spring_boot_dart) applications
and starters, like `spring-boot-starter-test`. Built on `test_api` and
`matcher` (not `package:test` itself), so it works with both `package:test`
and `flutter_test`.

```yaml
dev_dependencies:
  spring_boot_starter_test: ^0.2.3
  test: ^1.25.0          # or flutter_test
```

## `springBootTest`: the whole application (`@SpringBootTest`)

```dart
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/shop.spring.dart'; // generated springApplication

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
  closes with `closeAsync()` after the last one.
- `properties` win over every other source, the command line included.
- `dynamicProperties` (`@DynamicPropertySource`) adds properties whose
  values are known only when the context starts (see below).
- `systemEnvironment` is empty by default, so tests do not depend on the
  machine.
- `SpringLog` levels and handler are restored afterwards.
- `app.output` holds what the application printed (a failure report; the
  startup info goes through `SpringLog`); it is also printed when a test
  fails.

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

## Dynamic properties (`@DynamicPropertySource`)

Values known only when the tests run (a server's port, a temporary
directory) go through `dynamicProperties`. It is called whenever the
context starts (again after `markDirty`), and each supplier whenever the
property is read; these properties win over `properties`:

```dart
late HttpServer server;
setUpAll(() async => server = await HttpServer.bind('localhost', 0));

final app = springBootTest(
  springApplication,
  dynamicProperties: (registry) => registry
    ..add('catalog.url', () => 'http://localhost:${server.port}'),
);
```

Declare the `setUpAll` that provides the value before `springBootTest`, so
it runs first.

## `BeanOverride`: fakes and mocks (`@MockitoBean`, `@TestBean`)

```dart
BeanOverride<PaymentGateway>(FakeGateway())                 // the only bean of the type
BeanOverride<PaymentGateway>(MockGateway(), name: 'sandbox') // one of several
```

The original definition is removed before any bean is created, so the real
object is never built. The replacement keeps the name, aliases, qualifiers
and `@Primary` / `@Fallback`, so `@Qualifier` injection points still get it.
Use any fake or mock library (e.g. `mocktail`). Overriding a type with
several beans without `name:` replaces the `@Primary` one, like Spring;
without a single primary bean it fails and lists them. `name:` may also be
an alias of the bean.

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
  runner.withBean<Cache>(AppCache.new).run((context) {
    expect(context, hasSingleBean<Cache>()); // a missing back-off: two beans
    expect(context.getBean<Cache>(), isA<AppCache>());
  });
});

test('needs a size', () {
  runner.withPropertyValues(['neon.cache.size=-1']).run((context) {
    expect(context, hasFailed(isA<BeanCreationException>()));
  });
});
```

- `withBean<T>(supplier, name: ...)` registers an extra bean before the
  configurations are processed, like Boot's `withBean(type, supplier)`
  (each run gets a new instance from `supplier`): a
  `@ConditionalOnMissingBean` backs off, and a missing back-off shows up as
  a second bean (or, with the same name, a failed start). It never
  replaces a bean.
- `withBeanOverride<T>(instance, name: ...)` replaces a bean after the
  configurations were processed, like a `BeanOverride` (not in Boot's
  runner; prefer `withBean` to test back-offs).
- `withPropertyValues(['a=b', 'c: d', 'flag'])` takes `key=value` and
  `key:value` like Boot's `TestPropertyValues` (trimmed; no separator: an
  empty value).
- Also `withUserConfiguration(module)` (registered before the
  auto-configuration), `withSystemEnvironment`, `withInitializer`.

For asynchronous checks use `runAsync`: the context stays open until the
returned future completes and is then closed with `closeAsync()` (`run`
closes it with `close()` as soon as the body returns).

```dart
test('calls the client', () async {
  await runner.runAsync((context) async {
    expect(await context.getBean<CatalogClient>().find('1'), isNotNull);
  });
});
```

## Matchers

`hasSingleBean<T>()`, `hasBean<T>()`, `doesNotHaveBean<T>()`,
`hasBeanNamed('name')`, `hasFailed([matcher])`. They accept an
`AssertableApplicationContext`, a `springBootTest` context or any
`ListableBeanFactory`, and say which beans were found when they fail. Like
AssertJ's, the bean-count matchers include the parent contexts
(`withParent`).

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

## Differences from Spring

- `springBootTest` is a function for the tests of a `main` or `group`, not
  an annotation on a test class; no `webEnvironment` (there is no embedded
  web server), no test slices (`@WebMvcTest`, `@DataJpaTest`, ...) and no
  `@TestConfiguration`: pass extra modules to the `SpringApplication`.
- `BeanOverride` replaces the bean definition with a ready-made object of
  your own (like `@TestBean`); there are no generated mocks or spies and no
  automatic reset between tests (`@MockitoBean(reset)`): use any mock
  library and reset in `setUp`. Without an existing bean, the instance is
  registered.
- `ApplicationContextRunner.withBean` takes a supplier and the type as a
  type argument (`withBean<Cache>(AppCache.new)`), not a class; there is
  no constructor-arguments variant. `withBeanOverride` has no Boot
  counterpart.
- `ApplicationContextRunner.withAutoConfiguration(module, metadata)`
  takes the module's `@AutoConfigurationModule` by hand (Dart cannot read
  the annotation of a variable at runtime); the modules are then sorted
  like `AutoConfigurations.of(...)` (name, `order`, `before` / `after`).
- `withAllowCircularReferences(true)` fails every run with an
  `UnsupportedError`: circular references are always an error here (no
  early references); `false` is the default, as in Boot.
- No context caching across test files: each `springBootTest` starts its
  own context (shared by the tests of its `main` / `group`).
- `dynamicProperties` is a parameter, not an annotated static method; no
  `DynamicPropertyRegistrar` beans.
- `captureLogs` replaces `OutputCaptureExtension` for `SpringLog` output.

## Name clash

`package:test` (via `matcher`) and `spring_core_dart` both define
`Description` (Spring's `@Description`). It only matters if a test uses it:
`import 'package:test/test.dart' hide Description;`.
