/// The beans the Data starter adds to an application: the mapping context,
/// the entity converter, the in-memory store, the auditing handler (with
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

// The auto-configurations this starter builds on (logging, and through it
// spring_boot_dart's), so a test of an application that lists only this
// starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

/// The Data starter's auto-configuration module: the mapping context, the
/// converter, the stores and the factory of the repository beans
/// (`dataAutoConfiguration`).
@AutoConfigurationModule()
final BeanModule springBootStarterDataAutoConfiguration = BeanModule(
  'springBootStarterDataAutoConfiguration',
  [...dataAutoConfiguration],
);
