# spring_boot_starter_cache: examples

**What it does:** remembers the results of slow methods of a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) app — the
first call runs the method, the next calls with the same arguments get the
stored result.

## Setup

Add the dependency and run the generator again. That is all: the starter
is found and switched on automatically.

```yaml
dependencies:
  spring_boot_starter_cache: ^0.4.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.2   # required: generates the proxies caching runs on
```

```bash
dart run build_runner build
```

## 1. Cache a method

```dart
@Service()
class Books {
  Books(this.api);
  final CatalogApi api;

  @Cacheable('books')
  Future<Book> find(String isbn) => api.load(isbn); // once per isbn
}
```

Another bean calls `books.find('978-0')` twice: the API is asked once.
(Calls through `this` inside `Books` skip the cache — like in Spring.)

## 2. Choose the key

```dart
@Cacheable('books', key: '#isbn')                       // only isbn counts
Future<Book> find(String isbn, bool withReviews) => ...;

@Cacheable('books', unless: '#result == null')          // misses are not kept
Book? maybe(String isbn) => ...;
```

## 3. Keep the cache fresh

```dart
@CachePut('books', key: '#isbn')                        // always runs, stores the result
Book rename(String isbn, String title) => ...;

@CacheEvict('books', key: '#isbn')                      // removes the entry
Future<void> remove(String isbn) => ...;

@CacheEvict('books', allEntries: true)                  // clears the cache
void reloadAll() => ...;
```

## 4. Limits

```properties
# lib/resources/application.properties
spring.cache.simple.time-to-live=10m
spring.cache.simple.max-size=1000
spring.cache.simple.caches.prices.time-to-live=30s
```

## 5. Switch it off in tests

```dart
final app = springBootTest(
  springApplication,
  properties: {'spring.cache.type': 'none'},
);
```

## 6. What you get by default

Nothing to configure: the starter creates an `InMemoryCacheManager`. Each
cache (`'books'`, `'prices'`, ...) is a map in the app's memory, created
the first time an annotation names it. Entries live until the app stops
(or the time-to-live / size limits of step 4 drop them); `null` results
are stored too.

## 7. Your own cache

Declare a `CacheManager` bean and the default steps aside. To keep entries
somewhere else, implement `Cache` — with `CacheDefaults` four methods are
enough — and list your caches in a `SimpleCacheManager`:

```dart
final class StoreCache with CacheDefaults implements Cache {
  StoreCache(this.name, this.store);

  @override
  final String name;
  final KeyValueStore store; // your storage: a file, a database, ...

  @override
  ValueWrapper? get(Object? key) => switch (store.read('$name:$key')) {
    null => null,                                   // miss: the method runs
    final json => ValueWrapper(jsonDecode(json)),   // hit
  };

  @override
  void put(Object? key, Object? value) =>
      store.write('$name:$key', jsonEncode(value));

  @override
  void evict(Object? key) => store.delete('$name:$key');

  @override
  void clear() => store.deleteAll(prefix: '$name:');
}

@Configuration()
class CacheSetup {
  @Bean()
  CacheManager cacheManager(KeyValueStore store) => SimpleCacheManager([
    StoreCache('books', store),   // survives restarts
    InMemoryCache('prices'),      // in memory
  ]);
}
```

The `Cache` interface is synchronous (as in Spring); for asynchronous
storage (SQLite, `shared_preferences`) keep entries in memory and write
them back in the background — see "Your own cache or manager" in the
README.

[`example.dart`](example.dart) is a Spring Boot application with the
`@Cacheable` service above and its own `CacheManager` (the generator writes
`example.spring.dart`): `dart run example/example.dart`. All options: the
package
[README](https://pub.dev/packages/spring_boot_starter_cache).
