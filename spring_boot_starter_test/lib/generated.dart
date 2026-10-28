/// The names that the code generated for test classes uses; not for test
/// files to import.
///
/// `spring_core_dart_generator` writes `test/spring/<name>.test.spring.dart`
/// for each test file with `@SpringBootTest()` classes, and that file
/// calls `springBootTest`, `group`, `test`, `setUp` and the other hooks
/// through this library. It imports it with a prefix (`as _sbt`), so the
/// generated calls never clash with names the test file declares or
/// imports.
library;

export 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
export 'package:test_api/scaffolding.dart'
    show group, setUp, setUpAll, tearDown, tearDownAll, test;
