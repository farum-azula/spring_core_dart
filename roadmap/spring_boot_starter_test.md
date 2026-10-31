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

### Containers in tests (planned with the data starter, the owner's request)

As Spring Boot with Testcontainers (`@Testcontainers`, `@Container`,
`@ServiceConnection`, 3.1+): a test starts the database or service it
needs in Docker, the application is wired to it by itself, and the
container is removed afterwards. Without Docker the test is skipped with
the reason, or fails where Docker is required (`CONTAINERS_REQUIRED`,
set in CI, as `DESKTOP_SECRET_STORE_REQUIRED`).

```dart
@SpringBootTest()
class BookRepositoryTest {
  // Started once for the class (static), removed at the end; its host and
  // port become spring.datasource.* for the test's context.
  @Container()
  @ServiceConnection()
  static final postgres = PostgresContainer('postgres:17-alpine');

  @Container()
  @ServiceConnection()
  static final redis = RedisContainer('redis:7.4-alpine');

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

  @Autowired()
  late BookRepository books;

  @Test()
  Future<void> savesAndFinds() async { /* ... */ }
}
```

- **Our own Docker client, no third-party package:** the Docker Engine
  API over its socket (`/var/run/docker.sock`, `DOCKER_HOST`, Docker
  Desktop's and Colima's sockets, Windows' named pipe later): pull,
  create, start, logs, inspect (the mapped ports), stop, remove. A few
  hundred lines on `dart:io`'s `HttpClient` with a Unix socket.
- **Wait strategies:** a log line (`Wait.forLogMessage`), a port that
  accepts connections, an HTTP status, the container's health check.
- **Cleanup that survives a crash:** containers labelled with the test
  run's id and removed at the end; a reaper (Testcontainers' Ryuk: a
  small container that removes the run's containers when the test
  process's connection to it closes) so a killed `dart test` leaves
  nothing behind.
- **Ready-made containers:** `PostgresContainer`, `RedisContainer`,
  `KeycloakContainer` (realm import), later `MongoContainer`; each knows
  its `@ServiceConnection` properties (`spring.datasource.*`,
  `spring.data.redis.*`, the issuer URI).
- **Reuse between runs** (`withReuse(true)`, Testcontainers' reuse, off
  in CI): a local container kept alive across `dart test` runs, found by
  a hash of its configuration, for fast iterations.
- **The existing Docker-based tests** (the Keycloak e2e tests that need a
  Keycloak started by hand or by CI) move to containers.
- **Development, not tests:** Spring Boot's Docker Compose support
  (`spring-boot-docker-compose`, 3.1+): with a `compose.yaml` next to the
  application, `dart run` starts its services and wires their connection
  properties, `spring.docker.compose.lifecycle-management` stops them;
  only in development (`spring.docker.compose.enabled`), never in an AOT
  executable or a Flutter app.

Not in Flutter apps or on the web (they have no Docker); the containers
part of the starter is `dart:io` only, behind a conditional import.

### Open questions

- A shared context between classes with the same configuration (Spring's
  context cache): not planned while startup is fast.
- `@MockitoBean` as a name for `@TestBean`, for people coming from Spring:
  only if a mocking library is chosen (`mocktail` is a third-party package,
  so not a dependency of the starter).
- Test slices (`@WebMvcTest`-like) once the web and data starters exist.
