import 'package:spring_boot_starter_cache/src/cache.dart';

/// A [Cache] that stores nothing: every lookup is a miss, so the cached
/// methods always run.
///
/// It switches caching off without removing the annotations. The
/// [NoOpCacheManager] hands one out for every name; build one yourself to
/// switch off a single cache in a [SimpleCacheManager].
///
/// ```dart
/// // Prices must always be fresh for now; books stay cached.
/// SimpleCacheManager([InMemoryCache('books'), const NoOpCache('prices')]);
/// ```
///
/// Spring (Java):
/// ```java
/// new NoOpCache("books").get("978-0"); // null
/// ```
final class NoOpCache implements Cache {
  /// A cache named [name] that keeps nothing.
  const NoOpCache(this.name);

  @override
  final String name;

  @override
  ValueWrapper? get(Object? key) => null;

  @override
  void put(Object? key, Object? value) {}

  @override
  ValueWrapper? putIfAbsent(Object? key, Object? value) => null;

  @override
  void evict(Object? key) {}

  @override
  bool evictIfPresent(Object? key) => false;

  @override
  void clear() {}

  @override
  bool invalidate() => false;
}

/// A [CacheManager] whose caches store nothing: the cache annotations stay
/// in place, but every call runs the method.
///
/// Use it to switch caching off as a whole, most often in tests, where
/// cached results carried over from one call to the next can hide
/// behaviour. The usual way is the property `spring.cache.type=none`, which
/// makes the starter create this manager; you rarely build it yourself.
///
/// ```dart
/// // In a test: every call reaches the real method.
/// final app = springBootTest(
///   springApplication,
///   properties: {'spring.cache.type': 'none'},
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// CacheManager manager = new NoOpCacheManager();
/// ```
final class NoOpCacheManager implements CacheManager {
  /// A manager that gives a [NoOpCache] for any name; [cacheNames] lists
  /// the names asked for so far.
  NoOpCacheManager();

  final _names = <String>{};

  @override
  Cache? getCache(String name) {
    _names.add(name);
    return NoOpCache(name);
  }

  @override
  Iterable<String> get cacheNames => List.unmodifiable(_names);
}
