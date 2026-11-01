/// Containers in tests, for any image: Docker started from a test class or
/// a test, wired to the application, and removed afterwards.
///
/// Import it in test files that use containers:
///
/// ```dart
/// import 'package:spring_boot_starter_test/containers.dart';
/// ```
///
/// What it offers:
///
/// - `@Testcontainers()`, `@Container()` and `@ServiceConnection()` for
///   test classes (the generator starts the containers before the context
///   and removes them after it);
/// - `GenericContainer`: any image, with `withEnv`, `withCommand`,
///   `withExposedPorts`, `withCopyFile`, `waitingFor` (`Wait`) and
///   `withReuse`;
/// - the modules `PostgresContainer` and `KeycloakContainer`, which know
///   their `@ServiceConnection` properties;
/// - `DockerClient`: the Docker Engine API on `dart:io`, with no package,
///   for what the containers do not cover.
///
/// It is a library of its own, not part of `spring_boot_starter_test.dart`:
/// the annotation `Container` would clash with Flutter's widget of that
/// name in widget tests, and the classes need `dart:io` (they do not exist
/// on the web). Containers are removed by the test run, and by a reaper
/// (Testcontainers' Ryuk) when it dies; see `docs/testing.md`.
///
/// Spring (Java): Testcontainers (`@Testcontainers`, `@Container`,
/// `GenericContainer`, `PostgreSQLContainer`) and Spring Boot's
/// `@ServiceConnection`.
library;

export 'package:spring_boot_starter_test/src/containers/containers_annotations.dart';
// dart:io is the default, so that analysis (which takes the default) sees the
// classes; only a compiler for the web takes the empty stub.
export 'package:spring_boot_starter_test/src/containers/containers_io.dart'
    if (dart.library.js_interop) 'package:spring_boot_starter_test/src/containers/containers_stub.dart';
