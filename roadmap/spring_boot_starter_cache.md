# spring_boot_starter_cache

Done: `@Cacheable`, `@CachePut`, `@CacheEvict`, `@Caching` with SpEL keys
and conditions, the in-memory `CacheManager` with TTL and size limits.

## Cache stores

Persistent stores (SQLite, files, `shared_preferences` in Flutter) behind
the same `Cache` interface, cache statistics.
