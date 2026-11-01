// Annotations of test classes that use containers, Spring's and
// Testcontainers' way of writing them:
//
//   @SpringBootTest()
//   @Testcontainers()
//   class BookRepositoryTest {
//     @Container()
//     @ServiceConnection()
//     static final postgres = PostgresContainer('postgres:17-alpine');
//     ...
//   }
//
// They carry no behaviour: spring_core_dart_generator reads them from the
// test file and writes the calls that start the containers before the
// context and remove them after it (see docs/testing.md, containers).

/// Marks a test class that uses containers; optional, as in Spring.
///
/// A class with `@Container()` fields starts them whether or not it has
/// this annotation. It only sets what happens without Docker: by default
/// the whole class is skipped, with the reason; with
/// `disabledWithoutDocker: false` it fails instead, as it does anywhere
/// when the environment variable `CONTAINERS_REQUIRED=true` is set (set it
/// in CI, so a missing Docker never goes unnoticed).
///
/// ```dart
/// @SpringBootTest()
/// @Testcontainers(disabledWithoutDocker: false) // fails without Docker
/// class BookRepositoryTest { ... }
/// ```
///
/// Spring (Java): `@Testcontainers`, whose `disabledWithoutDocker` is
/// `false` by default (here the default is to skip, as in a project
/// without Docker most tests still run).
final class Testcontainers {
  /// Marks the class; [disabledWithoutDocker] is `true` by default.
  const Testcontainers({this.disabledWithoutDocker = true});

  /// Whether the class is skipped (`true`) or fails (`false`) when Docker
  /// is not available. `CONTAINERS_REQUIRED=true` makes it fail either way.
  final bool disabledWithoutDocker;
}

/// Marks a static field that holds a container the tests need: it starts
/// once, before the class's context, and is removed after the last test.
///
/// The field's value is a `GenericContainer` or a module such as
/// `PostgresContainer`. It must be `static` (the context starts before
/// the test class is created, and one container serves all its tests)
/// and public; the containers start in the order of the fields. Add
/// [ServiceConnection] to wire the application to it, or read its
/// `host` and `mappedPort(...)` in a `@DynamicPropertySource` method,
/// which runs after the containers started.
///
/// ```dart
/// @Container()
/// static final redis = GenericContainer('redis:7.4-alpine')
///     .withExposedPorts([6379])
///     .waitingFor(Wait.forLogMessage('Ready to accept connections'));
///
/// @DynamicPropertySource()
/// static void redisUrl(DynamicPropertyRegistry registry) => registry.add(
///   'cache.redis.url',
///   () => 'redis://${redis.host}:${redis.mappedPort(6379)}',
/// );
/// ```
///
/// Spring (Java): Testcontainers' `@Container`, on a static field of a
/// class with `@Testcontainers`. Instance fields (a container per test)
/// are not supported: the context needs the container before the first
/// test.
final class Container {
  /// Marks the field.
  const Container();
}

/// Marks a [Container] field whose connection properties become properties
/// of the test's context: `PostgresContainer` sets `spring.datasource.url`,
/// `username` and `password`, `KeycloakContainer` the issuer URIs.
///
/// The properties are a dynamic property source, which wins over every
/// other source (`properties:`, the config files, the environment); a
/// `@DynamicPropertySource` method runs after them and can still change
/// one. The container must implement `ServiceConnectionProperties`; for any
/// other, register its properties in a `@DynamicPropertySource` method.
///
/// ```dart
/// @Container()
/// @ServiceConnection()
/// static final postgres = PostgresContainer('postgres:17-alpine');
/// ```
///
/// Spring Boot (Java): `@ServiceConnection` on a `@Container` field, which
/// registers a `ConnectionDetails` bean from the container.
final class ServiceConnection {
  /// Marks the field.
  const ServiceConnection();
}
