import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache.dart';
import 'package:spring_boot_starter_cache/src/key_generator.dart';

// A monotonic clock would not survive a restart: entries kept on disk
// expire by the wall clock.
DateTime _wallClock() => DateTime.now();

/// The [CacheManager] of `spring.cache.type: disk`: caches whose entries
/// are kept in a [CacheStore], so they survive a restart (the app's `cache`
/// place in Flutter, a folder on a server).
///
/// Each entry is one file, `spring/caches/<cache>/<hash of the key>.json`,
/// with the key it was written under (a hash that two keys share is two
/// entries, not one), when it expires, the [version] it was written by and
/// the value as JSON through the application's `ObjectMapper`:
///
/// - `String`, numbers, `bool`, `null`;
/// - an object whose class the `ObjectMapper` reads (`@Introspected()` or a
///   JSON serializer);
/// - a `List`, `Set` or `Map<String, …>` of one of those;
/// - a `Resource` with an address, kept as its address alone (read back by
///   the `ResourceLoader`: a file the resources' cache keeps is one copy for
///   both).
///
/// Another value is not kept (the method runs again next time), and the
/// cache logs it once; an empty collection is not kept either, its element
/// type being unknown. Entries of another [version] are not read: a result
/// made from the app's own resources goes with a new version of the app.
///
/// A store answers later: the caches are [AsyncCache]s, for methods that
/// return a `Future` (another is a start-up error naming it).
///
/// Spring Boot has no such manager; the differences are in
/// `docs/configuration.md`.
final class DiskCacheManager implements CacheManager {
  /// Caches in [store], their values through [mapper] and [introspector],
  /// a resource read back by [resources]; [cacheNames] fixes the caches
  /// (others are made on demand), [timeToLive] is the default time an
  /// entry lives and [timeToLives] that of single caches, [maxSize] the
  /// most bytes each cache keeps (the oldest written go first), [version]
  /// the version entries are written by and read for. [clock] is the wall
  /// clock, for a test's own.
  DiskCacheManager({
    required this.store,
    required this.mapper,
    required this.introspector,
    this.resources,
    Iterable<String>? cacheNames,
    this.timeToLive,
    this.timeToLives = const {},
    this.maxSize,
    this.version,
    DateTime Function()? clock,
  }) : _fixed = cacheNames == null ? null : {...cacheNames},
       _clock = clock ?? _wallClock;

  /// The folder of every cache in the store.
  static const String root = 'spring/caches';

  /// Where the entries are kept.
  final CacheStore store;

  /// How values become JSON and back.
  final ObjectMapper mapper;

  /// The descriptions of the classes values are read back as.
  final Introspector introspector;

  /// What reads a `Resource` back from its address.
  final ResourceLoader? resources;

  /// How long an entry lives, `null` for ever.
  final Duration? timeToLive;

  /// How long an entry of a cache lives, by cache name; a cache not named
  /// here has [timeToLive].
  final Map<String, Duration?> timeToLives;

  /// The most bytes each cache keeps, `null` for no limit.
  final int? maxSize;

  /// The version entries are written by; one of another version is not
  /// read. `null`: every entry is read.
  final String? version;

  final Set<String>? _fixed;
  final DateTime Function() _clock;
  final Map<String, DiskCache> _caches = {};

  @override
  Cache? getCache(String name) {
    if (_fixed != null && !_fixed.contains(name)) {
      return null;
    }
    return _caches[name] ??= DiskCache._(this, name);
  }

  @override
  Iterable<String> get cacheNames => _fixed ?? _caches.keys;

  @override
  String toString() => 'DiskCacheManager($store)';
}

/// A cache of a [DiskCacheManager]: an [AsyncCache], one file an entry.
///
/// [get] answers from what this run already read or wrote (the last few
/// hundred entries, until they expire); [retrieve] reads the store.
///
/// A key is found again in a later run by its stable form
/// ([canonicalCacheKey]); a key without one (an object the
/// `ObjectMapper` does not read, a record) is not kept, and the cache logs
/// it once: Spring's caches match keys by `equals`, which a later run
/// cannot call.
final class DiskCache implements AsyncCache {
  DiskCache._(this._manager, this.name)
    : folder = '${DiskCacheManager.root}/${_segment(name)}',
      _codec = _ValueCodec(
        _manager.mapper,
        _manager.introspector,
        _manager.resources,
      );

