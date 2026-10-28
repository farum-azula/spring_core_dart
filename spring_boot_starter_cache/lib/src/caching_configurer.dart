import 'package:spring_boot_starter_cache/src/cache.dart';
import 'package:spring_boot_starter_cache/src/cache_error_handler.dart';
import 'package:spring_boot_starter_cache/src/cache_resolver.dart';
import 'package:spring_boot_starter_cache/src/key_generator.dart';

/// Sets, in one place, what every cache annotation uses unless it says
/// otherwise: the cache manager, the cache resolver, the key generator and
/// the handler for errors thrown by caches.
///
/// Most applications do not need it: the starter's defaults suit them, and
/// a single annotation can already name its own `keyGenerator`,
/// `cacheManager` or `cacheResolver`. Use it to change a default for the
/// whole application, typically the error handler, so that a cache that is
/// down only means "no cache". Declare one bean of it (usually a
/// `@Configuration` class that mixes it in) and override the methods to
/// change. A method returning `null` keeps the default:
///
/// | Method | Default |
/// |---|---|
/// | [cacheManager] | the `CacheManager` bean |
/// | [cacheResolver] | a `SimpleCacheResolver` of the cache manager |
/// | [keyGenerator] | `SimpleKeyGenerator` |
/// | [errorHandler] | `SimpleCacheErrorHandler` (rethrows) |
///
/// The methods are called once, when the first cache operation needs them.
/// Return objects (or beans injected into the configuration) rather than
/// marking the methods `@Bean`: `@Configuration` classes are not proxied in
/// Dart, so calling a `@Bean` method creates a second instance.
///
/// ```dart
/// // Normalized isbn keys everywhere, and a broken cache only logs.
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
  /// The cache manager of operations that name none; `null` (the default)
  /// for the `CacheManager` bean. Not used when [cacheResolver] returns a
  /// resolver.
  CacheManager? cacheManager() => null;

  /// The cache resolver of operations that name neither a cache manager
  /// nor a resolver; `null` (the default) for a `SimpleCacheResolver` of
  /// the cache manager.
  CacheResolver? cacheResolver() => null;

  /// The key generator of operations that set neither `key` nor
  /// `keyGenerator`; `null` (the default) for `SimpleKeyGenerator`, which
  /// makes the key from the arguments.
  KeyGenerator? keyGenerator() => null;

  /// What happens when a cache throws; `null` (the default) for
  /// `SimpleCacheErrorHandler`, which lets the error reach the caller of
  /// the cached method.
  CacheErrorHandler? errorHandler() => null;
}
