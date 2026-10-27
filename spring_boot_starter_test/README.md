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
  spring_boot_starter_test: ^0.4.0
  test: ^1.25.0          # or flutter_test
```

*In the guides:* [server, 12. Testing](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#12-testing), [app, 11. Testing](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#11-testing).

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

## Web tests: `MockMvc`, `webEnvironment`

With [`spring_boot_starter_web`](../spring_boot_starter_web/README.md),
`app.mockMvc` calls the controllers in memory, like Spring's `MockMvc`:
the same dispatcher a real server runs (filters, mapping, binding, error
handling), no socket. By default (`WebEnvironment.mock`) a test starts no
server at all.

```dart
final app = springBootTest(springApplication);

test('finds a book', () async {
  final mvc = app.mockMvc;
  await mvc.get('/api/books/1111').andExpect(
    status: 200,
    contentType: MediaType.applicationJson,
    headers: {'X-Trace': 'on'},
    json: {'isbn': '1111', 'title': 'Dune'},       // or a matcher: containsPair('title', 'Dune')
  );
  await mvc.get('/api/books', params: {'q': 'dune'}).andExpect(json: hasLength(1));
  await mvc
      .post('/api/books', json: {'isbn': '', 'title': ''})
      .andExpect(status: 400, contentType: MediaType.applicationProblemJson);
  await mvc.delete('/api/books/2222').andExpect(status: 204);
});
```

- `get(path, headers:, params:)`, `post` / `put` / `patch(path, json:, body:, headers:)`,
  `delete(path, headers:)`, and `perform(MockRequestBuilder(...))` for
  anything else (`MockRequestBuilder(HttpMethod.get, '/api/books/{isbn}', ['978-0'])`
  with `headers`, `params`, `cookies`, `principal`, `content`, `json`).
- `andExpect(status:, contentType:, headers:, body:, json:)` (`body` and
  `json` take a value or a matcher; a failure names the request and shows
  the response), `andDo((result) => ...)`, `andReturn()` (an `MvcResult`
  with `request` and `response`). `ResultActions` is a `Future`, so
  `await` it.
- **Server-sent events:** the result is ready as soon as the headers are
  out; read the events as they come from `result.response.eventStream`
  (`events` for those so far) and end the stream with `result.cancel()`.
- **Uploads:** `mvc.multipart(path, files: [...], params: {...})` sends a
  `multipart/form-data` request; `MockMultipartFile('cover', 'dune.png',
  'image/png', bytes)` is a file, one without a file name and with
  `application/json` a JSON part for `@RequestPart`. Downloads are read
  from `result.response.bodyBytes` (with `Range` / `If-Modified-Since`
  headers as needed).
- **WebSocket endpoints** (`spring_boot_starter_websocket`):
  `await mvc.webSocket('/ws/chat')` opens a connection in memory and
  returns the client's `WebSocketSession`.
- **`RequestPostProcessor`** changes a request before it is performed
  (Spring's `.with(...)`; Spring Security's `user(...)` and `csrf()` are
  ones): `builder.with_(processor)`, or for every request
  `MockMvc(app.getBean<DispatcherHandler>(), defaultPostProcessors: [...])`.

A real server on a free port, for clients that need a socket (a Feign
client, `dart:io`'s `HttpClient`, a WebSocket client):

```dart
final app = springBootTest(springApplication, webEnvironment: WebEnvironment.randomPort);

test('over HTTP', () async {
  final url = 'http://localhost:${app.localServerPort}/api/books/1111';
  ...
});
```

| `webEnvironment` | Spring | Server |
|---|---|---|
| `WebEnvironment.mock` (default) | `MOCK` | none; `app.mockMvc` |
| `WebEnvironment.randomPort` | `RANDOM_PORT` | a real one on a free port: `app.localServerPort` (`local.server.port`); the context starts once it listens |
| `WebEnvironment.definedPort` | `DEFINED_PORT` | a real one on `server.port` |
| `WebEnvironment.none` | `NONE` | none |

As a test class: `@SpringBootTest(webEnvironment: WebEnvironment.randomPort)`,
`@LocalServerPort() late int port;`, and `@Autowired() late MockMvc mvc;`
(`@AutoConfigureMockMvc()` on the class states it, as in Spring; it is
not required).

`ApplicationContextRunner` starts no server either (it sets
`spring.test.web-environment=mock`); add
`withPropertyValues(['spring.test.web-environment=random-port'])` for a
real one.

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

- `springBootTest` is a function for the tests of a `main` or `group`
  (test classes with `@SpringBootTest` are generated into it); no test
  slices (`@WebMvcTest`, `@DataJpaTest`, ...) and no
  `@TestConfiguration`: pass extra modules to the `SpringApplication`.
- `webEnvironment` defaults to `mock` as in Spring, but `MockMvc` needs no
  `@AutoConfigureMockMvc`: `app.mockMvc` (or an `@Autowired MockMvc`
  field) always works with the web starter. `andExpect` takes named
  expectations (`status:`, `json:` with matchers) instead of
  `status().isOk()` and `jsonPath(...)`; there is no `WebTestClient` or
  `TestRestTemplate` (use a Feign client or `HttpClient` against
  `localServerPort`).
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
