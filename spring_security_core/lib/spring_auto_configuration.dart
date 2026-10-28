/// The package's auto-configuration, found by the code generator in every
/// application that depends on `spring_security_core`.
///
/// Applications do not import it: the generated `*.spring.dart` file does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/security_core_auto_configuration.dart';

// The auto-configurations this package builds on (logging, and through it
// spring_boot_dart's), so a test of an application that lists only this
// package can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

/// The beans that switch security on: method security for the
/// annotations, the authentication event publisher, and the
/// `AuthenticationManager` built from the application's user store.
@AutoConfigurationModule()
final BeanModule springSecurityCoreAutoConfiguration = BeanModule(
  'springSecurityCoreAutoConfiguration',
  [...securityCoreAutoConfiguration],
);
