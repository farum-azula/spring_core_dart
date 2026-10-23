import 'package:spring_boot_starter_cache/src/cache.dart';
import 'package:spring_boot_starter_cache/src/cache_error_handler.dart';
import 'package:spring_boot_starter_cache/src/cache_resolver.dart';
import 'package:spring_boot_starter_cache/src/key_generator.dart';

/// The defaults of the cache annotations, like Spring's
/// `CachingConfigurer`: declare one bean of it (usually a `@Configuration`
/// class mixing it in) and override what to change. A method returning
/// `null` keeps the default:
///
/// | Method | Default |
/// |---|---|
/// | [cacheManager] | the `CacheManager` bean |
/// | [cacheResolver] | a `SimpleCacheResolver` of the cache manager |
/// | [keyGenerator] | `SimpleKeyGenerator` |
/// | [errorHandler] | `SimpleCacheErrorHandler` (rethrows) |
///
/// The methods are called once, when the first cache operation needs them.
/// Return objects (or injected beans) from them rather than marking them
/// `@Bean`: `@Configuration` classes are not proxied in Dart, so calling a
/// `@Bean` method creates another instance.
///
/// ```dart
/// @Configuration()
/// class CacheSetup with CachingConfigurer {
///   @override
///   KeyGenerator keyGenerator() => const IsbnKeys();
///
///   @override
///   CacheErrorHandler errorHandler() => const LoggingCacheErrorHandler();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// @EnableCaching
/// class CacheSetup implements CachingConfigurer {
///   @Override
///   public KeyGenerator keyGenerator() { return new IsbnKeys(); }
///
///   @Override
///   public CacheErrorHandler errorHandler() {
///     return new LoggingCacheErrorHandler();
///   }
/// }
/// ```
abstract mixin class CachingConfigurer {
  /// The default cache manager; `null` for the `CacheManager` bean. Not
  /// used when [cacheResolver] returns a resolver.
  CacheManager? cacheManager() => null;

  /// The default cache resolver; `null` for a `SimpleCacheResolver` of the
  /// cache manager.
  CacheResolver? cacheResolver() => null;

  /// The default key generator; `null` for `SimpleKeyGenerator`.
  KeyGenerator? keyGenerator() => null;

  /// What happens when a cache throws; `null` for
  /// `SimpleCacheErrorHandler`.
  CacheErrorHandler? errorHandler() => null;
}
