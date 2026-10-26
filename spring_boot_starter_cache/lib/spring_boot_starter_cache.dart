/// Caching for `spring_boot_dart` applications, like
/// `spring-boot-starter-cache`: `@Cacheable`, `@CachePut`, `@CacheEvict`,
/// `@Caching` and `@CacheConfig` on bean methods, a [CacheManager] with
/// time-to-live and size limits configured by `spring.cache.*`,
/// [CacheResolver]s and [CachingConfigurer] defaults.
///
/// ```dart
/// @Service()
/// class Books {
///   @Cacheable('books')
///   Book find(String isbn) => repository.load(isbn);
///
///   @CacheEvict('books', key: '#isbn')
///   void delete(String isbn) => repository.delete(isbn);
/// }
/// ```
///
/// Re-exports `spring_boot_starter_logging` and through it `spring_boot_dart`
/// and `spring_core_dart`: the starter is the only dependency an
/// application lists.
library;

// Logging and spring_boot_dart (re-exported by the logging starter), so
// this starter is the only dependency an application needs.
export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

export 'src/annotations.dart';
export 'src/cache.dart';
export 'src/cache_auto_configuration.dart' show cacheManagerFromProperties;
export 'src/cache_error_handler.dart';
export 'src/cache_interceptor.dart';
export 'src/cache_operation.dart';
export 'src/cache_resolver.dart';
export 'src/caching_configurer.dart';
export 'src/in_memory_cache.dart';
export 'src/key_generator.dart';
export 'src/no_op_cache.dart';
