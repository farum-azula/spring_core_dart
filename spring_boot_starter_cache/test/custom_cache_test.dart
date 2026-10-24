import 'dart:convert';

import 'package:spring_boot_starter_cache/spring_auto_configuration.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'books.dart';

/// The custom cache of the README: JSON in a map standing in for a store.
final class StoreCache with CacheDefaults implements Cache {
  StoreCache(this.name, this.store);

  @override
  final String name;
  final Map<String, String> store;

  String _key(Object? key) => '$name:$key';

  @override
  ValueWrapper? get(Object? key) => switch (store[_key(key)]) {
    null => null,
    final json => ValueWrapper(jsonDecode(json)),
  };

  @override
  void put(Object? key, Object? value) => store[_key(key)] = jsonEncode(value);

  @override
  void evict(Object? key) => store.remove(_key(key));

  @override
  void clear() => store.removeWhere((key, _) => key.startsWith('$name:'));
}

void main() {
  test('CacheDefaults derives putIfAbsent, evictIfPresent, invalidate', () {
    final cache = StoreCache('books', {});
    expect(cache.putIfAbsent('1', 'a'), isNull);
    expect(cache.putIfAbsent('1', 'b')?.value, 'a');
    expect(cache.evictIfPresent('1'), isTrue);
    expect(cache.evictIfPresent('1'), isFalse);
    cache
      ..put('2', null)
      ..put('3', 'c');
    // A stored null is a hit, not a miss.
    expect(cache.get('2'), isNotNull);
    expect(cache.get('2')!.value, isNull);
    expect(cache.invalidate(), isTrue);
    expect(cache.get('3'), isNull);
  });

  test('SimpleCacheManager knows exactly the caches it was given', () {
    final books = StoreCache('books', {});
    final manager = SimpleCacheManager([books, InMemoryCache('prices')]);
    expect(manager.getCache('books'), same(books));
    expect(manager.getCache('prices'), isA<InMemoryCache>());
    expect(manager.getCache('other'), isNull);
    expect(manager.cacheNames, ['books', 'prices']);
  });

  test('a cache of your own behind @Cacheable', () {
    final store = <String, String>{};
    final runner = const ApplicationContextRunner()
        .withUserConfiguration(
          BeanModule('app', [
            BeanDefinition<Books>(
              name: 'books',
              create: (_) => Books(),
              aopProxy: booksProxyFactory,
            ),
          ]),
        )
        .withBean<CacheManager>(
          () => SimpleCacheManager([StoreCache('books', store)]),
        )
        .withAutoConfiguration(springBootStarterCacheAutoConfiguration);
    runner.run((context) {
      final books = context.getBean<Books>()
        ..find('1')
        ..find('1');
      expect(books.count('find'), 1);
      expect(store, contains('books:1'));
    });
    // The entries are in the store: a new context (a restart) finds them.
    runner.run((context) {
      final books = context.getBean<Books>()..find('1');
      expect(books.count('find'), 0);
    });
  });
}
