# spring_boot_starter_cache: examples

This starter remembers the results of slow methods of a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
application: the first call runs the method, the next calls with the same
arguments get the stored result.

[`example.dart`](example.dart) is a small Spring Boot application. A
`Books` service reads books from a slow `CatalogApi` (which counts its
loads) through a cache, evicts an entry, and caches prices in a cache of
its own that keeps entries as JSON in a key-value store.

## Run it

```yaml
dependencies:
  spring_boot_starter_cache: ^0.4.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.2   # required: generates the proxies caching runs on
```

Adding the dependency and running the generator is all the setup: the
starter is found and switched on automatically. From the package
directory:

```bash
dart run build_runner build
dart run example/example.dart
```

After the startup lines it logs, through the `example` logger:

```text
... example : loads: 1
... example : loads after evict: 2
... example : price: 12.5
... example : stored: (prices:978-0)
```

The book is loaded once for two calls; after the eviction it is loaded
again; the price is stored in the key-value store under `prices:978-0`.

## 1. Cache a method

```dart
@Service()
@CacheConfig(cacheNames: ['books'])     // the default cache of this class
class Books {
  Books(this.api);
  final CatalogApi api;

  // Loaded once per isbn; later calls return the cached book.
  @Cacheable.of()
  Future<Book> find(String isbn) => api.load(isbn);
}
```

Another bean (here the `CacheTour` runner) calls `books.find('978-0')` twice: the API is
asked once. A `Future` method caches the book, not the future. Calls
through `this` inside `Books` skip the cache, as in Spring, because
caching works through the bean's generated proxy.

`@Cacheable('books')` names a cache directly; `@Cacheable.of()` takes the
names from `@CacheConfig`.

## 2. Keep the cache fresh

```dart
// The entry is removed once the book is gone.
@CacheEvict.of(key: '#isbn')
Future<void> remove(String isbn) => api.remove(isbn);

// Everything is reloaded: the cache is cleared first.
@CacheEvict.of(allEntries: true, beforeInvocation: true)
void reloadAll() {}
```

`@CachePut('books', key: '#isbn')` always runs the method and stores its
result, to refresh an entry.

## 3. Share one call between concurrent callers

```dart
// Concurrent calls for the same isbn wait for the first one.
@Cacheable('prices', sync: true)
Future<double> price(String isbn) async => 12.5;
```

## 4. Choose the key

The key is made of the arguments unless you say otherwise, with a SpEL
expression:

```dart
@Cacheable('books', key: '#isbn')                       // only isbn counts
Future<Book> find(String isbn, bool withReviews) => ...;

@Cacheable('books', unless: '#result == null')          // misses are not kept
Book? maybe(String isbn) => ...;
```

## 5. Your own cache

Without setup, the starter creates an `InMemoryCacheManager`: each cache
is a map in memory, created when first named. The example declares its
own `CacheManager` bean instead, which makes the starter's one step
aside. It mixes an in-memory cache with a cache kept in a store:

```dart
// A cache kept in a KeyValueStore as JSON. CacheDefaults adds
// putIfAbsent, evictIfPresent and invalidate; four methods are left.
final class StoreCache with CacheDefaults implements Cache {
  StoreCache(this.name, this.store);

  @override
  final String name;
  final KeyValueStore store;

  String _key(Object? key) => '$name:$key';

  @override
  ValueWrapper? get(Object? key) => switch (store.read(_key(key))) {
    null => null,                                   // a miss: the method runs
    final json => ValueWrapper(jsonDecode(json)),   // a hit
  };

  @override
  void put(Object? key, Object? value) =>
      store.write(_key(key), jsonEncode(value));

  @override
  void evict(Object? key) => store.delete(_key(key));

  @override
  void clear() => store.deleteAll(prefix: '$name:');
}

@Configuration()
class CacheSetup {
  @Bean()
  KeyValueStore store() => MapStore();          // a map standing in for a real store

  @Bean()
  CacheManager cacheManager(KeyValueStore store) => SimpleCacheManager([
    InMemoryCache('books'),       // in memory
    StoreCache('prices', store),  // in the store, as JSON
  ]);
}
```

With a persistent store, the cached prices would survive a restart. The
`Cache` interface is synchronous, as in Spring; for asynchronous storage
(SQLite, `shared_preferences`), keep entries in memory and write them back
in the background, as "Your own cache or manager" in the README shows.

## 6. Limits for the default caches

When you keep the starter's in-memory manager, properties set a time to
live and a size limit:

```properties
# lib/resources/application.properties
spring.cache.simple.time-to-live=10m
spring.cache.simple.max-size=1000
spring.cache.simple.caches.prices.time-to-live=30s
```

## 7. Switch it off in tests

```dart
final app = springBootTest(
  springApplication,
  properties: {'spring.cache.type': 'none'},
);
```

Every annotation option, key expressions, cache resolvers and the
differences from Spring are in the package
[README](https://pub.dev/packages/spring_boot_starter_cache).
