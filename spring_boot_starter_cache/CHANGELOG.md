## 0.3.2

- feat: hot reload on the Dart VM, flutter_notes example, fixes for example resources and workspace builds

## 0.3.1

- **Brings logging, like every Spring Boot starter:** depends on and re-exports `spring_boot_starter_logging` (and through it `spring_boot_dart` and `spring_core_dart`), so the starter is the only dependency an application lists, and one import gives everything. An application using it now gets the logging system (Boot's console format, `logging.*` properties) without adding the logging starter; `logging.enabled=false` turns it off.
- The example is a Spring Boot application (`@Cacheable` service, its own `CacheManager`), written by the generator.
- `spring_auto_configuration.dart` re-exports the logging starter's (and through it `spring_boot_dart`'s) auto-configuration, so a test naming `springBootAutoConfiguration` (`ApplicationContextRunner`) needs no other dependency.

## 0.3.0

- feat(spring_boot_starter_flutter): themes from properties, free reads in Spring widgets

## 0.2.3

- add spring application handling
- docs(spring_boot_starter_flutter): add an example for pub.dev

## 0.2.2

- ci: run only the tests of the packages a change affects

## 0.2.1

- feat: spring_boot_starter_flutter, @Log, --dart-define properties, Flutter counter example

## 0.2.0

- the auto-configured `cacheManager` backs off for a `CacheManager` registered by an `@Import`ed `BeanRegistrar` / `ImportBeanDefinitionRegistrar` of the application (there were two); its condition is decided when the auto-configuration is read, like Boot's `OnBeanCondition`
- `@CacheConfig` and class-level cache annotations are read from the class that declares the method's body, then its superclasses (the nearest wins, per annotation type for class-level ones), like Spring's `DefaultCacheConfig(method.getDeclaringClass())` and `findAnnotation`: a base class with `@CacheConfig(cacheNames:)` no longer fails the start, a base class with `@Cacheable` caches its methods in subclass beans, and a subclass's class-level annotations no longer apply to methods it inherits; needs the matching `spring_core_dart` and generator
- Cache annotations on a superclass or mixin method apply to an override without its own (`MethodSignature.mergedAnnotations`, nearest first; its own and its interface declarations' win), like Spring's `AnnotationCacheOperationSource`; needs the matching `spring_core_dart` and generator
- An empty `spring.cache.cache-names=` keeps the caches dynamic, like Boot (it fixed an empty set, so every cache was unknown).
- On a method returning a `Future`, an error before the call (an invalid SpEL `key` or `condition`, a failing cache) is a failed `Future` instead of a synchronous throw.
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
