/// Caching for `spring_boot_dart` applications, like
/// `spring-boot-starter-cache`: `@Cacheable`, `@CachePut`, `@CacheEvict`,
/// `@Caching` and `@CacheConfig` on bean methods, a [CacheManager] with
/// time-to-live and size limits configured by `spring.cache.*`.
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
/// Re-exports `spring_boot_dart`.
library;

export 'package:spring_boot_dart/spring_boot_dart.dart';

export 'src/annotations.dart';
export 'src/cache.dart';
export 'src/cache_auto_configuration.dart' show cacheManagerFromProperties;
export 'src/cache_interceptor.dart';
export 'src/in_memory_cache.dart';
export 'src/key_generator.dart';
export 'src/no_op_cache.dart';
