// A bean with cache annotations and its proxy, written exactly like the
// generator writes them (signatures with annotations, parameter names and
// class annotations).
import 'dart:async';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';

@CacheConfig(cacheNames: ['configured'])
class Books {
  final calls = <String, int>{};
  final pending = <String, Completer<String>>{};

  void _count(String method) => calls[method] = (calls[method] ?? 0) + 1;

  int count(String method) => calls[method] ?? 0;

  @Cacheable('books')
  String find(String isbn) {
    _count('find');
    return 'title of $isbn';
  }

  @Cacheable('books', key: '#isbn', condition: '#fresh == false')
  String findFresh(String isbn, bool fresh) {
    _count('findFresh');
    return 'fresh $isbn';
  }

  @Cacheable('books', key: '#p0', unless: '#result == null')
  String? maybe(String isbn) {
    _count('maybe');
    return isbn == 'missing' ? null : 'maybe $isbn';
  }

  @Cacheable('nulls')
  String? nothing(String isbn) {
    _count('nothing');
    return null;
  }

  @Cacheable('books', key: '#root.methodName')
  String byMethod() {
    _count('byMethod');
    return 'by method';
  }

  @Cacheable('books', key: "#root.targetClass + '/' + #a0")
  String byClass(String isbn) {
    _count('byClass');
    return 'by class';
  }

  @CachePut('books', key: '#isbn')
  String save(String isbn, String title) {
    _count('save');
    return title;
  }

  @CacheEvict('books', key: '#isbn')
  void delete(String isbn) => _count('delete');

  @CacheEvict('books', allEntries: true, beforeInvocation: true)
  void reload() {
    _count('reload');
    throw StateError('reload failed');
  }

  @CacheEvict('books', allEntries: true)
  void clearAfter({bool fail = false}) {
    _count('clearAfter');
    if (fail) {
      throw StateError('clear failed');
    }
  }

  @Caching(
    cacheable: [Cacheable('books')],
    evict: [CacheEvict('authors', allEntries: true)],
  )
  String combined(String isbn) {
    _count('combined');
    return 'combined $isbn';
  }

  @Cacheable.of()
  String configured(String isbn) {
    _count('configured');
    return 'configured $isbn';
  }

  @Cacheable('books', keyGenerator: 'upperKeys')
  String upper(String isbn) {
    _count('upper');
    return 'upper $isbn';
  }

  @Cacheable('books', cacheManager: 'secondManager')
  String second(String isbn) {
    _count('second');
    return 'second $isbn';
  }

  @Cacheable('async')
  Future<String> fetch(String isbn) async {
    _count('fetch');
    if (isbn == 'bad') {
      throw StateError('not found');
    }
    return 'fetched $isbn';
  }

  @Cacheable('async', sync: true)
  Future<String> fetchShared(String isbn) {
    _count('fetchShared');
    return (pending[isbn] = Completer<String>()).future;
  }

  String plain(String isbn) {
    _count('plain');
    return 'plain $isbn';
  }

  @Caching(
    cacheable: [Cacheable('books', key: '#isbn')],
    put: [CachePut('books', key: '#isbn', condition: '#force == true')],
  )
  String refresh(String isbn, bool force) {
    _count('refresh');
    return 'refreshed $isbn';
  }

  @Caching(
    cacheable: [Cacheable('books', key: '#isbn')],
    put: [CachePut('refreshed', key: '#isbn', condition: '#result != null')],
  )
  String refreshResult(String isbn) {
    _count('refreshResult');
    return 'refreshed $isbn';
  }

  @Cacheable('async', key: '#isbn.noSuchProperty')
  Future<String> fetchBadKey(String isbn) async {
    _count('fetchBadKey');
    return 'fetched $isbn';
  }
}

MethodSignature _sig(
  String name,
  List<String> parameterNames,
  List<Object> annotations, {
  String returnType = 'String',
}) => MethodSignature(
  name: name,
  declaringType: 'Books',
  targetType: 'Books',
  declaringTypes: const ['Books'],
  returnType: returnType,
  parameterTypes: [for (final _ in parameterNames) 'String'],
  parameterNames: parameterNames,
  annotations: annotations,
  annotationTypes: [
    for (final annotation in annotations) annotation.runtimeType.toString(),
  ],
  targetTypes: const ['Books'],
  targetAnnotations: const [
    CacheConfig(cacheNames: ['configured']),
  ],
  targetAnnotationTypes: const ['CacheConfig'],
);

