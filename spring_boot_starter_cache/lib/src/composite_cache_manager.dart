import 'package:spring_boot_starter_cache/src/cache.dart';

/// Several [CacheManager]s as one: a cache name is looked up in each in
/// order, and the first that has the cache gives it. Spring's
/// `CompositeCacheManager`.
///
/// With [fallbackToNoOpCache] a name none of them has is a cache that keeps
/// nothing (the method always runs), instead of no cache at all.
///
/// ```dart
/// @Bean()
/// CacheManager cacheManager(CacheManager memory, CacheManager disk) =>
///     CompositeCacheManager([memory, disk]);
/// ```
final class CompositeCacheManager implements CacheManager {
  /// The managers [managers], in the order they are asked.
  CompositeCacheManager(
    Iterable<CacheManager> managers, {
    this.fallbackToNoOpCache = false,
  }) : managers = List.unmodifiable(managers);

  /// The managers, in the order they are asked.
  final List<CacheManager> managers;

  /// Whether a name no manager has is a cache that keeps nothing.
  final bool fallbackToNoOpCache;

  final Map<String, Cache> _noOp = {};

  @override
  Cache? getCache(String name) {
    for (final manager in managers) {
      if (manager.getCache(name) case final cache?) {
        return cache;
      }
    }
    return fallbackToNoOpCache ? _noOp[name] ??= _NoOpCache(name) : null;
  }

  @override
  Iterable<String> get cacheNames => {
    for (final manager in managers) ...manager.cacheNames,
    ..._noOp.keys,
  };

  @override
  String toString() => 'CompositeCacheManager(${managers.join(', ')})';
}

final class _NoOpCache implements Cache {
  _NoOpCache(this.name);

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
