## 0.7.2

- README: the link goes to the package's own page on farum-azula.org, and what the README says was checked against the code and brought up to date.
- The package's page on pub.dev links its documentation, [farum-azula.org](https://farum-azula.org) (`documentation` in `pubspec.yaml`).

## 0.7.1

- No changes of its own; released with the family version 0.7.1.

## 0.7.0

- No changes of its own; released with the family version 0.7.0.

## 0.6.3

### Changes

- The generated test files are in `test/spring_gen/` (was `test/spring/`): import `spring_gen/<name>.test.spring.dart`.

## 0.6.2

### Changes

- `@TestPropertySource`, `@SpringBootTest` and the test resource directories document and use `resources:`; `classpath:` still works with a warning (see `spring_core_dart`).

## 0.6.1

- test(containers): labels unique per run — CI runs the docker tests twice at once and one run saw the (#19)
- feat(flutter): the desktop window from properties — title bar, initia… (#18)

## 0.6.0

### Changes

- Containers in tests, for any image, in `package:spring_boot_starter_test/containers.dart` (a library of its own: it needs `dart:io`, and its `Container` annotation would clash with Flutter's widget): `@Testcontainers()`, `@Container()` (a static field, started once before the class's context and removed after it) and `@ServiceConnection()` (the container's connection properties become dynamic properties of the context, which win over every other source; a `@DynamicPropertySource` method runs after the containers started); `GenericContainer` (`withEnv`, `withEnvironment`, `withCommand`, `withEntrypoint`, `withExposedPorts`, `withCopyFile`, `withCopyContent`, `withLabel`, `withHealthCheck`, `waitingFor`, `withStartupTimeout`, `withReuse`; `host`, `mappedPort`, `baseUrl`, `getLogs`, `execInContainer`, `start`, `stop`); the wait strategies `Wait.forListeningPort()`, `forLogMessage(regex, times)`, `forHttp(path)`, `forHealthcheck()` and `forAll`; the modules `PostgresContainer` (`jdbcUrl` and `url` in the data starter's URL form, `spring.datasource.url`, `username` and `password`) and `KeycloakContainer` (realm import, admin credentials, `spring.security.oauth2.resourceserver.jwt.issuer-uri` and `spring.security.oauth2.client.provider.<id>.issuer-uri`); `TestContainers`, which the generated code calls (and a test written as functions can). Without Docker a class is skipped with the reason; with `CONTAINERS_REQUIRED=true` (or `@Testcontainers(disabledWithoutDocker: false)`) it fails.
- `DockerClient`: the Docker Engine API over the daemon's Unix socket (`DOCKER_HOST`, `/var/run/docker.sock`, Docker Desktop's, Colima's, Rancher Desktop's and the rootless daemon's sockets) or `tcp://`, on `dart:io`, without a package: `ping`, `version`, `imageExists`, `pullImage`, `createContainer`, `putFiles` (a tar archive written by hand), `startContainer`, `containerLogs` (demultiplexed into lines), `inspectContainer`, `exec`, `listContainers`, `stopContainer`, `removeContainer`; errors carry the daemon's message. Windows' named pipe, TLS and registry credentials are not supported yet.
- Every container is labelled with the id of the run (`org.testcontainers.sessionId`), and the reaper of Testcontainers, the `testcontainers/ryuk` image, removes the run's containers when the process dies (even `kill -9`): the run keeps a TCP connection to it, which drops with the process. `TESTCONTAINERS_RYUK_DISABLED=true` switches it off, `TESTCONTAINERS_RYUK_CONTAINER_IMAGE` names another image. `withReuse(true)` keeps a container for the next run, found by a hash of its configuration (off when `CI` is set).
- `PostgresContainer` is ready when `database system is ready to accept connections` was logged twice (the image's temporary server, then the real one; as Testcontainers' `PostgreSQLContainer` waits, counting the lines printed before the wait began), the port accepts connections and the server answers the protocol's first message (`SSLRequest`) through the published port: a client no longer meets `Connection reset by peer` right after `start()`.
- Tests tagged `docker` (the client, the containers, the wait strategies, the reaper, Keycloak and PostgreSQL) are skipped without Docker; `dart_test.yaml` declares the tag.

### Fixed

- Stopping a container started with auto-remove failed on Linux with 409 "removal of container … is already in progress": the daemon removes it on its own once stopped; `DockerClient.removeContainer` treats that answer like a container already gone, and returns once the container no longer exists (a listing right after never shows it).
- A reset of a socket the containers support opened failed whatever test was running (`SocketException: Connection reset by peer`, in a `setUpAll`, on Linux's Docker only in practice): a socket that was written to completes its `done` with the error that ended it, and nobody listened to it, so it surfaced as an uncaught error that `package:test` charged to the running test. The connection to the reaper (kept open for the whole run) and the probes of `Wait.forListeningPort()` and `PostgresContainer` now handle it. A cut connection to the reaper is logged at debug level (`spring_boot_starter_test.containers.reaper`), forgotten, and registered again in the background and at the next container start; the containers stay protected meanwhile.

## 0.5.0

### Breaking

- `BeanOverride.named` (a `@TestBean(name: ...)` field) also registers the fake under its type argument, the field's type (unless it is `Object`), as Spring registers the override.

### Changes

- `BeanOverride.named(types: [...])` registers the fake under its own types instead of the replaced bean's, for a fake that implements only some of the original's interfaces; the generator fills them in for a `@TestBean(name: ...)` field whose value is created with a constructor.

## 0.4.3

- Flutter security (#15)
- feat: single sign-on with OAuth 2.0 / OpenID Connect (spring_boot_sta… (#11)
- docs: the READMEs and docs/ rewritten: what it is, why and when you need it, an example, then Spring (#10)

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- feat: spring_security_core, spring_boot_starter_security and a CI quality gate

## 0.3.2

- feat: spring_boot_starter_web, WebSocket server endpoints, uploads and downloads

## 0.3.1

- **Test classes:** the annotations `@SpringBootTest`, `@ActiveProfiles`, `@TestPropertySource`, `@TestEnvironment`, `@DynamicPropertySource`, `@ContextInitializer`, `@TestBean`, `@DirtiesContext`, `@Test`, `@TestOptions`, `@Disabled`, `@Tag`, `@DisplayName`, `@BeforeAll`, `@BeforeEach`, `@AfterEach`, `@AfterAll`, `@Nested` and `@CapturedOutput`, turned into tests by `spring_core_dart_generator` (`void main() => runSpringTests();`). See `docs/testing.md`.
- `SpringBootTestContext.findBean`, `getBeans`, `value` and `optionalValue` (an optional bean, every bean of a type, a `@Value` expression).
- `BeanOverride.named(instance, name:)`: replaces the bean with that name, keeping the types it is registered under but its own class and adding the fake's, so a fake of another class can replace it.
- Re-exports `MockHttpTransport` and `MockWebSocketTransport` (`spring_web_dart`'s `testing.dart`, now a dependency), like `MockRestServiceServer` in `spring-test`: tests of Feign and WebSocket clients need no other dependency.

## 0.3.0

- feat(spring_boot_starter_flutter): themes from properties, free reads in Spring widgets

## 0.2.3

- add spring application handling
- docs(spring_boot_starter_flutter): add an example for pub.dev

## 0.2.2

- ci: run only the tests of the packages a change affects

## 0.2.1

- feat: spring_boot_starter_flutter, @Log, --dart-define properties, Flutter counter example

## 0.2.0

- `hasSingleBean`, `hasBean` and `doesNotHaveBean` count the beans of the parent contexts too (`withParent`), like AssertJ's default `Scope.INCLUDE_ANCESTORS`.
- `BeanOverride` by type replaces the single `@Primary` bean among several (it failed); `BeanOverride(name:)` takes an alias and replaces the bean it names, keeping every alias (it failed).
- Breaking: initializers are `ApplicationContextInitializer` objects (`ApplicationContextInitializer.of((context) => ...)`), following `spring_boot_dart`.
- `ApplicationContextRunner.runAsync` refreshes with `refreshAsync()` (asynchronous `@PostConstruct` / init methods are awaited; a failed start is closed with `closeAsync()`).
- `ApplicationContextRunner` sorts its auto-configurations like Boot's `AutoConfigurations.of(...)`: by name, `order`, then `before` / `after` (`withAutoConfiguration(module, metadata)` takes the module's `@AutoConfigurationModule`).
- `ApplicationContextRunner.withParent`, `withAllowBeanDefinitionOverriding` and `withAllowCircularReferences` (`true` fails the run: circular references are always an error).
- `BeanOverride` names a new bean like `withBean` (`defaultBeanName`: `URLService` stays, type arguments are left out).
- Breaking: `ApplicationContextRunner.withBean<T>(supplier)` takes a supplier like Boot's `withBean(type, supplier)`: each run gets a new instance (an instance was reused after a previous run destroyed it).
- `springBootTest` closes its context with `closeAsync()` (asynchronous `@PreDestroy` and lifecycle stops are awaited); `ApplicationContextRunner.runAsync` too.

## 0.1.7

- `ApplicationContextRunner` attaches relaxed names to its environment, like an application started by `SpringApplication` (`app.read-timeout` finds `app.readTimeout`)
- breaking: `ApplicationContextRunner.withBean` registers an extra bean before the configurations are processed, like Boot's (a `@ConditionalOnMissingBean` backs off; a missing back-off gives a second bean), instead of replacing definitions; `withBeanOverride` replaces a bean like `BeanOverride`; `ApplicationContextRunner.beans` holds bean definitions, the overrides moved to `overrides`
- `withPropertyValues` accepts `key:value` like `TestPropertyValues`; breaking: values are trimmed
- `springBootTest(dynamicProperties:)` with `DynamicPropertyRegistry`: properties evaluated when the context starts (`@DynamicPropertySource`)
- `app.output` no longer holds the startup line (Spring Boot's startup info is now logged through `SpringLog`)
- `springBootTest` keeps the application's auto-configuration order and exclusions, and does not register the shutdown hook (it closes its own context)

## 0.1.6

- update road map
- ci: release with a button on main, skip new packages when publishing; shorter pubspec descriptions

## 0.1.5

- add feign runner + web socket runner
- add web core + faign starter for http calling

## 0.1.4

- feat: ObjectMapper in core — JSON on generated metadata (@Introspected, @JsonProperty/@JsonIgnore/@JsonInclude/@JsonCreator/@JsonValue), spring.jackson.* in Boot

## 0.1.3

- add scheduling + cache starters
- fix extension add aop docs

## 0.1.2

- ci: release only from the release branch; fix version-dependent test; Node 24 actions
- fix tests

## 0.1.1

- Example on pub.dev (`example/`) and a description within 180 characters.

## 0.1.0

Initial version.

- `springBootTest` (`@SpringBootTest`): the `test/resources/` test
  classpath (`resourceDirectories`), `propertyFiles`
  (`@TestPropertySource`), properties, profiles, environment,
  initializers, `markDirty` (`@DirtiesContext`), restored `SpringLog`
  state.
- `BeanOverride` (`@MockitoBean` / `@TestBean`), keeping name, aliases,
  qualifiers and `@Primary` / `@Fallback`.
- `ApplicationContextRunner` with `AssertableApplicationContext`.
- Matchers: `hasSingleBean`, `hasBean`, `doesNotHaveBean`, `hasBeanNamed`,
  `hasFailed`.
- `captureLogs`.
- Built on `test_api` + `matcher` for `flutter_test` compatibility.
