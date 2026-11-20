// Several managers at once: Spring's CompositeCacheManager (the first that
// has the cache gives it) and a layered cache of our own (a fast cache in
// front of slower ones, a hit in a slower one copied forward); a resource
// keyed by its content's version; spring.cache.type: disk from the
// properties.
import 'package:spring_boot_starter_cache/spring_auto_configuration.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

final class _File implements VersionedResource {
  _File(this.address, this.version);

  final String address;

  @override
  String? version;

  @override
  Uri get uri => Uri.parse(address);

  @override
  String get description => 'file [$address]';

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CompositeCacheManager', () {
    test('the first manager that has the cache gives it', () {
      final memory = InMemoryCacheManager(cacheNames: ['books']);
      final more = InMemoryCacheManager(cacheNames: ['books', 'authors']);
      final composite = CompositeCacheManager([memory, more]);
      expect(
        identical(composite.getCache('books'), memory.getCache('books')),
        isTrue,
      );
      expect(
        identical(composite.getCache('authors'), more.getCache('authors')),
        isTrue,
      );
      expect(composite.getCache('prices'), isNull);
      expect(composite.cacheNames, containsAll(['books', 'authors']));
    });

    test('with the fallback, a name none has keeps nothing', () {
      final composite = CompositeCacheManager([
        InMemoryCacheManager(cacheNames: ['books']),
      ], fallbackToNoOpCache: true);
      final prices = composite.getCache('prices')!..put('a', 1);
      expect(prices.get('a'), isNull);
      expect(composite.cacheNames, contains('prices'));
    });
  });

  group('LayeredCacheManager', () {
    late InMemoryCacheManager memory;
    late DiskCacheManager disk;
    late LayeredCacheManager layered;

    setUp(() {
      memory = InMemoryCacheManager();
      disk = DiskCacheManager(
        store: InMemoryCacheStore(),
        mapper: ObjectMapper(),
        introspector: Introspector(),
      );
      layered = LayeredCacheManager([memory, disk]);
    });

    test('a put goes to every layer', () async {
      (layered.getCache('books')! as LayeredCache).put('1', 'Dune');
      expect(memory.getCache('books')!.get('1')?.value, 'Dune');
      await (disk.getCache('books')! as DiskCache).flush();
      expect(
        (await (disk.getCache('books')! as DiskCache).retrieve('1'))?.value,
        'Dune',
      );
    });

    test('a hit in a slower layer is copied into the faster ones', () async {
      final slow = disk.getCache('books')! as DiskCache..put('1', 'Dune');
      await slow.flush();
      // Another run: the memory and the disk cache remember nothing.
      final fresh = InMemoryCacheManager();
      final cache =
          LayeredCacheManager([
                fresh,
                DiskCacheManager(
                  store: disk.store,
                  mapper: ObjectMapper(),
                  introspector: Introspector(),
                ),
              ]).getCache('books')!
              as LayeredCache;
      expect(cache.answersSynchronously, isFalse);
      expect(cache.get('1'), isNull, reason: 'get asks the fast layers only');
      expect((await cache.retrieve('1'))?.value, 'Dune');
      expect(fresh.getCache('books')!.get('1')?.value, 'Dune');
      expect(cache.get('1')?.value, 'Dune', reason: 'now in memory');
    });

    test('an evict and a clear go to every layer', () async {
      final cache = layered.getCache('books')! as LayeredCache
        ..put('1', 'Dune')
        ..put('2', 'Emma');
      expect(cache.evictIfPresent('1'), isTrue);
      expect(memory.getCache('books')!.get('1'), isNull);
      cache.clear();
      expect(memory.getCache('books')!.get('2'), isNull);
      await (disk.getCache('books')! as DiskCache).flush();
      expect(await cache.retrieve('2'), isNull);
    });

    test('in memory only, it answers at once', () {
      final cache =
          LayeredCacheManager([InMemoryCacheManager(), InMemoryCacheManager()])
                  .getCache('a')!
              as LayeredCache;
      expect(cache.answersSynchronously, isTrue);
    });
  });

  group('a resource as a key', () {
    MethodSignature method() =>
        const MethodSignature.of('thumbnail', AopTarget('Thumbs'));

    test('by its address alone, as in Spring', () {
      const generator = SimpleKeyGenerator();
      final file = _File('https://cdn.test/a.png', 'v1');
      final before = generator.generate(Object(), method(), [file]);
      file.version = 'v2';
      expect(generator.generate(Object(), method(), [file]), before);
    });

    test("with resource-version, by its content's version too", () {
      const generator = SimpleKeyGenerator(resourceVersion: true);
      final file = _File('https://cdn.test/a.png', 'v1');
      final before = generator.generate(Object(), method(), [file]);
      expect(before, ('https://cdn.test/a.png', 'v1'));
      file.version = 'v2';
      expect(generator.generate(Object(), method(), [file]), isNot(before));
      expect(
        generator.generate(Object(), method(), [file, 3]),
        SimpleKey([('https://cdn.test/a.png', 'v2'), 3]),
      );
    });
  });

  group('the properties', () {
    final runner = const ApplicationContextRunner().withAutoConfiguration(
      springBootStarterCacheAutoConfiguration,
    );

    test('type: disk keeps the entries in the CacheStore bean', () {
      final store = InMemoryCacheStore();
      runner
          .withBean<CacheStore>(() => store)
          .withPropertyValues([
            'spring.cache.type=disk',
            'spring.cache.disk.time-to-live=1h',
            'spring.cache.disk.max-size=10MB',
            'spring.cache.disk.version=2.1.0',
            'spring.cache.disk.caches.prices.time-to-live=5m',
          ])
          .run((context) {
            expect(context.startupFailure, isNull);
            final manager = context.getBean<CacheManager>();
            expect(manager, isA<DiskCacheManager>());
            manager as DiskCacheManager;
            expect(identical(manager.store, store), isTrue);
            expect(manager.timeToLive, const Duration(hours: 1));
            expect(manager.timeToLives['prices'], const Duration(minutes: 5));
            expect(manager.maxSize, 10 * 1024 * 1024);
            expect(manager.version, '2.1.0');
          });
    });

    test('without a store bean: a folder', () {
      runner.withPropertyValues(['spring.cache.type=disk']).run((context) {
        final manager = context.getBean<CacheManager>() as DiskCacheManager;
        expect(manager.store, isA<DirectoryCacheStore>());
        expect((manager.store as DirectoryCacheStore).path, '.spring/cache');
      });
    });

    test('resource-version reaches the interceptor', () {
      runner.withPropertyValues(['spring.cache.resource-version=true']).run((
        context,
      ) {
        expect(context.getBean<CacheProperties>().resourceVersion, isTrue);
        expect(context.getBean<CacheInterceptor>().resourceVersion, isTrue);
      });
    });
  });
}
