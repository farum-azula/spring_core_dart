import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:test/test.dart';

const _signature = MethodSignature(
  name: 'find',
  declaringType: 'Books',
  targetType: 'Books',
);

void main() {
  group('SimpleKeyGenerator', () {
    Object? key(List<Object?> args) =>
        const SimpleKeyGenerator().generate(Object(), _signature, args);

    test("Spring's rules", () {
      expect(key([]), same(SimpleKey.empty));
      expect(key(['978-0']), '978-0');
      expect(key([null]), SimpleKey([null]));
      expect(key(['978-0', 2]), SimpleKey(['978-0', 2]));
      expect(key(['978-0', 2]), isNot(SimpleKey([2, '978-0'])));
    });

    test('collections compare by content', () {
      expect(
        key([
          [1, 2],
        ]),
        key([
          [1, 2],
        ]),
      );
      expect(
        SimpleKey([
          {'a': 1},
          {1, 2},
        ]),
        SimpleKey([
          {'a': 1},
          {2, 1},
        ]),
      );
      expect(
        SimpleKey([
          [1, 2],
        ]).hashCode,
        SimpleKey([
          [1, 2],
        ]).hashCode,
      );
      expect(SimpleKey(['x', 1]).toString(), 'SimpleKey [x,1]');
    });
  });

  group('InMemoryCache', () {
    var now = DateTime(2026);
    DateTime clock() => now;

    setUp(() => now = DateTime(2026));

    test('stores, wraps null and evicts', () {
      final cache = InMemoryCache('books');
      expect(cache.get('a'), isNull);
      cache
        ..put('a', 1)
        ..put('n', null);
      expect(cache.get('a')?.value, 1);
      expect(cache.get('n'), isNotNull);
      expect(cache.get('n')!.value, isNull);
      expect(cache.putIfAbsent('a', 2)?.value, 1);
      expect(cache.putIfAbsent('b', 2), isNull);
      expect(cache.get('b')?.value, 2);
      expect(cache.evictIfPresent('b'), isTrue);
      expect(cache.evictIfPresent('b'), isFalse);
      cache.evict('a');
      expect(cache.get('a'), isNull);
      expect(cache.invalidate(), isTrue);
      expect(cache.invalidate(), isFalse);
    });

    test('time to live', () {
      final cache = InMemoryCache(
        'prices',
        spec: const CacheSpec(timeToLive: Duration(minutes: 5)),
        clock: clock,
      )..put('a', 1);
      now = now.add(const Duration(minutes: 4));
      expect(cache.get('a')?.value, 1);
      now = now.add(const Duration(minutes: 1));
      expect(cache.get('a'), isNull);
      expect(cache.size, 0);
    });

    test('expired entries never read are swept out by puts: memory stays '
        'bounded', () {
      // A key a second, each living a minute, nothing read: about 60 live.
      final cache = InMemoryCache(
        'prices',
        spec: const CacheSpec(timeToLive: Duration(minutes: 1)),
        clock: clock,
      );
      var largest = 0;
      for (var i = 0; i < 10000; i++) {
        cache.put('k$i', i);
        now = now.add(const Duration(seconds: 1));
        if (cache.size > largest) {
          largest = cache.size;
        }
      }
      expect(largest, lessThanOrEqualTo(2 * 60 + 2));
      // Reads (which reorder the entries) do not hide expired ones.
      for (var i = 0; i < 1000; i++) {
        cache
          ..get('k${10000 - 1 - (i % 30)}')
          ..put('n$i', i);
        now = now.add(const Duration(seconds: 1));
        if (cache.size > largest) {
          largest = cache.size;
        }
      }
      expect(largest, lessThanOrEqualTo(2 * 60 + 2));
      expect(cache.get('n999')?.value, 999);
    });

    // The sweep by count alone waited for 50 000 writes after a burst of
    // 100 000: at one write a second, the burst stayed in memory for half
    // a day.
    test('after a burst, slow writes sweep it out a time to live later', () {
      final cache = InMemoryCache(
        'prices',
        spec: const CacheSpec(timeToLive: Duration(minutes: 1)),
        clock: clock,
      );
      for (var i = 0; i < 100000; i++) {
        cache.put('burst$i', i);
      }
      expect(cache.size, 100000); // all live
      // Then a key a second, each living a minute: about 60 live.
      for (var i = 0; i < 300; i++) {
        now = now.add(const Duration(seconds: 1));
        cache.put('slow$i', i);
        if (i >= 60) {
          expect(cache.size, lessThanOrEqualTo(2 * 60 + 2), reason: 'at $i s');
        }
      }
      expect(cache.get('slow299')?.value, 299);
      expect(cache.get('burst0'), isNull);
    });

    // The time to live ran on the wall clock alone: set back 2 h, an entry
    // of 30 s was still served 5 minutes later (and for 2 h more).
    // Caffeine measures it on its ticker, System.nanoTime.
    test('a clock set back keeps no entry past its time to live', () {
      final cache = InMemoryCache(
        'prices',
        spec: const CacheSpec(timeToLive: Duration(seconds: 30)),
        clock: clock,
      )..put('a', 1);
      now = now
          .subtract(const Duration(hours: 2))
          .add(const Duration(minutes: 5));
      expect(cache.get('a'), isNull);
      // Written at the new time, it lives its 30 s on that clock.
      cache.put('b', 2);
      now = now.add(const Duration(seconds: 29));
      expect(cache.get('b')?.value, 2);
      now = now.add(const Duration(seconds: 1));
      expect(cache.get('b'), isNull);
    });

    // Real time counts whatever the clock says: a clock that stands still
    // (or the wall clock set back, which the stopwatch ignores) kept the
    // entries for ever.
    test('the time to live runs on a monotonic stopwatch', () async {
      final fixed = DateTime(2026);
      final cache = InMemoryCache(
        'prices',
        spec: const CacheSpec(timeToLive: Duration(milliseconds: 20)),
        clock: () => fixed,
      )..put('a', 1);
      final plain = InMemoryCache(
        'prices',
        spec: const CacheSpec(timeToLive: Duration(milliseconds: 20)),
      )..put('a', 1);
      expect(cache.get('a')?.value, 1);
      expect(plain.get('a')?.value, 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cache.get('a'), isNull);
      expect(plain.get('a'), isNull);
    });

    // The sweep a time to live after the last one waited for the wall
    // clock to pass it again: set back 2 h, a burst stayed in memory for
    // 2 h (or for half its size in writes).
    test('a clock set back, or one that stands still, does not hold the '
        'sweeps back', () async {
      final cache = InMemoryCache(
        'prices',
        spec: const CacheSpec(timeToLive: Duration(minutes: 1)),
        clock: clock,
      );
      for (var i = 0; i < 100000; i++) {
        cache.put('burst$i', i);
      }
      now = now.subtract(const Duration(hours: 2));
      for (var i = 0; i < 300; i++) {
        now = now.add(const Duration(seconds: 1));
        cache.put('slow$i', i);
        expect(cache.size, lessThanOrEqualTo(2 * 60 + 2), reason: 'at $i s');
      }
      expect(cache.get('slow299')?.value, 299);

      final fixed = DateTime(2026);
      final still = InMemoryCache(
        'prices',
        spec: const CacheSpec(timeToLive: Duration(milliseconds: 20)),
        clock: () => fixed,
      );
      for (var i = 0; i < 1000; i++) {
        still.put('burst$i', i);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      still.put('slow', 0);
      expect(still.size, 1);
    });

    test('max size drops the least recently used entry', () {
      final cache = InMemoryCache('books', spec: const CacheSpec(maxSize: 2))
        ..put('a', 1)
        ..put('b', 2)
        ..get('a') // a is now the most recently used
        ..put('c', 3);
      expect(cache.get('b'), isNull);
      expect(cache.get('a')?.value, 1);
      expect(cache.get('c')?.value, 3);
    });

    test('reads and writes make an entry the most recently used; expired '
        'and evicted entries leave the order', () {
      final cache = InMemoryCache(
        'books',
        spec: const CacheSpec(timeToLive: Duration(minutes: 1), maxSize: 3),
        clock: clock,
      );
      List<String> kept() => [
        for (final key in ['a', 'b', 'c', 'd', 'e'])
          if (cache.get(key) != null) key,
      ];
      cache
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3)
        ..put('a', 10) // rewritten: a is the most recent, b the least
        ..put('d', 4);
      expect(cache.size, 3);
      expect(cache.get('b'), isNull);
      cache
        ..get('c') // from least to most recent: a, d, c
        ..put('e', 5);
      expect(cache.get('a'), isNull);
      expect(cache.get('d')?.value, 4);
      cache.evict('d');
      expect(cache.size, 2);
      cache
        ..put('a', 1)
        ..put('b', 2); // c was the least recently used
      expect(cache.get('c'), isNull);
      // a expires; e and b, written again, live on: c then fits without
      // dropping a live entry.
      now = now.add(const Duration(seconds: 30));
      cache
        ..put('e', 5)
        ..put('b', 2);
      now = now.add(const Duration(seconds: 30));
      expect(cache.get('a'), isNull, reason: 'expired');
      expect(cache.size, 2);
      cache.put('c', 3);
      expect(kept(), ['b', 'c', 'e']);
      cache.clear();
      expect(cache.size, 0);
      cache
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3)
        ..put('d', 4);
      expect(kept(), ['b', 'c', 'd']);
    });

    // Each eviction took the first key of a LinkedHashMap that entries
    // had been removed from, and the VM skips removed slots one by one:
    // 150 000 writes to a full cache of 50 000 took seconds, growing with
    // the square of the size. Now each takes constant time (milliseconds
    // for all of them); the bound is far above that, and far below the
    // old cost, so the test does not depend on the machine.
    test('a full cache drops its least recently used entry in constant '
        'time', () {
      const maxSize = 50000;
      final cache = InMemoryCache(
        'books',
        spec: const CacheSpec(maxSize: maxSize),
      );
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 10 * maxSize; i++) {
        cache.put(i, i);
        if (i.isEven) {
          cache.get(i - maxSize ~/ 2); // a read moves it to the end
        }
      }
      stopwatch.stop();
      expect(cache.size, maxSize);
      expect(cache.get(10 * maxSize - 1)?.value, 10 * maxSize - 1);
      expect(cache.get(0), isNull);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('keeps the same entries as a map in recency order, with a time to '
        'live and a size limit', () {
      final random = Random(7);
      for (final spec in const [
        CacheSpec(maxSize: 20),
        CacheSpec(timeToLive: Duration(seconds: 40), maxSize: 20),
        CacheSpec(timeToLive: Duration(seconds: 40)),
      ]) {
        now = DateTime(2026);
        final cache = InMemoryCache('books', spec: spec, clock: clock);
        final reference = _ReferenceCache(spec, clock);
        for (var step = 0; step < 20000; step++) {
          final key = random.nextInt(40);
          final reason = '$spec, step $step, key $key';
          switch (random.nextInt(10)) {
            case 0 || 1 || 2 || 3:
              cache.put(key, step);
              reference.put(key, step);
            case 4 || 5 || 6:
              expect(cache.get(key)?.value, reference.get(key), reason: reason);
            case 7:
              expect(
                cache.putIfAbsent(key, step)?.value,
                reference.putIfAbsent(key, step),
                reason: reason,
              );
            case 8:
              expect(
                cache.evictIfPresent(key),
                reference.evictIfPresent(key),
                reason: reason,
              );
            default:
              cache.evict(key);
              reference.evict(key);
          }
          if (random.nextInt(1000) == 0) {
            expect(cache.invalidate(), reference.invalidate(), reason: reason);
          }
          expect(cache.size, reference.size, reason: reason);
          now = now.add(Duration(seconds: random.nextInt(3)));
        }
      }
    });

    test('null values can be refused', () {
      final cache = InMemoryCache('books', allowNullValues: false);
      expect(() => cache.put('a', null), throwsArgumentError);
    });

    // As Caffeine's maximumSize(0): allowed, and nothing is kept.
    test('max size 0 keeps no entry', () {
      for (final spec in const [
        CacheSpec(maxSize: 0),
        CacheSpec(timeToLive: Duration(minutes: 1), maxSize: 0),
      ]) {
        final cache = InMemoryCache('books', spec: spec, clock: clock)
          ..put('a', 1)
          ..put(null, 2);
        expect(cache.size, 0, reason: '$spec');
        expect(cache.get('a'), isNull);
        expect(cache.get(null), isNull);
        expect(cache.putIfAbsent('a', 3), isNull);
        expect(cache.size, 0);
      }
    });

    // The only check was an assertion, which release builds and `dart run`
    // skip: the first put then looped for ever. The script runs without
    // assertions, so it sees what a released app sees.
    test(
      'a negative max size or time to live is refused without assertions '
      'too',
      () async {
        final process = await Process.start(Platform.resolvedExecutable, [
          'run',
          'test/support/negative_max_size.dart',
        ], workingDirectory: _packageRoot());
        final output = StringBuffer();
        final done = [
          process.stdout.transform(utf8.decoder).forEach(output.write),
          process.stderr.transform(utf8.decoder).forEach(output.write),
        ];
        final exitCode = await process.exitCode.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        await Future.wait(done);
        expect(exitCode, 0, reason: '$output');
        expect(
          '$output',
          allOf(
            contains(
              "Invalid argument (maxSize of cache 'books'): must not be "
              'negative (0 keeps no entry): -1',
            ),
            contains(
              'Invalid argument (maxSize): must not be negative (0 keeps no '
              'entry): -1',
            ),
            contains(
              "Invalid argument (maxSize of cache 'prices'): must not be "
              'negative',
            ),
            contains(
              "Invalid argument (timeToLive of cache 'books'): must not be "
              'negative (0 keeps no entry): "-0:00:01.000000"',
            ),
            contains(
              "Invalid argument (timeToLive of cache 'prices'): must not be "
              'negative',
            ),
          ),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('InMemoryCacheManager', () {
    test('creates caches on demand with their specs', () {
      final manager = InMemoryCacheManager(
        defaultSpec: const CacheSpec(maxSize: 10),
        specs: {'prices': const CacheSpec(maxSize: 1)},
        specFor: (name) =>
            name == 'authors' ? const CacheSpec(maxSize: 5) : null,
      );
      expect(manager.cacheNames, isEmpty);
      final books = manager.getCache('books')! as InMemoryCache;
      expect(books.spec.maxSize, 10);
      expect(identical(manager.getCache('books'), books), isTrue);
      expect((manager.getCache('prices')! as InMemoryCache).spec.maxSize, 1);
      expect((manager.getCache('authors')! as InMemoryCache).spec.maxSize, 5);
      expect(manager.cacheNames, ['books', 'prices', 'authors']);
    });

    test('a fixed set of names', () {
      final manager = InMemoryCacheManager(cacheNames: ['books']);
      expect(manager.dynamic, isFalse);
      expect(manager.getCache('books'), isNotNull);
      expect(manager.getCache('authors'), isNull);
    });
  });

  test('NoOpCacheManager never stores', () {
    final manager = NoOpCacheManager();
    final cache = manager.getCache('books')!..put('a', 1);
    expect(cache.get('a'), isNull);
    expect(cache.putIfAbsent('a', 1), isNull);
    expect(cache.evictIfPresent('a'), isFalse);
    expect(cache.invalidate(), isFalse);
    expect(manager.cacheNames, ['books']);
  });
}

String _packageRoot() => Isolate.resolvePackageUriSync(
  Uri.parse('package:spring_boot_starter_cache/spring_boot_starter_cache.dart'),
)!.resolve('..').toFilePath();

/// What InMemoryCache did with a LinkedHashMap in recency order (correct,
/// with an eviction that cost O(maxSize)): the reference its entries are
/// compared with.
final class _ReferenceCache {
  _ReferenceCache(this.spec, this.clock);

  final CacheSpec spec;
  final DateTime Function() clock;
  final _entries = <Object?, (Object?, DateTime?)>{};
  var _writesSinceSweep = 0;
  DateTime? _lastSweep;

  int get size => _entries.length;

  Object? get(Object? key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    if (entry.$2 case final expiresAt? when !clock().isBefore(expiresAt)) {
      return null;
    }
    _entries[key] = entry;
    return entry.$1;
  }

  void put(Object? key, Object? value) {
    final ttl = spec.timeToLive;
    final now = clock();
    _entries
      ..remove(key)
      ..[key] = (value, ttl == null ? null : now.add(ttl));
    if (ttl != null &&
        (++_writesSinceSweep * 2 >= _entries.length ||
            !now.isBefore((_lastSweep ??= now).add(ttl)))) {
      _writesSinceSweep = 0;
      _lastSweep = now;
      _entries.removeWhere(
        (_, entry) => entry.$2 != null && !now.isBefore(entry.$2!),
      );
    }
    if (spec.maxSize case final maxSize?) {
      while (_entries.length > maxSize) {
        _entries.remove(_entries.keys.first);
      }
    }
  }

  // The values of the test are never null: null means absent.
  Object? putIfAbsent(Object? key, Object? value) {
    final existing = get(key);
    if (existing != null) {
      return existing;
    }
    put(key, value);
    return null;
  }

  bool evictIfPresent(Object? key) =>
      get(key) != null && _entries.remove(key) != null;

  void evict(Object? key) => _entries.remove(key);

  bool invalidate() {
    final had = _entries.isNotEmpty;
    _entries.clear();
    return had;
  }
}
