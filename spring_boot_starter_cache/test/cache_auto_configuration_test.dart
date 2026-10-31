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

  // A negative size made the first put loop for ever (assertions, which
  // release builds and `dart run` skip, were the only check): the first
  // @Cacheable call never answered. Caffeine's maximumSize refuses it.
  test('a negative max-size fails the start, naming the property', () {
    for (final property in [
      'spring.cache.simple.max-size',
      // Read when the cache is first used: checked at the start too.
      'spring.cache.simple.caches.prices.max-size',
    ]) {
      runner.withPropertyValues(['$property=-1']).run((context) {
        expect(
          context,
          hasFailed(
            predicate(
              (Object? failure) => '$failure'.contains(
                'Invalid argument ($property): must not be negative',
              ),
              'an error naming $property',
            ),
          ),
        );
      });
    }
  });

  // A cache name with dots: Spring Boot's bracket form was ignored (no
  // limit at all) and the plain form checked only at the first use.
  test('a cache name with dots: in brackets or plain, its limits apply and '
      'are checked at the start', () {
    runner
        .withPropertyValues([
          'spring.cache.simple.caches[books.byIsbn].max-size=2',
          'spring.cache.simple.caches[books.byIsbn].time-to-live=1m',
          'spring.cache.simple.caches.prices.eu.max-size=3',
          'spring.cache.simple.caches.authors.maxSize=4',
        ])
        .run((context) {
          final manager = context.getBean<CacheManager>();
          final byIsbn = manager.getCache('books.byIsbn')! as InMemoryCache;
          expect(byIsbn.spec.maxSize, 2);
          expect(byIsbn.spec.timeToLive, const Duration(minutes: 1));
          for (var i = 0; i < 5; i++) {
            byIsbn.put(i, i);
          }
          expect(byIsbn.size, 2);
          final eu = manager.getCache('prices.eu')! as InMemoryCache;
          expect(eu.spec.maxSize, 3);
          final authors = manager.getCache('authors')! as InMemoryCache;
          expect(authors.spec.maxSize, 4);
          final books = manager.getCache('books')! as InMemoryCache;
          expect(
            books.spec,
            isA<CacheSpec>().having((s) => s.maxSize, 'maxSize', isNull),
          );
        });
    for (final property in [
      'spring.cache.simple.caches[books.byIsbn].max-size',
      'spring.cache.simple.caches.prices.eu.max-size',
      'spring.cache.simple.caches[books.byIsbn].time-to-live',
      'spring.cache.simple.caches.prices.eu.time-to-live',
    ]) {
      final value = property.endsWith('max-size') ? '-1' : '-1s';
      runner.withPropertyValues(['$property=$value']).run((context) {
        expect(
          context,
          hasFailed(
            predicate(
              (Object? failure) => '$failure'.contains(
                'Invalid argument ($property): must not be negative',
              ),
              'an error naming $property',
            ),
          ),
        );
      });
    }
  });

  // As YAML writes them ("[books.byIsbn]": a key with dots).
  test('per-cache limits from YAML', () {
    const yaml = '''
spring:
  cache:
    simple:
      max-size: 100
      caches:
        "[books.byIsbn]":
          max-size: 2
        prices:
          time-to-live: 30s
''';
    final environment = StandardEnvironment();
    const YamlPropertySourceLoader()
        .load('application.yaml', yaml)
        .forEach(environment.propertySources.addLast);
    final manager = cacheManagerFromProperties(environment);
    final byIsbn = manager.getCache('books.byIsbn')! as InMemoryCache;
    expect(byIsbn.spec.maxSize, 2);
    final prices = manager.getCache('prices')! as InMemoryCache;
    expect(prices.spec.timeToLive, const Duration(seconds: 30));
    expect(prices.spec.maxSize, 100);
  });

  // SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAX_SIZE binds as `books` /
  // `max.size`; the last element alone was taken as the property: a cache
  // `books.max` with a property `size`, ignored without a word. Spring
  // Boot 4.1.2 binds {books=Spec(maxSize=5)}.
  group('per-cache limits from environment variables', () {
    InMemoryCache cache(Map<String, Object> variables, String name) {
      final environment = StandardEnvironment();
      environment.propertySources.addFirst(
        SystemEnvironmentPropertySource('test-variables', variables),
      );
      return cacheManagerFromProperties(environment).getCache(name)!
          as InMemoryCache;
    }

    test('every relaxed form of max-size and time-to-live binds', () {
      for (final variable in [
        'SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAX_SIZE',
        'SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAXSIZE',
      ]) {
        expect(
          cache({variable: '5'}, 'books').spec.maxSize,
          5,
          reason: variable,
        );
      }
      for (final variable in [
        'SPRING_CACHE_SIMPLE_CACHES_PRICES_TIME_TO_LIVE',
        'SPRING_CACHE_SIMPLE_CACHES_PRICES_TIMETOLIVE',
      ]) {
        expect(
          cache({variable: '30s'}, 'prices').spec.timeToLive,
          const Duration(seconds: 30),
          reason: variable,
        );
      }
      // `_` in the name is a dot (names come lower-cased).
      expect(
        cache({
          'SPRING_CACHE_SIMPLE_CACHES_BOOKS_BYISBN_MAX_SIZE': '2',
        }, 'books.byisbn').spec.maxSize,
        2,
      );
      final books = cache({
        'SPRING_CACHE_SIMPLE_MAX_SIZE': '100',
        'SPRING_CACHE_SIMPLE_CACHES_BOOKS_TIME_TO_LIVE': '1m',
      }, 'books');
      expect(books.spec.timeToLive, const Duration(minutes: 1));
      expect(books.spec.maxSize, 100, reason: 'the global one fills in');
    });

    test('a negative value fails the start, naming the property', () {
      expect(
        () => cache({
          'SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAX_SIZE': '-1',
        }, 'books'),
        throwsA(
          predicate(
            (Object? e) => '$e'.contains(
              'Invalid argument (spring.cache.simple.caches.books.max-size): '
              'must not be negative',
            ),
          ),
        ),
      );
    });

    test('the source of higher precedence wins over another form', () {
      for (final (variablesFirst, expected) in [(true, 7), (false, 5)]) {
        final environment = StandardEnvironment();
        const variables = SystemEnvironmentPropertySource(
          'test-variables',
          {
            'SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAX_SIZE': '7',
          },
        );
        const file = MapPropertySource('application.properties', {
          'spring.cache.simple.caches.books.max-size': '5',
        });
        environment.propertySources
          ..addFirst(variablesFirst ? file : variables)
          ..addFirst(variablesFirst ? variables : file);
        final books =
            cacheManagerFromProperties(environment).getCache('books')!
                as InMemoryCache;
        expect(books.spec.maxSize, expected, reason: '$variablesFirst');
      }
    });
  });

  // The forms the fifth round fixed, with the property found as the
  // longest end of the key now.
  test('per-cache keys: plain, bracketed, dotted, a cache named max-size, '
      'relaxed property names', () {
    runner
        .withPropertyValues([
          'spring.cache.simple.caches.a.max-size=1',
          'spring.cache.simple.caches[b.c].max-size=2',
          'spring.cache.simple.caches.d.e.max-size=3',
          'spring.cache.simple.caches[f][max-size]=4',
          'spring.cache.simple.caches[g.h][time-to-live]=5s',
          'spring.cache.simple.caches.max-size.max-size=6',
          'spring.cache.simple.caches[time-to-live].time-to-live=7s',
          'spring.cache.simple.caches.i.MAXSIZE=8',
          'spring.cache.simple.caches.j.max_size=9',
          'spring.cache.simple.caches.k.MAX_SIZE=10',
          'spring.cache.simple.caches.l.timeToLive=11s',
          'spring.cache.simple.caches.m.size=12', // not a property
        ])
        .run((context) {
          final manager = context.getBean<CacheManager>();
          CacheSpec spec(String name) =>
              (manager.getCache(name)! as InMemoryCache).spec;
          expect(spec('a').maxSize, 1);
          expect(spec('b.c').maxSize, 2);
          expect(spec('d.e').maxSize, 3);
          expect(spec('f').maxSize, 4);
          expect(spec('g.h').timeToLive, const Duration(seconds: 5));
          expect(spec('max-size').maxSize, 6);
          expect(spec('time-to-live').timeToLive, const Duration(seconds: 7));
          expect(spec('i').maxSize, 8);
          expect(spec('j').maxSize, 9);
          expect(spec('k').maxSize, 10);
          expect(spec('l').timeToLive, const Duration(seconds: 11));
          expect(spec('m').maxSize, isNull);
          expect(spec('m.size').maxSize, isNull);
        });
  });

  // A negative time to live was taken: every entry expired as it was
  // written. Caffeine's expireAfterWrite refuses a negative duration.
  test('a negative time-to-live fails the start, naming the property; 0 '
      'keeps no entry, as Caffeine', () {
    for (final property in [
      'spring.cache.simple.time-to-live',
      'spring.cache.simple.caches.prices.time-to-live',
    ]) {
      runner.withPropertyValues(['$property=-1s']).run((context) {
        expect(
          context,
          hasFailed(
            predicate(
              (Object? failure) => '$failure'.contains(
                'Invalid argument ($property): must not be negative',
              ),
              'an error naming $property',
            ),
          ),
        );
      });
    }
    runner.withPropertyValues(['spring.cache.simple.time-to-live=0']).run((
      context,
    ) {
      expect(context.hasFailed, isFalse);
      final books = context.getBean<Books>()
        ..find('1')
        ..find('1');
      expect(books.count('find'), 2);
      final cache = context.getBean<CacheManager>().getCache('books')!;
      expect(cache.get('1'), isNull);
    });
  });

  test('max-size=0 keeps no entry, as Caffeine', () {
    runner
        .withPropertyValues([
          'spring.cache.simple.max-size=0',
          'spring.cache.simple.caches.prices.max-size=1',
        ])
        .run((context) {
          expect(context.hasFailed, isFalse);
          final books = context.getBean<Books>()
            ..find('1')
            ..find('1');
          expect(books.count('find'), 2);
          final manager = context.getBean<CacheManager>();
          final cache = manager.getCache('books')! as InMemoryCache;
          expect(cache.spec.maxSize, 0);
          expect(cache.size, 0);
          final prices = manager.getCache('prices')! as InMemoryCache
            ..put('a', 1);
          expect(prices.get('a')?.value, 1);
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
