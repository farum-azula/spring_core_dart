// In an application the starter is picked up automatically: add the
// dependency, annotate bean methods and run the generator (it writes the
// proxies caching runs on). The service below is what you would write;
// main() uses the cache manager directly, so it runs without code
// generation.
import 'dart:convert';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';

class Book {
  const Book(this.isbn, this.title);
  final String isbn;
  final String title;
}

abstract interface class CatalogApi {
  Future<Book> load(String isbn);
  Future<void> remove(String isbn);
}

@Service()
@CacheConfig(cacheNames: ['books'])
class Books {
  Books(this.api);
  final CatalogApi api;

  /// Loaded once per ISBN; later calls return the cached book.
  @Cacheable.of()
  Future<Book> find(String isbn) => api.load(isbn);

  /// Concurrent calls for the same ISBN share one request.
  @Cacheable('prices', sync: true)
  Future<double> price(String isbn) async => 12.5;

  /// The entry is removed once the book is gone.
  @CacheEvict.of(key: '#isbn')
  Future<void> remove(String isbn) => api.remove(isbn);

  /// Everything is reloaded: the cache is cleared first.
  @CacheEvict.of(allEntries: true, beforeInvocation: true)
  void reloadAll() {}
}

// --- Your own cache -------------------------------------------------------

/// Any synchronous key-value storage: a file, a key-value database, ...
abstract interface class KeyValueStore {
  String? read(String key);
  void write(String key, String value);
  void delete(String key);
  void deleteAll({required String prefix});
}

/// A store in a map (stands in for a real one here).
final class MapStore implements KeyValueStore {
  final _data = <String, String>{};

  @override
  String? read(String key) => _data[key];

  @override
  void write(String key, String value) => _data[key] = value;

  @override
  void delete(String key) => _data.remove(key);

  @override
  void deleteAll({required String prefix}) =>
      _data.removeWhere((key, _) => key.startsWith(prefix));
}

/// A cache kept in a [KeyValueStore] as JSON. `CacheDefaults` adds
/// putIfAbsent, evictIfPresent and invalidate; only four methods are left.
final class StoreCache with CacheDefaults implements Cache {
  StoreCache(this.name, this.store);

  @override
  final String name;
  final KeyValueStore store;

  String _key(Object? key) => '$name:$key';

  @override
  ValueWrapper? get(Object? key) => switch (store.read(_key(key))) {
    null => null,
    final json => ValueWrapper(jsonDecode(json)),
  };

  @override
  void put(Object? key, Object? value) =>
      store.write(_key(key), jsonEncode(value));

  @override
  void evict(Object? key) => store.delete(_key(key));

  @override
  void clear() => store.deleteAll(prefix: '$name:');
}

/// Registered like this, it replaces the starter's in-memory manager:
@Configuration()
class CacheSetup {
  @Bean()
  KeyValueStore store() => MapStore();

  @Bean()
  CacheManager cacheManager(KeyValueStore store) => SimpleCacheManager([
    StoreCache('books', store), // in the store
    InMemoryCache('prices'), // in memory
  ]);
}

void main() {
  // spring.cache.simple.time-to-live=10m, spring.cache.simple.max-size=100
  final caches = InMemoryCacheManager(
    defaultSpec: const CacheSpec(
      timeToLive: Duration(minutes: 10),
      maxSize: 100,
    ),
  );
  final books = caches.getCache('books')!
    ..put('978-0', const Book('978-0', 'Dart in Spring'));

  final hit = books.get('978-0');
  print('cached: ${(hit?.value as Book?)?.title}'); // cached: Dart in Spring

  // The default key of a call with several arguments.
  print(
    SimpleKeyGenerator.generateKey(['978-0', 'en']),
  ); // SimpleKey [978-0,en]

  books.evict('978-0');
  print('after evict: ${books.get('978-0')}'); // after evict: null

  // Your own cache: entries are in the store, so a new manager over the
  // same store (e.g. after a restart) still has them.
  final store = MapStore();
  SimpleCacheManager([StoreCache('titles', store)])
      .getCache('titles')!
      .put('978-0', 'Dart in Spring');
  final again = SimpleCacheManager([StoreCache('titles', store)]);
  print('after restart: ${again.getCache('titles')!.get('978-0')?.value}');
  // after restart: Dart in Spring
}
