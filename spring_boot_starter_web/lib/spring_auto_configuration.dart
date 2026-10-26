/// The auto-configuration of spring_boot_starter_web, found by the
/// generator like Spring Boot's `AutoConfiguration.imports`.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/web_auto_configuration.dart';

// The auto-configurations this starter builds on (logging, and through it spring_boot_dart's), so a test of an application that lists only this starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

/// The beans of the web starter (`webMvcAutoConfiguration`).
@AutoConfigurationModule()
final BeanModule springBootStarterWebAutoConfiguration = BeanModule(
  'springBootStarterWebAutoConfiguration',
  [...webMvcAutoConfiguration],
);
