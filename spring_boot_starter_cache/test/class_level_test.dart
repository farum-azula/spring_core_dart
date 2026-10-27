import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:test/test.dart';

/// A call of `name(arg)` on a `Shelf` with `annotations` on the member and
/// `classAnnotations` on the class, counting the real calls.
final class _Call implements MethodInvocation {
  _Call(
    String name, {
    List<Object> annotations = const [],
    List<Object>? mergedAnnotations,
    List<Object> classAnnotations = const [],
    List<Object>? implementingClassAnnotations,
    List<List<Object>> superclassAnnotations = const [],
    this.arg = 'a',
    MemberKind kind = MemberKind.method,
    this.onProceed,
  }) : signature = MethodSignature(
         name: name,
         declaringType: 'Shelf',
         targetType: 'Shelf',
         kind: kind,
         returnType: 'String',
         parameterTypes: const ['String'],
         parameterNames: const ['isbn'],
         annotations: annotations,
         mergedAnnotations: mergedAnnotations,
         targetAnnotations: classAnnotations,
         implementingTypes: implementingClassAnnotations == null
             ? const []
             : const ['Base'],
         implementingTypeAnnotations: implementingClassAnnotations,
         superclassAnnotations: superclassAnnotations,
       );

  @override
  final MethodSignature signature;

  final Object? arg;
  final void Function()? onProceed;

  @override
  List<Object?> get args => [arg];

  @override
  Object get target => this;

  @override
  Object get proxy => this;

  @override
  Object? proceed([List<Object?>? arguments]) {
    onProceed?.call();
    return '${signature.name} $arg';
  }

  @override
  String toShortString() => 'execution(Shelf.${signature.name}(..))';
}

void main() {
  const pointcut = CacheAnnotationPointcut();

  group('class-level cache annotations', () {
    const onClass = [Cacheable('shelf')];

    test('apply to every public method without its own', () {
      final manager = InMemoryCacheManager();
      final interceptor = CacheInterceptor(cacheManager: manager);
      var calls = 0;
      _Call call(String name) =>
          _Call(name, classAnnotations: onClass, onProceed: () => calls++);
      expect(pointcut.matches(call('find').signature, 'shelf'), isTrue);
      expect(interceptor.invoke(call('find')), 'find a');
      expect(interceptor.invoke(call('find')), 'find a');
      expect(calls, 1);
      expect(manager.getCache('shelf')!.get('a')!.value, 'find a');
    });

    test("a method's own annotations win", () {
      final manager = InMemoryCacheManager();
      final interceptor = CacheInterceptor(cacheManager: manager);
      final own = _Call(
        'find',
        annotations: const [Cacheable('own')],
        classAnnotations: onClass,
      );
      interceptor.invoke(own);
      expect(manager.getCache('own')!.get('a'), isNotNull);
      expect(manager.getCache('shelf')!.get('a'), isNull);
    });

    test('not getters, setters or Object members', () {
      for (final call in [
        _Call('size', classAnnotations: onClass, kind: MemberKind.getter),
        _Call('size', classAnnotations: onClass, kind: MemberKind.setter),
        _Call('toString', classAnnotations: onClass),
      ]) {
        expect(pointcut.matches(call.signature, 'shelf'), isFalse);
        expect(
          AnnotationCacheOperationSource().getCacheOperations(call.signature),
          isEmpty,
        );
      }
    });

    test('those of an overridden superclass method apply to an override '
        'without its own, before the class ones', () {
      final manager = InMemoryCacheManager();
      final interceptor = CacheInterceptor(cacheManager: manager);
      var calls = 0;
      _Call call() => _Call(
        'find',
        mergedAnnotations: const [Cacheable('base')],
        classAnnotations: onClass,
        onProceed: () => calls++,
      );
      expect(pointcut.matches(call().signature, 'shelf'), isTrue);
      expect(interceptor.invoke(call()), 'find a');
      expect(interceptor.invoke(call()), 'find a');
      expect(calls, 1);
      expect(manager.getCache('base')!.get('a'), isNotNull);
      expect(manager.getCache('shelf')!.get('a'), isNull);

      // The override's own annotations win over the overridden ones.
      interceptor.invoke(
        _Call(
          'find',
          annotations: const [Cacheable('own')],
          mergedAnnotations: const [Cacheable('own'), Cacheable('other')],
        ),
      );
      expect(manager.getCache('own')!.get('a'), isNotNull);
      expect(manager.getCache('other')?.get('a'), isNull);
    });

    test('come from the class declaring the method, then its '
        'superclasses (the nearest per annotation type), like Spring', () {
      final manager = InMemoryCacheManager();
      // Shelf extends Base extends Root; find is inherited from Base.
      CacheInterceptor(cacheManager: manager).invoke(
        _Call(
          'find',
          classAnnotations: const [Cacheable('subclass')],
          implementingClassAnnotations: const [],
          superclassAnnotations: const [
            [
              CacheConfig(cacheNames: ['base']),
            ],
            [
              CacheConfig(cacheNames: ['root']),
              Cacheable.of(),
              CachePut('root'),
            ],
          ],
        ),
      );
      // Not the subclass's @Cacheable('subclass').
      expect(manager.cacheNames, ['base', 'root']);

      final local = AnnotationCacheOperationSource.cacheAnnotationsOf(
        _Call(
          'find',
          classAnnotations: const [Cacheable('own')],
          superclassAnnotations: const [
            [Cacheable('base'), CacheEvict('base')],
          ],
        ).signature,
      );
      expect(local, const [Cacheable('own'), CacheEvict('base')]);
    });

    test('@CacheConfig alone does not make a member cached', () {
      final call = _Call(
        'find',
        classAnnotations: const [
          CacheConfig(cacheNames: ['x']),
        ],
      );
      expect(pointcut.matches(call.signature, 'shelf'), isFalse);
    });
  });

  test('#root.method.name and other method properties in keys', () {
    final manager = InMemoryCacheManager();
    CacheInterceptor(cacheManager: manager).invoke(
      _Call(
        'find',
        annotations: const [
          Cacheable(
            'books',
            key: "#root.method.name + '/' + #root.method.parameterCount",
          ),
        ],
      ),
    );
    expect(manager.getCache('books')!.get('find/1'), isNotNull);
  });

  test('a null key fails the call, like Spring', () {
    final interceptor = CacheInterceptor(cacheManager: InMemoryCacheManager());
    expect(
      () => interceptor.invoke(
        _Call(
          'find',
          arg: null,
          annotations: const [Cacheable('books', key: '#isbn')],
        ),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('Null key returned for cache operation'),
        ),
      ),
    );
  });
}
