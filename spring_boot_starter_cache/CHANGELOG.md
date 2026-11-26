## 0.10.0

- **Breaking (entries on disk):** a key's stable form is JSON (`canonicalCacheKey`), so no two keys share it; a key without one (an object the `ObjectMapper` does not read, a record, a class whose qualified name another shares) is not kept, logged once. Entries written by 0.9 are not read again, except one under the key `null`, whose form did not change. Values and keys name their class by `Introspection.qualifiedName`, so two classes `Book` of two libraries are not confused.
- A disk-cache entry expires within the run too (`get` and `retrieve` answered from the entries this run read or wrote, without their expiry); an expired or unreadable entry is deleted when found; `invalidate()` is `true` only for entries this run knew of.
- `spring.cache.disk.max-size`: a put no longer reads every file of the cache (sizes read once a run, then kept): 1000 puts of 4 KB in 1.4 s, was 40 s for 200.
- A cache name is one folder segment (`users/admins` is not inside `users`; `..` stays inside the caches' folder).
- `@Cacheable(sync: true)` on a disk cache computes once for concurrent callers, the store's read included.
- An invalid cache annotation fails a `Future` method through its `Future` in a release build too (without the startup check).
- `spring.cache.type: disk` without a `CacheStore` where there are no folders (a browser) fails the start.
- `LayeredCache`: a `null` goes past a layer that keeps no `null`, to the others; the documentation says that a copy into a faster layer lives that layer's whole time to live.
- `DirectoryCacheStore`: a folder it makes is private (`rwx------`), temporary files have names from `Random.secure` and are made exclusively, a folder that is a symbolic link is refused.
- The startup check is left out when `spring.main.startup-checks.enabled=false` at run time.

## 0.9.0

- Its code names the introspection classes by their new names (`Introspector`, `Introspection`, `IntrospectedProperty`, `IntrospectedMethod`, `IntrospectedConstructor`, `IntrospectedParameter`; spring_core_dart's renames); nothing changes for its users.

## 0.8.4

- **The startup check leaves the release build:** `cacheOperationValidator`, which checks the cache annotations of every proxied bean when it is created, is in a module of its own, `springBootStarterCacheStartupChecksAutoConfiguration`, in the build by `spring.main.startup-checks.enabled`: not set, in debug and profile builds only, so a release build ships none of its code (a wrong annotation then fails at the member's first call, where the interceptor checks it); `true` in `application.yml` or `application.properties` keeps it in every build, `false` in none. `CacheOperationValidator` is in a file of its own, still exported by the library.

## 0.8.3

- `spring.cache.type: disk`: caches whose entries are kept on disk and survive a restart (`DiskCacheManager`): the app's `cache` place in Flutter (the Flutter starter's `CacheStore`), a folder elsewhere (`spring.cache.disk.directory`, `DirectoryCacheStore`). One file an entry, `spring/caches/<cache>/<hash of the key>.json`, with its key, its expiry by the wall clock (`spring.cache.disk.time-to-live`, per cache `caches.<name>.time-to-live`), its version (`spring.cache.disk.version`: an entry of another one is not read) and the value as JSON through the application's `ObjectMapper` (`String`, numbers, `bool`, `null`, an object the mapper reads, a `List`, `Set` or `Map<String, …>` of those, a `Resource` with an address, kept as its address); another value is not kept, and logged once. `spring.cache.disk.max-size` keeps each cache under a number of bytes, the oldest written going first.
- `AsyncCache`, a cache whose store answers later: Spring's `Cache.retrieve`. For a method that returns a `Future` the interceptor waits for it; a put, an evict and a clear start at once and finish in order. A method that does not return a `Future` on such a cache is a start-up error naming the method and the cache.
- `CompositeCacheManager`, Spring's: a cache name looked up in several managers, the first that has it giving it (`fallbackToNoOpCache` for a name none has).
- `LayeredCacheManager` and `LayeredCache` (not Spring's): a fast cache in front of slower ones (memory in front of the disk), a hit in a slower one copied into the faster ones, a put and an evict going to every layer.
- `spring.cache.resource-version` (off by default): a key made of a `VersionedResource` (a file the Flutter starter keeps) is its address and its content's version, so a result made from a file that changed at the same address is made again (`SimpleKeyGenerator(resourceVersion: true)`).

## 0.8.2

- No changes of its own; released with the family version 0.8.2.

## 0.8.1

- No changes of its own; released with the family version 0.8.1.

## 0.8.0

- `KeyScopingCache`: a `Cache` that keeps its entries under another key than the one it is asked with (one that adds the caller or a tenant) says so with `storedKey`. **Fixed** with it: `@Cacheable(sync: true)` shared one run of the method between every call that missed the same key of the annotation at once, also when the cache keeps that key apart per caller, so one caller could get the answer of another.

## 0.7.4

- `InMemoryCacheManager` (the default) and `SimpleCacheManager` are `IsolateLocalState`: a pool of server isolates names them in its warning, each isolate having its own cached values.

## 0.7.3

- No changes of its own; released with the family version 0.7.3.

## 0.7.2

- README: the link goes to the package's own page on farum-azula.org, and what the README says was checked against the code and brought up to date.
- The package's page on pub.dev links its documentation, [farum-azula.org](https://farum-azula.org) (`documentation` in `pubspec.yaml`).

## 0.7.1

- No changes of its own; released with the family version 0.7.1.

## 0.7.0

- No changes of its own: its generated code (`lib/spring_gen/`) is regenerated with spring_core_dart_generator 0.7.0.

## 0.6.3

### Changes

- The editor metadata of `spring.cache.*` is made from code and the starter reads the same classes: `CacheProperties` (`type` is the `CacheType` enum, `cache-names`, `simple.*`) is bound by the Binder, and `cacheManagerFromProperties` takes it before the `Environment`. The hand-written `spring_metadata_additional.json` is gone.

## 0.6.2

- No changes of its own; released with the family version 0.6.2.

## 0.6.1

- No changes of its own; released with the family version 0.6.1.

## 0.6.0

### Changes

- `CacheAnnotationPointcut.annotationTypes` lists the annotations the pointcut matches (`@Cacheable`, `@CachePut`, `@CacheEvict`, `@Caching`); the generator reads it to give a proxy class only to the beans that carry one (smaller generated code; regenerate the `.spring.dart` files).

## 0.5.0

### Breaking

- A negative `spring.cache.simple.max-size` or `time-to-live`, also a per-cache one, fails the start with an error naming the property, as Caffeine refuses them (a negative size hung the isolate); `0` is allowed and keeps nothing.
- The time to live is measured on a monotonic stopwatch, as Caffeine's ticker: `InMemoryCache(clock:)` and `InMemoryCacheManager(clock:)` have no clock by default, an injected clock no longer holds entries alive (real time expires them too), and a clock set back before a write expires the entry. Tests with a fixed clock and a short time to live change (see "Time to live in tests" in the README).
- Boot's bracket form for a cache name with dots applies (`spring.cache.simple.caches[books.byIsbn].max-size`), and every per-cache value is checked at the start, whether its cache exists yet or not.

### Changes

- Per-cache settings bind from any relaxed form and from environment variables, as in Boot: `SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAX_SIZE=5`.
- Writes sweep out expired entries now and then, also after a burst of writes, so a cache with only a time to live no longer keeps them until they are read.
- A full cache drops its least recently used entry in constant time (it took longer the larger `max-size` was).

## 0.4.3

- Flutter security (#15)
- feat: single sign-on with OAuth 2.0 / OpenID Connect (spring_boot_sta… (#11)
- docs: the READMEs and docs/ rewritten: what it is, why and when you need it, an example, then Spring (#10)

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- No more "Bean 'cacheInterceptor' ... is not eligible for getting processed by all BeanPostProcessors" at startup: the annotation validator asks for the interceptor at the first cached bean (`CacheOperationValidator.lazy`; the constructor taking the interceptor stays).

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