  final DiskCacheManager _manager;
  final _ValueCodec _codec;

  @override
  final String name;

  /// The folder of this cache in the store: the name as one path segment,
  /// so the cache `users/admins` is not inside the cache `users`.
  final String folder;

  static const _log = SpringLog('spring.cache');
  static const int _remembered = 256;

  // What this run read or wrote, by path: the latest last.
  final Map<String, _Remembered?> _known = {};
  Future<void> _writes = Future.value();
  bool _warned = false;
  bool _warnedKey = false;

  // With maxSize: the size of each entry, the oldest written first, and
  // their total; read from the store once, then kept as entries come and
  // go, so a put does not read the whole cache.
  Map<String, int>? _sizes;
  int _total = 0;

  // A cache name as one segment of a path: `/` escaped, and no `.`, `..`
  // or empty segment.
  static String _segment(String name) => switch (Uri.encodeComponent(name)) {
    '' => '%',
    '.' => '%2E',
    '..' => '%2E%2E',
    final segment => segment,
  };

  Duration? get _timeToLive => _manager.timeToLives.containsKey(name)
      ? _manager.timeToLives[name]
      : _manager.timeToLive;

  @override
  bool get answersSynchronously => false;

  int get _now => _manager._clock().millisecondsSinceEpoch;

  // The stable form of [key], or `null` (logged once) when it has none.
  String? _canonical(Object? key) {
    try {
      return canonicalCacheKey(key, _manager.mapper, _manager.introspector);
    } on UnsupportedError catch (error) {
      if (!_warnedKey) {
        _warnedKey = true;
        _log.warning(
          () =>
              "cache '$name' keeps nothing on disk under a key of "
              '${key.runtimeType}: ${error.message}',
        );
      }
      return null;
    }
  }

  String _pathOf(String canonical) => '$folder/${_fnv64(canonical)}.json';

  void _remember(String path, _Remembered? entry) {
    _known
      ..remove(path)
      ..[path] = entry;
    while (_known.length > _remembered) {
      _known.remove(_known.keys.first);
    }
  }

  // What this run knows of [path]; `known: false` when it must be read.
  ({bool known, ValueWrapper? hit}) _recall(String path) {
    if (!_known.containsKey(path)) {
      return (known: false, hit: null);
    }
    final entry = _known[path];
    if (entry == null) {
      return (known: true, hit: null);
    }
    if (entry.expired(_now)) {
      _known.remove(path);
      _then(() => _dropStale(path));
      return (known: true, hit: null);
    }
    return (known: true, hit: entry.value);
  }

  @override
  ValueWrapper? get(Object? key) {
    final canonical = _canonical(key);
    return canonical == null ? null : _recall(_pathOf(canonical)).hit;
  }

  @override
  Future<ValueWrapper?> retrieve(Object? key) async {
    final canonical = _canonical(key);
    if (canonical == null) {
      return null;
    }
    final path = _pathOf(canonical);
    final recalled = _recall(path);
    if (recalled.known) {
      return recalled.hit;
    }
    await _writes;
    final bytes = await _manager.store.read(path);
    if (bytes == null) {
      return null;
    }
    final Map<String, Object?> entry;
    try {
      entry = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    } on Object {
      _then(() => _dropStale(path));
      return null;
    }
    if (entry['key'] != canonical) {
      return null; // another key with the same hash
    }
    final expires = entry['expires'];
    if (entry['version'] != _manager.version ||
        (expires is int && _now >= expires)) {
      _then(() => _dropStale(path));
      return null;
    }
    try {
      final hit = ValueWrapper(await _codec.decode(entry['value']));
      _remember(path, _Remembered(hit, expires is int ? expires : null));
      return hit;
    } on Object catch (error) {
      // A class renamed or gone since it was written: a miss.
      _log.debug(() => "cache '$name': an entry not read back: $error");
      _then(() => _dropStale(path));
      return null;
    }
  }

