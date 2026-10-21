/// Discovered by the generator of every application that depends on
/// `spring_boot_starter_logging` (see `AutoConfigurationModule`).
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/logging_auto_configuration.dart';

/// Installs the logging system and exposes `LoggingSystem` / `LogBuffer`.
@AutoConfigurationModule()
final BeanModule springBootStarterLoggingAutoConfiguration = BeanModule(
  'springBootStarterLoggingAutoConfiguration',
  [...loggingAutoConfiguration],
);
