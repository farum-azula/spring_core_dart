import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_supabase/src/config/supabase_properties.dart';
import 'package:spring_boot_starter_supabase/src/supabase_credentials.dart';

/// A cache key that carries who the cached call was made as.
///
/// With row-level security one call answers differently per user; a key
/// made of the arguments alone would hand one user's rows to another, or
/// an answer read as the service role to a user.
final class SupabaseCacheKey {
  /// The [key] of a call made as [caller] (`SupabaseCaller.key`).
  const SupabaseCacheKey(this.caller, this.key);

  /// `anon`, `user:<id>` or `service`.
  final String caller;

  /// The key itself: what the arguments or the `key:` expression gave.
  final Object? key;

  @override
  bool operator ==(Object other) =>
      other is SupabaseCacheKey && other.caller == caller && other.key == key;

  @override
  int get hashCode => Object.hash(caller, key);

  @override
  String toString() => '$caller/$key';
}

/// The default `KeyGenerator` with this starter (the bean
/// `supabaseKeyGenerator`): the key is who calls, plus the arguments.
///
/// ```dart
/// @Cacheable('todos')            // one entry per user and list
/// Future<List<Todo>> open(String listId) => todos.findByListId(listId);
/// ```
///
/// An application with a `CachingConfigurer` of its own names it where it
/// is wanted (`@Cacheable('todos', keyGenerator: 'supabaseKeyGenerator')`)
/// or calls it from its own generator.
///
/// Spring (Java): a `KeyGenerator` bean; Spring's default is
/// `SimpleKeyGenerator`, which this one wraps.
final class SupabaseKeyGenerator implements KeyGenerator {
  /// A generator asking [credentials] who calls.
  const SupabaseKeyGenerator(this.credentials);

  /// Who the current call is made as.
  final SupabaseCredentials credentials;

  @override
  Object? generate(Object target, MethodSignature method, List<Object?> args) =>
      SupabaseCacheKey(
        credentials.caller.key,
        SimpleKeyGenerator.generateKey(args),
      );
}

/// The default `CacheResolver` with this starter (the bean
/// `supabaseCacheResolver`): it gives the caches of the cache manager,
/// each keeping the entries of every caller apart, whatever made the key.
///
/// An explicit `key:` goes past any `KeyGenerator` (the cache starter's
/// rule, as in Spring), so [SupabaseKeyGenerator] alone would leave
/// `@Cacheable('todos', key: '#listId')` shared between users. The caches
/// given here add the caller to such a key, and leave a key that already
/// has it as it is.
///
/// A cache named in `spring.supabase.cache.shared` is the exception: its
/// entries are the same for everyone, and no key of it carries a caller.
final class SupabaseCacheResolver implements CacheResolver {
  /// A resolver over [cacheManager], asking [credentials] who calls;
  /// [properties] name the shared caches.
  SupabaseCacheResolver({
    required this.cacheManager,
    required this.credentials,
    required SupabaseCacheProperties properties,
  }) : shared = Set.unmodifiable(properties.shared);

  /// Where the caches come from.
  final CacheManager cacheManager;

  /// Who the current call is made as.
  final SupabaseCredentials credentials;

  /// The names of the caches whose entries are the same for everyone.
  final Set<String> shared;

  final _caches = <String, Cache>{};

  @override
  Iterable<Cache> resolveCaches(CacheOperationInvocationContext context) => [
    for (final name in context.operation.cacheNames) _cache(name, context),
  ];

  Cache _cache(String name, CacheOperationInvocationContext context) {
    final cache = cacheManager.getCache(name);
    if (cache == null) {
      throw StateError(
        "Cannot find cache named '$name' for "
        '${context.operation.description}',
      );
    }
    final scoped = _caches[name];
    if (scoped is _CallerCache && identical(scoped.cache, cache)) {
      return scoped;
    }
    return _caches[name] = _CallerCache(
      cache,
      credentials,
      shared: shared.contains(name),
    );
  }
}

// A cache whose keys carry the caller (or, for a shared cache, never do).
final class _CallerCache implements Cache {
  _CallerCache(this.cache, this.credentials, {required this.shared});

  final Cache cache;
  final SupabaseCredentials credentials;
  final bool shared;

  Object? _key(Object? key) => switch (key) {
    final SupabaseCacheKey scoped => shared ? scoped.key : scoped,
    _ => shared ? key : SupabaseCacheKey(credentials.caller.key, key),
  };

  @override
  String get name => cache.name;

  @override
  ValueWrapper? get(Object? key) => cache.get(_key(key));

  @override
  void put(Object? key, Object? value) => cache.put(_key(key), value);

  @override
  ValueWrapper? putIfAbsent(Object? key, Object? value) =>
      cache.putIfAbsent(_key(key), value);

  @override
  void evict(Object? key) => cache.evict(_key(key));

  @override
  bool evictIfPresent(Object? key) => cache.evictIfPresent(_key(key));

  @override
  void clear() => cache.clear();

  @override
  bool invalidate() => cache.invalidate();
}

/// The `CachingConfigurer` of this starter (the bean
/// `supabaseCachingConfigurer`, unless the application has a
/// `CachingConfigurer` of its own): [SupabaseKeyGenerator] and
/// [SupabaseCacheResolver] as the defaults of `@Cacheable`, `@CachePut`
/// and `@CacheEvict`.
final class SupabaseCachingConfigurer with CachingConfigurer {
  /// The defaults [generator] and [resolver].
  SupabaseCachingConfigurer({required this.generator, required this.resolver});

  /// The default key generator.
  final KeyGenerator generator;

  /// The default cache resolver.
  final CacheResolver resolver;

  @override
  KeyGenerator? keyGenerator() => generator;

  @override
  CacheResolver? cacheResolver() => resolver;
}
