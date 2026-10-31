# spring_boot_starter_cache

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Caching for [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications: put `@Cacheable` on a bean method, and repeated calls with
the same arguments return the stored result instead of running the method
again.

Some methods are slow or costly and give the same answer for the same
arguments: a network call, a database query, a heavy computation. Keeping
their results by hand means a map per method, keys, invalidation and
expiry, mixed into the business code. With this starter you annotate the
method; the cache sits in front of it. The results live in memory by
default, with an optional time to live and size limit, and you can put
your own storage behind the same annotations.

It is the Dart counterpart of `spring-boot-starter-cache`, for servers and
Flutter apps alike.

```dart
@Service()
class Books {
  Books(this.api);
  final CatalogApi api;

  // Slow: the API is called once per isbn, later calls read the cache.
  @Cacheable('books')
  Future<Book> find(String isbn) => api.load(isbn);

  // The book is gone: so is its cache entry.
  @CacheEvict('books', key: '#isbn')
  Future<void> delete(String isbn) => api.delete(isbn);
}
```

*In the guides:* [server, 8. Cache and scheduling](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#8-cache-and-scheduling), [app, 8. Cache & scheduling](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#8-cache--scheduling).

## Setup

```yaml
dependencies:
  spring_boot_starter_cache: ^0.5.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.5.0   # required: generates the proxies caching runs on
```

```bash
dart run build_runner build
```

Add the dependency and run the generator again: the starter is found and
switched on automatically, there is no `@EnableCaching`.

One import is enough:
`package:spring_boot_starter_cache/spring_boot_starter_cache.dart`
re-exports `spring_boot_dart` and `spring_boot_starter_logging`. The
starter is the only dependency an application needs: it brings the
others, logging included, as every Spring Boot starter does.

### Calls through the proxy only

The generator writes an AOP proxy for each bean (generator option
`aop_proxies`, `all` by default), and the starter registers an advisor
that wraps every method with a cache annotation. So, exactly as in Spring:

- the cache applies to calls **from other beans**, which go through the
  proxy;
- a call through `this` inside the same class goes straight to the method
  and skips the cache. To call a cached method of your own class, inject
  the bean into itself with `@Lazy()`:

```dart
@Service()
class Books implements BookService {
  Books(@Lazy() this._self); // the proxy of this same bean
  final BookService _self;

  @Cacheable('books')
  @override
  Book find(String isbn) => ...;

  List<Book> findAll(List<String> isbns) =>
      [for (final isbn in isbns) _self.find(isbn)]; // cached; find(isbn) would not be
}
```

## Annotations

| Annotation | What it does |
|---|---|
| `@Cacheable('books')` | Returns the cached result when there is one; otherwise runs the method and stores the result. |
| `@CachePut('books', key: '#isbn')` | Always runs the method and stores the result, to refresh the entry. Next to a `@Cacheable` hit, the method runs anyway only when the put's `condition` passes (a condition reading `#result` counts as passing), as in Spring. |
| `@CacheEvict('books', key: '#isbn')` | Removes the entry after the method returned. `allEntries: true` clears the whole cache; `beforeInvocation: true` evicts before the call, so also when it throws. |
| `@Caching(cacheable: [...], put: [...], evict: [...])` | Several operations on one method. Repeating an annotation works too. |
| `@CacheConfig(cacheNames: ['books'])` | On the class: default cache names, `keyGenerator`, `cacheManager` and `cacheResolver` for its methods. |

`@Cacheable`, `@CachePut`, `@CacheEvict` and `@Caching` on a class apply
to every public method that has no cache annotation of its own (not to
getters, setters or `toString`), as in Spring.

Class-level annotations and `@CacheConfig` are read from the class that
declares the method's body and, when it has none, from its superclasses
(the nearest wins), as in Spring. So a base class with `@CacheConfig` or
`@Cacheable` serves the beans that extend it, while a subclass's
class-level annotations do not apply to the methods it inherits.

`@Cacheable('books')` names one cache. For several caches, or to take
them from `@CacheConfig`, use the `.of` constructor:
`@Cacheable.of(cacheNames: ['books', 'isbn'])` or
`@Cacheable.of(key: '#isbn')`; the same for `CachePut.of` and
`CacheEvict.of`.

Options of `@Cacheable` (and of the others, where they make sense):

| Option | Meaning |
|---|---|
| `key` | SpEL computing the key. Default: the arguments (see [Keys](#keys)). |
| `condition` | SpEL; the cache is used only when it is `true`. |
| `unless` | SpEL with `#result`; the result is not stored when it is `true`. It does not prevent a hit. |
| `sync` | For `Future` methods: concurrent calls with the same key share one call (see [Async methods](#async-methods)). |
| `keyGenerator` | The name of a `KeyGenerator` bean computing the key (not with `key`). |
| `cacheManager` | The name of the `CacheManager` bean to use. |
| `cacheResolver` | The name of a `CacheResolver` bean that picks the caches (not with `cacheManager`). |

`@CacheConfig` fills in only what an operation leaves open, as in Spring:
its cache names when the operation names none, its `keyGenerator` when the
operation sets neither `key` nor `keyGenerator`, and its `cacheResolver`
(else its `cacheManager`) when the operation sets neither of those.

The annotations of every proxied bean are checked when the bean is
created, so a wrong combination fails the startup, naming the member,
rather than the first call: `key` with `keyGenerator`, `cacheManager` with
`cacheResolver`, `sync` with other operations, several caches or `unless`,
an operation without cache names (unless a cache resolver picks them),
`@Cacheable` / `@CachePut` on a method returning a `Stream`.

## Keys

Without `key`, the key is made of the arguments, as Spring's
`SimpleKeyGenerator` does: no arguments → `SimpleKey.empty`, one argument
→ the argument itself, several → `SimpleKey([...])`, which compares by
content (lists, sets and maps inside too).

`key`, `condition` and `unless` are SpEL expressions, written plain,
without `#{}`:

| Expression | Value |
|---|---|
| `#isbn` | the argument named `isbn` |
| `#p0`, `#a0` | the first argument |
| `#result` | the result (in `unless`; in `key` and `condition` of `@CachePut`; in `@CacheEvict` after the call) |
| `#root.methodName` | `find` |
| `#root.method.name` | `find` (also `returnType`, `parameterTypes`, `parameterNames`, `parameterCount`) |
| `#root.args` | all arguments, `#root.args[1]` |
| `#root.target` | the bean |
| `#root.targetClass` | the bean's class name, `Books` |
| `#root.caches` | the cache names of the operation |
| `@region` | the bean named `region` |

A key that comes out `null` (from `key` or a key generator) fails the
call with an `ArgumentError`, as in Spring.

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

Reading properties or calling methods of your own objects (`#book.isbn`,
`#result.isbn`, `@clock.zone()`) needs `@Introspected()` on their class:
Dart has no reflection, so the generator writes the accessors SpEL uses.
Strings, numbers, lists and maps work as they are (`#isbn.length()`,
`#tags.size()`).

## Async methods

Methods returning a `Future` cache the **value**, not the future: the
value is stored when the future completes, a hit returns an already
completed `Future`, and errors are never cached, so the next call tries
again.

```dart
// Callers asking for the same price at the same time share one request.
@Cacheable('prices', sync: true)
Future<double> price(String isbn) => api.price(isbn);
```

With `sync: true`, calls that arrive while the first one is still running
wait for it instead of calling `api.price` again. As in Spring, a `sync`
operation must be the only cache annotation of the method, use one cache
and have no `unless`. The waiting is shared per cache and key, not per
method: two `sync` methods that use the same cache and compute the same
key share one pending result, even though they are different methods.

A `Stream` cannot be cached: it can be listened to once, so the cached
stream would fail every later caller. `@Cacheable` and `@CachePut` on a
method returning a `Stream` fail the build (and the startup, for
hand-written proxies). Collect the values instead:

```dart
@Cacheable('events')
Future<List<Event>> recent() => api.events().toList();
```

## The default: caches in memory

Without any setup the starter creates the `cacheManager` bean, an
`InMemoryCacheManager` (Spring's `ConcurrentMapCacheManager`):

- each cache is an `InMemoryCache`, a map in the memory of the running
  app, created the first time an annotation names it (`'books'`, ...);
- entries are lost when the app stops, and when the context restarts
  (also on a hot reload that changes beans): the cache starts empty;
- nothing expires and there is no size limit unless you set them (below);
  the time to live is measured on a monotonic clock, as Caffeine's
  ticker, so setting the device's or server's clock neither keeps
  entries longer nor drops them early;
  expired entries are dropped when they are read, and writes sweep out
  the others now and then (after a burst of writes, the writes a time to
  live or two later do; a cache no longer written keeps them until they
  are read);
- `null` results are stored too: a stored `null` is a hit, as in Spring;
- one app, one isolate: the cache is not shared between processes,
  isolates or devices.

That is right for most caches: results of slow calls that are cheap to
recompute after a restart.

### Properties

The default manager is built from `spring.cache.*`, only when the
application declares no `CacheManager` of its own:

| Property | Default | Meaning |
|---|---|---|
| `spring.cache.type` | `generic` with `Cache` beans, else `simple` | `generic`: a `SimpleCacheManager` of the `Cache` beans (at least one needed); `simple`: caches in memory; `none`: cache nothing (the annotations stay, the methods always run). Another value fails the start |
| `spring.cache.cache-names` | — | a fixed set of caches, such as `books,authors` or a YAML list; an annotation naming another cache then fails. Without it (or empty), caches are created on first use |
| `spring.cache.simple.time-to-live` | none | how long entries live: `10m`, `30s`, `PT1H`, or milliseconds. `0` or more: `0` keeps nothing (as Caffeine's `expireAfterWrite(Duration.ZERO)`); a negative value fails the start with an error naming the property, as Caffeine refuses one |
| `spring.cache.simple.max-size` | none | the most entries per cache; the least recently used go first. `0` or more: `0` keeps nothing (as Caffeine's `maximumSize(0)`); a negative value fails the start with an error naming the property |
| `spring.cache.simple.caches.<name>.time-to-live` | — | the same for one cache (also checked at the start) |
| `spring.cache.simple.caches.<name>.max-size` | — | the same for one cache (also checked at the start) |

A cache name with dots goes in brackets, as in any Spring Boot map
(`spring.cache.simple.caches[books.byIsbn].max-size=2`; in YAML the key
`"[books.byIsbn]":`); written plainly
(`spring.cache.simple.caches.books.byIsbn.max-size`) it works too: the
property is the end of the key (`max-size`, `time-to-live`, or a relaxed
form: `maxSize`, `max_size`, `MAXSIZE`), the rest the cache name. Every
per-cache value is checked at the start, whether the cache exists yet or
not.

In environment variables, as in Spring Boot:
`SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAX_SIZE=5` or `..._BOOKS_MAXSIZE=5`,
`SPRING_CACHE_SIMPLE_CACHES_PRICES_TIME_TO_LIVE=30s` or
`..._PRICES_TIMETOLIVE=30s`. The cache name comes out in lower case, so a
name with capitals or dashes cannot be set this way (in Boot neither); a
`_` inside it is a dot here (`..._BOOKS_BYISBN_MAX_SIZE` sets the cache
`books.byisbn`; Boot binds nothing for it).

```properties
# lib/resources/application.properties
spring.cache.simple.time-to-live=10m
spring.cache.simple.max-size=1000
spring.cache.simple.caches.prices.time-to-live=30s     # prices go stale faster
```

Inject the manager to look at or clear caches by hand:

```dart
// An admin action: drop every cached book.
@Component()
class CacheAdmin {
  CacheAdmin(this.caches);
  final CacheManager caches;

  void clearBooks() => caches.getCache('books')?.clear();
}
```

To adjust the starter's manager without replacing it, for example to
create some caches at startup, declare a `CacheManagerCustomizer` bean:
each one is called once with the new manager. The function
`cacheManagerFromProperties(environment)` builds the same manager for a
`CacheManager` bean of your own, such as one that wraps it.

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

To keep entries somewhere else, such as a file or a key-value database so
they survive a restart, implement `Cache`. With the `CacheDefaults` mixin
four methods are enough; `putIfAbsent`, `evictIfPresent` and `invalidate`
are derived from them. Then hand your caches to a `SimpleCacheManager`
(Spring's `SimpleCacheManager`), alone or mixed with in-memory ones:

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

- **Return `ValueWrapper` for a hit and `null` for a miss.**
  `ValueWrapper(null)` is a cached `null`; returning plain `null` makes the
  method run again.
- **Keys** are the method arguments (one argument: the argument itself;
  several: a `SimpleKey`), or what `key:` computes. A store that needs
  strings must turn them into strings: `'$key'` works for strings, numbers
  and `SimpleKey`; for your own classes override `toString`, or set
  `key: '#isbn'` so the key is a string anyway.
- **Values** are whatever the methods return. A store outside memory must
  serialize them: JSON for maps, lists, strings and numbers; your classes
  need `toJson` / `fromJson` (decode in `get` into the right type).
- **`invalidate()`** of `CacheDefaults` always returns `true`, also for an
  empty cache. The annotations never call it; implement it yourself if
  your code needs to know whether there were entries.
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
  should only mean "no cache", or see `CacheErrorHandler` in
  [section 7](#7-defaults-for-everything-cachingconfigurer).

### 3. Caches created on demand

`SimpleCacheManager` knows only the caches it was given:
`@Cacheable('other')` then fails with "Cannot find cache named 'other'".
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

To keep the starter's manager (or your main one) for most methods and use
another one for some, give the other one a name, hide it from injection by
type (`autowireCandidate: false`), and name it in the annotation:

```dart
@Configuration()
class CacheSetup {
  // Sessions are kept in the store; everything else stays in memory.
  @Bean(autowireCandidate: false)
  CacheManager sessionCaches(KeyValueStore store) =>
      SimpleCacheManager([StoreCache('sessions', store)]);
}

@Cacheable('sessions', cacheManager: 'sessionCaches')
Session load(String token) => ...;
```

### 5. Your own keys

When the arguments do not make a good key as they are, implement
`KeyGenerator`, declare it as a bean and name it in the annotation:

```dart
// "978-0-00" and "978000" are the same book.
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

### 6. Choosing caches per call: `CacheResolver`

A `CacheResolver` decides at each call which caches an operation uses,
for example one cache per tenant. It sees the operation (its cache names,
key, ...), the bean, the method and the arguments. Declare it as a bean
and name it with `cacheResolver:`, in the annotation or in
`@CacheConfig`:

```dart
// Each tenant gets its own caches: "acme.books", "globex.books", ...
final class TenantCacheResolver implements CacheResolver {
  TenantCacheResolver(this.manager, this.tenants);
  final CacheManager manager;
  final TenantContext tenants;

  @override
  Iterable<Cache> resolveCaches(CacheOperationInvocationContext context) => [
    for (final name in context.operation.cacheNames)
      manager.getCache('${tenants.current}.$name')!,
  ];
}

@Configuration()
class CacheSetup {
  @Bean()
  CacheResolver tenantCacheResolver(CacheManager manager, TenantContext tenants) =>
      TenantCacheResolver(manager, tenants);
}

@Cacheable('books', cacheResolver: 'tenantCacheResolver')
Book find(String isbn) => ...;
```

Spring (Java):

```java
@Cacheable(cacheNames = "books", cacheResolver = "tenantCacheResolver")
Book find(String isbn) { ... }
```

Built in: `SimpleCacheResolver(manager)` (the default: the operation's
names in the cache manager) and `NamedCacheResolver(manager, ['audit'])`
(always the same caches; the operations then need no names). As in Spring
Boot, the starter's `cacheManager` backs off when a bean named
`cacheResolver` exists.

### 7. Defaults for everything: `CachingConfigurer`

One bean implementing `CachingConfigurer` sets the defaults of all cache
operations; a method returning `null` (the default) keeps the starter's:

| Method | Default |
|---|---|
| `cacheManager()` | the `CacheManager` bean |
| `cacheResolver()` | `SimpleCacheResolver` of the cache manager |
| `keyGenerator()` | `SimpleKeyGenerator` |
| `errorHandler()` | `SimpleCacheErrorHandler`: cache errors reach the caller |

```dart
@Configuration()
class CacheSetup with CachingConfigurer {
  @override
  KeyGenerator keyGenerator() => const IsbnKeys();

  // A cache that is down: log, run the method, carry on.
  @override
  CacheErrorHandler errorHandler() => const LoggingCacheErrorHandler();
}
```

Spring (Java):

```java
@Configuration
@EnableCaching
class CacheSetup implements CachingConfigurer {
  @Override
  public KeyGenerator keyGenerator() { return new IsbnKeys(); }

  @Override
  public CacheErrorHandler errorHandler() { return new LoggingCacheErrorHandler(); }
}
```

The methods are called once, when caching is first used. Return objects
(or beans injected into the configuration) rather than marking the
methods `@Bean`: Dart does not proxy `@Configuration` classes, so calling
a `@Bean` method creates a second instance.

With a `CacheErrorHandler` that does not rethrow, a failed `get` counts as
a miss (the method runs) and a failed `put`, `evict` or `clear` is
skipped. `LoggingCacheErrorHandler` logs them at warning level to
`spring.cache` (`logStackTraces: true` adds the stack trace).

## Testing

Cached results carry over between calls, which can hide behaviour in
tests. Switch caching off with a property:

```dart
final app = springBootTest(
  springApplication,
  properties: {'spring.cache.type': 'none'},
);
```

Or keep it on and check the cache through the `CacheManager` bean:
`app.getBean<CacheManager>().getCache('books')!.get('978-0')`.

### Time to live in tests

The time to live runs on a monotonic stopwatch, in real time. A `clock`
given to `InMemoryCache` or `InMemoryCacheManager` moves expiry forward
but no longer holds entries alive (since 0.5.0): an entry expires once
its time to live has passed on the stopwatch **or** on the clock. With a
fixed clock and a time to live of 1 second, 0.4.3 still returned an
entry 1.2 seconds later; now it is gone. So, to test expiry:

- **Move a clock, don't wait.** A clock you move by hand needs nothing
  else:

  ```dart
  var now = DateTime.utc(2026);
  final cache = InMemoryCache('books',
      spec: const CacheSpec(timeToLive: Duration(minutes: 10)),
      clock: () => now);
  cache.put('978-0', book);
  now = now.add(const Duration(minutes: 9));
  expect(cache.get('978-0')?.value, book);
  now = now.add(const Duration(minutes: 1)); // the whole time to live
  expect(cache.get('978-0'), isNull);
  ```

- **`fake_async` alone expires nothing.** `async.elapse` moves fake time,
  not the stopwatch: a cache without a clock keeps its entries however
  far you elapse. Give it a clock that follows fake time,
  `() => clock.now()` (package `clock`, which `fakeAsync` fakes) or
  `async.getClock(start).now`, and write and read inside the same
  `fakeAsync`. Write the closure: the tear-off `clock.now` keeps the
  clock of the zone it was taken in, the real one outside `fakeAsync`.

  ```dart
  fakeAsync((async) {
    final cache = InMemoryCache('books',
        spec: const CacheSpec(timeToLive: Duration(minutes: 10)),
        clock: () => clock.now());
    cache.put('978-0', book);
    async.elapse(const Duration(minutes: 9));
    expect(cache.get('978-0')?.value, book);
    async.elapse(const Duration(minutes: 1));
    expect(cache.get('978-0'), isNull);
  });
  ```

- **Choose a long time to live.** Real time expires entries too, whatever
  the clock, so a time to live of a second can expire an entry the test
  still expects on a slow machine. Give minutes and move the clock past
  them. A clock set back before the write also counts as expired (it
  tells nothing then), so don't start a fake clock earlier than the
  writes it reads.
- **In an application test**, the `cacheManager` the starter makes from
  the properties has no clock: declare your own `InMemoryCacheManager`
  bean with the specs and a `clock` (it replaces the starter's), then
  move that clock.

## Differences from Spring

- No `@EnableCaching`: adding the starter turns caching on;
  `spring.cache.type=none` turns it off.
- `@Cacheable('books')` takes one name; several names go to
  `@Cacheable.of(cacheNames: [...])`, because a Dart constructor cannot
  have both an optional positional parameter and named ones.
- `#root.caches` holds cache names, `#root.targetClass` the class name,
  `#root.method` the `MethodSignature` (`name`, `returnType`, ... as
  text).
- `CacheManagerCustomizer` is not generic: every customizer gets the
  manager and checks its type. The container finds beans by their exact
  type, so `CacheManagerCustomizer<InMemoryCacheManager>` could not be
  matched against a manager.
- `Future` results are cached by value (Spring 6.1 does the same for
  `CompletableFuture`).
- The `sync` wait is shared per cache and key, so two different `sync`
  methods with the same cache and key share one pending result.
- Built-in store: memory, with time to live and size limit. Spring's
  `ConcurrentMapCacheManager` has neither; it needs Caffeine for that.
- `spring.cache.simple.time-to-live`, `spring.cache.simple.max-size` and
  `spring.cache.simple.caches.<name>.*` are this starter's: Spring Boot's
  `simple` type has no settings (time to live and size come from Caffeine
  or Redis there, under `spring.cache.caffeine.*` /
  `spring.cache.redis.*`). `spring.cache.type` knows `generic`, `simple`
  and `none` only.
- `SimpleKeyGenerator` wraps a single collection argument in a
  `SimpleKey`, because Dart lists, sets and maps compare by identity and
  the key compares by content; Spring wraps only arrays.
- `Stream` results cannot be cached: `@Cacheable` / `@CachePut` on a
  method returning a `Stream` fail the build. Spring 6.1 collects a `Flux`
  into a list and replays it; a generic interceptor cannot create a
  `Stream<T>` of the right type without reflection. Return a
  `Future<List<T>>`.
- The `Cache` API is a subset of Spring's: `name`, `get`, `put`,
  `putIfAbsent`, `evict`, `evictIfPresent`, `clear`, `invalidate`. There
  is no `get(key, Class)`, `get(key, Callable)` (value loader), `retrieve`
  (asynchronous) or `getNativeCache`.
- `invalidate()` returns `true` for a cache that had nothing left to
  remove in two cases: `CacheDefaults` always returns `true`, and
  `InMemoryCache` counts entries that have expired but were neither read
  nor swept out yet.
- `CachingConfigurer` methods are called once; they must not be `@Bean`
  methods (no `@Configuration` proxies in Dart). `CacheErrorHandler`
  methods receive the stack trace next to the error.
- Annotations are checked when the bean is created, for every member;
  the `sync` rules too (Spring checks those at the first call).
