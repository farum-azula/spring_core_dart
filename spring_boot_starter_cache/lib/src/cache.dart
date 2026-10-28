/// A value found in a cache, wrapped so that a stored `null` can be told
/// apart from a missing entry.
///
/// [Cache.get] returns a `ValueWrapper` for a hit and `null` for a miss.
/// Without the wrapper a method whose result was `null` would look
/// uncached and run again every time. You meet it when you read a cache by
/// hand or write a [Cache] of your own: return `ValueWrapper(value)` for a
/// hit (also when `value` is `null`) and `null` for a miss.
///
/// ```dart
/// // An admin page shows what is cached for one isbn.
/// final wrapper = cacheManager.getCache('books')!.get('978-0');
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
  /// Wraps [value], which may be `null`.
  const ValueWrapper(this.value);

  /// The cached value; `null` when `null` was stored.
  final Object? value;

  @override
  String toString() => 'ValueWrapper($value)';
}

/// One named cache: a store of keys and values that the cache annotations
/// read and write.
///
/// `@Cacheable('books')` asks the [CacheManager] for the cache named
/// `books` and calls [get] and [put] on it; `@CacheEvict` calls [evict] or
/// [clear]. The starter's caches live in memory (`InMemoryCache`). Implement
/// this interface to keep entries somewhere else (a file, a key-value
/// database), usually with the [CacheDefaults] mixin so that only `get`,
/// `put`, `evict` and `clear` need writing. Code can also use a cache
/// directly, for example to look at an entry or empty a cache by hand.
///
/// The interface is synchronous. A store with an asynchronous API keeps its
/// entries in memory and writes them back in the background (the package
/// README shows how).
///
/// ```dart
/// // A book's data was corrected: replace its entry, keep the rest.
/// final books = cacheManager.getCache('books')!;
/// books.put('978-0', correctedBook);
/// books.get('978-0')?.value; // correctedBook
/// books.evict('978-1');      // and drop a book that was withdrawn
/// ```
///
/// Spring (Java):
/// ```java
/// Cache books = cacheManager.getCache("books");
/// books.put("978-0", book);
/// books.get("978-0").get();
/// books.evict("978-0");
/// ```
///
/// Only part of Spring's `Cache` is here: there is no `get(key, Class)`,
/// `get(key, Callable)`, `retrieve` or `getNativeCache`.
abstract interface class Cache {
  /// The name the annotations use to find this cache (`'books'`).
  String get name;

  /// The entry stored for [key]: a [ValueWrapper] for a hit (its value may
  /// be `null`), or `null` when there is no entry.
  ValueWrapper? get(Object? key);

  /// Stores [value] for [key], replacing an existing entry.
  void put(Object? key, Object? value);

  /// Stores [value] only when [key] has no entry yet. Returns the existing
  /// entry when there was one (and stores nothing), or `null` when [value]
  /// was stored.
  ValueWrapper? putIfAbsent(Object? key, Object? value);

  /// Removes the entry of [key], if any. A store may do it later (for
  /// example in the background); use [evictIfPresent] when it must be gone
  /// now.
  void evict(Object? key);

  /// Removes the entry of [key] right away. Returns whether there was one.
  bool evictIfPresent(Object? key);

  /// Removes every entry. A store may do it later; use [invalidate] when the
  /// cache must be empty now.
  void clear();

  /// Removes every entry right away. Returns whether the cache had any
  /// (implementations that cannot tell may return `true`).
  bool invalidate();
}

/// Finds caches by name: the object the cache annotations ask for the cache
/// they name.
///
/// Every application with the starter has one: unless the application
/// declares its own, the starter creates an `InMemoryCacheManager` from
/// the `spring.cache.*` properties. Declare a `CacheManager` bean to choose
/// the caches yourself (fixed names, your own storage, a mix); the
/// starter's one then steps aside and `spring.cache.*` no longer applies.
/// Inject it to reach the caches by hand.
///
/// ```dart
/// // Only these two caches exist; @Cacheable('other') fails the call.
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
  /// The cache named [name]. A manager that creates caches on demand
  /// creates it now; otherwise an unknown name gives `null`.
  Cache? getCache(String name);

  /// The names of the caches the manager holds so far (caches created on
  /// demand appear once they were asked for).
  Iterable<String> get cacheNames;
}

/// Implements `putIfAbsent`, `evictIfPresent` and `invalidate` of [Cache]
/// on top of `get`, `put`, `evict` and `clear`.
///
/// Mix it into a cache of your own so you write only the four basic
/// operations and `name`. The derived ones are not atomic (`putIfAbsent`
/// is a `get` followed by a `put`), which is fine for the cache
/// annotations: they use only the basic four. `invalidate` here always
/// returns `true`.
///
/// ```dart
/// // Entries kept in a key-value store as JSON, so they survive a restart.
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
/// Spring (Java), where a base class plays this part:
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

/// Adjusts the [CacheManager] that the starter builds from `spring.cache.*`,
/// before any cache is used.
///
/// Use it when the properties are not enough but you still want the
/// starter's manager rather than declaring your own: for example to create
/// some caches at startup. Declare it as a bean; every customizer is called
/// once with the new manager. It is not called for a `CacheManager` bean the
/// application declares itself.
///
/// The interface is not generic, unlike Spring Boot's: every customizer
/// receives the manager and checks its type itself (the container finds
/// beans by their exact type, so a `CacheManagerCustomizer<X>` could not be
/// matched).
///
/// ```dart
/// // Create the `books` cache at startup, so it is listed before first use.
/// @Component()
/// class WarmCaches implements CacheManagerCustomizer {
///   @override
///   void customize(CacheManager cacheManager) {
///     if (cacheManager is InMemoryCacheManager) {
///       cacheManager.getCache('books');
///     }
///   }
/// }
/// ```
///
/// Spring Boot (Java):
/// ```java
/// @Bean
/// CacheManagerCustomizer<ConcurrentMapCacheManager> warm() {
///   return manager -> manager.setCacheNames(List.of("books"));
/// }
/// ```
abstract interface class CacheManagerCustomizer {
  /// Changes [cacheManager]; called once, right after the starter created
  /// it.
  void customize(CacheManager cacheManager);
}

/// A [CacheManager] that holds a fixed list of caches you build yourself.
///
/// It is the way to put caches of your own (or a mix of yours and
/// `InMemoryCache`s) behind the annotations. It never creates a cache: an
/// unknown name gives `null`, so `@Cacheable('other')` fails the call with
/// "Cannot find cache named 'other'". The starter also uses it for
/// `spring.cache.type=generic`, with the `Cache` beans of the application.
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
  /// A manager of [caches], found by their [Cache.name]; of two caches with
  /// the same name the later one wins.
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
