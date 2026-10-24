## Unreleased

- Class-level `@Cacheable` / `@CachePut` / `@CacheEvict` / `@Caching` apply to every public method without cache annotations of its own, like Spring (they were ignored).
- `#root.method.name` (and `returnType`, `parameterTypes`, `parameterNames`, `parameterCount`) in cache SpEL.
- A `null` cache key fails the call with an `ArgumentError`, like Spring (it was used as a key).
- `spring.cache.type=generic`, the default when there are `Cache` beans: a `SimpleCacheManager` of them, like Boot's `GenericCacheConfiguration`.
- `CacheManagerCustomizer` beans customize the auto-configured manager; `cacheManagerFromProperties(caches:, customizers:)`.
- `CacheAnnotationPointcut` is an `AnnotationPointcut`, so the cache advisor keeps proxy pruning on
- a `@CachePut` whose `condition` fails before the call no longer forces a `@Cacheable` hit to run the method (Spring's `hasCachePut`; a condition reading `#result` still counts as passing)
- `spring.cache.cache-names` accepts a YAML list (`spring.cache.cache-names[0]`)

## 0.1.7

- `@CacheConfig` defaults apply like Spring's: `keyGenerator` only to operations without `key` and `keyGenerator` (a `key` next to `@CacheConfig(keyGenerator:)` no longer throws), `cacheManager` / `cacheResolver` only to operations without either.
- Breaking: cache annotations are validated when a proxied bean is created (every member, at startup) instead of at the first call: invalid combinations now fail the start.
- Breaking: `@Cacheable` / `@CachePut` on a method returning a `Stream` fail the build (generator) and the startup; return a `Future<List<T>>`.
- `cacheResolver:` on `@Cacheable`, `@CachePut`, `@CacheEvict` and `@CacheConfig`; `CacheResolver`, `SimpleCacheResolver`, `NamedCacheResolver`, `CacheOperationInvocationContext`; public `CacheOperation` types (`CacheableOperation`, `CachePutOperation`, `CacheEvictOperation`) and `AnnotationCacheOperationSource`.
- `CachingConfigurer` (default cache manager, cache resolver, key generator, error handler) and `CacheErrorHandler` (`SimpleCacheErrorHandler`, `LoggingCacheErrorHandler`).
- The starter's `cacheManager` also backs off when a bean named `cacheResolver` exists, like Spring Boot.
- `CacheInterceptor` takes `cacheResolver:` and `errorHandler:`; its `keyGenerator` / `cacheManager` defaults are resolved lazily (argument, else `CachingConfigurer`, else `SimpleKeyGenerator` / the `CacheManager` bean).

## 0.1.6

- update road map
- ci: release with a button on main, skip new packages when publishing; shorter pubspec descriptions

## 0.1.5

- add feign runner + web socket runner
- add web core + faign starter for http calling

## 0.1.4

- feat: ObjectMapper in core — JSON on generated metadata (@Introspected, @JsonProperty/@JsonIgnore/@JsonInclude/@JsonCreator/@JsonValue), spring.jackson.* in Boot

## 0.1.3

- Initial version: @Cacheable, @CachePut, @CacheEvict, @Caching; CacheManager.
