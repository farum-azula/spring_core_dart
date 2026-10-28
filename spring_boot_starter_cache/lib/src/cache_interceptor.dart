import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache.dart';
import 'package:spring_boot_starter_cache/src/cache_error_handler.dart';
import 'package:spring_boot_starter_cache/src/cache_operation.dart';
import 'package:spring_boot_starter_cache/src/cache_resolver.dart';
import 'package:spring_boot_starter_cache/src/caching_configurer.dart';
import 'package:spring_boot_starter_cache/src/key_generator.dart';

/// The rule that picks which bean methods the [CacheInterceptor] wraps:
/// those with `@Cacheable`, `@CachePut`, `@CacheEvict` or `@Caching`, on
/// the method or, for public methods, on its class.
///
/// The starter pairs it with the interceptor in an advisor, so the
/// generated proxies run the cache logic only around those methods.
/// Applications do not use it, unless they set caching up without the
/// starter's auto-configuration.
///
/// ```dart
/// // Caching without the auto-configuration: apply the interceptor to the
/// // annotated methods of proxied beans.
/// DefaultPointcutAdvisor(const CacheAnnotationPointcut(), interceptor);
/// ```
///
/// Spring (Java):
/// ```java
/// // Registered by @EnableCaching (BeanFactoryCacheOperationSourceAdvisor).
/// ```
final class CacheAnnotationPointcut implements AnnotationPointcut {
  /// The pointcut; it has no settings.
  const CacheAnnotationPointcut();

  /// Whether [annotation] is a `@Cacheable`, `@CachePut`, `@CacheEvict`
  /// or `@Caching`.
  static bool isCacheAnnotation(Object annotation) =>
      AnnotationCacheOperationSource.isCacheAnnotation(annotation);

  @override
  bool matches(MethodSignature signature, String beanName) =>
      AnnotationCacheOperationSource.cacheAnnotationsOf(signature).isNotEmpty;

  @override
  String toString() => 'CacheAnnotationPointcut';
}

/// The code that runs around every call of a cached method and does what
/// its cache annotations say.
///
/// For one call it:
///
/// 1. removes the entries of `@CacheEvict(beforeInvocation: true)`;
/// 2. looks the `@Cacheable` key up and, on a hit, returns the stored value
///    without running the method (unless a `@CachePut` on the same method
///    forces the call);
/// 3. otherwise runs the method, stores the result for `@Cacheable` (unless
///    its `unless` says no) and for `@CachePut`;
/// 4. removes the entries of the other `@CacheEvict`s, after a hit too.
///
/// For a method returning a `Future`, the value is stored when the future
/// completes (errors are never stored) and a hit returns a completed
/// future; every error, even of a SpEL expression, comes through the
/// future. Errors thrown by a cache go to the [errorHandler], which by
/// default rethrows them to the caller.
///
/// The starter creates it as a bean and applies it with a
/// [CacheAnnotationPointcut]; applications never call it. Its defaults
/// ([cacheManager], [cacheResolver], [keyGenerator], [errorHandler]) are
/// the ones passed in, else those of the `CachingConfigurer` bean, else
/// the `CacheManager` bean, a [SimpleCacheResolver], [SimpleKeyGenerator]
/// and [SimpleCacheErrorHandler]. Build one yourself only to use caching
/// without the auto-configuration:
///
/// ```dart
/// // A hand-made setup: caches in memory, applied to annotated methods.
/// final interceptor = CacheInterceptor(
///   cacheManager: InMemoryCacheManager(),
/// );
/// final advisor =
///     DefaultPointcutAdvisor(const CacheAnnotationPointcut(), interceptor);
/// ```
///
/// Spring (Java):
/// ```java
/// CacheInterceptor interceptor = new CacheInterceptor();
/// interceptor.setCacheManager(new ConcurrentMapCacheManager());
/// interceptor.setCacheOperationSource(new AnnotationCacheOperationSource());
/// ```
final class CacheInterceptor implements MethodInterceptor {
  /// An interceptor with the given defaults; every argument is optional.
  ///
  /// `cacheManager`, `cacheResolver`, `keyGenerator` and `errorHandler`
  /// override the defaults described above. [beanFactory] is where the
  /// bean names in annotations (`cacheManager: 'sessionCaches'`), the
  /// `CachingConfigurer` and the `CacheManager` bean are found; without it,
  /// pass a `cacheManager`. [introspector] lets SpEL read properties of
  /// `@Introspected` arguments (`#book.isbn`); `cacheOperationSource` and
  /// `parser` replace how annotations and expressions are read.
  CacheInterceptor({
    this._cacheManager,
    this._cacheResolver,
    this._keyGenerator,
    this._errorHandler,
    this.beanFactory,
    AnnotationCacheOperationSource? cacheOperationSource,
    BeanIntrospector? introspector,
    ExpressionParser? parser,
  }) : cacheOperationSource =
           cacheOperationSource ?? AnnotationCacheOperationSource(),
       introspector = introspector ?? BeanIntrospector.shared,
       _parser = parser ?? SpelExpressionParser();

