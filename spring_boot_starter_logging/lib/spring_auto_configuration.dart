/// Discovered by the generator of every application that depends on
/// `spring_boot_starter_logging` (see `AutoConfigurationModule`).
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/logging_auto_configuration.dart';

// The auto-configurations this starter builds on, so a test of an application
// that lists only this starter can name them
// (`ApplicationContextRunner()
// .withAutoConfiguration(springBootAutoConfiguration)`).
export 'package:spring_boot_dart/spring_auto_configuration.dart';

/// Installs the logging system and exposes `LoggingSystem` / `LogBuffer`.
@AutoConfigurationModule()
final BeanModule springBootStarterLoggingAutoConfiguration = BeanModule(
  'springBootStarterLoggingAutoConfiguration',
  [...loggingAutoConfiguration],
);
