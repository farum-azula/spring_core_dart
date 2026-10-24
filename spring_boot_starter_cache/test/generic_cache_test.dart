import 'package:spring_boot_starter_cache/spring_auto_configuration.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

final class Seen implements CacheManagerCustomizer {
  final managers = <CacheManager>[];

  @override
  void customize(CacheManager cacheManager) => managers.add(cacheManager);
}

void main() {
  final runner = const ApplicationContextRunner().withAutoConfiguration(
    springBootStarterCacheAutoConfiguration,
  );

  test('Cache beans give a generic manager of them, like Boot', () {
    runner
        .withBean<Cache>(() => InMemoryCache('books'), name: 'booksCache')
        .withBean<Cache>(() => InMemoryCache('authors'), name: 'authorsCache')
        .run((context) {
          final manager = context.getBean<CacheManager>();
          expect(manager, isA<SimpleCacheManager>());
          expect(manager.cacheNames, unorderedEquals(['books', 'authors']));
          expect(manager.getCache('other'), isNull);
        });
  });

  test('spring.cache.type wins over the Cache beans; generic needs one', () {
    runner
        .withBean<Cache>(() => InMemoryCache('books'))
        .withPropertyValues(['spring.cache.type=simple'])
        .run((context) {
          expect(context.getBean<CacheManager>(), isA<InMemoryCacheManager>());
        });
    runner.withPropertyValues(['spring.cache.type=GENERIC']).run((context) {
      expect(context, hasFailed());
      expect(
        '${context.startupFailure}',
        contains('spring.cache.type=generic'),
      );
    });
  });

  test('CacheManagerCustomizer beans customize the manager', () {
    final seen = Seen();
    runner.withBean<CacheManagerCustomizer>(() => seen).run((context) {
      expect(seen.managers.single, same(context.getBean<CacheManager>()));
    });
  });
}
