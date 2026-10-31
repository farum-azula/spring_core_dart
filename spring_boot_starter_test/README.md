# spring_boot_starter_test

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Tools for testing an application built with
[`spring_boot_dart`](../spring_boot_dart), or a starter written for it.

A unit test that creates its objects by hand cannot tell you whether the
application starts: whether the config files bind, the beans find each
other, and the controllers answer as a client expects. This package starts
the real application inside a test, once for many tests, and lets the
test change what it must:

- start the whole application with test properties and profiles, and get
  its beans;
- replace a bean that talks to the outside world (a payment provider, a
  mail server, the clock) with a fake or a mock;
- call the controllers through the real web layer without opening a
  socket (`MockMvc`), or start a real server on a free port;
- check what a starter's auto-configuration creates under which
  properties (`ApplicationContextRunner`);
- check what the application logged.

Tests can be written as plain functions in `main` or as test classes with
annotations (`@SpringBootTest()`, `@Autowired()`, `@Test()`), the way
Spring tests look; the generator turns the classes into the same
functions. The package is built on `test_api` and `matcher`, not on
`package:test` itself, so it works with both `package:test` and
`flutter_test`.

```yaml
dev_dependencies:
  spring_boot_starter_test: ^0.5.0
  test: ^1.25.0          # or flutter_test
```

