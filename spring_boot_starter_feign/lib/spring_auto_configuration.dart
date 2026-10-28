/// The beans the Feign starter adds to an application: the HTTP transport
/// and the factory that builds the `@FeignClient` clients.
///
/// The generator finds this library in every dependency that has one and
/// registers its module (it is marked `@AutoConfigurationModule()`), so
/// listing the starter in `pubspec.yaml` is enough; Spring Boot finds its
/// auto-configurations through `AutoConfiguration.imports` the same way.
/// Applications do not import it; a test that builds a context by hand
/// may name [springBootStarterFeignAutoConfiguration].
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_feign/src/feign_auto_configuration.dart';

// The auto-configurations this starter builds on (logging, and through it
// spring_boot_dart's), so a test of an application that lists only this
// starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

/// The Feign starter's auto-configuration module: the HTTP transport and
/// the factory of the `@FeignClient` beans (`feignAutoConfiguration`).
@AutoConfigurationModule()
final BeanModule springBootStarterFeignAutoConfiguration = BeanModule(
  'springBootStarterFeignAutoConfiguration',
  [...feignAutoConfiguration],
);
