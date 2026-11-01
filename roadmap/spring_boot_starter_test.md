# spring_boot_starter_test

## Done

- `springBootTest(...)`: the whole application once per test file
  (`@SpringBootTest`), with `args`, `properties`, `propertyFiles`,
  `dynamicProperties`, `profiles`, `systemEnvironment`, `overrides`
  (`BeanOverride`), `initializers`, `test/resources/` first on the
  classpath, `markDirty()` for a fresh context.
- `ApplicationContextRunner` for auto-configuration tests.
- Matchers: `hasSingleBean`, `hasBean`, `doesNotHaveBean`, `hasBeanNamed`,
  `hasFailed`.
- `captureLogs()`.
- Works under `package:test` and `flutter_test`.

Flutter gets its own starter on top of this one:
[spring_boot_starter_flutter_test.md](spring_boot_starter_flutter_test.md).

## Done: test classes with annotations

Tests written as in Spring: a class with `@SpringBootTest`, `@Autowired`
fields, `@TestBean` fakes and `@Test` methods, turned by the generator into
the functions above. Documented in [docs/testing.md](../docs/testing.md).

```dart
import 'spring/checkout.test.spring.dart';

@SpringBootTest(args: ['--shop.name=Night Books'])
@ActiveProfiles(['dev', 'test'])
class CheckoutTest {
  @Autowired()
  late Checkout checkout;

  @TestBean(name: 'sandbox')
  final gateway = FakeGateway();

  @Test('checkout pays through the fake')
  void pays() {
    checkout.pay(3);
    expect(gateway.charged, [3]);
  }
}

void main() => runSpringTests();
```

- **Annotations** (`lib/src/test_annotations.dart`): `SpringBootTest`,
  `ActiveProfiles`, `TestPropertySource`, `TestEnvironment`,
  `DynamicPropertySource`, `ContextInitializer`, `TestBean`,
  `DirtiesContext`, `Test`, `DisplayName`, `Disabled`, `Tag`,
  `TestOptions`, `BeforeAll`, `BeforeEach`, `AfterEach`, `AfterAll`,
  `Nested`, `CapturedOutput`; `Autowired`, `Qualifier` and `Value` are the
  framework's. `package:test`'s `@Skip`, `@Timeout`, `@Tags`... only
  annotate libraries, hence `@Disabled`, `@Tag` and `@TestOptions`.
- **Runtime**: `SpringBootTestContext.findBean`, `getBeans`, `value`,
  `optionalValue`; `BeanOverride.named` (replaces a bean by name keeping
  its types); `package:spring_boot_starter_test/generated.dart` for the
  generated code.
- **Builder** `spring_core_dart_generator:spring_test`
  (`lib/src/test_builder.dart`): `test/{{}}_test.dart` →
  `test/spring/{{}}.test.spring.dart` (its own folder, one file per test
  file). It reads the test file as syntax and copies its
  imports, so bean types are never written out (`instance.checkout =
  app.getBean();`). Finds the `@SpringBootApplication` entry point of the
  package, or the one named by `application:`. Build errors with the
  file, line and column (docs/testing.md section 16).
- **Tests**: `spring_core_dart_generator/test/spring_test_builder_test.dart`
  (the generated code for every annotation, every build error),
  `spring_boot_starter_test/test/test_class_support_test.dart` (the
  runtime), and running classes in `example/server_guide/test/`
  (`boot_class_test.dart`, the class version of `boot_test.dart`;
  `lifecycle_class_test.dart`, every annotation and the order they run in).

## Next

1. **Editor**: the `dart_spring` language server shows run buttons on
   `@Test` methods (tests in a group named after the class) and completes
   the annotations; snippets `sbt` (test class), `tst` (test method).
2. **Open to other starters**: the Flutter test starter
   ([spring_boot_starter_flutter_test.md](spring_boot_starter_flutter_test.md))
   adds `@WidgetTest`, `@TargetPlatformTest` and `@Golden` to the same
   generated file; the builder needs a way for a starter to add method
   annotations and what they generate.

### Done: containers in tests (the owner's request, November 2026)

As Spring Boot with Testcontainers (`@Testcontainers`, `@Container`,
`@ServiceConnection`, 3.1+): a test starts the database or service it
needs in Docker, the application is wired to it by itself, and the
container is removed afterwards, for any image. Documented in
[docs/testing.md](../docs/testing.md), section 20.

```dart
@SpringBootTest()
class BookRepositoryTest {
  // Started once for the class (static), removed at the end; its URL, user
  // and password become spring.datasource.* for the test's context.
  @Container()
  @ServiceConnection()
  static final postgres = PostgresContainer('postgres:17-alpine');

  // Any image: wait for a log line or a port, map ports, set properties.
  @Container()
  static final keycloak = GenericContainer('quay.io/keycloak/keycloak:26.8')
      .withCommand(['start-dev', '--import-realm'])
      .withCopyFile('../example/keycloak/neon-realm.json',
          '/opt/keycloak/data/import/neon-realm.json')
      .withExposedPorts([8080])
      .waitingFor(Wait.forHttp('/realms/neon').forStatusCode(200));

  @DynamicPropertySource()
  static void properties(DynamicPropertyRegistry registry) => registry.add(
      'spring.security.oauth2.client.provider.keycloak.issuer-uri',
      () => '${keycloak.baseUrl(8080)}/realms/neon');
  ...
}
```

- **A library of its own**, `package:spring_boot_starter_test/containers.dart`
  (not part of the main one: it needs `dart:io`, nothing exists on the web,
  and its `Container` annotation would clash with Flutter's widget in widget
  tests). Its dart:io part is the default of a conditional export; only a
  compiler for the web takes the empty stub.
