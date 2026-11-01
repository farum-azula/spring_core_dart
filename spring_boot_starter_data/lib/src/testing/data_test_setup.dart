import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/src/testing/data_test_slice.dart';
import 'package:spring_boot_starter_data/src/testing/test_database.dart';

/// What makes a test context the slice of a `@DataTest`: the data beans of
/// an application and the starter's auto-configuration, an in-memory
/// database, and nothing else.
///
/// It gives `springBootTest` two things for the application it describes:
/// [properties], which leave out the auto-configuration of the other
/// starters, and an [initializer], which leaves out the application's other
/// beans ([DataTestSlice]) and replaces its databases ([TestDatabase]). The
/// generated code of a `@DataTest` class does it; in a test written as
/// functions, do it by hand, and wrap each test in `runInTestTransaction`:
///
/// ```dart
/// void main() {
///   final data = DataTestSetup(springApplication);
///   final app = springBootTest(
///     springApplication,
///     properties: data.properties,
///     initializers: [data.initializer],
///   );
///
///   test('saves a book', () => runInTestTransaction(app.context, () async {
///     await app.getBean<BookRepository>().save(Book(title: 'Dune'));
///   }));
/// }
/// ```
///
/// Spring (Java): the annotations of `@DataJdbcTest`:
/// `@TypeExcludeFilters`, `@AutoConfigureDataJdbc`,
/// `@AutoConfigureTestDatabase` and `@Transactional`.
final class DataTestSetup {
  /// The slice of [application]: its data beans, those of the types in
  /// [include], and the databases replaced unless [replaceDatabase] is
  /// false.
  DataTestSetup(
    SpringApplication application, {
    List<Type> include = const [],
    this.replaceDatabase = true,
  }) : include = List.unmodifiable(include),
       _modules = application.modules,
       _autoConfigurations = application.autoConfigurations;

  /// The beans added to the slice by the types of their classes.
  final List<Type> include;

  /// Whether the databases of the properties are replaced.
  final bool replaceDatabase;

  final List<BeanModule> _modules;
  final List<BeanModule> _autoConfigurations;

  /// The names of the auto-configuration modules a slice keeps: the core
  /// one, logging and the data starter's own.
  static List<String> get autoConfigurationNames => [
    springBootAutoConfiguration.name,
    springBootStarterLoggingAutoConfiguration.name,
    springBootStarterDataAutoConfiguration.name,
  ];

  /// The properties of the slice: `spring.autoconfigure.exclude` names the
  /// auto-configuration modules of the application that are not
  /// [autoConfigurationNames] (the web, cache, security... starters).
  ///
  /// Pass them to `springBootTest(properties:)` first, so the test's own
  /// properties can still add to or replace them.
  Map<String, Object?> get properties {
    final excluded = [
      for (final module in _autoConfigurations)
        if (!autoConfigurationNames.contains(module.name)) module.name,
    ];
    return {
      if (excluded.isNotEmpty)
        'spring.autoconfigure.exclude': excluded.join(','),
    };
  }

  /// The initializer of the slice, for `springBootTest(initializers:)`: it
  /// replaces the databases and leaves out the beans, in each context the
  /// test starts.
  ///
  /// It also adds the data starter's auto-configuration when the
  /// application lacks it. The generator puts the auto-configuration of
  /// every dependency into an application, so an application that lists the
  /// starter has it; the application of the starter's own tests (which is
  /// not a dependency of itself) does not.
  ApplicationContextInitializer get initializer =>
      ApplicationContextInitializer.of((context) {
        if (replaceDatabase) {
          TestDatabase(
            hasSqliteDriver: TestDatabase.hasSqliteDriverIn(
              DataTestSlice.applicationDefinitions(_modules),
            ),
          ).initialize(context);
        }
        if (!_autoConfigurations.any(
          (module) =>
              module.name == springBootStarterDataAutoConfiguration.name,
        )) {
          context.register(springBootStarterDataAutoConfiguration);
        }
        context.addBeanFactoryPostProcessor(
          DataTestSlice(_modules, include: include),
        );
      });
}
