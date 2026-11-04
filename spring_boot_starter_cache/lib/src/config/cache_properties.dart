import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The kind of `CacheManager` the starter builds.
enum CacheType {
  /// Uses the application's `Cache` beans (a `SimpleCacheManager`).
  generic,

  /// Keeps entries in memory (an `InMemoryCacheManager`).
  simple,

  /// Caches nothing, so the methods always run (a `NoOpCacheManager`).
  none,
}

/// The `spring.cache.*` properties.
///
/// Spring Boot (Java): `CacheProperties`.
@ConfigurationProperties('spring.cache')
class CacheProperties {
  /// The kind of cache manager. Default: `generic` when the application
  /// has `Cache` beans, else `simple`.
  CacheType? type;

  /// A fixed set of caches (`books,authors`, or a YAML list); an annotation
  /// that names another cache then fails. Default: empty (caches are
  /// created on demand).
  List<String> cacheNames = [];

  /// The settings of the `simple` cache manager.
  SimpleCacheProperties simple = SimpleCacheProperties();
}

/// The `spring.cache.simple.*` properties.
@Introspected()
class SimpleCacheProperties {
  /// An entry expires this long after it was written (`10m`, `30s`,
  /// `PT1H`, or milliseconds), measured on a monotonic clock as Caffeine's
  /// ticker (setting the system clock moves no expiry). Default: none; `0`
  /// keeps nothing; a negative value fails the start.
  Duration? timeToLive;

  /// The most entries per cache; when full, the least recently used entry
  /// goes. Default: none; `0` keeps nothing; a negative value fails the
  /// start.
  int? maxSize;

  /// The limits of single caches, by cache name; what one leaves out comes
  /// from the two settings above. A name with dots goes in brackets
  /// (`caches[books.byIsbn].max-size`).
  Map<String, CacheLimits> caches = {};
}

/// The limits of one cache (`spring.cache.simple.caches.<name>.*`).
@Introspected()
class CacheLimits {
  /// The same as `spring.cache.simple.time-to-live`, for this cache. A
  /// negative value fails the start. Default: the global one.
  Duration? timeToLive;

  /// The same as `spring.cache.simple.max-size`, for this cache. A negative
  /// value fails the start. Default: the global one.
  int? maxSize;
}
