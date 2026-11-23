import 'package:spring_boot_starter_cache/src/cache.dart';

/// Caches in layers: a fast one in front of slower ones (memory in front of
/// the disk, the disk in front of a shared store). Not Spring's: Spring
/// leaves a layered cache to the cache library.
///
/// A cache name is a [LayeredCache] of that name in every manager that has
/// it, in the order of [layers]. An entry is looked for layer by layer, and
/// one found in a slower layer is copied into the faster ones in front of
/// it; a put and an evict go to every layer. A layer that keeps no `null`
/// (`allowNullValues: false`) is left out of the put of a `null`, which
/// the other layers keep.
///
/// A copy into a faster layer lives that layer's whole time to live from
/// the copy: an entry can outlive the slower layer's time by up to the
/// faster layer's. Keep the faster layers' times short.
///
/// ```dart
/// @Bean()
/// CacheManager layered(CacheManager memory, CacheManager disk) =>
///     LayeredCacheManager([memory, disk]);
/// ```
final class LayeredCacheManager implements CacheManager {
  /// The managers [layers], the fastest first.
  LayeredCacheManager(Iterable<CacheManager> layers)
    : layers = List.unmodifiable(layers);

  /// The managers, the fastest first.
  final List<CacheManager> layers;

  final Map<String, LayeredCache> _caches = {};

  @override
  Cache? getCache(String name) {
    final existing = _caches[name];
    if (existing != null) {
      return existing;
    }
    final caches = [
      for (final layer in layers) ?layer.getCache(name),
    ];
    return caches.isEmpty ? null : _caches[name] = LayeredCache(name, caches);
  }

  @override
  Iterable<String> get cacheNames => {
    for (final layer in layers) ...layer.cacheNames,
  };

  @override
  String toString() => 'LayeredCacheManager(${layers.join(', ')})';
}

/// One cache over [layers], the fastest first (see [LayeredCacheManager]).
///
/// It is an [AsyncCache] when a layer is one: a method that returns a
/// `Future` then waits for the slower layers; [get] asks only the layers
/// that answer at once.
final class LayeredCache implements AsyncCache {
  /// The cache [name] over [layers], the fastest first.
  LayeredCache(this.name, Iterable<Cache> layers)
    : layers = List.unmodifiable(layers);

  @override
  final String name;

  /// The caches, the fastest first.
  final List<Cache> layers;

  bool _answers(Cache cache) =>
      cache is! AsyncCache || cache.answersSynchronously;

  @override
  bool get answersSynchronously => layers.every(_answers);

  @override
  ValueWrapper? get(Object? key) {
    for (final (index, layer) in layers.indexed) {
      if (!_answers(layer)) {
        continue;
      }
      if (layer.get(key) case final hit?) {
        _copyForward(index, key, hit);
        return hit;
      }
    }
    return null;
  }

  @override
  Future<ValueWrapper?> retrieve(Object? key) async {
    for (final (index, layer) in layers.indexed) {
      final hit = layer is AsyncCache
          ? await layer.retrieve(key)
          : layer.get(key);
      if (hit != null) {
        _copyForward(index, key, hit);
        return hit;
      }
    }
    return null;
  }

  void _copyForward(int found, Object? key, ValueWrapper hit) {
    for (final layer in layers.take(found)) {
      _put(layer, key, hit.value);
    }
  }

  @override
  void put(Object? key, Object? value) {
    for (final layer in layers) {
      _put(layer, key, value);
    }
  }

  // A layer that refuses null (Spring's IllegalArgumentException of a
  // cache that does not allow null values) is skipped for a null.
  static void _put(Cache layer, Object? key, Object? value) {
    if (value != null) {
      layer.put(key, value);
      return;
    }
    try {
      layer.put(key, null);
    } on ArgumentError {
      layer.evict(key);
    }
  }

  @override
  ValueWrapper? putIfAbsent(Object? key, Object? value) {
    final existing = get(key);
    if (existing != null) {
      return existing;
    }
    put(key, value);
    return null;
  }

  @override
  void evict(Object? key) {
    for (final layer in layers) {
      layer.evict(key);
    }
  }

  @override
  bool evictIfPresent(Object? key) {
    var present = false;
    for (final layer in layers) {
      present = layer.evictIfPresent(key) || present;
    }
    return present;
  }

  @override
  void clear() {
    for (final layer in layers) {
      layer.clear();
    }
  }

  @override
  bool invalidate() {
    var any = false;
    for (final layer in layers) {
      any = layer.invalidate() || any;
    }
    return any;
  }

  @override
  String toString() => 'LayeredCache($name: ${layers.join(', ')})';
}
