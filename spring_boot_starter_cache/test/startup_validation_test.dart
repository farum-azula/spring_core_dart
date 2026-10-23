// Cache annotations are checked when a proxied bean is created, for every
// member, so a wrong annotation fails the startup instead of a call.
import 'package:spring_boot_starter_cache/spring_auto_configuration.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'books.dart';

class Catalog {}

MethodSignature _sig(
  String name,
  List<Object> annotations, {
  String returnType = 'String',
}) => MethodSignature(
  name: name,
  declaringType: 'Catalog',
  targetType: 'Catalog',
  returnType: returnType,
  parameterNames: const ['isbn'],
  annotations: annotations,
);

/// A bean whose generated proxy would have [signatures].
BeanModule _catalog(List<MethodSignature> signatures) => BeanModule('app', [
  BeanDefinition<Catalog>(
    name: 'catalog',
    create: (_) => Catalog(),
    aopProxy: AopProxyFactory(
      signatures: signatures,
      create: (target, invoker) =>
          throw StateError('the proxy must not be created'),
    ),
  ),
]);

void main() {
  final runner = const ApplicationContextRunner().withAutoConfiguration(
    springBootStarterCacheAutoConfiguration,
  );

  Matcher failsWith(String text) => isA<AssertableApplicationContext>()
      .having((c) => c.hasFailed, 'hasFailed', isTrue)
      .having((c) => '${c.startupFailure}', 'startupFailure', contains(text));

  test('an invalid annotation on any member fails the startup', () {
    runner
        .withUserConfiguration(
          _catalog([
            _sig('first', const [Cacheable('books')]),
            _sig('plain', const []),
            _sig('second', const [
              Cacheable('books', key: '#isbn', keyGenerator: 'keys'),
            ]),
          ]),
        )
        .run((context) {
          expect(
            context,
            failsWith(
              'Both key and keyGenerator are set for @Cacheable on '
              'Catalog.second',
            ),
          );
        });
  });

  test('cacheManager with cacheResolver, sync rules, missing names', () {
    for (final (annotations, message) in [
      (
        const [CacheEvict('books', cacheManager: 'm', cacheResolver: 'r')],
        'Both cacheManager and cacheResolver',
      ),
      (
        const [Cacheable('books', sync: true), CacheEvict('authors')],
        'cannot be combined',
      ),
      (const [CachePut.of()], 'No cache names for @CachePut on Catalog.last'),
    ]) {
      runner
          .withUserConfiguration(
            _catalog([
              _sig('first', const [Cacheable('books')]),
              _sig('last', annotations),
            ]),
          )
          .run((context) => expect(context, failsWith(message)));
    }
  });

  test('@Cacheable on a member returning a Stream fails the startup', () {
    runner
        .withUserConfiguration(
          _catalog([
            _sig('first', const [Cacheable('books')]),
            _sig('events', const [Cacheable('events')], returnType: 'Stream'),
          ]),
        )
        .run((context) {
          expect(
            context,
            failsWith(
              '@Cacheable on Catalog.events: the member returns a Stream',
            ),
          );
        });
  });

  test('valid annotations start; the proxy is created', () {
    runner
        .withUserConfiguration(
          BeanModule('app', [
            BeanDefinition<Books>(
              name: 'books',
              create: (_) => Books(),
              aopProxy: booksProxyFactory,
            ),
            BeanDefinition<KeyGenerator>(
              name: 'upperKeys',
              create: (_) => const UpperKeys(),
            ),
          ]),
        )
        .run((context) {
          expect(context, isNot(hasFailed()));
          expect(AopUtils.isAopProxy(context.getBean<Books>()), isTrue);
        });
  });

  test('the cache manager backs off for a bean named cacheResolver', () {
    final manager = InMemoryCacheManager();
    runner
        .withUserConfiguration(
          BeanModule('resolver', [
            BeanDefinition<CacheResolver>(
              name: 'cacheResolver',
              create: (_) => NamedCacheResolver(manager, ['all']),
            ),
          ]),
        )
        .run((context) {
          expect(context, doesNotHaveBean<CacheManager>());
          expect(context, hasSingleBean<CacheResolver>());
        });
  });
}