  /// The container in which bean names from annotations, the
  /// `CachingConfigurer` and the `CacheManager` bean are looked up; `null`
  /// when the interceptor was built without one.
  final BeanFactory? beanFactory;

  /// Turns the annotations of a method into the operations to apply.
  final AnnotationCacheOperationSource cacheOperationSource;

  /// The generated accessors that let SpEL read properties and call
  /// methods of `@Introspected` classes (`#book.isbn`).
  final BeanIntrospector introspector;

  final ExpressionParser _parser;
  CacheManager? _cacheManager;
  CacheResolver? _cacheResolver;
  KeyGenerator? _keyGenerator;
  CacheErrorHandler? _errorHandler;
  var _configured = false;
  final _expressions = <String, Expression>{};
  final _operations = Map<MethodSignature, List<CacheOperation>>.identity();
  final _resolvers = Map<CacheOperation, CacheResolver>.identity();
  final _keyGenerators = Map<CacheOperation, KeyGenerator>.identity();
  final _inFlight = <(String, Object?), Future<Object?>>{};

  // Takes what the CachingConfigurer bean (if any) provides for the
  // defaults that were not passed in, once.
  void _configure() {
    if (_configured) {
      return;
    }
    _configured = true;
    final configurer = beanFactory?.findBean<CachingConfigurer>();
    if (configurer == null) {
      return;
    }
    _cacheResolver ??= configurer.cacheResolver();
    _cacheManager ??= configurer.cacheManager();
    _keyGenerator ??= configurer.keyGenerator();
    _errorHandler ??= configurer.errorHandler();
  }

  /// The cache manager of operations that name none: the one passed in,
  /// else the `CachingConfigurer`'s, else the `CacheManager` bean. Throws a
  /// `StateError` when there is neither a manager nor a [beanFactory].
  CacheManager get cacheManager {
    _configure();
    return _cacheManager ??= switch (beanFactory) {
      final factory? => factory.getBean<CacheManager>(),
      null => throw StateError(
        'CacheInterceptor has no cache manager: pass one or a bean factory',
      ),
    };
  }

  /// The cache resolver of operations that name neither a manager nor a
  /// resolver: the one passed in, else the `CachingConfigurer`'s, else a
  /// [SimpleCacheResolver] of [cacheManager].
  CacheResolver get cacheResolver {
    _configure();
    return _cacheResolver ??= SimpleCacheResolver(cacheManager);
  }

  /// The key generator of operations with neither `key` nor
  /// `keyGenerator`: the one passed in, else the `CachingConfigurer`'s,
  /// else [SimpleKeyGenerator].
  KeyGenerator get keyGenerator {
    _configure();
    return _keyGenerator ??= const SimpleKeyGenerator();
  }

  /// What happens when a cache throws: the handler passed in, else the
  /// `CachingConfigurer`'s, else [SimpleCacheErrorHandler], which rethrows.
  CacheErrorHandler get errorHandler {
    _configure();
    return _errorHandler ??= const SimpleCacheErrorHandler();
  }

  /// The cache operations of the member [signature], checked; empty when
  /// it has none. Computed once per member.
  ///
  /// Throws a `StateError` naming the member for a wrong combination of
  /// settings (see [AnnotationCacheOperationSource]) and for an operation
  /// without cache names when no resolver can pick the caches.
  /// [CacheOperationValidator] calls it for every annotated member when the
  /// bean is created, so these mistakes fail the startup.
  List<CacheOperation> cacheOperations(MethodSignature signature) =>
      _operations[signature] ??= _validate(signature);

  List<CacheOperation> _validate(MethodSignature signature) {
    final operations = cacheOperationSource.getCacheOperations(signature);
    for (final operation in operations) {
      if (operation.cacheNames.isEmpty && !_resolvesWithoutNames(operation)) {
        throw StateError(
          'No cache names for ${operation.description}: name them in the '
          "annotation (@${operation.annotation}('books')) or in @CacheConfig "
          'on the class, or give a cacheResolver',
        );
      }
    }
    return operations;
  }

