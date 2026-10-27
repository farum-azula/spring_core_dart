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

    test('null values can be refused', () {
      final cache = InMemoryCache('books', allowNullValues: false);
      expect(() => cache.put('a', null), throwsArgumentError);
    });
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