  @override
  void put(Object? key, Object? value) {
    final ttl = _timeToLive;
    if (ttl == Duration.zero) {
      return;
    }
    final canonical = _canonical(key);
    if (canonical == null) {
      return;
    }
    final Object? encoded;
    try {
      encoded = _codec.encode(value);
    } on UnsupportedError catch (error) {
      if (!_warned) {
        _warned = true;
        _log.warning(
          () =>
              "cache '$name' keeps no ${value.runtimeType} on disk: "
              '${error.message}',
        );
      }
      return;
    }
    final path = _pathOf(canonical);
    final now = _manager._clock();
    final expires = ttl == null ? null : now.add(ttl).millisecondsSinceEpoch;
    final bytes = utf8.encode(
      jsonEncode({
        'key': canonical,
        'written': now.millisecondsSinceEpoch,
        'expires': expires,
        'version': _manager.version,
        'value': encoded,
      }),
    );
    _remember(path, _Remembered(ValueWrapper(value), expires));
    _then(() async {
      await _manager.store.write(path, bytes);
      await _trim(path, bytes.length);
    });
  }

  @override
  ValueWrapper? putIfAbsent(Object? key, Object? value) {
    final known = get(key);
    if (known != null) {
      return known;
    }
    put(key, value);
    return null;
  }

  @override
  void evict(Object? key) {
    final canonical = _canonical(key);
    if (canonical == null) {
      return;
    }
    final path = _pathOf(canonical);
    _remember(path, null);
    _then(() async {
      await _manager.store.delete(path);
      _forget(path);
    });
  }

  @override
  bool evictIfPresent(Object? key) {
    final present = get(key) != null;
    evict(key);
    return present;
  }

  @override
  void clear() {
    _known.clear();
    _then(() async {
      await _manager.store.delete(folder);
      if (_sizes != null) {
        _sizes = {};
        _total = 0;
      }
    });
  }

  /// Clears the cache, as [clear]. `true` only when this run knew of an
  /// entry that had not expired; `false` when it cannot tell, as Spring's
  /// `Cache.invalidate()` (entries this run did not read are on disk,
  /// unknown).
  @override
  bool invalidate() {
    final now = _now;
    final had = _known.values.any(
      (entry) => entry != null && !entry.expired(now),
    );
    clear();
    return had;
  }

  /// Waits for the writes started so far.
  Future<void> flush() => _writes;

  // The writes in the order they were asked for; a failed one is logged
  // and the next ones go on.
  void _then(Future<void> Function() write) {
    _writes = _writes.then((_) => write()).catchError((Object error) {
      _log.warning(() => "cache '$name': the store failed: $error");
    });
  }

  // Deletes an expired or unreadable entry, unless this run has put a new
  // one there since.
  Future<void> _dropStale(String path) async {
    if (_known[path] case final entry? when !entry.expired(_now)) {
      return;
    }
    await _manager.store.delete(path);
    _forget(path);
  }

  void _forget(String path) {
    if (_sizes?.remove(path) case final size?) {
      _total -= size;
    }
  }

  // Past maxSize, the oldest written go first.
  Future<void> _trim(String path, int size) async {
    final limit = _manager.maxSize;
    if (limit == null) {
      return;
    }
    final sizes = _sizes ??= await _load();
    _forget(path);
    sizes[path] = size;
    _total += size;
    while (_total > limit && sizes.isNotEmpty) {
      final oldest = sizes.keys.first;
      await _manager.store.delete(oldest);
      _known.remove(oldest);
      _forget(oldest);
    }
  }

  // The entries in the store, the oldest written first: read once a run.
  Future<Map<String, int>> _load() async {
    final entries = <({String path, int size, int written})>[];
    for (final path in await _manager.store.list(folder)) {
      final bytes = await _manager.store.read(path);
      if (bytes == null) {
        continue;
      }
      var written = 0;
      try {
        final entry = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
        written = (entry['written'] as int?) ?? 0;
      } on Object {
        // unreadable: the first to go
      }
      entries.add((path: path, size: bytes.length, written: written));
    }
    entries.sort((a, b) => a.written.compareTo(b.written));
    _total = 0;
    final sizes = <String, int>{};
    for (final entry in entries) {
      sizes[entry.path] = entry.size;
      _total += entry.size;
    }
    return sizes;
  }

  @override
  String toString() => 'DiskCache($name)';
}

// An entry this run read or wrote, with when it expires.
final class _Remembered {
  const _Remembered(this.value, this.expires);

  final ValueWrapper value;
  final int? expires;

  bool expired(int now) => expires != null && now >= expires!;
}

