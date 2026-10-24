import 'dart:async';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:test/test.dart';

import 'books.dart';

void main() {
  late InMemoryCacheManager manager;
  late Books proxy;

  Cache cache(String name) => manager.getCache(name)!;

  setUp(() {
    manager = InMemoryCacheManager();
    final interceptor = CacheInterceptor(cacheManager: manager);
    proxy = booksProxyFactory.createProxy(Books(), [
      DefaultPointcutAdvisor(const CacheAnnotationPointcut(), interceptor),
    ]) as Books;
  });

  test('the pointcut matches members with cache annotations only', () {
    const pointcut = CacheAnnotationPointcut();
    final byName = {for (final s in booksSignatures) s.name: s};
    expect(pointcut.matches(byName['find']!, 'books'), isTrue);
    expect(pointcut.matches(byName['combined']!, 'books'), isTrue);
    expect(pointcut.matches(byName['plain']!, 'books'), isFalse);
  });

  group('@Cacheable', () {
    test('a hit returns the cached value without calling the method', () {
      expect(proxy.find('1'), 'title of 1');
      expect(proxy.find('1'), 'title of 1');
      expect(proxy.find('2'), 'title of 2');
      expect(proxy.count('find'), 2);
      expect(cache('books').get('1')?.value, 'title of 1'); // default key
    });

    test('key and condition', () {
      proxy
        ..findFresh('1', false)
        ..findFresh('1', false);
      expect(proxy.count('findFresh'), 1);
      expect(cache('books').get('1')?.value, 'fresh 1'); // key: #isbn
      proxy
        ..findFresh('2', true)
        ..findFresh('2', true);
      expect(proxy.count('findFresh'), 3); // condition false: not cached
    });

    test('unless sees #result', () {
      expect(proxy.maybe('missing'), isNull);
      expect(proxy.maybe('missing'), isNull);
      expect(proxy.count('maybe'), 2);
      proxy
        ..maybe('1')
        ..maybe('1');
      expect(proxy.count('maybe'), 3);
    });

    test('null results are cached', () {
      expect(proxy.nothing('1'), isNull);
      expect(proxy.nothing('1'), isNull);
      expect(proxy.count('nothing'), 1);
      expect(cache('nulls').get('1'), isNotNull);
    });

    test('#root variables', () {
      proxy
        ..byMethod()
        ..byMethod()
        ..byClass('7');
      expect(proxy.count('byMethod'), 1);
      expect(cache('books').get('byMethod')?.value, 'by method');
      expect(cache('books').get('Books/7')?.value, 'by class');
    });

    test('@CacheConfig supplies the cache names', () {
      proxy
        ..configured('1')
        ..configured('1');
      expect(proxy.count('configured'), 1);
      expect(cache('configured').get('1')?.value, 'configured 1');
    });

    test('methods without annotations are not touched', () {
      proxy
        ..plain('1')
        ..plain('1');
      expect(proxy.count('plain'), 2);
    });
  });

  test('@CachePut always calls and stores the result', () {
    proxy.find('1');
    expect(proxy.save('1', 'New title'), 'New title');
    expect(proxy.save('1', 'Newer title'), 'Newer title');
    expect(proxy.count('save'), 2);
    expect(proxy.find('1'), 'Newer title');
    expect(proxy.count('find'), 1);
  });

  test('a @CachePut whose condition fails does not force a @Cacheable '
      'hit to run (Spring hasCachePut)', () {
    cache('books').put('1', 'cached 1');
    expect(proxy.refresh('1', false), 'cached 1');
    expect(proxy.count('refresh'), 0);
    expect(proxy.refresh('1', true), 'refreshed 1');
    expect(proxy.count('refresh'), 1);
    expect(cache('books').get('1')?.value, 'refreshed 1');
    // A condition reading #result cannot be decided before the call: the
    // put counts as passing, so the method runs despite the hit.
    expect(proxy.refreshResult('1'), 'refreshed 1');
    expect(proxy.count('refreshResult'), 1);
    expect(cache('refreshed').get('1')?.value, 'refreshed 1');
  });

  group('@CacheEvict', () {
    test('removes one key after the call', () {
      proxy
        ..find('1')
        ..find('2')
        ..delete('1');
      expect(cache('books').get('1'), isNull);
      expect(cache('books').get('2'), isNotNull);
    });

    test('beforeInvocation evicts even when the method throws', () {
      proxy.find('1');
      expect(proxy.reload, throwsStateError);
      expect(cache('books').get('1'), isNull);
    });

    test('after the call nothing is evicted when the method throws', () {
      proxy.find('1');
      expect(() => proxy.clearAfter(fail: true), throwsStateError);
      expect(cache('books').get('1'), isNotNull);
      proxy.clearAfter();
      expect(cache('books').get('1'), isNull);
    });
  });

  test('@Caching combines operations', () {
    cache('authors').put('ada', 'Ada');
    proxy
      ..combined('1')
      ..combined('1');
    expect(proxy.count('combined'), 1);
    expect(cache('authors').get('ada'), isNull);
  });

  group('async methods', () {
    test('the value is cached and a hit is a typed Future', () async {
      expect(await proxy.fetch('1'), 'fetched 1');
      final hit = proxy.fetch('1');
      expect(hit, isA<Future<String>>());
      expect(await hit, 'fetched 1');
      expect(proxy.count('fetch'), 1);
      expect(cache('async').get('1')?.value, 'fetched 1');
    });

    test('errors are not cached', () async {
      await expectLater(proxy.fetch('bad'), throwsStateError);
      await expectLater(proxy.fetch('bad'), throwsStateError);
      expect(proxy.count('fetch'), 2);
      expect(cache('async').get('bad'), isNull);
    });

    test('sync: true shares one call between concurrent callers', () async {
      final first = proxy.fetchShared('1');
      final second = proxy.fetchShared('1');
      expect(proxy.count('fetchShared'), 1);
      proxy.pending['1']!.complete('shared');
      expect(await first, 'shared');
      expect(await second, 'shared');
      expect(await proxy.fetchShared('1'), 'shared'); // now from the cache
      expect(proxy.count('fetchShared'), 1);
    });

    test('sync: true after an error lets the next call try again', () async {
      final failing = proxy.fetchShared('2');
      proxy.pending['2']!.completeError(StateError('down'));
      await expectLater(failing, throwsStateError);
      final retry = proxy.fetchShared('2');
      expect(proxy.count('fetchShared'), 2);
      proxy.pending['2']!.complete('up');
      expect(await retry, 'up');
    });
  });

  group('configuration errors', () {
    test('a fixed cache manager rejects unknown caches', () {
      final fixed = CacheInterceptor(
        cacheManager: InMemoryCacheManager(cacheNames: ['authors']),
      );
      final books = booksProxyFactory.createProxy(Books(), [
        DefaultPointcutAdvisor(const CacheAnnotationPointcut(), fixed),
      ]) as Books;
      expect(
        () => books.find('1'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains("Cannot find cache named 'books'"),
          ),
        ),
      );
    });

    test('named beans need a bean factory', () {
      expect(
        () => proxy.upper('a'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains("KeyGenerator bean 'upperKeys'"),
          ),
        ),
      );
    });
  });
}