- **Our own Docker client, no package** (`DockerClient`): the Docker Engine
  API over the daemon's Unix socket (`DOCKER_HOST` `unix://` or `tcp://`,
  `/var/run/docker.sock`, Docker Desktop's, Colima's, Rancher Desktop's and
  the rootless daemon's sockets) on `dart:io`'s `HttpClient`: ping, version,
  pull (a clear error for a missing image), create (environment, command,
  ports published on random free host ports of the loopback interface,
  labels, a health check, copied files through a tar archive written by
  hand), start, logs (demultiplexed into lines), inspect, exec, list, stop,
  remove; errors carry the daemon's message.
- **`GenericContainer`** with `withEnv`, `withEnvironment`, `withCommand`,
  `withEntrypoint`, `withExposedPorts`, `withCopyFile`, `withCopyContent`,
  `withLabel`, `withHealthCheck`, `waitingFor`, `withStartupTimeout`,
  `withReuse`; `host`, `mappedPort`, `baseUrl`, `getLogs`, `execInContainer`;
  the waits `Wait.forListeningPort()` (a connection that stays open: Docker
  Desktop's forwarder accepts and drops), `forLogMessage(regex, times)`,
  `forHttp(path).forStatusCode(...)`, `forHealthcheck()`, `forAll`.
- **Modules:** `PostgresContainer` (`jdbcUrl` and `url` in the data starter's
  form; `spring.datasource.url`, `username`, `password`) and
  `KeycloakContainer` (realm import, admin credentials, the issuer URI as
  `spring.security.oauth2.resourceserver.jwt.issuer-uri` and
  `spring.security.oauth2.client.provider.<id>.issuer-uri`). The test starter
  does not import the data or security starters: the properties are strings.
  No `RedisContainer` (Redis is postponed; `GenericContainer` covers it).
- **Cleanup that survives a crash:** every container is labelled with the
  run's id; Testcontainers' own reaper, the `testcontainers/ryuk` image,
  is driven with its simple protocol (the run sends
  `label=org.testcontainers.sessionId=<id>` to its TCP port and keeps the
  connection; when the process dies, even with `kill -9`, the connection
  drops and Ryuk removes the containers ten seconds later). One reaper per
  run, a run being one isolate (a test file under `dart test`); the
  connection closes with the last container, so a script can exit.
  `TESTCONTAINERS_RYUK_DISABLED=true` opts out.
- **The builder** reads `@Container`, `@ServiceConnection` and
  `@Testcontainers` (also on `@DataTest` classes): the containers start in a
  `setUpAll` before the `@BeforeAll` methods and the context and are removed
  in a `tearDownAll` declared first (so last); service connections go into
  the dynamic property source before the `@DynamicPropertySource` methods.
  Static fields only (instance fields would start after the context).
- **Without Docker** a class is skipped with the reason (a check for the
  daemon's socket when the tests are declared: `package:test` cannot skip
  from a `setUpAll`, and Dart has no synchronous socket to ping with);
  `CONTAINERS_REQUIRED=true` (CI sets it) or
  `@Testcontainers(disabledWithoutDocker: false)` fails instead.
- **Reuse** (`withReuse(true)`, opt-in, off when `CI` is set): found by a
  hash of the configuration, no run id, `stop()` leaves it.
- **The data starter:** `@DataTest(replaceDatabase: false)` with a
  `@ServiceConnection` `PostgresContainer` runs the slice on it (migrations,
  rollback per test); the data starter's `postgres` tests start their own
  container when `SPRING_TEST_POSTGRES_URL` is not set (CI keeps its service
  container for them).
- **Tests** (tag `docker`, skipped without Docker, their own CI job):
  the client against the daemon, `GenericContainer` (waits, files, health
  check, a container that exits, the startup timeout, reuse, PostgreSQL), a
  child process killed with `kill -9` whose container the reaper removes, a
  Keycloak smoke test; without a daemon the tar archives, the endpoint, the
  configuration, the wait strategies against a fake container and the
  modules' properties; the builder's output and errors
  (`spring_core_dart_generator/test/spring_test_builder_test.dart`); and in
  the data starter a `@DataTest` and a `@SpringBootTest` class on containers.

Left:

- Windows' named pipe (`npipe:////./pipe/docker_engine`; `tcp://` works),
  TLS to a remote daemon and registry credentials (`~/.docker/config.json`).
- Docker Compose support for development, not tests: Spring Boot's
  `spring-boot-docker-compose` (3.1+): with a `compose.yaml` next to the
  application, `dart run` starts its services and wires their connection
  properties, `spring.docker.compose.lifecycle-management` stops them; only
  in development (`spring.docker.compose.enabled`), never in an AOT
  executable or a Flutter app.
- The Keycloak end-to-end tests of the security packages (they expect a
  Keycloak started by hand or by CI, `example/keycloak`) move to
  `KeycloakContainer`.
- More modules (`MongoContainer`...), networks between containers,
  `withCreateContainerCmdModifier`-like access to the create request, the
  transaction matrix of the data starter on a container.

### Open questions

- A shared context between classes with the same configuration (Spring's
  context cache): not planned while startup is fast.
- `@MockitoBean` as a name for `@TestBean`, for people coming from Spring:
  only if a mocking library is chosen (`mocktail` is a third-party package,
  so not a dependency of the starter).
- Test slices: `@DataTest` (the data starter's `@DataJdbcTest`) is done, built
  on `springBootTest` and the generator (the starters never depend on each
  other); a `@WebMvcTest`-like slice for the web starter is still open.
