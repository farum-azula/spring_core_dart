import 'package:spring_boot_starter_cache/src/cache.dart';

/// The limits of an in-memory cache: how long an entry lives, and how many
/// entries the cache keeps.
///
/// Without limits an [InMemoryCache] keeps every entry until the app
/// stops, which is wrong for data that goes stale or for caches with many
/// keys. A spec fixes both: an entry expires a set time after it was
/// written, and when the cache is full the least recently used entry goes
/// first. Most applications set the limits with properties; build a spec
/// in code when you declare an [InMemoryCacheManager] yourself.
///
/// ```dart
/// // Prices change often: keep them 30 seconds, at most 1000 of them.
/// InMemoryCacheManager(
///   specs: {
///     'prices': const CacheSpec(
///       timeToLive: Duration(seconds: 30),
///       maxSize: 1000,
///     ),
///   },
/// )
/// ```
///
/// The same with properties, for the starter's manager:
/// ```properties
/// spring.cache.simple.time-to-live=10m
/// spring.cache.simple.max-size=1000
/// spring.cache.simple.caches.prices.time-to-live=30s
/// ```
///
/// Spring (Java) has no limits on its in-memory `ConcurrentMapCache`; they
/// come with Caffeine:
/// ```java
/// Caffeine.newBuilder()
///     .expireAfterWrite(Duration.ofMinutes(10)).maximumSize(1000)
/// ```
final class CacheSpec {
  /// Entries expire [timeToLive] after they were written (never when
  /// `null`); at most [maxSize] entries are kept (no limit when `null`).
  /// [maxSize] must be positive.
  const CacheSpec({this.timeToLive, this.maxSize})
    : assert(maxSize == null || maxSize > 0, 'maxSize must be positive');

  /// No expiry and no size limit: the default of every in-memory cache.
  static const unlimited = CacheSpec();

  /// How long an entry lives after it was last written; `null` for ever.
  /// Reading an entry does not extend its life.
  final Duration? timeToLive;

  /// The most entries the cache keeps; `null` for no limit. A new entry
  /// beyond it removes the least recently read or written one.
  final int? maxSize;

  @override
  String toString() => 'CacheSpec(timeToLive: $timeToLive, maxSize: $maxSize)';
}

