import 'dart:collection';

import 'package:spring_boot_starter_cache/src/cache.dart';

// Real time, monotonic, shared by every cache: what time to live is
// measured on, as Caffeine measures it on its ticker (`System.nanoTime`).
// Setting the wall clock does not move it.
final _ticker = Stopwatch()..start();

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
  ///
  /// Neither may be negative; `0` keeps nothing (every entry is dropped,
  /// or expired, as soon as it is written), as Caffeine's `maximumSize(0)`
  /// and `expireAfterWrite(Duration.ZERO)`. A negative one is refused when
  /// a cache is created with the spec (an `ArgumentError`); a negative
  /// [maxSize] already here when assertions are on.
  const CacheSpec({this.timeToLive, this.maxSize})
    : assert(maxSize == null || maxSize >= 0, 'maxSize must not be negative');

  /// No expiry and no size limit: the default of every in-memory cache.
  static const unlimited = CacheSpec();

  /// How long an entry lives after it was last written; `null` for ever.
  /// Reading an entry does not extend its life. It is measured on a
  /// monotonic clock, so setting the wall clock moves no expiry.
  final Duration? timeToLive;

  /// The most entries the cache keeps; `null` for no limit, `0` for none.
  /// A new entry beyond it removes the least recently read or written one.
  final int? maxSize;

  // Throws when [spec] has a negative size or time to live: Caffeine's
  // `maximumSize` and `expireAfterWrite` refuse them too. The const
  // constructor can only assert, which release builds skip.
  static CacheSpec _checked(CacheSpec spec, [String? name]) {
    String of(String limit) => name == null ? limit : "$limit of cache '$name'";
    if (spec.maxSize case final maxSize? when maxSize < 0) {
      throw ArgumentError.value(
        maxSize,
        of('maxSize'),
        'must not be negative (0 keeps no entry)',
      );
    }
    if (spec.timeToLive case final timeToLive? when timeToLive.isNegative) {
      throw ArgumentError.value(
        '$timeToLive',
        of('timeToLive'),
        'must not be negative (0 keeps no entry)',
      );
    }
    return spec;
  }

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
/// to compute again. The time to live is measured on a monotonic clock (a
/// `Stopwatch`, as Caffeine measures it on `System.nanoTime`): setting the
/// wall clock, by hand or by a time server, neither keeps entries longer
/// nor drops them early. Expired entries are not removed by a timer: an
/// expired entry counts as a miss and is dropped when it is read, and
/// [put] sweeps out all expired entries after as many writes as half the
/// entries, and
/// at the first write a time to live after the previous sweep. Between
/// sweeps, a cache with a time to live and no size limit holds at most
/// twice the entries that were live at the last sweep; after a burst of
/// writes, the writes a time to live or two later bring it back to its
/// live entries. A cache that is no longer written keeps its expired
/// entries until they are read or the cache is cleared. `null` values are
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
  ///
  /// The time to live runs on a monotonic stopwatch, never on the wall
  /// clock. A test passes `clock`, a fake one, to move time itself: an
  /// entry then also expires once `clock` has moved by the time to live
  /// since the write, or was set back before the write (it then tells
  /// nothing); the stopwatch still counts, so real time expires entries
  /// too. With [allowNullValues] `false`, storing `null` throws an
  /// `ArgumentError`. A [spec] with a negative `maxSize` or `timeToLive`
  /// throws an `ArgumentError`.
  InMemoryCache(
    this.name, {
    CacheSpec spec = CacheSpec.unlimited,
    this.allowNullValues = true,
    this._clock,
  }) : spec = CacheSpec._checked(spec, name);

  @override
  final String name;

  /// The time to live and size limit of the entries.
  final CacheSpec spec;

  /// Whether `null` can be stored. `true` by default, as in Spring: a
  /// method that returned `null` is then a hit on the next call. When
  /// `false`, [put] of `null` throws an `ArgumentError`.
  final bool allowNullValues;

  // A clock of the test's own; `null`: the stopwatch alone.
  final DateTime Function()? _clock;

  // The entries by key, also linked in a ring from the least to the most
  // recently used: a read or a write moves an entry to the end, so the
  // entry after [_lru] is the one a full cache drops. Every step is O(1);
  // the first key of a LinkedHashMap is not, once entries were removed
  // from it (the VM skips the removed slots one by one).
  final _entries = HashMap<Object?, _Entry>();
  final _lru = _Entry._ring();

  /// The number of entries, including expired ones that were neither read
  /// nor swept out by a [put] since they expired.
  int get size => _entries.length;

  // Writes since expired entries were last swept out, and when that was:
  // on the stopwatch, and on [_clock] when there is one. On the wall clock
  // alone, a clock set back held the sweeps back for as long.
  var _writesSinceSweep = 0;
  int? _sweptTick;
  DateTime? _sweptAt;

  @override
  ValueWrapper? get(Object? key) {
    final entry = _entries[key];
    if (entry == null) {
      return null;
    }
    if (spec.timeToLive case final ttl?
        when _passed(
          ttl,
          entry.writtenTick,
          entry.writtenAt,
          _ticker.elapsedMicroseconds,
          _clock?.call(),
        )) {
      _remove(entry);
      return null;
    }
    _toEnd(entry);
    return ValueWrapper(entry.value);
  }

  // Whether [ttl] has passed since [tick] of the stopwatch and [at] of
  // [_clock], which read [nowTick] and [nowAt] now: on the stopwatch, or
  // on the clock, where a clock set back before [at] counts as passed (it
  // tells nothing then). As in Caffeine, an entry has expired once its
  // whole time to live has passed.
  static bool _passed(
    Duration ttl,
    int tick,
    DateTime? at,
    int nowTick,
    DateTime? nowAt,
  ) {
    if (nowTick - tick >= ttl.inMicroseconds) {
      return true;
    }
    if (nowAt == null || at == null) {
      return false;
    }
    final byClock = nowAt.difference(at);
    return byClock.isNegative || byClock >= ttl;
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
    final tick = ttl == null ? 0 : _ticker.elapsedMicroseconds;
    final at = ttl == null ? null : _clock?.call();
    if (_entries[key] case final entry?) {
      entry
        ..value = value
        ..writtenTick = tick
        ..writtenAt = at;
      _toEnd(entry);
    } else {
      _append(_entries[key] = _Entry(key, value, tick, at));
    }
    // Reads reorder the entries, so expired ones may sit anywhere: a full
    // sweep once the writes since the last one reach half the entries
    // costs O(1) a write and keeps the map within twice the entries live
    // at the last sweep. After a burst those are many, so a sweep also
    // comes a time to live after the last one: every entry of the burst
    // has expired by then (or by the next one, written meanwhile).
    if (ttl != null &&
        (++_writesSinceSweep * 2 >= _entries.length ||
            _passed(ttl, _sweptTick ??= tick, _sweptAt ??= at, tick, at))) {
      _writesSinceSweep = 0;
      _sweptTick = tick;
      _sweptAt = at;
      for (var entry = _lru._next; !identical(entry, _lru);) {
        final next = entry._next;
        if (_passed(ttl, entry.writtenTick, entry.writtenAt, tick, at)) {
          _remove(entry);
        }
        entry = next;
      }
    }
    if (spec.maxSize case final maxSize?) {
      // Stops at the end of the ring whatever the size says: the ring's
      // start holds no entry.
      while (_entries.length > maxSize && !identical(_lru._next, _lru)) {
        _remove(_lru._next);
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
  void evict(Object? key) {
    if (_entries.remove(key) case final entry?) {
      _unlink(entry);
    }
  }

  @override
  bool evictIfPresent(Object? key) {
    if (get(key) == null) {
      return false;
    }
    evict(key);
    return true;
  }

  @override
  void clear() {
    _entries.clear();
    _lru
      .._next = _lru
      .._previous = _lru;
  }

  @override
  bool invalidate() {
    final had = _entries.isNotEmpty;
    clear();
    return had;
  }

  void _remove(_Entry entry) {
    _entries.remove(entry.key);
    _unlink(entry);
  }

  void _toEnd(_Entry entry) {
    _unlink(entry);
    _append(entry);
  }

  // Links [entry] as the most recently used.
  void _append(_Entry entry) {
    final last = _lru._previous;
    entry
      .._previous = last
      .._next = _lru;
    last._next = entry;
    _lru._previous = entry;
  }

  static void _unlink(_Entry entry) {
    entry._previous._next = entry._next;
    entry._next._previous = entry._previous;
  }

  @override
  String toString() => 'InMemoryCache($name, ${_entries.length} entries)';
}

// An entry of an [InMemoryCache], between the entries used just before
// and just after it in the cache's ring.
final class _Entry {
  _Entry(this.key, this.value, this.writtenTick, this.writtenAt);

  // The start and end of a cache's ring, which holds no entry.
  _Entry._ring() : key = null, writtenTick = 0 {
    _previous = this;
    _next = this;
  }

  final Object? key;
  Object? value;
  // When it was last written: on the stopwatch (microseconds), and on the
  // cache's clock when it has one.
  int writtenTick;
  DateTime? writtenAt;
  late _Entry _previous;
  late _Entry _next;
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
  /// [allowNullValues] applies to every cache. Their time to live runs on
  /// a monotonic stopwatch; a test passes `clock`, a fake one, which then
  /// expires entries too (see [InMemoryCache.new]).
  /// A [defaultSpec] or one of [specs] with a negative `maxSize` or
  /// `timeToLive` throws an `ArgumentError` here; one from [specFor] when
  /// its cache is created.
  InMemoryCacheManager({
    Iterable<String>? cacheNames,
    CacheSpec defaultSpec = CacheSpec.unlimited,
    Map<String, CacheSpec> specs = const {},
    this.specFor,
    this.allowNullValues = true,
    this._clock,
  }) : defaultSpec = CacheSpec._checked(defaultSpec),
       specs = Map.unmodifiable({
         for (final MapEntry(:key, :value) in specs.entries)
           key: CacheSpec._checked(value, key),
       }),
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
