import 'package:spring_boot_starter_cache/spring_auto_configuration.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'books.dart';

final _app = BeanModule('app', [
  BeanDefinition<Books>(
    name: 'books',
    create: (_) => Books(),
    aopProxy: booksProxyFactory,
  ),
  BeanDefinition<KeyGenerator>(
    name: 'upperKeys',
    create: (_) => const UpperKeys(),
  ),
]);

final class _ManagerRegistrar implements BeanRegistrar {
  _ManagerRegistrar(this.manager);
  final CacheManager manager;

  @override
  void register(BeanRegistry registry, Environment environment) => registry
      .registerBean<CacheManager>((_) => manager, name: 'appCacheManager');
}

final class _ManagerDefinitionRegistrar
    implements ImportBeanDefinitionRegistrar {
  _ManagerDefinitionRegistrar(this.manager);
  final CacheManager manager;

  @override
  void registerBeanDefinitions(BeanDefinitionRegistry registry) =>
      registry.registerBeanDefinition(
        BeanDefinition<CacheManager>(
          name: 'appCacheManager',
          create: (_) => manager,
        ),
      );
}

void main() {
  final runner = const ApplicationContextRunner()
      .withUserConfiguration(_app)
      .withAutoConfiguration(springBootStarterCacheAutoConfiguration);

  test('caching works without any setup', () {
    runner.run((context) {
      expect(context, hasSingleBean<CacheManager>());
      expect(context.getBean<CacheManager>(), isA<InMemoryCacheManager>());
      final books = context.getBean<Books>();
      expect(AopUtils.isAopProxy(books), isTrue);
      books
        ..find('1')
        ..find('1');
      expect(books.count('find'), 1);
      // A KeyGenerator bean named in the annotation.
      books
        ..upper('a')
        ..upper('a');
      expect(books.count('upper'), 1);
      expect(
        context.getBean<CacheManager>().getCache('books')!.get('A')?.value,
        'upper a',
      );
    });
  });

  test('backs off when the application declares a CacheManager', () {
    final own = InMemoryCacheManager(cacheNames: ['books', 'configured']);
    runner.withBean<CacheManager>(() => own).run((context) {
      expect(context.getBean<CacheManager>(), same(own));
      context.getBean<Books>().find('1');
      expect(own.getCache('books')!.get('1'), isNotNull);
    });
  });

  test('backs off for a CacheManager of a registrar the application '
      '@Imports', () {
    final own = InMemoryCacheManager();
    for (final registrar in <Object Function()>[
      () => _ManagerRegistrar(own),
      () => _ManagerDefinitionRegistrar(own),
    ]) {
      // What the generator emits for `@Configuration() @Import([...])
      // class AppConfig {}`.
      final app = BeanModule(
        'imports',
        [
          BeanDefinition<Object>(
            name: 'appConfig',
            source: 'package:app/app.dart#AppConfig',
            annotations: const [Configuration()],
            create: (_) => Object(),
          ),
        ],
        registrars: [
          ImportDeclaration(
            registrar,
            importer: 'package:app/app.dart#AppConfig',
          ),
        ],
      );
      runner.withUserConfiguration(app).run((context) {
        expect(context, hasSingleBean<CacheManager>());
        expect(context.getBean<CacheManager>(), same(own));
      });
    }
  });

  test('a CacheManager bean named in the annotation', () {
    final second = InMemoryCacheManager();
    final module = BeanModule('second', [
      BeanDefinition<CacheManager>(
        name: 'secondManager',
        create: (_) => second,
        autowireCandidate: false,
      ),
    ]);
    runner.withUserConfiguration(module).run((context) {
      final books = context.getBean<Books>()
        ..second('1')
        ..second('1');
      expect(books.count('second'), 1);
      expect(second.getCache('books')!.get('1')?.value, 'second 1');
      // The other methods keep the starter's manager.
      books
        ..find('1')
        ..find('1');
      expect(books.count('find'), 1);
      expect(context.getBean<CacheManager>(), isNot(same(second)));
    });
  });

  test('spring.cache.cache-names fixes the caches', () {
    runner.withPropertyValues(['spring.cache.cache-names=authors']).run((
      context,
    ) {
      final manager = context.getBean<CacheManager>() as InMemoryCacheManager;
      expect(manager.cacheNames, ['authors']);
      expect(
        () => context.getBean<Books>().find('1'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains("Cannot find cache named 'books'"),
          ),
        ),
      );
    });
  });

  test('an empty spring.cache.cache-names keeps the caches dynamic', () {
    for (final value in ['', ' , ']) {
      runner.withPropertyValues(['spring.cache.cache-names=$value']).run((
        context,
      ) {
        expect(context.hasFailed, isFalse);
        expect(context.getBean<Books>().find('1'), isNotNull);
        expect(context.getBean<CacheManager>().cacheNames, contains('books'));
      });
    }
  });

  test('spring.cache.cache-names as a YAML list', () {
    runner
        .withPropertyValues([
          'spring.cache.cache-names[0]=authors',
          'spring.cache.cache-names[1]=books',
        ])
        .run((context) {
          final manager =
              context.getBean<CacheManager>() as InMemoryCacheManager;
          expect(manager.cacheNames, ['authors', 'books']);
        });
  });

  test('time to live and size limits from properties', () {
    runner
        .withPropertyValues([
          'spring.cache.simple.time-to-live=10m',
          'spring.cache.simple.max-size=100',
          'spring.cache.simple.caches.prices.time-to-live=30s',
        ])
        .run((context) {
          final manager = context.getBean<CacheManager>();
          final books = manager.getCache('books')! as InMemoryCache;
          expect(books.spec.timeToLive, const Duration(minutes: 10));
          expect(books.spec.maxSize, 100);
          final prices = manager.getCache('prices')! as InMemoryCache;
          expect(prices.spec.timeToLive, const Duration(seconds: 30));
          expect(prices.spec.maxSize, 100);
        });
  });

  test('spring.cache.type=none keeps the annotations but caches nothing', () {
    runner.withPropertyValues(['spring.cache.type=none']).run((context) {
      expect(context.getBean<CacheManager>(), isA<NoOpCacheManager>());
      final books = context.getBean<Books>()
        ..find('1')
        ..find('1');
      expect(books.count('find'), 2);
    });
  });

  test('an unknown spring.cache.type fails at startup', () {
    runner.withPropertyValues(['spring.cache.type=redis']).run((context) {
      expect(context, hasFailed());
    });
  });
}