/// A [Cache] that keeps its entries in a map in the memory of the running
/// app, with an optional time to live and size limit ([CacheSpec]).
///
/// It is the cache behind the annotations by default: the starter's
/// [InMemoryCacheManager] creates one per cache name. Entries are lost when
/// the app stops or the context restarts, and are not shared between
/// isolates or processes. That suits results of slow calls that are cheap
/// to compute again. Expired entries are not removed by a timer: an expired
/// entry counts as a miss and is dropped when it is read. `null` values are
/// stored like any other unless [allowNullValues] is `false`.
///
/// Build one yourself to mix it with caches of your own in a
/// [SimpleCacheManager], or in a test.
///
/// ```dart
/// // Books kept 5 minutes in memory, next to a cache of your own.
/// SimpleCacheManager([
///   InMemoryCache('books',
///       spec: const CacheSpec(timeToLive: Duration(minutes: 5))),
///   StoreCache('sessions', store),
/// ]);
/// ```
///
/// Spring (Java):
/// ```java
/// Cache cache = new ConcurrentMapCache("books");
/// cache.put("978-0", book);
/// ```
final class InMemoryCache implements Cache {
  /// A cache named [name] with the limits of [spec] (none by default).
  /// [clock] gives the current time for the time to live (`DateTime.now`
  /// by default; tests pass a fake one). With [allowNullValues] `false`,
  /// storing `null` throws an `ArgumentError`.
  InMemoryCache(
    this.name, {
    this.spec = CacheSpec.unlimited,
    this.allowNullValues = true,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  @override
  final String name;

  /// The time to live and size limit of the entries.
  final CacheSpec spec;

  /// Whether `null` can be stored. `true` by default, as in Spring: a
  /// method that returned `null` is then a hit on the next call. When
  /// `false`, [put] of `null` throws an `ArgumentError`.
  final bool allowNullValues;

  final DateTime Function() _clock;

  // Insertion order = recency: a read moves the entry to the end, so the
  // first entry is the least recently used one.
  final _entries = <Object?, _Entry>{};

  /// The number of entries, including expired ones that were not read
  /// since they expired.
  int get size => _entries.length;

  @override
  ValueWrapper? get(Object? key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    if (entry.expiresAt case final expiresAt?
        when !_clock().isBefore(expiresAt)) {
      return null;
    }
    _entries[key] = entry;
    return ValueWrapper(entry.value);
  }

  @override
  void put(Object? key, Object? value) {
    if (value == null && !allowNullValues) {
      throw ArgumentError(
        "Cache '$name' is configured to not allow null values but null was "
        'provided',
      );
    }
    final ttl = spec.timeToLive;
    _entries
      ..remove(key)
      ..[key] = _Entry(value, ttl == null ? null : _clock().add(ttl));
    if (spec.maxSize case final maxSize?) {
      while (_entries.length > maxSize) {
        _entries.remove(_entries.keys.first);
      }
    }
  }

  @override
  ValueWrapper? putIfAbsent(Object? key, Object? value) {
    final existing = get(key);
    if (existing != null) {
      return existing;
    }
    put(key, value);
    return null;
  }

  @override
  void evict(Object? key) => _entries.remove(key);

  @override
  bool evictIfPresent(Object? key) => get(key) != null && _remove(key);

  bool _remove(Object? key) => _entries.remove(key) != null;

  @override
  void clear() => _entries.clear();

  @override
  bool invalidate() {
    final had = _entries.isNotEmpty;
    _entries.clear();
    return had;
  }

  @override
  String toString() => 'InMemoryCache($name, ${_entries.length} entries)';
}

final class _Entry {
  _Entry(this.value, this.expiresAt);

  final Object? value;
  final DateTime? expiresAt;
}

/// A [CacheManager] of [InMemoryCache]s, created the first time a name is
/// asked for: the manager the starter uses by default.
///
/// Without any setup, the starter builds one from the `spring.cache.*`
/// properties, so most applications never create it themselves. Declare
/// it as your own `CacheManager` bean to set the same things in code:
/// a fixed set of caches, limits for all caches ([defaultSpec]), for some
/// ([specs]) or computed by name ([specFor]). With `cacheNames` the set
/// of caches is fixed, and an annotation naming another cache fails the
/// call with "Cannot find cache named ...".
///
/// ```dart
/// @Configuration()
/// class CacheSetup {
///   // Two caches only; prices go stale faster than books.
///   @Bean()
///   CacheManager cacheManager() => InMemoryCacheManager(
///     cacheNames: ['books', 'prices'],
///     defaultSpec: const CacheSpec(timeToLive: Duration(minutes: 10)),
///     specs: {'prices': const CacheSpec(timeToLive: Duration(seconds: 30))},
///   );
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// CacheManager manager = new ConcurrentMapCacheManager(); // dynamic
/// CacheManager fixed = new ConcurrentMapCacheManager("books", "authors");
/// ```
final class InMemoryCacheManager implements CacheManager {
  /// A manager whose caches take their limits from [specs] by name, then
  /// [specFor], then [defaultSpec].
  ///
  /// When `cacheNames` is given, those caches are created now and no other
  /// exists; when it is `null` (the default), caches are created on demand.
  /// [allowNullValues] applies to every cache, and `clock` gives them the
  /// current time (`DateTime.now` by default; tests pass a fake one).
  InMemoryCacheManager({
    Iterable<String>? cacheNames,
    this.defaultSpec = CacheSpec.unlimited,
    Map<String, CacheSpec> specs = const {},
    this.specFor,
    this.allowNullValues = true,
    this._clock,
  }) : specs = Map.unmodifiable(specs),
       dynamic = cacheNames == null {
    for (final name in cacheNames ?? const <String>[]) {
      _caches[name] = _create(name);
    }
  }

  /// The limits of caches that have none in [specs] or [specFor]; no
  /// limits by default.
  final CacheSpec defaultSpec;

  /// The limits of particular caches, by cache name.
  final Map<String, CacheSpec> specs;

  /// Computes the limits of a cache from its name, for limits that are not
  /// known in advance (the starter reads them from properties here). A
  /// `null` result falls back to [defaultSpec].
  final CacheSpec? Function(String name)? specFor;

  /// Whether the caches store `null` values; `true` by default.
  final bool allowNullValues;

  /// Whether caches are created on demand: `true` when no `cacheNames` were
  /// given.
  final bool dynamic;

  final DateTime Function()? _clock;
  final _caches = <String, InMemoryCache>{};

  InMemoryCache _create(String name) => InMemoryCache(
    name,
    spec: specs[name] ?? specFor?.call(name) ?? defaultSpec,
    allowNullValues: allowNullValues,
    clock: _clock,
  );

  @override
  Cache? getCache(String name) =>
      _caches[name] ?? (dynamic ? _caches[name] = _create(name) : null);

  @override
  Iterable<String> get cacheNames => List.unmodifiable(_caches.keys);
}
