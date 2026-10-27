import 'package:spring_boot_starter_cache/src/cache.dart';

/// Limits of one in-memory cache: how long entries live and how many are
/// kept (the least recently used ones go first).
///
/// ```dart
/// const CacheSpec(timeToLive: Duration(minutes: 10), maxSize: 1000)
/// ```
///
/// From properties:
/// ```properties
/// spring.cache.simple.time-to-live=10m
/// spring.cache.simple.max-size=1000
/// spring.cache.simple.caches.prices.time-to-live=30s
/// ```
///
/// Spring (Java) has no limits on `ConcurrentMapCache`; with Caffeine:
/// ```java
/// Caffeine.newBuilder()
///     .expireAfterWrite(Duration.ofMinutes(10)).maximumSize(1000)
/// ```
final class CacheSpec {
  /// Entries expire [timeToLive] after they were written (never when
  /// `null`); at most [maxSize] entries are kept (no limit when `null`).
  const CacheSpec({this.timeToLive, this.maxSize})
    : assert(maxSize == null || maxSize > 0, 'maxSize must be positive');

  /// No expiry, no size limit.
  static const unlimited = CacheSpec();

  /// How long an entry lives after it was written.
  final Duration? timeToLive;

  /// The maximum number of entries.
  final int? maxSize;

  @override
  String toString() => 'CacheSpec(timeToLive: $timeToLive, maxSize: $maxSize)';
}

/// A cache in memory, like Spring's `ConcurrentMapCache`, with optional
/// time to live and size limit ([CacheSpec]). Entries are removed lazily:
/// an expired entry is a miss and is dropped when it is read.
///
/// ```dart
/// final cache = InMemoryCache('books',
///     spec: const CacheSpec(timeToLive: Duration(minutes: 5), maxSize: 100));
/// cache.put('978-0', book);
/// cache.get('978-0')?.value; // book, for 5 minutes
/// ```
///
/// Spring (Java):
/// ```java
/// Cache cache = new ConcurrentMapCache("books");
/// cache.put("978-0", book);
/// ```
final class InMemoryCache implements Cache {
  /// A cache named [name] with the limits of [spec]. [clock] returns the
  /// current time (tests pass a fake one). With [allowNullValues] false,
  /// storing `null` throws.
  InMemoryCache(
    this.name, {
    this.spec = CacheSpec.unlimited,
    this.allowNullValues = true,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  @override
  final String name;

  /// Time to live and size limit.
  final CacheSpec spec;

  /// Whether `null` results are cached (Spring's default: yes).
  final bool allowNullValues;

  final DateTime Function() _clock;

  // Insertion order = recency: a read moves the entry to the end, so the
  // first entry is the least recently used one.
  final _entries = <Object?, _Entry>{};

  /// The number of entries, expired ones that were not read yet included.
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

/// The default [CacheManager]: [InMemoryCache]s created on demand, like
/// Spring's `ConcurrentMapCacheManager`. With [cacheNames] the set is fixed
/// and an unknown name is an error.
///
/// ```dart
/// final manager = InMemoryCacheManager(
///   defaultSpec: const CacheSpec(timeToLive: Duration(minutes: 10)),
///   specs: {'prices': const CacheSpec(timeToLive: Duration(seconds: 30))},
/// );
/// manager.getCache('books'); // created now
/// ```
///
/// Spring (Java):
/// ```java
/// CacheManager manager = new ConcurrentMapCacheManager(); // dynamic
/// CacheManager fixed = new ConcurrentMapCacheManager("books", "authors");
/// ```
final class InMemoryCacheManager implements CacheManager {
  /// A manager whose caches use [specs] by name, then [specFor], then
  /// [defaultSpec]. When [cacheNames] is given, only those caches exist.
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

  /// Limits of caches without an entry in [specs] or [specFor].
  final CacheSpec defaultSpec;

  /// Limits per cache name.
  final Map<String, CacheSpec> specs;

  /// Limits computed per cache name (e.g. from properties); `null` falls
  /// back to [defaultSpec].
  final CacheSpec? Function(String name)? specFor;

  /// Whether `null` values are cached.
  final bool allowNullValues;

  /// Whether caches are created on demand (no fixed `cacheNames`).
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
