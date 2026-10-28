/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_cache`.
///
/// Applications do not import it: the generated `*.spring.dart` file does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache_auto_configuration.dart';

// The auto-configurations this starter builds on (logging, and through it
// spring_boot_dart's), so a test of an application that lists only this
// starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

/// The beans that switch caching on: the default `CacheManager` built from
/// `spring.cache.*`, and the interceptor that runs `@Cacheable`,
/// `@CachePut` and `@CacheEvict` around the methods of proxied beans.
@AutoConfigurationModule()
final BeanModule springBootStarterCacheAutoConfiguration = BeanModule(
  'springBootStarterCacheAutoConfiguration',
  [...cacheAutoConfiguration],
);
