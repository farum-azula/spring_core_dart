# spring_boot_starter_cache

Done: `@Cacheable`, `@CachePut`, `@CacheEvict`, `@Caching` with SpEL keys
and conditions, the in-memory `CacheManager` with TTL and size limits.

## An asynchronous cache (planned; the owner, November 2026)

The `Cache` interface is synchronous (`ValueWrapper? get(key)`,
`void put(...)`), so only a store that answers at once fits behind it:
memory, a synchronous SQLite, a file. A store over the network (Redis,
one cache for every isolate and server) or an asynchronous one
(`shared_preferences`, IndexedDB) does not. Spring has `Cache.retrieve`
(a `CompletableFuture`) since 6.1.

- `Cache` and `CacheManager` answer `FutureOr` (`get`, `put`, `evict`,
  `clear`, `putIfAbsent`), and the `CacheInterceptor` with them:
  `sync: true`, `@CachePut`, `@CacheEvict(beforeInvocation:)`, the
  `CacheErrorHandler`.
- `FutureOr`, not `Future` (the owner, November 2026): the in-memory
  cache answers at once, so `@Cacheable` on a method that is not
  asynchronous (`Book? find(String isbn)`, used in the server guide; a
  value needed in a Flutter `build`) keeps working and nothing breaks.
  Such a method on a store that answers later (Dart cannot wait for a
  `Future` there) is a startup error naming the method and the store. An
  asynchronous method takes the value without an extra turn of the event
  loop when the store answered at once.
- Then the stores below, and one over the network.

## Cache stores

Persistent stores (SQLite, files, `shared_preferences` in Flutter) behind
the same `Cache` interface, cache statistics.
