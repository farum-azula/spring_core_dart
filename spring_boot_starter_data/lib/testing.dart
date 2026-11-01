/// What a test of the data layer needs: the slice of a `@DataTest` class
/// (the application's data beans, an in-memory database) and the
/// transaction that is rolled back around each test.
///
/// A test class marked `@DataTest()` needs none of it by hand:
/// `spring_core_dart_generator` writes the calls into the generated
/// `test/spring/<name>.test.spring.dart`. Import this library to write the
/// same tests as functions, with `springBootTest` of
/// `spring_boot_starter_test` (a `dev_dependency`; this starter does not
/// depend on it, the generated code and the test join the two):
///
/// ```dart
/// import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
/// import 'package:spring_boot_starter_data/testing.dart';
/// import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
/// import 'package:test/test.dart';
///
/// import '../bin/shop.spring.dart'; // springApplication
///
/// void main() {
///   // The repositories of the shop on an in-memory SQLite database.
///   final data = DataTestSetup(springApplication);
///   final app = springBootTest(
///     springApplication,
///     properties: data.properties,
///     initializers: [data.initializer],
///   );
///
///   test('saves a book, rolled back afterwards', () {
///     return runInTestTransaction(app.context, () async {
///       final books = app.getBean<BookRepository>();
///       await books.save(Book(title: 'Dune'));
///       expect(await books.count(), 1);
///     });
///   });
/// }
/// ```
///
/// Spring (Java): `@DataJdbcTest`, `@AutoConfigureTestDatabase` and the
/// transaction of `@Transactional` tests (`spring-boot-test-autoconfigure`
/// and `spring-test`).
library;

export 'package:spring_boot_starter_data/src/testing/data_test_setup.dart';
export 'package:spring_boot_starter_data/src/testing/data_test_slice.dart';
export 'package:spring_boot_starter_data/src/testing/test_database.dart';
export 'package:spring_boot_starter_data/src/testing/test_transaction.dart';