*In the guides:* [server, 12. Testing](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#12-testing), [app, 11. Testing](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#11-testing).

The whole topic, including test classes and what the generator writes for
them, is in the [testing guide](../docs/testing.md).

## A first test

```dart
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/shop.spring.dart'; // the generated springApplication

void main() {
  final gateway = FakeGateway();

  // The real shop, started once for the tests below, with a fake gateway.
  final app = springBootTest(
    springApplication,
    profiles: ['test'],                             // reads application-test.properties
    overrides: [BeanOverride<PaymentGateway>(gateway)],
  );

  test('checkout pays through the fake', () {
    app.getBean<Checkout>().pay(10);
    expect(gateway.charged, [10]);
  });
}
```

`springBootTest` returns at once; the application starts before the first
test. The `springApplication` it takes is the one the generator wrote for
your entry point, so run `dart run build_runner build` (or `watch`) first.

Spring (Java):

```java
@SpringBootTest
@ActiveProfiles("test")
class CheckoutTest {
  @MockitoBean PaymentGateway gateway;
  @Autowired Checkout checkout;

  @Test
  void paysThroughTheGateway() { ... }
}
```

## `springBootTest`: the whole application

`springBootTest` starts the application for the tests of the enclosing
`main` or `group`. It does everything `runApplication` does: reads the
config files, applies the auto-configuration, binds
`@ConfigurationProperties`, calls the runners. Use it for tests that need
the real wiring: a service with its repositories, properties from the
config files, controllers behind `MockMvc`.

```dart
void main() {
  final gateway = FakeGateway();

  final app = springBootTest(
    springApplication,
    args: ['--shop.name=Night Books'],             // as on the command line
    properties: {'logging.console.enabled': false}, // win over every other source
    profiles: ['test'],
    systemEnvironment: {'SHOP_MAX_BASKET_SIZE': '25'}, // instead of the machine's
    overrides: [BeanOverride<PaymentGateway>(gateway)],
  );

  test('pays through the fake', () {
    app.getBean<Checkout>().pay(10);
    expect(gateway.charged, [10]);
  });

  test('changes shared state', () {
    app.getBean<Basket>().add(book);
    // The basket is not empty any more: the next test gets a new context.
    app.markDirty();
  });
}
```

How it runs:

- The context starts once, in a `setUpAll`, before the first test of the
  `main` or `group`. It is closed with `closeAsync()` in a `tearDownAll`
  after the last test, so asynchronous `@PreDestroy` methods and lifecycle
  stops are awaited.
- `app.markDirty()` closes the context at the end of the current test; the
  next test starts a new one. Call it after a test that changed beans in a
  way later tests must not see; `setUp(app.markDirty)` gives every test a
  fresh context.
- `app` is usable inside tests, `setUp`, and a `setUpAll` declared after
  the `springBootTest` call. Elsewhere `app.context` throws a
  `StateError`, because the context does not exist yet.
- The `SpringLog` levels and handler that the application changed are
  restored after the last test.

The options:

| Parameter | What it does | Spring |
|---|---|---|
| `args` | command-line arguments | `@SpringBootTest(args)` |
| `properties` | properties that win over every other source, the command line and `propertyFiles` included | `@SpringBootTest(properties)` |
| `propertyFiles` | resource locations of `.properties` files; later files win; a missing file fails the start with a `StateError` | `@TestPropertySource(locations)` |
| `dynamicProperties` | properties known only when the tests run ([below](#dynamic-properties)) | `@DynamicPropertySource` |
| `profiles` | become `spring.profiles.active`, replacing the value of the config files | `@ActiveProfiles` |
| `systemEnvironment` | the environment variables the application sees; empty by default, so tests do not depend on the machine | none |
| `resourceDirectories` | directories first on the classpath; default `['test/resources']` ([below](#test-configuration-testresources)) | the test classpath |
| `overrides` | beans replaced by fakes or mocks ([below](#replacing-beans-beanoverride)) | `@MockitoBean`, `@TestBean` |
| `initializers` | `ApplicationContextInitializer`s run on the context before it is refreshed | `@ContextConfiguration(initializers)` |
| `webEnvironment` | which web server starts; none by default ([below](#web-tests-mockmvc-and-webenvironment)) | `@SpringBootTest(webEnvironment)` |

What the returned `SpringBootTestContext` offers:

| Member | What it gives |
|---|---|
| `getBean<T>({qualifier})`, `getBeanByName(name)` | a bean; throws when there is none |
| `findBean<T>({qualifier})` | a bean or `null` |
| `getBeans<T>({qualifier})` | every bean of `T`, sorted by `@Order` |
| `value<T>(expression)`, `optionalValue<T>(expression)` | a `${...}` / `#{...}` expression resolved as a `@Value` field would be |
| `context`, `environment` | the running context and its environment |
| `mockMvc` | requests to the controllers in memory (with the web starter) |
| `localServerPort` | the port of the real server (`WebEnvironment.randomPort` / `definedPort`) |
| `output` | the lines the application printed, such as the failure report of a context that did not start; also printed when a test fails. The startup information is logged through `SpringLog`, not printed: use [`captureLogs`](#checking-logs-capturelogs) for it |
| `markDirty()` | a new context for the next test |

## Test configuration: `test/resources/`

Settings and data that only the tests need go to `test/resources/`. While
`springBootTest` runs, that directory comes first on the classpath, before
the application's `lib/resources/`. It is never embedded into the
application: the generator embeds only `lib/resources/`.

```text
lib/resources/application.properties          # the application's config
test/resources/application-test.properties    # test-only settings
test/resources/fixtures/books.json            # classpath:fixtures/books.json in tests
```

```dart
final app = springBootTest(
  springApplication,
  profiles: ['test'],                                    // + application-test.properties
  propertyFiles: ['classpath:payments-test.properties'], // found in test/resources/ first
);
```

- **Prefer a test profile.** `application-test.properties` with
  `profiles: ['test']` adds its keys on top of `application.properties`.
  A file with the same path as one in `lib/resources/` replaces it
  entirely, as in Spring: a `test/resources/application.properties` hides
  the real one.
- **`profiles` replaces the active profiles** of the config files. List
  the application's own profiles too when the tests need them:
  `profiles: ['dev', 'test']`.
- **Precedence**, highest first: `dynamicProperties`, `properties`,
  `propertyFiles` (later files win), command-line `args`,
  `systemEnvironment`, the config files.
- **Relative directories** are resolved against the package of the test
  file (the nearest `pubspec.yaml`), so it does not matter whether the
  tests run from the package, a workspace root or an IDE.
- **Other directories**: `resourceDirectories: ['test/fixtures',
  'test/resources']`; the first one listed comes first. Browser tests have
  no file system, so there the directories are simply not found.

## Dynamic properties

Some values exist only once the tests run: the port of a fake server, a
temporary directory. `properties:` is fixed when `springBootTest` is
called, so such values go through `dynamicProperties`, which registers a
function per property:

```dart
late HttpServer server;
// Declared before springBootTest, so the server is up when the context starts.
setUpAll(() async => server = await HttpServer.bind('localhost', 0));

final app = springBootTest(
  springApplication,
  dynamicProperties: (registry) => registry
    ..add('catalog.url', () => 'http://localhost:${server.port}'),
);
```

The callback runs each time the context starts (again after
`markDirty`), and each function each time the application reads the
property. These values win over every other source, `properties`
included. Adding the same name twice keeps the second function.

Spring (Java):

```java
@DynamicPropertySource
static void properties(DynamicPropertyRegistry registry) {
  registry.add("catalog.url", server::baseUrl);
}
```

## Replacing beans: `BeanOverride`

A bean that talks to something a test cannot use (a payment provider, the
wall clock, a mail server) is replaced with an object of the test:

```dart
BeanOverride<PaymentGateway>(FakeGateway())                  // the only bean of the type
BeanOverride<PaymentGateway>(MockGateway(), name: 'sandbox') // one of several, by name
```

The original definition is removed before any bean is created, so the real
object, and whatever it would connect to, is never built. Every bean that
injects it gets the replacement. Any fake or mock works (for example from
`mocktail`); nothing is reset between tests, so reset shared mocks in
`setUp`.

Which bean is replaced:

- with `name:`, the bean of that name, or the bean that name is an alias
  of;
- without it, the only bean of `T`; among several, the single `@Primary`
  one. Several beans and no single primary fail the start with a
  `StateError` that lists them;
- without any bean of `T`, the instance is added as a new bean, named
  after the type (`PaymentGateway` → `paymentGateway`, see
  `defaultBeanName`).

The replacement keeps the original's name, aliases, qualifiers, order and
`@Primary` / `@Fallback` flags, so `@Qualifier` injection points still
find it. When several overrides replace the same bean, the last one wins.

Things to know, as the code behaves today:

- **The replacement is registered under `T` only.** If the original was
  also found under another type (it implemented a second interface), that
  type no longer finds it. `BeanOverride.named(instance, name: ...)`, which
  `@TestBean(name: ...)` generates, keeps the original's types instead
  (except its own class) and adds `T` (unless it is `Object`) and the
  class of the instance; for a `@TestBean(name: ...)` field, `T` is the
  field's type, under which Spring registers the override too. Dart
  cannot check that the instance has the original's types: a fake that
  implements only some of the original's interfaces fails where another
  one is injected. Give the fake's own types then,
  `BeanOverride.named(fake, name: ..., types: [FakeGateway,
  PaymentGateway])`, and it is registered under those (and `T`). A
  `@TestBean(name: ...)` field whose value is created with a constructor
  (`= FakeGateway()`, also a named or private class's constructor, with
  an import prefix, in parentheses or followed by a cascade, whatever the
  field's declared type) does that by itself: the generated override
  lists that class and all its public supertypes, as the generator
  registers a bean of that class (`types: [FakeGateway,
  PaymentGateway]`; a `SubGateway extends RealGateway` keeps every type
  of `RealGateway`; a fake `HttpClient` stays an `HttpClient`, written
  through `dart:io`; a private class is left out, its runtime class is
  added anyway). A type with a private class as a type argument cannot
  be written in the generated file and is listed in its raw form only
  (`FakeRepo<_Draft>()` gives `FakeRepo<dynamic>, Repo<dynamic>`). Any
  other value (`= Fakes.gateway()`, a function or static method, which
  may return any subclass), a class that cannot be resolved, or another
  type that cannot be written in the generated file (a function or
  record type argument) keeps the original's types.
- **A misspelt `name:` does not fail.** When no bean has that name, the
  instance is added under it, next to the real bean, which stays. The
  usual symptom is the real bean still being used, or an error about two
  beans of `T`.
- **Without `name:` and without a bean of `T`,** the instance is
  registered as `defaultBeanName(T)`; if an unrelated bean already has
  that name, that bean is removed.

## Web tests: `MockMvc` and `webEnvironment`

With [`spring_boot_starter_web`](../spring_boot_starter_web/README.md),
`app.mockMvc` sends requests to the controllers in memory. It runs the same
dispatcher a real server runs (filters, mapping, binding, `@Valid`,
exception handlers and the `ProblemDetail` answers), without a socket, so
it is fast and needs no free port. By default (`WebEnvironment.mock`) no
server starts at all.

```dart
final app = springBootTest(springApplication);

test('finds, searches, rejects and deletes books', () async {
  final mvc = app.mockMvc;
  await mvc.get('/api/books/1111').andExpect(
    status: 200,
    contentType: MediaType.applicationJson,
    headers: {'X-Trace': 'on'},
    json: {'isbn': '1111', 'title': 'Dune'}, // or a matcher: containsPair('title', 'Dune')
  );
  await mvc.get('/api/books', params: {'q': 'dune'}).andExpect(json: hasLength(1));
  // An empty ISBN fails validation: a 400 with a ProblemDetail body.
  await mvc
      .post('/api/books', json: {'isbn': '', 'title': ''})
      .andExpect(status: 400, contentType: MediaType.applicationProblemJson);
  await mvc.delete('/api/books/2222').andExpect(status: 204);
});
```

Each call returns a `ResultActions`, which is a `Future`: `await` it, or a
failed expectation is never reported.

- **Requests:** `get(path, headers:, params:)`; `post`, `put` and
  `patch(path, json:, body:, headers:)` (`json` is encoded with
  `Content-Type: application/json`; `body` is a `String` or bytes, sent as
  is); `delete(path, headers:)`. For anything else,
  `perform(MockRequestBuilder(...))`: the builder takes the method, a path
  whose `{name}` placeholders are filled from a list
  (`MockRequestBuilder(HttpMethod.get, '/api/books/{isbn}', ['978-0'])`),
  and has `headers`, `params`, `cookies`, `principal`, `content(...)` and
  `json(...)`.
- **Expectations:** `andExpect(status:, contentType:, headers:, body:,
  json:)` checks only what is given. `contentType` matches compatible
  types (`application/json` matches `application/json;charset=utf-8`);
  `body` and `json` take a value or a matcher. A failure names the request
  and shows the whole response. A `json:` check on a body that is not JSON
  throws a `FormatException` rather than reporting a failed expectation.
- **The result:** `andDo((result) => ...)` runs code with it;
  `andReturn()` (or `await`) gives the `MvcResult`, with `request` and
  `response` (`statusCode`, `headers`, `cookies`, `bodyText`, `bodyBytes`,
  `json`).
- **Server-sent events:** the result is ready as soon as the headers are
  out. Read the events as they come from `result.response.eventStream`
  (`events` holds those so far), and end the stream with
  `result.cancel()`.
- **Uploads:** `mvc.multipart(path, files: [...], params: {...})` sends a
  `multipart/form-data` body through the server's multipart parsing and
  limits. `MockMultipartFile('cover', 'dune.png', 'image/png', bytes)` is a
  file; one without a file name and with `application/json` is a JSON part
  for `@RequestPart`. Downloads are read from `result.response.bodyBytes`;
  send `Range` or `If-Modified-Since` headers like any other.
- **WebSocket endpoints** (`spring_boot_starter_websocket`):
  `await mvc.webSocket('/ws/chat')` performs the handshake in memory and
  returns the client's `WebSocketSession`. A refused handshake throws a
  `WebSocketException` with the status and body.
- **`RequestPostProcessor`s** change a request just before it is sent: a
  logged-in user, a CSRF token, a header. Add one to a request with
  `builder.with_(processor)`, or to every request with
  `MockMvc(app.getBean<DispatcherHandler>(), defaultPostProcessors: [...])`.
  `spring_boot_starter_security/testing.dart` provides `user(...)`,
  `jwt()`, `csrf()` and others.

Spring (Java):

```java
mockMvc.perform(get("/api/books/1111"))
    .andExpect(status().isOk())
    .andExpect(jsonPath("$.title").value("Dune"));
```

Some clients need a real socket: a Feign client, `dart:io`'s `HttpClient`,
a WebSocket client. For them, start a real server on a free port:

```dart
final app = springBootTest(springApplication, webEnvironment: WebEnvironment.randomPort);

test('over HTTP', () async {
  final url = 'http://localhost:${app.localServerPort}/api/books/1111';
  ...
});
```

| `webEnvironment` | Spring | Server |
|---|---|---|
| `WebEnvironment.mock` (default) | `MOCK` | none; use `app.mockMvc` |
| `WebEnvironment.randomPort` | `RANDOM_PORT` | a real one on a free port; the context counts as started once it listens; `app.localServerPort` gives the port (`local.server.port`) |
| `WebEnvironment.definedPort` | `DEFINED_PORT` | a real one on `server.port`; the start fails when the port is taken |
| `WebEnvironment.none` | `NONE` | none; `app.mockMvc` still works |

`app.localServerPort` throws a `StateError` when no real server runs.
`app.mockMvc` throws a `StateError` without the web starter.

In a test class: `@SpringBootTest(webEnvironment:
WebEnvironment.randomPort)`, a `@LocalServerPort() late int port;` field,
and an `@Autowired() late MockMvc mvc;` field. `@AutoConfigureMockMvc()` on
the class states the intent as in Spring, but is not required.

## Testing auto-configuration: `ApplicationContextRunner`

This is the tool for starter authors. A starter's auto-configuration must
react to its surroundings: create a bean by default, back off when the
application declares its own, change with a property, fail on a bad value.
Starting a whole application for each case would be slow and would read
its config files. The runner starts a small context per test with only the
modules and properties you give it. Application tests use `springBootTest`
instead.

```dart
final runner = const ApplicationContextRunner()
    .withAutoConfiguration(neonCacheAutoConfiguration);

test('creates a cache by default', () {
  runner.run((context) {
    expect(context, hasSingleBean<Cache>());
  });
});

test('backs off for the application cache', () {
  // The application's own Cache, registered before the auto-configuration.
  runner.withBean<Cache>(AppCache.new).run((context) {
    expect(context, hasSingleBean<Cache>()); // a missing back-off gives two
    expect(context.getBean<Cache>(), isA<AppCache>());
  });
});

test('rejects a negative size', () {
  runner.withPropertyValues(['neon.cache.size=-1']).run((context) {
    expect(context, hasFailed(isA<BeanCreationException>()));
  });
});
```

The runner is immutable: each `with...` method returns a new runner, so a
base runner can be shared and extended in each test. It reads no config
files, and the environment is empty unless set. `@ConfigurationProperties`
beans are bound and relaxed names work, as in an application.

| Method | What it does |
|---|---|
| `withAutoConfiguration(module, [metadata])` | adds an auto-configuration module under test. Pass its `@AutoConfigurationModule` as `metadata` when it has an `order`, `before` or `after`: Dart cannot read the annotation of a variable at run time. The modules are sorted as Spring Boot sorts them (by `order`, then name, then `before` / `after`), whatever order they were added in |
| `withUserConfiguration(module)` | adds an application module, registered before the auto-configuration, so its beans are seen by the conditions |
| `withBean<T>(supplier, name:)` | registers a bean before the configurations; every run gets a new instance from `supplier`. A `@ConditionalOnMissingBean` backs off; a missing back-off shows up as a second bean, or as a failed start when the names clash. It never replaces a bean |
| `withBeanOverride<T>(instance, name:)` | replaces a bean after the configurations were registered, like a `BeanOverride`. It hides back-off mistakes: use `withBean` to test back-offs |
| `withPropertyValues(['a=b', 'c: d', 'flag'])` | properties as `key=value` or `key:value`, split at the first `=` or `:` and trimmed; no separator gives an empty value. They win over every other source |
| `withSystemEnvironment({...})` | environment variables, added to those of earlier calls |
| `withInitializer(initializer)` | an `ApplicationContextInitializer` called before the refresh; initializers run in the order they were added (their `order` is not used) |
| `withParent(context)` | a parent context, for a starter that runs in a child context |
| `withAllowBeanDefinitionOverriding(bool)` | lets a definition replace another of the same name; off by default |
| `withAllowCircularReferences(bool)` | `false` is the default and the only working value; `true` fails every run with an `UnsupportedError`, since circular references are always an error here |

`run` passes the context to the body and closes it with `close()` when the
body returns. A context that failed to start is passed too, instead of
throwing: check it with `hasFailed()` or `context.startupFailure`. For a
body that awaits, use `runAsync`: the context is refreshed with
`refreshAsync()` and closed with `closeAsync()` once the returned future
completes. With `run`, the context would be closed at the body's first
`await`.

```dart
test('calls the client', () async {
  await runner.runAsync((context) async {
    expect(await context.getBean<CatalogClient>().find('1'), isNotNull);
  });
});
```

No web server starts in a runner: it sets
`spring.test.web-environment=mock`. Add
`withPropertyValues(['spring.test.web-environment=random-port'])` for a
real one.

Spring (Java):

```java
new ApplicationContextRunner()
    .withConfiguration(AutoConfigurations.of(NeonCacheAutoConfiguration.class))
    .withPropertyValues("neon.cache.size=-1")
    .run(context -> assertThat(context).hasFailed());
```

## Matchers

| Matcher | Passes when the context has |
|---|---|
| `hasSingleBean<T>()` | exactly one bean of `T` |
| `hasBean<T>()` | at least one bean of `T` |
| `doesNotHaveBean<T>()` | no bean of `T` |
| `hasBeanNamed('name')` | a bean with that name or alias |
| `hasFailed([matcher])` | failed to start (an `AssertableApplicationContext` only); with a matcher, the error must match it |

They accept the context of `ApplicationContextRunner`, a `springBootTest`
handle, or any `ListableBeanFactory` such as an application context. On
failure they list the beans found, or the reason the context did not
start. As in AssertJ, beans of parent contexts (`withParent`) count too.

## Checking logs: `captureLogs`

`captureLogs` records what is logged through `SpringLog` during each test,
so a test can check that code warns or logs an error instead of throwing.
Call it once in `main` or a `group`, outside the tests:

```dart
final logs = captureLogs(level: SpringLogLevel.debug);

test('warns about slow payments', () {
  checkout.pay(slowOrder);
  expect(logs.messages, contains('slow payment'));
  expect(logs.atLevel(SpringLogLevel.warning), hasLength(1));
  expect(logs.ofLogger('neon.checkout'), isNotEmpty); // and its child loggers
});
```

Every test starts with an empty capture. Records are captured after the
loggers' own levels filtered them; `level` sets `SpringLog.level` during
each test and puts the old level back afterwards. `records`, `messages` and
`text` give what was logged; `atLevel` is exact (warnings do not include
errors).

Spring Boot's `OutputCaptureExtension` captures everything the process
prints; this captures `SpringLog` records only.

## Test classes

The same tests can be written as classes, the way Spring writes them. The
generator (`spring_core_dart_generator`, already a dev dependency of the
application) turns each class into the functions above:

```dart
import 'spring/checkout.test.spring.dart'; // generated

@SpringBootTest()
@ActiveProfiles(['test'])
class CheckoutTest {
  @TestBean()
  final PaymentGateway gateway = FakeGateway(); // replaces the only PaymentGateway

  @Autowired()
  late Checkout checkout;

  @Test()
  void paysThroughTheFake() => checkout.pay(10);
}

void main() => runSpringTests();
```

Every annotation, the generated code and the build errors are described in
the [testing guide](../docs/testing.md).

## Differences from Spring

- **Functions first.** `springBootTest` is a function for the tests of a
  `main` or `group`; test classes with `@SpringBootTest()` are generated
  into it. There are no test slices (`@WebMvcTest`, `@DataJpaTest`, ...)
  and no `@TestConfiguration`: pass extra modules to the
  `SpringApplication`, or use `ApplicationContextRunner` for a part of the
  configuration.
- **`MockMvc` needs no `@AutoConfigureMockMvc`.** `app.mockMvc` (or an
  `@Autowired() late MockMvc mvc;` field) always works with the web
  starter. `andExpect` takes named checks (`status:`, `json:` with
  matchers) instead of `status().isOk()` and `jsonPath(...)`. There is no
  `WebTestClient` or `TestRestTemplate`: use a Feign client or
  `HttpClient` against `localServerPort`.
- **`BeanOverride` takes a ready-made object** of your own, like
  `@TestBean`. There are no generated mocks or spies and no automatic
  reset between tests (`@MockitoBean(reset)`): use any mock library and
  reset in `setUp`. Without an existing bean, the instance is added.
- **`ApplicationContextRunner.withBean`** takes a supplier and the type as
  a type argument (`withBean<Cache>(AppCache.new)`), not a class; there is
  no constructor-arguments variant. `withBeanOverride` has no Boot
  counterpart.
- **`withAutoConfiguration(module, metadata)`** takes the module's
  `@AutoConfigurationModule` by hand; the modules are then sorted like
  `AutoConfigurations.of(...)`.
- **No circular references:** `withAllowCircularReferences(true)` fails
  every run with an `UnsupportedError` (there are no early references);
  `false` is the default, as in Boot.
- **No context cache across test files:** each `springBootTest` starts its
  own context, shared by the tests of its `main` or `group`.
- **`@DirtiesContext` on a class restarts the context after each of its
  tests,** as Spring's `classMode = AFTER_EACH_TEST_METHOD`. Spring's
  default for a class, `AFTER_CLASS`, closes the context once the class is
  done so later classes get a new one; here each class has its own
  context, closed after its tests anyway, so that default would change
  nothing. There is no `classMode` or `methodMode`.
- **`dynamicProperties` is a parameter**, not an annotated static method
  (test classes have `@DynamicPropertySource()`); there are no
  `DynamicPropertyRegistrar` beans.
- **The environment is empty** unless `systemEnvironment` sets it; Java
  tests see the machine's variables.
- **`captureLogs` replaces `OutputCaptureExtension`** for `SpringLog`
  output only.

## Name clash

`package:test` (through `matcher`) and `spring_core_dart` both define
`Description` (`spring_core_dart`'s is the `@Description` annotation). It
only matters when a test file uses it:
`import 'package:test/test.dart' hide Description;`.
