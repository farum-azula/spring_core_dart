// @CacheConfig inheritance, cache resolvers, CachingConfigurer defaults and
// cache error handlers, on the interceptor with hand-written calls.
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:test/test.dart';

/// A call of `Catalog.<name>(isbn)` carrying `annotations`.
final class _Invocation implements MethodInvocation {
  _Invocation(
    List<Object> annotations, {
    List<Object> classAnnotations = const [],
    String name = 'find',
  }) : signature = MethodSignature(
         name: name,
         declaringType: 'Catalog',
         targetType: 'Catalog',
         parameterNames: const ['isbn'],
         returnType: 'String',
         annotations: annotations,
         targetAnnotations: classAnnotations,
       );

  @override
  final MethodSignature signature;

  @override
  List<Object?> get args => const ['1'];

  int calls = 0;

  @override
  Object get target => this;

  @override
  Object get proxy => this;

  @override
  Object? proceed([List<Object?>? arguments]) => 'value ${++calls}';

  @override
  String toShortString() => 'execution(Catalog.${signature.name}(..))';
}

/// Beans by name; `findBean` finds the single bean of a type.
final class _Beans implements BeanFactory {
  _Beans(this.beans);

  final Map<String, Object> beans;

  @override
  Object getBeanByName(String name) =>
      beans[name] ?? (throw StateError('no bean $name'));

  @override
  T? findBean<T extends Object>({String? qualifier}) =>
      beans.values.whereType<T>().singleOrNull;

  @override
  T getBean<T extends Object>({String? qualifier}) =>
      findBean<T>() ?? (throw StateError('no bean of $T'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Prefixes the operation's cache names with a tenant.
final class _TenantResolver implements CacheResolver {
  _TenantResolver(this.manager);

  final CacheManager manager;
  final seen = <CacheOperationInvocationContext>[];

  @override
  Iterable<Cache> resolveCaches(CacheOperationInvocationContext context) {
    seen.add(context);
    return [
      for (final name in context.operation.cacheNames)
        manager.getCache('acme.$name')!,
    ];
  }
}

final class _FirstArgKeys implements KeyGenerator {
  const _FirstArgKeys();

  @override
  Object? generate(Object target, MethodSignature method, List<Object?> args) =>
      'k:${args.first}';
}

/// A cache whose store is down.
final class _BrokenCache with CacheDefaults implements Cache {
  @override
  String get name => 'books';

  @override
  ValueWrapper? get(Object? key) => throw StateError('get down');

  @override
  void put(Object? key, Object? value) => throw StateError('put down');

  @override
  void evict(Object? key) => throw StateError('evict down');

  @override
  void clear() => throw StateError('clear down');
}

final class _Recording implements CacheErrorHandler {
  final errors = <String>[];

  @override
  void handleCacheGetError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
  ) => errors.add('get ${cache.name} $key: $exception');

  @override
  void handleCachePutError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
    Object? value,
  ) => errors.add('put ${cache.name} $key=$value');

  @override
  void handleCacheEvictError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
  ) => errors.add('evict ${cache.name} $key');

  @override
  void handleCacheClearError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
  ) => errors.add('clear ${cache.name}');
}

final class _Configurer with CachingConfigurer {
  _Configurer({this.resolver, this.keys, this.handler});

  final CacheResolver? resolver;
  final KeyGenerator? keys;
  final CacheErrorHandler? handler;

  @override
  CacheResolver? cacheResolver() => resolver;

  @override
  KeyGenerator? keyGenerator() => keys;

  @override
  CacheErrorHandler? errorHandler() => handler;
}

