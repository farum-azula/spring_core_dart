/// Testing support for `spring_boot_dart` applications and starters, like
/// `spring-boot-starter-test`:
///
/// - `springBootTest`: the whole application for a test file
///   (`@SpringBootTest`), with properties, profiles, dynamic properties
///   (`DynamicPropertyRegistry`) and `BeanOverride`s;
/// - `ApplicationContextRunner`: small contexts to test auto-configuration;
/// - matchers: `hasSingleBean`, `hasBean`, `doesNotHaveBean`,
///   `hasBeanNamed`, `hasFailed`;
/// - `captureLogs`: records logged through `SpringLog` in each test;
/// - `MockHttpTransport` and `MockWebSocketTransport` (from
///   `spring_web_dart`): prepared answers for Feign and WebSocket clients,
///   like Spring's `MockRestServiceServer`;
/// - test classes: `SpringBootTest`, `Autowired` fields, `TestBean`,
///   `Test` methods and the other annotations, turned into tests by
///   `spring_core_dart_generator` (`void main() => runSpringTests();`).
///
/// Built on `test_api` and `matcher`, so it works with both `package:test`
/// and `flutter_test`. Re-exports `spring_boot_dart` and the transport mocks
/// of `spring_web_dart` (`MockHttpTransport`, `MockWebSocketTransport`).
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
