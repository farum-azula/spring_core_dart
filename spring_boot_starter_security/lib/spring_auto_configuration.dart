/// Discovered by the generator of every application that depends on
/// `spring_boot_starter_security` (see `AutoConfigurationModule`).
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_security/src/config/security_auto_configuration.dart';

// The auto-configurations this starter builds on, so a test of an
// application that lists only this starter can name them.
export 'package:spring_boot_starter_web/spring_auto_configuration.dart';
export 'package:spring_security_core/spring_auto_configuration.dart';

/// The security filter chain, the default user and the JWT decoder.
@AutoConfigurationModule()
final BeanModule springBootStarterSecurityAutoConfiguration = BeanModule(
  'springBootStarterSecurityAutoConfiguration',
  [...securityAutoConfiguration],
);
