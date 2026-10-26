// Caching in a Spring Boot application: annotate bean methods, the
// generator writes the proxies caching runs on and picks the starter up
// (example.spring.dart, from `dart run build_runner build`).
//
//   dart run example/example.dart
import 'dart:convert';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';

import 'example.spring.dart';

class Book {
  const Book(this.isbn, this.title);
  final String isbn;
  final String title;
}

/// The slow source behind the cache (a remote API in a real app); counts
/// its loads.
@Component()
class CatalogApi {
  var loads = 0;

  Future<Book> load(String isbn) async {
    loads++;
    return Book(isbn, 'Dune');
  }

  Future<void> remove(String isbn) async {}
}

@Service()
@CacheConfig(cacheNames: ['books'])
class Books {
  Books(this.api);
  final CatalogApi api;

  /// Loaded once per ISBN; later calls return the cached book.
  @Cacheable.of()
  Future<Book> find(String isbn) => api.load(isbn);

  /// Concurrent calls for the same ISBN share one computation.
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

  /// The stored keys.
  Iterable<String> get keys => _data.keys;
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

/// A `CacheManager` bean replaces the starter's in-memory manager.
@Configuration()
class CacheSetup {
  @Bean()
  KeyValueStore store() => MapStore();

  @Bean()
  CacheManager cacheManager(KeyValueStore store) => SimpleCacheManager([
    InMemoryCache('books'), // in memory
    StoreCache('prices', store), // in the store, as JSON
  ]);
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = springApplication.run(args);
  final books = context.getBean<Books>();
  final api = context.getBean<CatalogApi>();

  await books.find('978-0');
  await books.find('978-0');
  print('loads: ${api.loads}'); // loads: 1 (the second call was cached)

  await books.remove('978-0');
  await books.find('978-0');
  print('loads after evict: ${api.loads}'); // loads after evict: 2

  // The prices cache is the StoreCache of CacheSetup: entries are JSON in
  // the store, so they would survive a restart with a persistent store.
  print(await books.price('978-0')); // 12.5
  final store = context.getBean<KeyValueStore>() as MapStore;
  print(store.keys); // (prices:978-0)

  context.close();
}