/// The key [key] as text that is the same in every run: what an entry on
/// disk is found by. It is JSON, so no two keys share it: a `String` is a
/// JSON string, another value a list that starts with its kind. A
/// `Resource` is its address (and its version, when the key generator added
/// it); an object the `ObjectMapper` reads is its class's
/// [Introspection.qualifiedName] and its JSON. A set and a map are in a
/// sorted order, as they are equal in any order.
///
/// Throws an [UnsupportedError] for a key without such a form: an object
/// the `ObjectMapper` does not read, a record, an object of a class whose
/// qualified name another class shares; a later run could not tell those
/// apart.
String canonicalCacheKey(
  Object? key,
  ObjectMapper mapper,
  Introspector introspector,
) {
  int byText(Object? a, Object? b) => jsonEncode(a).compareTo(jsonEncode(b));
  Object? of(Object? key) => switch (key) {
    null || String() || bool() => key,
    int() => ['i', '$key'],
    double() => ['d', '$key'],
    Enum() => ['e', '${key.runtimeType}', key.name],
    Resource() => ['r', '${key.uri ?? key.description}'],
    SimpleKey() => ['k', key.params.map(of).toList()],
    Record() => throw UnsupportedError(
      'a record has no form that is the same in every run',
    ),
    List() => ['l', key.map(of).toList()],
    Set() => ['set', key.map(of).toList()..sort(byText)],
    Map() => [
      'm',
      [
        for (final e in key.entries) [of(e.key), of(e.value)],
      ]..sort(byText),
    ],
    _ => ['o', _uniqueName(introspector, key), mapper.valueToTree(key)],
  };
  return jsonEncode(of(key));
}

// The qualified name of [value]'s class, which reads it back; throws an
// UnsupportedError when it has none or shares it.
String _uniqueName(Introspector introspector, Object value) {
  final introspection = introspector.findIntrospection(value);
  if (introspection == null) {
    throw UnsupportedError(
      'the ObjectMapper does not read ${value.runtimeType} (no '
      '@Introspected() or JSON serializer)',
    );
  }
  final name = introspection.qualifiedName;
  if (introspector.byQualifiedName(name)?.type != introspection.type) {
    throw UnsupportedError(
      'another class is named $name too, which a later run could not tell '
      'apart from it',
    );
  }
  return name;
}

// FNV-1a over the UTF-8 of [text], 64 bits in hex: a file name. Two keys
// with one hash are told apart by the key kept in the file. In two halves
// of 32 bits, as JavaScript has no 64-bit integers: the prime is
// 2^40 + 0x1b3, so a product is the halves times 0x1b3 plus the low half
// moved 40 bits up.
String _fnv64(String text) {
  const twoTo32 = 0x100000000;
  var high = 0xcbf29ce4;
  var low = 0x84222325;
  for (final byte in utf8.encode(text)) {
    low ^= byte;
    final lowProduct = low * 0x1b3;
    final carry = lowProduct ~/ twoTo32;
    high = (high * 0x1b3 + carry + (low * 256) % twoTo32) % twoTo32;
    low = lowProduct % twoTo32;
  }
  return high.toRadixString(16).padLeft(8, '0') +
      low.toRadixString(16).padLeft(8, '0');
}

/// [text]'s FNV-1a hash of 64 bits, in hex: what the cache names an
/// entry's file by. Public for tests.
String cacheFileHash(String text) => _fnv64(text);

// Values as JSON with their types, so they come back as what was put.
final class _ValueCodec {
  _ValueCodec(this.mapper, this.introspector, this.resources);

  final ObjectMapper mapper;
  final Introspector introspector;
  final ResourceLoader? resources;

  Object? encode(Object? value) {
    switch (value) {
      case null:
        return {'t': 'null'};
      case String() || bool() || num():
        return {'t': 'json', 'v': value};
      case Resource():
        final uri = value.uri;
        if (uri == null || resources == null) {
          throw UnsupportedError('a resource without an address');
        }
        return {'t': 'resource', 'v': '$uri'};
      case List() || Set():
        final items = (value as Iterable<Object?>).toList();
        final element = _elementTag(items);
        return {
          't': value is Set ? 'set' : 'list',
          'e': element,
          'v': [for (final item in items) _raw(item, element)],
        };
      case Map():
        if (value.keys.any((key) => key is! String)) {
          throw UnsupportedError('a map whose keys are not all strings');
        }
        final element = _elementTag(value.values.toList());
        return {
          't': 'map',
          'e': element,
          'v': {
            for (final MapEntry(:key, :value) in value.entries)
              key as String: _raw(value, element),
          },
        };
      default:
        return {
          't': 'o',
          'c': _uniqueName(introspector, value),
          'v': mapper.valueToTree(value),
        };
    }
  }

