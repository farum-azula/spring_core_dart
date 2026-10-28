/// The beans the web starter adds to an application: the server, the
/// dispatcher, the controller mapping, sessions and uploads.
///
/// The generator finds this library in every dependency that has one and
/// registers its module, so listing the starter in `pubspec.yaml` is
/// enough; Spring Boot finds its auto-configurations through
/// `AutoConfiguration.imports` the same way. Applications do not import
/// it; a test that builds a context by hand may name
/// [springBootStarterWebAutoConfiguration].
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/web_auto_configuration.dart';

// The auto-configurations this starter builds on (logging, and through it
// spring_boot_dart's), so a test of an application that lists only this
// starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

/// The web starter's auto-configuration module: the bean definitions of
/// `webMvcAutoConfiguration`.
@AutoConfigurationModule()
final BeanModule springBootStarterWebAutoConfiguration = BeanModule(
  'springBootStarterWebAutoConfiguration',
  [...webMvcAutoConfiguration],
);