  // A resolver other than SimpleCacheResolver may pick caches by itself.
  bool _resolvesWithoutNames(CacheOperation operation) {
    if (operation.cacheResolver != null) {
      return true;
    }
    if (operation.cacheManager != null) {
      return false;
    }
    _configure();
    final resolver = _cacheResolver;
    return resolver != null && resolver is! SimpleCacheResolver;
  }

  @override
  Object? invoke(MethodInvocation invocation) {
    final operations = cacheOperations(invocation.signature);
    if (operations.isEmpty) {
      return invocation.proceed();
    }
    if (invocation is AsyncMethodInvocation) {
      // An async member fails through its Future, not synchronously: also
      // for an invalid SpEL key or condition, or a failing cache.
      try {
        return _invoke(invocation, operations, isAsync: true);
      } on Object catch (error, stackTrace) {
        return Future<Object?>.error(error, stackTrace);
      }
    }
    return _invoke(invocation, operations, isAsync: false);
  }

  Object? _invoke(
    MethodInvocation invocation,
    List<CacheOperation> operations, {
    required bool isAsync,
  }) {
    final call = _Call(this, invocation, operations);

    for (final operation in operations) {
      if (operation is CacheEvictOperation &&
          operation.beforeInvocation &&
          call.condition(operation)) {
        call.evict(operation);
      }
    }

    final cacheables = [
      for (final operation in operations)
        if (operation is CacheableOperation && call.condition(operation))
          operation,
    ];
    final keys = {
      for (final operation in cacheables) operation: call.key(operation),
    };
    ValueWrapper? hit;
    search:
    for (final operation in cacheables) {
      for (final cache in call.caches(operation)) {
        hit = call.get(cache, keys[operation]);
        if (hit != null) {
          break search;
        }
      }
    }
    // Like Spring's hasCachePut: a @CachePut whose condition already fails
    // does not force the call (one needing #result is assumed to pass).
    final hasPut = operations.any(
      (o) => o is CachePutOperation && call.conditionBeforeInvocation(o),
    );
    if (hit != null && !hasPut) {
      call.afterInvocation(hit.value, const {});
      return isAsync ? Future<Object?>.value(hit.value) : hit.value;
    }

    final missed = hit == null ? keys : const <CacheableOperation, Object?>{};
    (String, Object?)? inFlightKey;
    final single = cacheables.singleOrNull;
    if (isAsync && hit == null && single != null && single.sync) {
      inFlightKey = (call.caches(single).first.name, keys[single]);
      if (_inFlight[inFlightKey] case final pending?) {
        return pending;
      }
    }

    final result = invocation.proceed();
    if (invocation is AsyncMethodInvocation && result is Future) {
      final future = invocation.chain(
        result as Future<Object?>,
        onValue: (value) => call.afterInvocation(value, missed),
      );
      if (inFlightKey case final key?) {
        _inFlight[key] = future;
        // Block bodies: returning the removed future would adopt its error.
        unawaited(
          future.then<void>(
            (_) {
              unawaited(_inFlight.remove(key));
            },
            onError: (Object _) {
              unawaited(_inFlight.remove(key));
            },
          ),
        );
      }
      return future;
    }
    call.afterInvocation(result, missed);
    return result;
  }

  Expression _expression(String text) =>
      _expressions[text] ??= _parser.parseExpression(text);

  CacheResolver _resolverFor(CacheOperation operation) =>
      _resolvers[operation] ??= switch (operation) {
        CacheOperation(cacheResolver: final name?) => _bean<CacheResolver>(
          name,
          'CacheResolver',
        ),
        CacheOperation(cacheManager: final name?) => SimpleCacheResolver(
          _bean<CacheManager>(name, 'CacheManager'),
        ),
        _ => cacheResolver,
      };

  KeyGenerator _keyGeneratorFor(CacheOperation operation) =>
      _keyGenerators[operation] ??= switch (operation.keyGenerator) {
        final name? => _bean<KeyGenerator>(name, 'KeyGenerator'),
        null => keyGenerator,
      };

  T _bean<T extends Object>(String name, String kind) {
    final factory = beanFactory;
    if (factory == null) {
      throw StateError("No bean factory to look up the $kind bean '$name'");
    }
    final bean = factory.getBeanByName(name);
    if (bean is! T) {
      throw StateError("Bean '$name' is not a $kind");
    }
    return bean;
  }
}