  // The one type of [items]: a JSON type's name or `o:<class>`.
  String _elementTag(List<Object?> items) {
    if (items.isEmpty) {
      throw UnsupportedError('an empty collection, of no known element type');
    }
    String tag(Object? item) => switch (item) {
      String() => 'String',
      int() => 'int',
      double() => 'double',
      bool() => 'bool',
      null => throw UnsupportedError('a collection with null in it'),
      _ => 'o:${_uniqueName(introspector, item)}',
    };
    final first = tag(items.first);
    for (final item in items.skip(1)) {
      final other = tag(item);
      if (other != first) {
        // int and double together are numbers.
        if ({first, other}.difference({'int', 'double'}).isEmpty) {
          return 'num';
        }
        throw UnsupportedError('a collection of more than one type');
      }
    }
    return first;
  }

  Object? _raw(Object? item, String element) =>
      element.startsWith('o:') ? mapper.valueToTree(item) : item;

  Future<Object?> decode(Object? tree) async {
    final entry = tree! as Map<String, Object?>;
    switch (entry['t']) {
      case 'null':
        return null;
      case 'json':
        return entry['v'];
      case 'resource':
        final loader =
            resources ?? (throw StateError('no ResourceLoader to read it'));
        return loader.getResource(entry['v']! as String);
      case 'o':
        return _object(entry['c']! as String, entry['v']);
      case 'list' || 'set' || 'map':
        return _collection(entry);
    }
    throw FormatException('an entry of an unknown kind: ${entry['t']}');
  }

  Object _object(String className, Object? tree) {
    final introspection =
        introspector.byQualifiedName(className) ??
        (throw StateError('no class $className to read the entry as'));
    return mapper.treeToValue(tree, introspection.classType);
  }

  Object _collection(Map<String, Object?> entry) {
    final kind = entry['t'];
    final element = entry['e']! as String;
    if (kind == 'map') {
      final raw = entry['v']! as Map<String, Object?>;
      if (element.startsWith('o:')) {
        final className = element.substring(2);
        final introspection = introspector.byQualifiedName(className)!;
        return introspection.mapOf({
          for (final MapEntry(:key, :value) in raw.entries)
            key: _object(className, value),
        });
      }
      return switch (element) {
        'String' => raw.cast<String, String>().map(MapEntry.new),
        'int' => {
          for (final MapEntry(:key, :value) in raw.entries)
            key: (value! as num).toInt(),
        },
        'double' || 'num' => {
          for (final MapEntry(:key, :value) in raw.entries)
            key: (value! as num).toDouble(),
        },
        'bool' => raw.cast<String, bool>().map(MapEntry.new),
        _ => throw FormatException('an unknown element type $element'),
      };
    }
    final raw = entry['v']! as List<Object?>;
    final set = kind == 'set';
    if (element.startsWith('o:')) {
      final className = element.substring(2);
      final introspection = introspector.byQualifiedName(className)!;
      final items = [for (final item in raw) _object(className, item)];
      return set ? introspection.setOf(items) : introspection.listOf(items);
    }
    final Iterable<Object> items = switch (element) {
      'String' => raw.cast<String>(),
      'int' => [for (final item in raw) (item! as num).toInt()],
      'double' => [for (final item in raw) (item! as num).toDouble()],
      'num' => raw.cast<num>(),
      'bool' => raw.cast<bool>(),
      _ => throw FormatException('an unknown element type $element'),
    };
    return switch (element) {
      'String' =>
        set ? items.cast<String>().toSet() : items.cast<String>().toList(),
      'int' => set ? items.cast<int>().toSet() : items.cast<int>().toList(),
      'double' =>
        set ? items.cast<double>().toSet() : items.cast<double>().toList(),
      'num' => set ? items.cast<num>().toSet() : items.cast<num>().toList(),
      _ => set ? items.cast<bool>().toSet() : items.cast<bool>().toList(),
    };
  }
}
