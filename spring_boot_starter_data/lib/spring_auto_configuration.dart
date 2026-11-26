/// The beans the Data starter adds to an application: the data sources and
/// templates of its SQL databases, the mapping context, the entity
/// converter, the in-memory store, the auditing handler (with
/// `@EnableDataAuditing`) and the factory that builds the repositories;
/// in debug builds, unless the configuration says otherwise,
/// its startup checks and its statement logging.
///
/// The generator finds this library in every dependency that has one and
/// registers its modules (they are marked `@AutoConfigurationModule()`),
/// so listing the starter in `pubspec.yaml` is enough; Spring Boot finds
/// its auto-configurations through `AutoConfiguration.imports` the same
/// way. Applications do not import it; a test that builds a context by
/// hand may name [springBootStarterDataAutoConfiguration], and the
/// switched modules with it.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/data_auto_configuration.dart';
import 'package:spring_boot_starter_data/src/data_source_auto_configuration.dart';
import 'package:spring_boot_starter_data/src/data_startup_checks.dart';
import 'package:spring_boot_starter_data/src/properties/properties_beans.dart';

// The auto-configurations this starter builds on (logging, and through it
// spring_boot_dart's), so a test of an application that lists only this
// starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

// What the build knows of the starter's stores (`memory`, `jdbc`): the
// generator reads the `@DataStoreDeclaration` constants this library
// declares or exports.
export 'src/store/data_store_declarations.dart';

/// The Data starter's auto-configuration module: the SQL data sources,
/// transaction managers and templates (`dataSourceAutoConfiguration`), the
/// mapping context, the converter, the stores and the factory of the
/// repository beans (`dataAutoConfiguration`).
@AutoConfigurationModule()
final BeanModule springBootStarterDataAutoConfiguration = BeanModule(
  'springBootStarterDataAutoConfiguration',
  // The SQL beans first: the in-memory transaction manager of
  // dataAutoConfiguration is only made when none of them made one.
  [...dataSourceAutoConfiguration, ...dataAutoConfiguration],
  imports: [dataConfigBeans],
);

/// The startup checks of the Data starter (`dataStartupChecks`): the
/// `transactionValidator`, which fails the start for a `@Transactional`
/// method that is not async or names a transaction manager that does not
/// exist, and the `dataFailureAnalyzer`, which explains a database that
/// fails the start.
///
/// In the build by `spring.main.startup-checks.enabled`: `true` in every
/// build, `false` in none, not set in debug builds only, so a profile or
/// a release build ships none of their code (a wrong `@Transactional` method
/// then fails at its first call).
///
/// Registered after the main module: without its `transactionInterceptor`
/// (the main module excluded by name) the validator steps back.
@AutoConfigurationModule(
  build: AutoConfigurationBuild('spring.main.startup-checks.enabled'),
  after: ['springBootStarterDataAutoConfiguration'],
)
final BeanModule springBootStarterDataStartupChecksAutoConfiguration =
    BeanModule(
      'springBootStarterDataStartupChecksAutoConfiguration',
      dataStartupChecks,
    );

/// The statement logging of the Data starter
/// (`sqlLoggingAutoConfiguration`): the `jdbcLogSettings` of
/// `spring.data.jdbc.show-sql`, `format-sql` and `show-parameters`, with
/// `slow-query-threshold`.
///
/// In the build by `spring.data.jdbc.show-sql`: `true` in the
/// configuration without a profile keeps it in every build, `false` in
/// none, not set in debug builds only (where a profile, a
/// `dev` one, can still turn it on when the application runs). Without it
/// the main module's `jdbcSlowQueryLogSettings` reads the slow-query
/// threshold alone: the slow statements are logged at warn in every build.
///
/// Registered before the main module, so its `jdbcLogSettings` is there
/// when `jdbcSlowQueryLogSettings` looks for one and steps back.
@AutoConfigurationModule(
  build: AutoConfigurationBuild('spring.data.jdbc.show-sql'),
  before: ['springBootStarterDataAutoConfiguration'],
)
final BeanModule springBootStarterDataSqlLoggingAutoConfiguration = BeanModule(
  'springBootStarterDataSqlLoggingAutoConfiguration',
  sqlLoggingAutoConfiguration,
);
