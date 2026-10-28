import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache.dart';
import 'package:spring_boot_starter_cache/src/cache_operation.dart';

/// What a [CacheResolver] knows about the call it picks caches for: the
/// cache operation, the bean, the method and the arguments.
///
/// The framework creates it for each cache operation of each call; you
/// only read it, inside [CacheResolver.resolveCaches]. One method with
/// both `@Cacheable` and `@CacheEvict` gives two contexts per call.
///
/// Spring (Java): `CacheOperationInvocationContext`.
abstract interface class CacheOperationInvocationContext {
  /// The cache annotation being applied, with the class's `@CacheConfig`
  /// defaults filled in: its cache names, key, condition and so on.
  CacheOperation get operation;

  /// The bean the method is called on (the real bean, not its proxy).
  Object get target;

  /// The called method: its name, parameter names and types, annotations.
  MethodSignature get method;

  /// The arguments of the call, in parameter order.
  List<Object?> get args;
}

/// Decides, at each call, which caches a cache annotation uses.
///
/// Normally the caches are fixed: the names in the annotation, looked up in
/// the `CacheManager` by a [SimpleCacheResolver]. A resolver of your own
/// can choose them from the call instead, for example one cache per
/// customer of a multi-tenant app, or always the same audit cache whatever
/// the annotation names ([NamedCacheResolver]). Declare it as a bean and
/// name it with `cacheResolver:` in the annotation or in `@CacheConfig`,
/// or make it the default with a `CachingConfigurer`.
///
/// ```dart
/// // Caches per tenant: `books` becomes `acme.books`.
/// final class TenantCacheResolver implements CacheResolver {
///   TenantCacheResolver(this.manager, this.tenants);
///   final CacheManager manager;
///   final TenantContext tenants;
///
///   @override
///   Iterable<Cache> resolveCaches(
///     CacheOperationInvocationContext context,
///   ) => [
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
  /// The caches the operation of [context] reads or writes on this call.
  /// At least one is needed: an empty result fails the call with a
  /// `StateError`.
  Iterable<Cache> resolveCaches(CacheOperationInvocationContext context);
}

/// The [CacheResolver] used by default: it looks the cache names of the
/// annotation up in a [CacheManager].
///
/// An unknown name fails the call with a `StateError` ("Cannot find cache
/// named ..."). Every operation uses one, unless it names a
/// `cacheResolver`; you build one yourself mainly to wrap it, or to return
/// it from a `CachingConfigurer` with another manager.
///
/// ```dart
/// // A resolver of your own that falls back to the names of the annotation.
/// final fallback = SimpleCacheResolver(cacheManager);
/// ```
///
/// Spring (Java):
/// ```java
/// CacheResolver resolver = new SimpleCacheResolver(cacheManager);
/// ```
final class SimpleCacheResolver implements CacheResolver {
  /// A resolver looking the caches up in [cacheManager].
  SimpleCacheResolver(this.cacheManager);

  /// The manager the cache names are looked up in.
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

/// A [CacheResolver] that always gives the same caches, whatever the
/// annotation names.
///
/// Use it to send several methods to one set of caches chosen in one
/// place. The annotations that use it need no cache names. An unknown name
/// fails the call with a `StateError`.
///
/// ```dart
/// // Every operation naming `cacheResolver: 'auditResolver'` uses `audit`.
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
  /// A resolver that always looks [cacheNames] up in [cacheManager].
  NamedCacheResolver(this.cacheManager, List<String> cacheNames)
    : cacheNames = List.unmodifiable(cacheNames);

  /// The manager the names are looked up in.
  final CacheManager cacheManager;

  /// The caches every operation uses, unmodifiable.
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
