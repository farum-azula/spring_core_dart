/// Tools for testing a `spring_boot_dart` application or a starter: start
/// the application in a test, swap beans for fakes, call controllers
/// without a server, and check what an auto-configuration creates.
///
/// Import it in test files only (it is a `dev_dependency`). It re-exports
/// `spring_boot_dart` and the test doubles of `spring_web_dart`, so one
/// import is enough. What it offers, by task:
///
/// - Test the whole application: `springBootTest` starts it once for the
///   tests of a `main` or `group`, with test properties, profiles,
///   `DynamicPropertyRegistry` values and `BeanOverride` fakes. The same
///   tests can be written as classes with `@SpringBootTest()`,
///   `@Autowired()` fields, `@TestBean()` and `@Test()`;
///   `spring_core_dart_generator` turns them into these functions
///   (`void main() => runSpringTests();`).
/// - Test controllers: `MockMvc` (`app.mockMvc`) sends requests through
///   the web starter's dispatcher in memory.
/// - Test an auto-configuration: `ApplicationContextRunner` starts a small
///   context per test, without config files.
/// - Check a context: the matchers `hasSingleBean`, `hasBean`,
///   `doesNotHaveBean`, `hasBeanNamed` and `hasFailed`.
/// - Check logging: `captureLogs` records what `SpringLog` logged during
///   each test.
/// - Fake remote services: `MockHttpTransport` and `MockWebSocketTransport`
///   (from `spring_web_dart`) give prepared answers to Feign and WebSocket
///   clients, like Spring's `MockRestServiceServer`.
///
/// It is built on `test_api` and `matcher`, not on `package:test`, so it
/// works with both `package:test` and `flutter_test`.
library;

export 'package:spring_boot_dart/spring_boot_dart.dart';
export 'package:spring_boot_starter_test/src/application_context_runner.dart';
export 'package:spring_boot_starter_test/src/bean_override.dart';
export 'package:spring_boot_starter_test/src/dynamic_property_registry.dart';
export 'package:spring_boot_starter_test/src/log_capture.dart';
export 'package:spring_boot_starter_test/src/matchers.dart';
export 'package:spring_boot_starter_test/src/mock_mvc.dart';
export 'package:spring_boot_starter_test/src/spring_boot_test.dart';
export 'package:spring_boot_starter_test/src/test_annotations.dart';
export 'package:spring_web_dart/testing.dart';