/// Checks the cache annotations of each proxied bean when the bean is
/// created, so a wrong annotation fails the startup instead of the first
/// call of the method.
///
/// It is a bean post-processor: the container hands it every new bean,
/// and for the beans with a generated proxy it asks the [CacheInterceptor]
/// to read and check the annotations of every member
/// ([CacheInterceptor.cacheOperations]). Spring does the same when it
/// builds the proxy. The starter registers it; applications do not use
/// it.
///
/// ```dart
/// // In the auto-configuration: the interceptor is fetched at first use.
/// CacheOperationValidator.lazy(() => factory.getBean<CacheInterceptor>())
/// ```
final class CacheOperationValidator extends BeanPostProcessor
    implements BeanFactoryAware {
  /// A validator that checks with [interceptor].
  CacheOperationValidator(CacheInterceptor interceptor)
    : _interceptor = (() => interceptor);

  /// A validator that calls [interceptor] to get the interceptor only when
  /// the first bean with cache annotations comes.
  ///
  /// The auto-configuration uses this one. The dependencies of a
  /// post-processor are created before the other post-processors are
  /// registered, so they would miss them (the context then logs that they
  /// are "not eligible for getting processed by all BeanPostProcessors");
  /// fetching the interceptor late avoids that.
  CacheOperationValidator.lazy(CacheInterceptor Function() interceptor)
    : _interceptor = interceptor;

  final CacheInterceptor Function() _interceptor;

  /// The interceptor whose [CacheInterceptor.cacheOperations] checks the
  /// annotations; obtained on first use.
  late final CacheInterceptor interceptor = _interceptor();

  BeanFactory? _beanFactory;

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  // Before initialization, so it runs ahead of the auto proxy creator
  // (which proxies after initialization) whatever the order.
  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    final factory = _beanFactory;
    if (factory is! BeanDefinitionRegistry ||
        !(factory! as BeanDefinitionRegistry).containsBeanDefinition(
          beanName,
        )) {
      return bean;
    }
    final definition = (factory as BeanDefinitionRegistry).getBeanDefinition(
      beanName,
    );
    for (final signature
        in definition.aopProxy?.signatures ?? const <MethodSignature>[]) {
      if (AnnotationCacheOperationSource.cacheAnnotationsOf(signature)
          .isNotEmpty) {
        interceptor.cacheOperations(signature);
      }
    }
    return bean;
  }
}

// One cache operation of one call, for resolvers.
final class _Context implements CacheOperationInvocationContext {
  _Context(this.operation, this._invocation);

  @override
  final CacheOperation operation;

  final MethodInvocation _invocation;

  @override
  Object get target => _invocation.target;

  @override
  MethodSignature get method => _invocation.signature;

  @override
  List<Object?> get args => _invocation.args;
}

// One intercepted call: evaluates the SpEL of its operations, resolves
// their caches and routes cache errors to the error handler.
final class _Call {
  _Call(this._interceptor, this._invocation, this._operations);

  final CacheInterceptor _interceptor;
  final MethodInvocation _invocation;
  final List<CacheOperation> _operations;
  final _caches = Map<CacheOperation, List<Cache>>.identity();

  bool condition(CacheOperation operation, [_Result? result]) =>
      operation.condition == null ||
      _evaluate(operation.condition!, operation, result) == true;

  // The condition before the call: an expression reading `#result` (not
  // available yet) counts as passing (Spring's VariableNotAvailableException).
  bool conditionBeforeInvocation(CacheOperation operation) {
    final text = operation.condition;
    return text == null || _readsResult.hasMatch(text) || condition(operation);
  }

  static final _readsResult = RegExp(r'#result\b');

  bool unless(CacheOperation operation, _Result result) {
    final unless = switch (operation) {
      CacheableOperation(:final unless) ||
      CachePutOperation(:final unless) => unless,
      CacheEvictOperation() => null,
    };
    return unless != null && _evaluate(unless, operation, result) == true;
  }

  Object key(CacheOperation operation, [_Result? result]) {
    final key = switch (operation.key) {
      final key? => _evaluate(key, operation, result),
      null =>
        _interceptor
            ._keyGeneratorFor(operation)
            .generate(
              _invocation.target,
              _invocation.signature,
              _invocation.args,
            ),
    };
    // Like Spring's CacheAspectSupport.generateKey.
    return key ??
        (throw ArgumentError(
          'Null key returned for cache operation ${operation.description}: '
          'the key expression or key generator gave null',
        ));
  }

  List<Cache> caches(CacheOperation operation) =>
      _caches[operation] ??= _resolve(operation);

  List<Cache> _resolve(CacheOperation operation) {
    final resolver = _interceptor._resolverFor(operation);
    final caches = resolver
        .resolveCaches(_Context(operation, _invocation))
        .toList();
    if (caches.isEmpty) {
      throw StateError(
        'No cache could be resolved for ${operation.description} using '
        'resolver $resolver: at least one cache is needed per operation',
      );
    }
    return caches;
  }

