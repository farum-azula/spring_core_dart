/// Testing support for `spring_boot_dart` applications and starters, like
/// `spring-boot-starter-test`:
///
/// - [springBootTest]: the whole application for a test file
///   (`@SpringBootTest`), with properties, profiles and [BeanOverride]s;
/// - [ApplicationContextRunner]: small contexts to test auto-configuration;
/// - matchers: [hasSingleBean], [hasBean], [doesNotHaveBean],
///   [hasBeanNamed], [hasFailed];
/// - [captureLogs]: records logged through `SpringLog` in each test.
///
/// Built on `test_api` and `matcher`, so it works with both `package:test`
/// and `flutter_test`. Re-exports `spring_boot_dart`.
library;

export 'package:spring_boot_dart/spring_boot_dart.dart';
export 'package:spring_boot_starter_test/src/application_context_runner.dart';
export 'package:spring_boot_starter_test/src/bean_override.dart';
export 'package:spring_boot_starter_test/src/log_capture.dart';
export 'package:spring_boot_starter_test/src/matchers.dart';
export 'package:spring_boot_starter_test/src/spring_boot_test.dart';
