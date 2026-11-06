/// The starter's auto-configuration. Applications never import it: the
/// generator finds this file in every dependency and adds its module to
/// the generated application, which is what makes the dependency alone
/// enough. A test that builds a context by hand can name it.
library;

import 'package:spring_boot_actuator/spring_boot_actuator.dart';
import 'package:spring_boot_starter_actuator/src/actuator_auto_configuration.dart';
import 'package:spring_boot_starter_actuator/src/config/config.dart';

// The auto-configurations this starter builds on (the web starter, and
// through it logging and spring_boot_dart's), so a test of an application
// that lists only this starter can name them.
export 'package:spring_boot_starter_web/spring_auto_configuration.dart';

/// The actuator's beans: the health, info and mappings endpoints, their
/// contributors, and their answers over the web starter. After the web
/// starter's module, whose dispatcher it adds a handler mapping to.
@AutoConfigurationModule(after: ['springBootStarterWebAutoConfiguration'])
final BeanModule springBootStarterActuatorAutoConfiguration = BeanModule(
  'springBootStarterActuatorAutoConfiguration',
  [...actuatorAutoConfiguration],
  imports: [actuatorProperties, actuatorWebProperties],
);
