# spring_boot_starter_cache

Caching for [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications, like `spring-boot-starter-cache`: put `@Cacheable` on a bean
method and repeated calls with the same arguments return the stored result
instead of running the method again.

```dart
@Service()
class Books {
  Books(this.api);
  final CatalogApi api;

  @Cacheable('books')
  Future<Book> find(String isbn) => api.load(isbn); // slow: called once per isbn

  @CacheEvict('books', key: '#isbn')
  Future<void> delete(String isbn) => api.delete(isbn);
}
```

## Setup

Add the dependency and run the generator again. The starter is found and
switched on automatically — no `@EnableCaching`.

```yaml
dependencies:
  spring_boot_dart: ^0.1.0
  spring_boot_starter_cache: ^0.1.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.1.0   # required: generates the proxies caching runs on
```

```bash
dart run build_runner build
```

One import is enough:
`package:spring_boot_starter_cache/spring_boot_starter_cache.dart`
re-exports `spring_boot_dart`.

How it works: the generator writes an AOP proxy for each bean (option
`aop_proxies`, `all` by default), and the starter registers an advisor
that wraps every method with a cache annotation. So, exactly as in Spring:

- the cache applies to calls **from other beans** (through the proxy);
- a call through `this` inside the same class skips the cache. To call a
  cached method of your own class, inject the bean into itself with
  `@Lazy()`:

```dart
@Service()
class Books implements BookService {
  Books(@Lazy() this._self);
  final BookService _self;

  @Cacheable('books')
  @override
  Book find(String isbn) => ...;

  List<Book> findAll(List<String> isbns) =>
      [for (final isbn in isbns) _self.find(isbn)]; // cached; find(isbn) is not
}
```

## Annotations

| Annotation | What it does |
|---|---|
| `@Cacheable('books')` | Returns the cached result when there is one; otherwise runs the method and stores the result. |
| `@CachePut('books', key: '#isbn')` | Always runs the method and stores the result (refreshes the entry). |
| `@CacheEvict('books', key: '#isbn')` | Removes the entry after the method returned. `allEntries: true` clears the cache, `beforeInvocation: true` evicts before the call (also when it throws). |
| `@Caching(cacheable: [...], put: [...], evict: [...])` | Several operations on one method. Repeating an annotation works too. |
| `@CacheConfig(cacheNames: ['books'])` | On the class: default cache names, `keyGenerator`, `cacheManager` for its methods. |

`@Cacheable('books')` names one cache. For several caches, or to take them
from `@CacheConfig`, use `.of`: `@Cacheable.of(cacheNames: ['books', 'isbn'])`,
`@Cacheable.of(key: '#isbn')` (same for `CachePut.of` and `CacheEvict.of`).

Options of `@Cacheable` (and, where they make sense, of the others):

| Option | Meaning |
|---|---|
| `key` | SpEL computing the key. Default: the arguments (see below). |
| `condition` | SpEL; the cache is used only when it is `true`. |
| `unless` | SpEL with `#result`; the result is not stored when it is `true`. |
| `sync` | For `Future` methods: concurrent calls with the same key share one call. |
| `keyGenerator` | Name of a `KeyGenerator` bean computing the key. |
| `cacheManager` | Name of the `CacheManager` bean to use. |

## Keys

Without `key`, the key is made of the arguments, like Spring's
`SimpleKeyGenerator`: no arguments → `SimpleKey.empty`, one argument → the
argument itself, several → `SimpleKey([...])`, which compares by content
(lists, sets and maps inside too).

`key`, `condition` and `unless` are SpEL expressions — plain, without
`#{}`:

| Expression | Value |
|---|---|
| `#isbn` | the argument named `isbn` |
| `#p0`, `#a0` | the first argument |
| `#result` | the result (`unless`; `key` and `condition` of `@CachePut`; `@CacheEvict` after the call) |
| `#root.methodName` | `find` |
| `#root.args` | all arguments, `#root.args[1]` |
| `#root.target` | the bean |
| `#root.targetClass` | the bean class name, `Books` |
| `#root.caches` | the cache names of the operation |
| `@region` | the bean named `region` |

Examples:

```dart
@Cacheable('books', key: '#isbn')                         // ignore the other arguments
Book find(String isbn, bool includeReviews) => ...;

@Cacheable('books', key: "#isbn + '-' + #lang")            // a combined key
Book translated(String isbn, String lang) => ...;

@Cacheable('books', condition: '#isbn.length() == 13')     // cache 13-digit ISBNs only
Book findIsbn(String isbn) => ...;

@Cacheable('books', unless: '#result == null')            // do not remember misses
Book? maybe(String isbn) => ...;

@CachePut('books', key: '#result.isbn')                   // Book is @Introspected
Book save(Book book) => ...;
```

Reading properties or calling methods of your own objects
(`#book.isbn`, `#result.isbn`, `@clock.zone()`) needs `@Introspected()`
on their class, because Dart has no reflection: the generator then writes
the accessors SpEL uses. Strings, numbers, lists and maps work as they are
(`#isbn.length()`, `#tags.size()`).

## Async methods

Methods returning a `Future` cache the **value**, not the future: the
value is stored when the future completes, a hit returns an already
completed `Future`, and errors are never cached (the next call tries
again).

```dart
@Cacheable('prices', sync: true)
Future<double> price(String isbn) => api.price(isbn);
```

With `sync: true`, calls that arrive while the first one is still running
wait for it instead of calling `api.price` again. Like in Spring, a `sync`
operation must be the only cache annotation of the method, use one cache
and no `unless`.

## The default: caches in memory

Without any setup the starter creates the `cacheManager` bean, an
`InMemoryCacheManager` (Spring's `ConcurrentMapCacheManager`):

- each cache is an `InMemoryCache`, a map in the memory of the running
  app, created the first time an annotation names it (`'books'`, ...);
- entries are lost when the app stops, and after a restart of the context
  (also a hot reload that changes beans): the cache starts empty;
- nothing expires and there is no size limit unless you set them (below);
  expired entries are dropped when they are read;
- `null` results are stored too (a stored `null` is a hit, like in Spring);
- one app, one isolate: the cache is not shared between processes,
  isolates or devices.

That is right for most caches: results of slow calls that are cheap to
recompute after a restart.

### Properties

The default manager is built from `spring.cache.*` (only when the
application declares no `CacheManager` of its own):

| Property | Default | Meaning |
|---|---|---|
| `spring.cache.type` | `simple` | `simple`: caches in memory; `none`: cache nothing (annotations stay, methods always run) |
| `spring.cache.cache-names` | — | A fixed set of caches, e.g. `books,authors`; an unknown name is then an error. Without it caches are created on first use. |
| `spring.cache.simple.time-to-live` | none | How long entries live: `10m`, `30s`, `PT1H`, or milliseconds. |
| `spring.cache.simple.max-size` | none | Maximum entries per cache; the least recently used go first. |
| `spring.cache.simple.caches.<name>.time-to-live` | — | The same for one cache. |
| `spring.cache.simple.caches.<name>.max-size` | — | The same for one cache. |

```properties
# lib/resources/application.properties
spring.cache.simple.time-to-live=10m
spring.cache.simple.max-size=1000
spring.cache.simple.caches.prices.time-to-live=30s
```

Inject the manager to look at or clear caches by hand:

```dart
@Component()
class CacheAdmin {
  CacheAdmin(this.caches);
  final CacheManager caches;

  void clearBooks() => caches.getCache('books')?.clear();
}
```

## Your own cache or manager

The annotations only talk to two interfaces, so anything can stand behind
them:

| Type | What it does | Built in |
|---|---|---|
| `CacheManager` | finds a cache by name (`getCache('books')`) | `InMemoryCacheManager`, `SimpleCacheManager`, `NoOpCacheManager` |
| `Cache` | one cache: `get`, `put`, `evict`, `clear`, ... | `InMemoryCache`, `NoOpCache` |

**Declare a `CacheManager` bean and the starter's one steps aside** (it is
created only when there is none). The `spring.cache.*` properties then no
longer apply: your bean decides.

### 1. The default, configured in code

```dart
@Configuration()
class CacheSetup {
  @Bean()
  CacheManager cacheManager() => InMemoryCacheManager(
    cacheNames: ['books', 'prices'],                     // only these two
    defaultSpec: const CacheSpec(timeToLive: Duration(minutes: 10)),
    specs: {'prices': const CacheSpec(timeToLive: Duration(seconds: 30))},
  );
}
```

### 2. Your own storage

Implement `Cache`. With the `CacheDefaults` mixin four methods are enough
(`putIfAbsent`, `evictIfPresent` and `invalidate` are derived from them).
Then hand your caches to a `SimpleCacheManager` (Spring's
`SimpleCacheManager`), alone or mixed with in-memory ones:

```dart
import 'dart:convert';

/// Any synchronous key-value storage: a file, a key-value database, ...
abstract interface class KeyValueStore {
  String? read(String key);
  void write(String key, String value);
  void delete(String key);
  void deleteAll({required String prefix});
}

/// Entries kept in the store as JSON, so they survive a restart.
final class StoreCache with CacheDefaults implements Cache {
  StoreCache(this.name, this.store);

  @override
  final String name;
  final KeyValueStore store;

  String _key(Object? key) => '$name:$key';

  @override
  ValueWrapper? get(Object? key) => switch (store.read(_key(key))) {
    null => null,                               // a miss: the method runs
    final json => ValueWrapper(jsonDecode(json)), // a hit (also a stored null)
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
  CacheManager cacheManager(KeyValueStore store) => SimpleCacheManager([
    StoreCache('books', store),   // kept in the store
    InMemoryCache('prices'),      // in memory
  ]);
}
```

What to keep in mind:

- **Return `ValueWrapper` for a hit and `null` for a miss.** `ValueWrapper(null)`
  is a cached `null`; returning plain `null` makes the method run again.
- **Keys** are the method arguments (one argument: the argument itself;
  several: a `SimpleKey`), or what `key:` computes. A store that needs
  strings must turn them into strings: `'$key'` works for strings, numbers
  and `SimpleKey`; for your own classes override `toString`, or set
  `key: '#isbn'` so the key is a string anyway.
- **Values** are whatever the methods return. A store outside memory must
  serialize them: JSON for maps, lists, strings and numbers; your classes
  need `toJson` / `fromJson` (decode in `get` into the right type).
- **The `Cache` interface is synchronous**, as in Spring. For an
  asynchronous store (SQLite, `shared_preferences` in Flutter, a server),
  keep the entries in memory, load the stored ones in the background
  (until then calls are misses: the methods simply run) and write changes
  back in the background:

  ```dart
  import 'dart:async'; // unawaited

  final class WriteBehindCache with CacheDefaults implements Cache {
    WriteBehindCache(this.name, this.store) {
      unawaited(
        store.readAll(prefix: '$name:').then((entries) {
          entries.forEach((key, json) => _memory.putIfAbsent(
            key.substring(name.length + 1),
            () => jsonDecode(json),
          ));
        }),
      );
    }

    @override
    final String name;
    final AsyncStore store;               // Future-based API
    final _memory = <String, Object?>{};

    @override
    ValueWrapper? get(Object? key) =>
        _memory.containsKey('$key') ? ValueWrapper(_memory['$key']) : null;

    @override
    void put(Object? key, Object? value) {
      _memory['$key'] = value;
      unawaited(store.write('$name:$key', jsonEncode(value)));
    }

    @override
    void evict(Object? key) {
      _memory.remove('$key');
      unawaited(store.delete('$name:$key'));
    }

    @override
    void clear() {
      _memory.clear();
      unawaited(store.deleteAll(prefix: '$name:'));
    }
  }
  ```

- **Errors** thrown by your cache reach the caller of the cached method
  (Spring's default too); catch them inside the cache if a broken store
  should only mean "no cache".

### 3. Caches created on demand

`SimpleCacheManager` knows only the caches it was given
(`@Cacheable('other')` then fails with "Cannot find cache named 'other'").
To create caches when they are first named, implement `CacheManager`:

```dart
final class StoreCacheManager implements CacheManager {
  StoreCacheManager(this.store);
  final KeyValueStore store;
  final _caches = <String, Cache>{};

  @override
  Cache? getCache(String name) =>
      _caches.putIfAbsent(name, () => StoreCache(name, store));

  @override
  Iterable<String> get cacheNames => _caches.keys;
}
```

### 4. Several managers

Keep the starter's manager (or your main one) for most methods and use
another one for some: give it a name, hide it from injection by type
(`autowireCandidate: false`), and name it in the annotation:

```dart
@Configuration()
class CacheSetup {
  @Bean(autowireCandidate: false)
  CacheManager sessionCaches(KeyValueStore store) =>
      SimpleCacheManager([StoreCache('sessions', store)]);
}

@Cacheable('sessions', cacheManager: 'sessionCaches')
Session load(String token) => ...;
```

### 5. Your own keys

Implement `KeyGenerator`, declare it as a bean and name it in the
annotation:

```dart
final class IsbnKeys implements KeyGenerator {
  const IsbnKeys();

  @override
  Object? generate(Object target, MethodSignature method, List<Object?> args) =>
      (args.first! as String).replaceAll('-', '');
}

@Configuration()
class Keys {
  @Bean()
  KeyGenerator isbnKeys() => const IsbnKeys();
}

@Cacheable('books', keyGenerator: 'isbnKeys')
Book find(String isbn) => ...;
```

## Testing

Cached results carry over between calls, which can hide behavior in
tests. Switch caching off with a property:

```dart
final app = springBootTest(
  springApplication,
  properties: {'spring.cache.type': 'none'},
);
```

Or keep it on and check the cache through the `CacheManager` bean
(`app.getBean<CacheManager>().getCache('books')!.get('978-0')`).

## Differences from Spring

- No `@EnableCaching`: adding the starter turns caching on;
  `spring.cache.type=none` turns it off.
- `@Cacheable('books')` takes one name; several names go to
  `@Cacheable.of(cacheNames: [...])` (Dart cannot mix an optional
  positional parameter with named ones).
- `#root.caches` holds cache names, `#root.targetClass` the class name.
- `Future` results are cached by value (Spring 6.1 does the same for
  `CompletableFuture`).
- Built-in store: memory, with time to live and size limit (Spring's
  `ConcurrentMapCacheManager` has neither; it needs Caffeine for that).
- Errors thrown by a cache propagate to the caller (Spring's default
  `SimpleCacheErrorHandler`); there is no `CacheErrorHandler` yet.