void main() {
  final source = AnnotationCacheOperationSource();

  List<CacheOperation> operations(
    List<Object> annotations, {
    List<Object> classAnnotations = const [],
    String returnType = 'String',
  }) => source.getCacheOperations(
    MethodSignature(
      name: 'find',
      declaringType: 'Catalog',
      targetType: 'Catalog',
      returnType: returnType,
      annotations: annotations,
      targetAnnotations: classAnnotations,
    ),
  );

  Matcher error(String text) => throwsA(
    isA<StateError>().having((e) => e.message, 'message', contains(text)),
  );

  group('@CacheConfig defaults (Spring DefaultCacheConfig)', () {
    const config = CacheConfig(
      cacheNames: ['books'],
      keyGenerator: 'configKeys',
      cacheManager: 'configManager',
    );

    test('keyGenerator applies only without key and keyGenerator', () {
      // A key next to @CacheConfig(keyGenerator:) used to throw.
      final [withKey] = operations(
        const [Cacheable.of(key: '#isbn')],
        classAnnotations: const [config],
      );
      expect(withKey.key, '#isbn');
      expect(withKey.keyGenerator, isNull);
      expect(withKey.cacheNames, ['books']);

      final [inherited] = operations(
        const [CachePut.of()],
        classAnnotations: const [config],
      );
      expect(inherited.keyGenerator, 'configKeys');

      final [own] = operations(
        const [CacheEvict.of(keyGenerator: 'ownKeys')],
        classAnnotations: const [config],
      );
      expect(own.keyGenerator, 'ownKeys');
    });

    test('a key next to @CacheConfig(keyGenerator:) works at the call', () {
      final manager = InMemoryCacheManager();
      final invocation = _Invocation(
        const [Cacheable.of(key: "'fixed'")],
        classAnnotations: const [config],
      );
      final interceptor = CacheInterceptor(
        cacheManager: manager,
        beanFactory: _Beans({'configManager': manager}),
      );
      expect(interceptor.invoke(invocation), 'value 1');
      expect(interceptor.invoke(invocation), 'value 1');
      expect(manager.getCache('books')!.get('fixed')?.value, 'value 1');
    });

    test('cacheManager / cacheResolver: only when the operation has '
        'neither; the resolver wins', () {
      final [ownResolver] = operations(
        const [Cacheable.of(cacheResolver: 'tenants')],
        classAnnotations: const [config],
      );
      expect(ownResolver.cacheResolver, 'tenants');
      expect(ownResolver.cacheManager, isNull);

      final [ownManager] = operations(
        const [Cacheable.of(cacheManager: 'other')],
        classAnnotations: const [CacheConfig(cacheResolver: 'tenants')],
      );
      expect(ownManager.cacheManager, 'other');
      expect(ownManager.cacheResolver, isNull);

      final [both] = operations(
        const [Cacheable('books')],
        classAnnotations: const [
          CacheConfig(cacheManager: 'm', cacheResolver: 'r'),
        ],
      );
      expect(both.cacheResolver, 'r');
      expect(both.cacheManager, isNull);
    });

    test('operation types expose their attributes', () {
      final [cacheable, put, evict] = operations(const [
        Cacheable('a', unless: 'u'),
        CachePut('b', unless: 'false'),
        CacheEvict('c', allEntries: true, beforeInvocation: true),
      ]);
      expect(cacheable, isA<CacheableOperation>());
      expect((cacheable as CacheableOperation).unless, 'u');
      expect((put as CachePutOperation).unless, 'false');
      expect((evict as CacheEvictOperation).cacheWide, isTrue);
      expect(evict.beforeInvocation, isTrue);
      expect(evict.name, 'Catalog.find');
      expect(evict.description, '@CacheEvict on Catalog.find');
    });
  });

  group('invalid annotations', () {
    test('key with keyGenerator, cacheManager with cacheResolver', () {
      expect(
        () => operations(const [
          Cacheable('books', key: '#isbn', keyGenerator: 'k'),
        ]),
        error(
          'Both key and keyGenerator are set for @Cacheable on '
          'Catalog.find',
        ),
      );
      expect(
        () => operations(const [
          CachePut('books', cacheManager: 'm', cacheResolver: 'r'),
        ]),
        error(
          'Both cacheManager and cacheResolver are set for @CachePut on '
          'Catalog.find',
        ),
      );
    });

    test('a Stream result cannot be cached', () {
      expect(
        () => operations(const [Cacheable('books')], returnType: 'Stream'),
        error('@Cacheable on Catalog.find: the member returns a Stream'),
      );
      expect(
        () => operations(const [CachePut('books')], returnType: 'Stream'),
        error('Future<List<T>>'),
      );
      // Evicting around a stream-returning member is fine.
      expect(
        operations(const [CacheEvict('books')], returnType: 'Stream'),
        hasLength(1),
      );
    });

    test('names may be left out only when a resolver picks the caches', () {
      final interceptor = CacheInterceptor(
        cacheManager: InMemoryCacheManager(),
      );
      expect(
        () => interceptor.invoke(_Invocation(const [Cacheable.of()])),
        error('No cache names for @Cacheable on Catalog.find'),
      );
      expect(
        () => interceptor.invoke(
          _Invocation(const [Cacheable.of(cacheManager: 'm')], name: 'other'),
        ),
        error('No cache names'),
      );
      final manager = InMemoryCacheManager();
      final named = CacheInterceptor(
        cacheResolver: NamedCacheResolver(manager, ['audit']),
      );
      expect(named.invoke(_Invocation(const [Cacheable.of()])), 'value 1');
      expect(manager.getCache('audit')!.get('1')?.value, 'value 1');
    });
  });

  group('CacheResolver', () {
    test('a CacheResolver bean named in the annotation', () {
      final manager = InMemoryCacheManager();
      final tenants = _TenantResolver(manager);
      final interceptor = CacheInterceptor(
        cacheManager: manager,
        beanFactory: _Beans({'tenants': tenants}),
      );
      final invocation = _Invocation(const [
        Cacheable('books', cacheResolver: 'tenants'),
      ]);
      interceptor
        ..invoke(invocation)
        ..invoke(invocation);
      expect(invocation.calls, 1);
      expect(manager.getCache('acme.books')!.get('1')?.value, 'value 1');
      expect(manager.cacheNames, isNot(contains('books')));
      final context = tenants.seen.first;
      expect(context.operation, isA<CacheableOperation>());
      expect(context.operation.cacheNames, ['books']);
      expect(context.method.name, 'find');
      expect(context.args, ['1']);
      expect(context.target, same(invocation));
    });

    test('@CacheConfig(cacheResolver:) for the class', () {
      final manager = InMemoryCacheManager();
      CacheInterceptor(
        beanFactory: _Beans({'tenants': _TenantResolver(manager)}),
      ).invoke(
        _Invocation(
          const [Cacheable.of()],
          classAnnotations: const [
            CacheConfig(cacheNames: ['books'], cacheResolver: 'tenants'),
          ],
        ),
      );
      expect(manager.getCache('acme.books')!.get('1'), isNotNull);
    });

    test('a resolver resolving nothing fails the call', () {
      final interceptor = CacheInterceptor(
        cacheResolver: NamedCacheResolver(InMemoryCacheManager(), const []),
      );
      expect(
        () => interceptor.invoke(_Invocation(const [Cacheable('books')])),
        error('No cache could be resolved for @Cacheable on Catalog.find'),
      );
    });

    test('SimpleCacheResolver names the missing cache', () {
      final interceptor = CacheInterceptor(
        cacheResolver: SimpleCacheResolver(SimpleCacheManager(const [])),
      );
      expect(
        () => interceptor.invoke(_Invocation(const [Cacheable('books')])),
        error(
          "Cannot find cache named 'books' for @Cacheable on "
          'Catalog.find',
        ),
      );
    });
  });

  group('CachingConfigurer', () {
    test('provides the default resolver and key generator', () {
      final manager = InMemoryCacheManager();
      final interceptor = CacheInterceptor(
        beanFactory: _Beans({
          'cacheSetup': _Configurer(
            resolver: _TenantResolver(manager),
            keys: const _FirstArgKeys(),
          ),
        }),
      );
      final invocation = _Invocation(const [Cacheable('books')]);
      interceptor
        ..invoke(invocation)
        ..invoke(invocation);
      expect(invocation.calls, 1);
      expect(manager.getCache('acme.books')!.get('k:1')?.value, 'value 1');
      expect(interceptor.keyGenerator, isA<_FirstArgKeys>());
      expect(interceptor.cacheResolver, isA<_TenantResolver>());
    });

    test('null methods keep the defaults; arguments win', () {
      final manager = InMemoryCacheManager();
      final interceptor = CacheInterceptor(
        keyGenerator: const SimpleKeyGenerator(),
        beanFactory: _Beans({
          'cacheManager': manager,
          'cacheSetup': _Configurer(keys: const _FirstArgKeys()),
        }),
      );
      expect(interceptor.keyGenerator, isA<SimpleKeyGenerator>());
      expect(interceptor.errorHandler, isA<SimpleCacheErrorHandler>());
      expect(interceptor.cacheManager, same(manager));
      expect(interceptor.cacheResolver, isA<SimpleCacheResolver>());
    });
  });

  group('CacheErrorHandler', () {
    test('the default rethrows the cache error', () {
      final interceptor = CacheInterceptor(
        cacheManager: SimpleCacheManager([_BrokenCache()]),
      );
      expect(
        () => interceptor.invoke(_Invocation(const [Cacheable('books')])),
        error('get down'),
      );
    });

    test('a handler that does not rethrow: get is a miss, the rest is '
        'skipped', () {
      final handler = _Recording();
      final interceptor = CacheInterceptor(
        cacheManager: SimpleCacheManager([_BrokenCache()]),
        beanFactory: _Beans({'cacheSetup': _Configurer(handler: handler)}),
      );
      final find = _Invocation(const [Cacheable('books')]);
      expect(interceptor.invoke(find), 'value 1');
      expect(interceptor.invoke(find), 'value 2'); // nothing cached
      expect(
        interceptor.invoke(
          _Invocation(const [CacheEvict('books')], name: 'delete'),
        ),
        'value 1',
      );
      interceptor.invoke(
        _Invocation(const [
          CacheEvict('books', allEntries: true),
        ], name: 'clear'),
      );
      expect(handler.errors, [
        'get books 1: Bad state: get down',
        'put books 1=value 1',
        'get books 1: Bad state: get down',
        'put books 1=value 2',
        'evict books 1',
        'clear books',
      ]);
    });

    test('LoggingCacheErrorHandler logs a warning and goes on', () {
      final records = <SpringLogRecord>[];
      final handler = SpringLog.handler;
      SpringLog.handler = records.add;
      addTearDown(() => SpringLog.handler = handler);
      final interceptor = CacheInterceptor(
        cacheManager: SimpleCacheManager([_BrokenCache()]),
        errorHandler: const LoggingCacheErrorHandler(),
      );
      expect(
        interceptor.invoke(_Invocation(const [Cacheable('books')])),
        'value 1',
      );
      final messages = [
        for (final record in records)
          if (record.loggerName == 'spring.cache') record.message,
      ];
      expect(messages, [
        "Cache 'books' failed to get entry with key '1': Bad state: get down",
        "Cache 'books' failed to put entry with key '1': Bad state: put down",
      ]);
    });
  });
}
