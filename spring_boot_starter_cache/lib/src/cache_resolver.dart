import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache.dart';
import 'package:spring_boot_starter_cache/src/cache_operation.dart';

/// One cache operation of an intercepted call, like Spring's
/// `CacheOperationInvocationContext`: what a [CacheResolver] decides on.
abstract interface class CacheOperationInvocationContext {
  /// The operation (its cache names, key, ...).
  CacheOperation get operation;

  /// The bean the method is called on.
  Object get target;

  /// The called member.
  MethodSignature get method;

  /// The arguments of the call.
  List<Object?> get args;
}

/// Picks the caches of a cache operation at each call, like Spring's
/// `CacheResolver`: name a `CacheResolver` bean with `cacheResolver:` (in
/// the annotation or in `@CacheConfig`), or make it the default with a
/// `CachingConfigurer`. Without one, a [SimpleCacheResolver] looks the
/// operation's cache names up in the `CacheManager`.
///
/// ```dart
/// // Caches per tenant: `books` becomes `acme.books`.
/// final class TenantCacheResolver implements CacheResolver {
///   TenantCacheResolver(this.manager, this.tenants);
///   final CacheManager manager;
///   final TenantContext tenants;
///
///   @override
///   Iterable<Cache> resolveCaches(CacheOperationInvocationContext context) => [
///     for (final name in context.operation.cacheNames)
///       manager.getCache('${tenants.current}.$name')!,
///   ];
/// }
///
/// @Cacheable('books', cacheResolver: 'tenantCacheResolver')
/// Book find(String isbn) => ...;
/// ```
///
/// Spring (Java):
/// ```java
/// class TenantCacheResolver implements CacheResolver {
///   public Collection<? extends Cache> resolveCaches(
///       CacheOperationInvocationContext<?> context) { ... }
/// }
///
/// @Cacheable(cacheNames = "books", cacheResolver = "tenantCacheResolver")
/// Book find(String isbn) { ... }
/// ```
abstract interface class CacheResolver {
  /// The caches of [context]'s operation; at least one, or the call fails.
  Iterable<Cache> resolveCaches(CacheOperationInvocationContext context);
}

/// The default [CacheResolver], like Spring's `SimpleCacheResolver`: the
/// operation's cache names looked up in [cacheManager]; an unknown name
/// fails the call ("Cannot find cache named ...").
///
/// ```dart
/// final resolver = SimpleCacheResolver(InMemoryCacheManager());
/// ```
///
/// Spring (Java):
/// ```java
/// CacheResolver resolver = new SimpleCacheResolver(cacheManager);
/// ```
final class SimpleCacheResolver implements CacheResolver {
  /// A resolver looking caches up in [cacheManager].
  SimpleCacheResolver(this.cacheManager);

  /// Where the caches come from.
  final CacheManager cacheManager;

  @override
  Iterable<Cache> resolveCaches(CacheOperationInvocationContext context) => [
    for (final name in context.operation.cacheNames)
      cacheManager.getCache(name) ??
          (throw StateError(
            "Cannot find cache named '$name' for "
            '${context.operation.description}',
          )),
  ];

  @override
  String toString() => 'SimpleCacheResolver($cacheManager)';
}

/// A [CacheResolver] that always resolves [cacheNames] in [cacheManager],
/// whatever the operation names, like Spring's `NamedCacheResolver`.
///
/// ```dart
/// @Bean()
/// CacheResolver auditResolver(CacheManager manager) =>
///     NamedCacheResolver(manager, ['audit']);
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// CacheResolver auditResolver(CacheManager manager) {
///   return new NamedCacheResolver(manager, "audit");
/// }
/// ```
final class NamedCacheResolver implements CacheResolver {
  /// A resolver of [cacheNames] in [cacheManager].
  NamedCacheResolver(this.cacheManager, List<String> cacheNames)
    : cacheNames = List.unmodifiable(cacheNames);

  /// Where the caches come from.
  final CacheManager cacheManager;

  /// The caches every operation uses.
  final List<String> cacheNames;

  @override
  Iterable<Cache> resolveCaches(CacheOperationInvocationContext context) => [
    for (final name in cacheNames)
      cacheManager.getCache(name) ??
          (throw StateError(
            "Cannot find cache named '$name' for "
            '${context.operation.description}',
          )),
  ];

  @override
  String toString() => 'NamedCacheResolver($cacheNames)';
}