final booksSignatures = [
  _sig('find', ['isbn'], const [Cacheable('books')]),
  _sig(
    'findFresh',
    ['isbn', 'fresh'],
    const [Cacheable('books', key: '#isbn', condition: '#fresh == false')],
  ),
  _sig(
    'maybe',
    ['isbn'],
    const [Cacheable('books', key: '#p0', unless: '#result == null')],
  ),
  _sig('nothing', ['isbn'], const [Cacheable('nulls')]),
  _sig('byMethod', [], const [Cacheable('books', key: '#root.methodName')]),
  _sig(
    'byClass',
    ['isbn'],
    const [Cacheable('books', key: "#root.targetClass + '/' + #a0")],
  ),
  _sig('save', ['isbn', 'title'], const [CachePut('books', key: '#isbn')]),
  _sig(
    'delete',
    ['isbn'],
    const [CacheEvict('books', key: '#isbn')],
    returnType: 'void',
  ),
  _sig('reload', [], const [
    CacheEvict('books', allEntries: true, beforeInvocation: true),
  ], returnType: 'void'),
  _sig(
    'clearAfter',
    ['fail'],
    const [CacheEvict('books', allEntries: true)],
    returnType: 'void',
  ),
  _sig(
    'combined',
    ['isbn'],
    const [
      Caching(
        cacheable: [Cacheable('books')],
        evict: [CacheEvict('authors', allEntries: true)],
      ),
    ],
  ),
  _sig('configured', ['isbn'], const [Cacheable.of()]),
  _sig(
    'upper',
    ['isbn'],
    const [Cacheable('books', keyGenerator: 'upperKeys')],
  ),
  _sig(
    'second',
    ['isbn'],
    const [Cacheable('books', cacheManager: 'secondManager')],
  ),
  _sig('fetch', ['isbn'], const [Cacheable('async')], returnType: 'Future'),
  _sig(
    'fetchShared',
    ['isbn'],
    const [Cacheable('async', sync: true)],
    returnType: 'Future',
  ),
  _sig('plain', ['isbn'], const []),
  _sig(
    'refresh',
    ['isbn', 'force'],
    const [
      Caching(
        cacheable: [Cacheable('books', key: '#isbn')],
        put: [CachePut('books', key: '#isbn', condition: '#force == true')],
      ),
    ],
  ),
  _sig(
    'refreshResult',
    ['isbn'],
    const [
      Caching(
        cacheable: [Cacheable('books', key: '#isbn')],
        put: [
          CachePut('refreshed', key: '#isbn', condition: '#result != null'),
        ],
      ),
    ],
  ),
  _sig(
    'fetchBadKey',
    ['isbn'],
    const [Cacheable('async', key: '#isbn.noSuchProperty')],
    returnType: 'Future',
  ),
];

/// What the generator writes for [Books].
class BooksProxy extends Books implements Advised {
  BooksProxy(this._target, this._invoker);

  final Books _target;
  final ProxyInvoker _invoker;

  @override
  Object get aopTarget => _target;

  @override
  List<PointcutAdvisor> get aopAdvisors => _invoker.advisors;

  @override
  void addAdvisor(PointcutAdvisor advisor) => _invoker.addAdvisor(advisor);

  @override
  bool removeAdvisor(PointcutAdvisor advisor) =>
      _invoker.removeAdvisor(advisor);

  @override
  void addAdvice(MethodInterceptor advice) => _invoker.addAdvice(advice);

  @override
  bool removeAdvice(MethodInterceptor advice) => _invoker.removeAdvice(advice);

  @override
  Map<String, int> get calls => _target.calls;

  @override
  Map<String, Completer<String>> get pending => _target.pending;

  @override
  int count(String method) => _target.count(method);

  String _call(int index, List<Object?> args, String Function() call) =>
      _invoker.invoke(this, _target, index, args, (_) => call())! as String;

  String? _maybe(int index, List<Object?> args, String? Function() call) =>
      _invoker.invoke(this, _target, index, args, (_) => call()) as String?;

  void _void(int index, List<Object?> args, void Function() call) {
    _invoker.invoke(this, _target, index, args, (_) {
      call();
      return null;
    });
  }

  @override
  String find(String isbn) => _call(0, [isbn], () => _target.find(isbn));

  @override
  String findFresh(String isbn, bool fresh) =>
      _call(1, [isbn, fresh], () => _target.findFresh(isbn, fresh));

  @override
  String? maybe(String isbn) => _maybe(2, [isbn], () => _target.maybe(isbn));

  @override
  String? nothing(String isbn) =>
      _maybe(3, [isbn], () => _target.nothing(isbn));

  @override
  String byMethod() => _call(4, const [], _target.byMethod);

  @override
  String byClass(String isbn) => _call(5, [isbn], () => _target.byClass(isbn));

  @override
  String save(String isbn, String title) =>
      _call(6, [isbn, title], () => _target.save(isbn, title));

  @override
  void delete(String isbn) => _void(7, [isbn], () => _target.delete(isbn));

  @override
  void reload() => _void(8, const [], _target.reload);

  @override
  void clearAfter({bool fail = false}) =>
      _void(9, [fail], () => _target.clearAfter(fail: fail));

  @override
  String combined(String isbn) =>
      _call(10, [isbn], () => _target.combined(isbn));

  @override
  String configured(String isbn) =>
      _call(11, [isbn], () => _target.configured(isbn));

  @override
  String upper(String isbn) => _call(12, [isbn], () => _target.upper(isbn));

  @override
  String second(String isbn) => _call(13, [isbn], () => _target.second(isbn));

  @override
  Future<String> fetch(String isbn) => _invoker.invokeAsync<String>(
    this,
    _target,
    14,
    [isbn],
    (args) => _target.fetch(args[0]! as String),
  );

  @override
  Future<String> fetchShared(String isbn) => _invoker.invokeAsync<String>(
    this,
    _target,
    15,
    [isbn],
    (args) => _target.fetchShared(args[0]! as String),
  );

  @override
  String plain(String isbn) => _call(16, [isbn], () => _target.plain(isbn));

  @override
  String refresh(String isbn, bool force) =>
      _call(17, [isbn, force], () => _target.refresh(isbn, force));

  @override
  String refreshResult(String isbn) =>
      _call(18, [isbn], () => _target.refreshResult(isbn));

  @override
  Future<String> fetchBadKey(String isbn) => _invoker.invokeAsync<String>(
    this,
    _target,
    19,
    [isbn],
    (args) => _target.fetchBadKey(args[0]! as String),
  );
}

/// The proxy factory the generator writes into the bean definition.
final booksProxyFactory = AopProxyFactory(
  signatures: booksSignatures,
  create: (target, invoker) => BooksProxy(target as Books, invoker),
);

/// A key generator bean: upper-cased first argument.
class UpperKeys implements KeyGenerator {
  const UpperKeys();

  @override
  Object? generate(Object target, MethodSignature method, List<Object?> args) =>
      (args.first! as String).toUpperCase();
}
