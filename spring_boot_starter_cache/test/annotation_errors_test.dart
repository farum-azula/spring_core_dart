import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:test/test.dart';

/// A call of `find(isbn)` carrying [annotations].
final class _Invocation implements MethodInvocation {
  _Invocation(
    List<Object> annotations, {
    List<Object> classAnnotations = const [],
  }) : signature = MethodSignature(
         name: 'find',
         declaringType: 'Books',
         targetType: 'Books',
         parameterNames: const ['isbn'],
         annotations: annotations,
         targetAnnotations: classAnnotations,
       );

  @override
  final MethodSignature signature;

  @override
  List<Object?> get args => const ['1'];

  @override
  Object get target => this;

  @override
  Object get proxy => this;

  @override
  Object? proceed([List<Object?>? arguments]) => 'value';

  @override
  String toShortString() => 'execution(Books.find(..))';
}

void main() {
  spelExamples();

  Object? call(List<Object> annotations) =>
      CacheInterceptor(cacheManager: InMemoryCacheManager())
          .invoke(_Invocation(annotations));

  Matcher error(String text) => throwsA(
    isA<StateError>().having((e) => e.message, 'message', contains(text)),
  );

  test('cache names are required (annotation or @CacheConfig)', () {
    expect(
      () => call(const [Cacheable.of()]),
      error('No cache names for @Cacheable on Books.find'),
    );
    final interceptor = CacheInterceptor(cacheManager: InMemoryCacheManager());
    expect(
      interceptor.invoke(
        _Invocation(
          const [Cacheable.of()],
          classAnnotations: const [
            CacheConfig(cacheNames: ['books']),
          ],
        ),
      ),
      'value',
    );
  });

  test('key and keyGenerator exclude each other', () {
    expect(
      () => call(const [Cacheable('books', key: '#isbn', keyGenerator: 'k')]),
      error('Both key and keyGenerator'),
    );
  });

  test('sync: true restrictions', () {
    expect(
      () => call(const [Cacheable('books', sync: true), CacheEvict('authors')]),
      error('cannot be combined'),
    );
    expect(
      () => call(const [
        Cacheable('books', cacheNames: ['more'], sync: true),
      ]),
      error('allows a single cache'),
    );
    expect(
      () => call(const [Cacheable('books', sync: true, unless: 'true')]),
      error('does not support unless'),
    );
  });

  test('several annotations on one method combine', () {
    final manager = InMemoryCacheManager();
    CacheInterceptor(cacheManager: manager).invoke(
      _Invocation(const [Cacheable('books'), Cacheable('isbn', key: "'k'")]),
    );
    expect(manager.getCache('books')!.get('1')?.value, 'value');
    expect(manager.getCache('isbn')!.get('k')?.value, 'value');
  });
}

final class _Factory implements BeanFactory {
  @override
  Object getBeanByName(String name) =>
      name == 'region' ? 'eu' : throw StateError('no bean $name');

  @override
  T? findBean<T extends Object>({String? qualifier}) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void spelExamples() {
  test('SpEL examples of the README', () {
    final manager = InMemoryCacheManager();
    final interceptor = CacheInterceptor(
      cacheManager: manager,
      beanFactory: _Factory(),
    );
    interceptor.invoke(
      _Invocation(const [
        Cacheable(
          'a',
          key: "#isbn + '-' + #p0",
          condition: '#isbn.length() == 1',
        ),
        Cacheable('b', key: '@region'),
      ]),
    );
    expect(manager.getCache('a')!.get('1-1')?.value, 'value');
    expect(manager.getCache('b')!.get('eu')?.value, 'value');
  });
}
