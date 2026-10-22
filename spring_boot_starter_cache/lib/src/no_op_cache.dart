import 'package:spring_boot_starter_cache/src/cache.dart';

/// A cache that stores nothing: every lookup is a miss, so cached methods
/// always run, like Spring's `NoOpCache`.
///
/// ```dart
/// const NoOpCache('books').get('978-0'); // null
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

/// A [CacheManager] whose caches store nothing, like Spring's
/// `NoOpCacheManager`: caching annotations stay in place but every call
/// runs the method. Chosen by `spring.cache.type=none` (handy in tests).
///
/// ```dart
/// final manager = NoOpCacheManager();
/// manager.getCache('books')!.get('978-0'); // null
/// ```
///
/// Spring (Java):
/// ```java
/// CacheManager manager = new NoOpCacheManager();
/// ```
final class NoOpCacheManager implements CacheManager {
  /// A manager that creates a [NoOpCache] for any name.
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
