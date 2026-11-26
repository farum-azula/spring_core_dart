/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_cache`.
///
/// Applications do not import it: the generated `*.spring.dart` file does
/// (the modules below are marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the modules.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache_auto_configuration.dart';
import 'package:spring_boot_starter_cache/src/config/config.dart';

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
  imports: [cacheConfigBeans],
);

/// The startup check of the cache starter (`cacheStartupChecks`): the
/// `cacheOperationValidator`, which checks the cache annotations of every
/// proxied bean when it is created, so a wrong one stops the start.
///
/// In the build by `spring.main.startup-checks.enabled`: `true` in every
/// build, `false` in none, not set in debug builds only, so a
/// release build ships none of its code (a wrong annotation then fails at
/// the member's first call).
///
/// Registered after the main module: without its `cacheInterceptor` (the
/// main module excluded by name) the validator steps back.
@AutoConfigurationModule(
  build: AutoConfigurationBuild('spring.main.startup-checks.enabled'),
  after: ['springBootStarterCacheAutoConfiguration'],
)
final BeanModule springBootStarterCacheStartupChecksAutoConfiguration =
    BeanModule(
      'springBootStarterCacheStartupChecksAutoConfiguration',
      cacheStartupChecks,
    );
