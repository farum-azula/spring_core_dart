/// Discovered by the generator of every application that depends on
/// `spring_security_core` (see `AutoConfigurationModule`).
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/security_core_auto_configuration.dart';

// The auto-configurations this package builds on (logging, and through it
// spring_boot_dart's), so a test of an application that lists only this
// package can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

/// Method security, authentication events and the `AuthenticationManager`.
@AutoConfigurationModule()
final BeanModule springSecurityCoreAutoConfiguration = BeanModule(
  'springSecurityCoreAutoConfiguration',
  [...securityCoreAutoConfiguration],
);
