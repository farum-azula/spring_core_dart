/// The beans the Data starter adds to an application: the data sources and
/// templates of its SQL databases, the mapping context, the entity
/// converter, the in-memory store, the auditing handler (with
/// `@EnableDataAuditing`) and the factory that builds the repositories.
///
/// The generator finds this library in every dependency that has one and
/// registers its module (it is marked `@AutoConfigurationModule()`), so
/// listing the starter in `pubspec.yaml` is enough; Spring Boot finds its
/// auto-configurations through `AutoConfiguration.imports` the same way.
/// Applications do not import it; a test that builds a context by hand
/// may name [springBootStarterDataAutoConfiguration].
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/data_auto_configuration.dart';
import 'package:spring_boot_starter_data/src/data_source_auto_configuration.dart';
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
