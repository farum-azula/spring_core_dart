// Annotations of test classes that exercise the data layer, Spring's
// `@DataJdbcTest`:
//
//   @DataTest()
//   class BookRepositoryTest {
//     @Autowired()
//     late BookRepository books;
//
//     @Test()
//     Future<void> savesABook() async { ... } // rolled back afterwards
//   }
//
//   void main() => runSpringTests();
//
// They carry no behaviour and no test dependency: `spring_core_dart_generator`
// reads them from the test file and writes `<name>.test.spring.dart`, which
// starts the slice with the machinery of `spring_boot_starter_test` and the
// classes of `package:spring_boot_starter_data/testing.dart`.

/// Marks a test class that runs against the data layer of the application
/// only: its repositories, an in-memory database and a transaction around
/// every test that is rolled back afterwards.
///
/// Use it to test repositories (derived queries, `@Query`, mappings,
/// migrations) without the services, controllers and other components that
/// sit on top of them. The test class is written like a `@SpringBootTest`
/// class: `@Autowired()` fields, `@Test()` methods, `@ActiveProfiles`,
/// `@TestPropertySource`, `@TestBean`, `@BeforeEach`...
///
/// What the context holds:
///
/// - **The application's data beans**: its repositories, the
///   `EntityIntrospections` of its entities, the driver of its database
///   package, and the beans of the types the starter looks up (a
///   `DataSource`, a `PlatformTransactionManager`, an `AuditorAware`, a
///   `DateTimeProvider`, a `NamingStrategy`, a `DataStore`, a
///   `JdbcTemplate`...), plus the configuration class of an
///   `@EnableDataAuditing`. The other beans of the application (services,
///   controllers, components) are left out, as Spring's slice leaves out
///   the `@Component` beans. [include] adds more.
/// - **The auto-configuration of the starter** (and of logging); that of
///   other starters (web, cache, security...) is left out.
/// - **An in-memory database** when the application configures a SQL one
///   (see [replaceDatabase]); without a data source the repositories keep
///   using the in-memory store.
///
/// Each test (with its `@BeforeEach` and `@AfterEach` methods) runs in a
/// transaction of every `PlatformTransactionManager` its repositories use
/// (or of the one [transactionManager] names), which is
/// rolled back at the end, so tests never see each other's data; the
/// repositories and `@Transactional` methods join it. [Commit] and
/// [Rollback] change that. A test that needs a transaction of its own
/// (`Propagation.requiresNew`) needs a second connection, which the
/// in-memory SQLite database does not have: see
/// `docs/testing.md`.
///
/// The annotation does nothing at run time. The generator turns the class
/// into a call of `DataTestSetup` and `runInTestTransaction` (from
/// `package:spring_boot_starter_data/testing.dart`) around `springBootTest`.
///
/// ```dart
/// import 'spring_gen/book_repository.test.spring.dart'; // generated
///
/// @DataTest()
/// class BookRepositoryTest {
///   @Autowired()
///   late BookRepository books;
///
///   @Test()
///   Future<void> findsABookByItsTitle() async {
///     await books.save(Book(title: 'Dune', year: 1965));
///     expect(await books.findByTitle('Dune'), hasLength(1));
///   } // rolled back: the next test starts with no books
/// }
///
/// void main() => runSpringTests();
/// ```
///
/// Spring (Java): `@DataJdbcTest` (with `@AutoConfigureTestDatabase` and
/// the rollback of `@Transactional` tests):
/// ```java
/// @DataJdbcTest
/// class BookRepositoryTest {
///   @Autowired BookRepository books;
///   @Test void findsABookByItsTitle() { ... }
/// }
/// ```
final class DataTest {
  /// Every option has a default: `@DataTest()` alone starts the package's
  /// only application without arguments, with `test/resources/` on the
  /// classpath, and replaces its database.
  const DataTest({
    this.application,
    this.args = const [],
    this.properties = const {},
    this.resourceDirectories = const ['test/resources'],
    this.include = const [],
    this.replaceDatabase = true,
    this.transactionManager = '',
  });