  ValueWrapper? get(Cache cache, Object? key) {
    try {
      return cache.get(key);
    } on Object catch (error, stackTrace) {
      _interceptor.errorHandler.handleCacheGetError(
        error,
        stackTrace,
        cache,
        key,
      );
      return null; // handled: a miss
    }
  }

  void _put(Cache cache, Object? key, Object? value) {
    try {
      cache.put(key, value);
    } on Object catch (error, stackTrace) {
      _interceptor.errorHandler.handleCachePutError(
        error,
        stackTrace,
        cache,
        key,
        value,
      );
    }
  }

  void evict(CacheEvictOperation operation, [_Result? result]) {
    final caches = this.caches(operation);
    if (operation.cacheWide) {
      for (final cache in caches) {
        try {
          cache.clear();
        } on Object catch (error, stackTrace) {
          _interceptor.errorHandler.handleCacheClearError(
            error,
            stackTrace,
            cache,
          );
        }
      }
      return;
    }
    final key = this.key(operation, result);
    for (final cache in caches) {
      try {
        cache.evict(key);
      } on Object catch (error, stackTrace) {
        _interceptor.errorHandler.handleCacheEvictError(
          error,
          stackTrace,
          cache,
          key,
        );
      }
    }
  }

  // After the method returned [value] (or a hit was found): stores it for
  // the @Cacheable operations that missed and for @CachePut, then evicts.
  void afterInvocation(Object? value, Map<CacheableOperation, Object?> missed) {
    final result = _Result(value);
    for (final MapEntry(key: operation, value: key) in missed.entries) {
      if (!unless(operation, result)) {
        for (final cache in caches(operation)) {
          _put(cache, key, value);
        }
      }
    }
    for (final operation in _operations) {
      switch (operation) {
        case CachePutOperation()
            when condition(operation, result) && !unless(operation, result):
          final key = this.key(operation, result);
          for (final cache in caches(operation)) {
            _put(cache, key, value);
          }
        case CacheEvictOperation()
            when !operation.beforeInvocation && condition(operation, result):
          evict(operation, result);
        default:
          break;
      }
    }
  }

  Object? _evaluate(String text, CacheOperation operation, _Result? result) {
    final signature = _invocation.signature;
    final args = _invocation.args;
    final context =
        StandardEvaluationContext({
            'methodName': signature.name,
            'method': signature,
            'args': args,
            'target': _invocation.target,
            'targetClass': signature.targetType,
            'caches': operation.cacheNames,
          })
          ..addPropertyAccessor(const _MethodSignatureAccessor())
          ..addPropertyAccessor(
            IntrospectionPropertyAccessor(_interceptor.introspector),
          )
          ..addMethodResolver(
            IntrospectionMethodResolver(_interceptor.introspector),
          );
    if (_interceptor.beanFactory case final factory?) {
      context.beanResolver = BeanFactoryResolver(factory);
    }
    for (var i = 0; i < args.length; i++) {
      context
        ..setVariable('p$i', args[i])
        ..setVariable('a$i', args[i]);
      if (i < signature.parameterNames.length) {
        context.setVariable(signature.parameterNames[i], args[i]);
      }
    }
    if (result != null) {
      context.setVariable('result', result.value);
    }
    return _interceptor._expression(text).getValue(context);
  }
}

// `#root.method.name` and the other properties of the method, like
// Spring's `java.lang.reflect.Method` in the root object (read-only).
final class _MethodSignatureAccessor implements PropertyAccessor {
  const _MethodSignatureAccessor();

  static Object? _read(MethodSignature method, String name) => switch (name) {
    'name' => method.name,
    'declaringClass' || 'declaringType' => method.declaringType,
    'returnType' => method.returnType,
    'parameterTypes' => method.parameterTypes,
    'parameterNames' => method.parameterNames,
    'parameterCount' => method.parameterTypes.length,
    'annotations' => method.annotations,
    _ => _missing,
  };

  static final _missing = Object();

  @override
  bool canRead(EvaluationContext context, Object target, String name) =>
      target is MethodSignature && !identical(_read(target, name), _missing);

  @override
  Object? read(EvaluationContext context, Object target, String name) =>
      _read(target as MethodSignature, name);

  @override
  bool canWrite(EvaluationContext context, Object target, String name) => false;

  @override
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  ) => throw UnsupportedError('The method of a cache call is read-only');
}

// A method result (wrapped, so `null` results differ from "no result").
final class _Result {
  _Result(this.value);

  final Object? value;
}
