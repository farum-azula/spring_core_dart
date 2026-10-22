/// Discovered by the generator of every application that depends on
/// `spring_boot_starter_feign` (see `AutoConfigurationModule`).
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_feign/src/feign_auto_configuration.dart';

/// The HTTP transport and the factory of the `@FeignClient` beans.
@AutoConfigurationModule()
final BeanModule springBootStarterFeignAutoConfiguration = BeanModule(
  'springBootStarterFeignAutoConfiguration',
  [...feignAutoConfiguration],
);
