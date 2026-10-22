/// A cached value, so that a cached `null` differs from a miss, like
/// Spring's `Cache.ValueWrapper`.
///
/// ```dart
/// final wrapper = cache.get('978-0');
/// if (wrapper != null) {
///   print(wrapper.value); // may be null: null was cached
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// Cache.ValueWrapper wrapper = cache.get("978-0");
/// if (wrapper != null) System.out.println(wrapper.get());
/// ```
final class ValueWrapper {
  /// Wraps [value].
  const ValueWrapper(this.value);

  /// The cached value.
  final Object? value;

  @override
  String toString() => 'ValueWrapper($value)';
}

/// One named cache, like Spring's `Cache`: what `@Cacheable` and friends
/// read and write. Implement it to plug in another store.
///
/// ```dart
/// final books = cacheManager.getCache('books')!;
/// books.put('978-0', book);
/// books.get('978-0')?.value; // book
/// books.evict('978-0');
/// ```
///
/// Spring (Java):
/// ```java
/// Cache books = cacheManager.getCache("books");
/// books.put("978-0", book);
/// books.get("978-0").get();
/// books.evict("978-0");
/// ```
abstract interface class Cache {
  /// The cache name.
  String get name;

  /// The value stored for [key], or `null` when there is none.
  ValueWrapper? get(Object? key);

  /// Stores [value] for [key], replacing an existing entry.
  void put(Object? key, Object? value);

  /// Stores [value] unless [key] has a value; returns the existing value,
  /// or `null` when [value] was stored.
  ValueWrapper? putIfAbsent(Object? key, Object? value);

  /// Removes the entry of [key] (may happen later in asynchronous stores).
  void evict(Object? key);

  /// Removes the entry of [key] now; whether there was one.
  bool evictIfPresent(Object? key);

  /// Removes every entry (may happen later in asynchronous stores).
  void clear();

  /// Removes every entry now; whether there was any.
  bool invalidate();
}

/// Looks up caches by name, like Spring's `CacheManager`. The starter
/// creates one from `spring.cache.*`; declare your own `CacheManager` bean
/// to replace it.
///
/// ```dart
/// @Configuration()
/// class CacheSetup {
///   @Bean()
///   CacheManager cacheManager() =>
///       InMemoryCacheManager(cacheNames: ['books', 'authors']);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// CacheManager cacheManager() {
///   return new ConcurrentMapCacheManager("books", "authors");
/// }
/// ```
abstract interface class CacheManager {
  /// The cache named [name], or `null` when the manager has none (and
  /// does not create caches on demand).
  Cache? getCache(String name);

  /// Names of the caches known so far.
  Iterable<String> get cacheNames;
}

/// The derived operations of [Cache], written on top of `get`, `put`,
/// `evict` and `clear`: a store of your own implements only those four
/// (plus `name`), like extending Spring's `AbstractValueAdaptingCache`.
///
/// ```dart
/// final class StoreCache with CacheDefaults implements Cache {
///   StoreCache(this.name, this.store);
///
///   @override
///   final String name;
///   final KeyValueStore store; // your storage
///
///   @override
///   ValueWrapper? get(Object? key) => switch (store.read('$name:$key')) {
///     null => null,
///     final json => ValueWrapper(jsonDecode(json)),
///   };
///
///   @override
///   void put(Object? key, Object? value) =>
///       store.write('$name:$key', jsonEncode(value));
///
///   @override
///   void evict(Object? key) => store.delete('$name:$key');
///
///   @override
///   void clear() => store.deleteAll(prefix: '$name:');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class StoreCache extends AbstractValueAdaptingCache {
///   protected Object lookup(Object key) { ... }
///   public void put(Object key, Object value) { ... }
///   public void evict(Object key) { ... }
///   public void clear() { ... }
/// }
/// ```
mixin CacheDefaults implements Cache {
  @override
  ValueWrapper? putIfAbsent(Object? key, Object? value) {
    final existing = get(key);
    if (existing == null) {
      put(key, value);
    }
    return existing;
  }

  @override
  bool evictIfPresent(Object? key) {
    if (get(key) == null) {
      return false;
    }
    evict(key);
    return true;
  }

  @override
  bool invalidate() {
    clear();
    return true;
  }
}

/// A [CacheManager] for a fixed list of caches, like Spring's
/// `SimpleCacheManager`: the way to put caches of your own (or a mix with
/// `InMemoryCache`) behind the annotations. An unknown name gives `null`,
/// so `@Cacheable('other')` fails with "Cannot find cache named 'other'".
///
/// ```dart
/// @Configuration()
/// class CacheSetup {
///   @Bean()
///   CacheManager cacheManager(KeyValueStore store) => SimpleCacheManager([
///     StoreCache('books', store),     // kept across restarts
///     InMemoryCache('prices'),        // in memory
///   ]);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// CacheManager cacheManager(KeyValueStore store) {
///   var manager = new SimpleCacheManager();
///   manager.setCaches(List.of(new StoreCache("books", store),
///       new ConcurrentMapCache("prices")));
///   return manager;
/// }
/// ```
final class SimpleCacheManager implements CacheManager {
  /// A manager of [caches] (by their names; a later one with the same name
  /// wins).
  SimpleCacheManager(Iterable<Cache> caches)
    : _caches = {for (final cache in caches) cache.name: cache};

  final Map<String, Cache> _caches;

  @override
  Cache? getCache(String name) => _caches[name];

  @override
  Iterable<String> get cacheNames => _caches.keys;

  @override
  String toString() => 'SimpleCacheManager(${_caches.keys.join(', ')})';
}