  /// The entry point of the application to start, as a path in the package
  /// (`bin/admin.dart`, `lib/main.dart`, `test/data/app/data_app.dart`).
  ///
  /// Leave it `null` when the package has one `@SpringBootApplication`
  /// entry point in `bin/` or `lib/`. Like `@SpringBootTest(application:)`.
  final String? application;

  /// The command-line arguments the application starts with, such as
  /// `--spring.sql.migration.enabled=false`. Empty by default.
  final List<String> args;

  /// Properties for the tests, which win over the config files, the
  /// environment and [args]; `@TestPropertySource` ones win over them.
  /// Empty by default. Spring's `@DataJdbcTest(properties = ...)`.
  final Map<String, Object?> properties;

  /// Directories put first on the classpath while the tests run
  /// (`test/resources` by default), as for `@SpringBootTest`.
  final List<String> resourceDirectories;

  /// Beans of the application to add to the slice, by the types of their
  /// classes: a service a repository's test needs, a configuration class
  /// (it brings its `@Bean` methods).
  ///
  /// A configuration class whose `@Bean` method makes a data bean (an
  /// `AuditorAware`, a `NamingStrategy`) is in the slice already, but its
  /// other `@Bean` methods are not. A bean of the list that needs other
  /// beans of the application fails the start as usual: add them too. A
  /// type no bean of the application has fails the start.
  ///
  /// Spring: `@Import` on the test class, or `includeFilters`.
  final List<Type> include;

  /// Whether the SQL databases the properties configure
  /// (`spring.datasource.url`, `spring.datasources.<name>.url`) are
  /// replaced by in-memory SQLite ones (the default). Spring's
  /// `@AutoConfigureTestDatabase(replace = ANY)`.
  ///
  /// The replacement needs the `sqlite3` package among the dependencies of
  /// the application (the generator wires its driver): without it the start
  /// fails and says so. With `false` the configured database is used as it
  /// is, for example one a container started: the tests still roll back.
  /// Spring's `replace = NONE`.
  ///
  /// The schema comes from the application's migrations
  /// (`lib/resources/db/migration`) or SQL scripts; without either the
  /// tables are created from the entities (`spring.data.jdbc.schema=create`)
  /// unless that property is set.
  final bool replaceDatabase;

  /// The name of the transaction manager bean the tests run in (its bean
  /// name or qualifier, as in `@Transactional(transactionManager: ...)`);
  /// empty, the default, runs each test in a transaction of every manager
  /// the application's repositories use.
  ///
  /// Name one when the application has several databases and the test
  /// touches one of them: only that database is rolled back, and the
  /// repositories of the others write for real. A test fails with a
  /// `StateError` when no manager has the name. Spring's
  /// `@Transactional(transactionManager: 'name')` on a test class.
  final String transactionManager;
}

/// Says whether the transaction of a [DataTest] test is rolled back at its
/// end: `@Rollback(false)` commits it, `@Rollback()` rolls it back (what
/// happens without any annotation).
///
/// It goes on a test method, on a test class, or on a `@Nested` group; the
/// innermost one wins. A failing test is always rolled back.
///
/// ```dart
/// @DataTest()
/// @Rollback(false) // every test of the class commits
/// class SeededTest { ... }
/// ```
///
/// Spring (Java): `org.springframework.test.annotation.Rollback`.
final class Rollback {
  /// Rolls the transaction back, or commits it with `Rollback(false)`.
  const Rollback([this.value = true]);

  /// Whether the transaction is rolled back at the end of the test.
  final bool value;
}

/// Commits the transaction of a [DataTest] test instead of rolling it back;
/// the same as `@Rollback(false)`.
///
/// Use it when a test checks what only a commit does (the constraints a
/// database checks when it commits, the `afterCommit` callbacks). The data
/// stays: later tests see it, so put the tests that depend on each other's
/// data in one class, or clean up in `@AfterEach`. On a test method, a
/// class or a `@Nested` group. A failing test is rolled back even so.
///
/// ```dart
/// @Test()
/// @Commit()
/// Future<void> keepsTheBook() async => ...;
/// ```
///
/// Spring (Java): `org.springframework.test.annotation.Commit`.
final class Commit {
  /// Marks the test or the class.
  const Commit();
}
