/// Caching of method results for `spring_boot_dart` applications: import
/// it to put `@Cacheable`, `@CachePut` and `@CacheEvict` on bean methods.
///
/// A slow method (a network call, a heavy computation) marked
/// `@Cacheable('books')` runs once per argument; later calls with the same
/// argument get the stored result back. Adding the package is all the setup
/// there is: the starter switches itself on and keeps the caches in memory,
/// with time-to-live and size limits taken from the `spring.cache.*`
/// properties. The rest of this library is for applications that go
/// further: their own `CacheManager` or `Cache` storage, key generators,
/// `CacheResolver`s that pick caches per call, and `CachingConfigurer`
/// defaults.
///
/// ```dart
/// @Service()
/// class Books {
///   Books(this.repository);
///   final BookRepository repository;
///
///   // The first call for an isbn loads it; later calls return the copy.
///   @Cacheable('books')
///   Book find(String isbn) => repository.load(isbn);
///
///   // A deleted book must not be served from the cache any more.
///   @CacheEvict('books', key: '#isbn')
///   void delete(String isbn) => repository.delete(isbn);
/// }
/// ```
///
/// This import re-exports `spring_boot_starter_logging` and, through it,
/// `spring_boot_dart` and `spring_core_dart`: the starter is the only
/// dependency an application lists. It is the Dart version of Spring
/// Boot's `spring-boot-starter-cache`.
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
