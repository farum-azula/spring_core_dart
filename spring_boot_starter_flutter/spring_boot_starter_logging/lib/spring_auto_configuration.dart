/// The starter's auto-configuration. Applications never import it: the
/// generator finds this file in every dependency and adds its module to
/// the generated application, which is what makes the dependency alone
/// enough. A test that builds a context by hand can name it.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/logging_auto_configuration.dart';

// The auto-configurations this starter builds on, so a test of an application
// that lists only this starter can name them
// (`ApplicationContextRunner()
// .withAutoConfiguration(springBootAutoConfiguration)`).
export 'package:spring_boot_dart/spring_auto_configuration.dart';

/// The beans that install the logging system when the context starts and
/// make `LoggingSystem` and `LogBuffer` injectable; all off with
/// `logging.enabled=false`.
@AutoConfigurationModule()
final BeanModule springBootStarterLoggingAutoConfiguration = BeanModule(
  'springBootStarterLoggingAutoConfiguration',
  [...loggingAutoConfiguration],
);
