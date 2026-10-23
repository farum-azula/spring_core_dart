import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache.dart';
import 'package:spring_boot_starter_cache/src/cache_error_handler.dart';
import 'package:spring_boot_starter_cache/src/cache_operation.dart';
import 'package:spring_boot_starter_cache/src/cache_resolver.dart';
import 'package:spring_boot_starter_cache/src/caching_configurer.dart';
import 'package:spring_boot_starter_cache/src/key_generator.dart';

/// Matches the members carrying `@Cacheable`, `@CachePut`, `@CacheEvict`
/// or `@Caching`, like Spring's `CacheOperationSourcePointcut`.
///
/// ```dart
/// DefaultPointcutAdvisor(const CacheAnnotationPointcut(), interceptor);
/// ```
///
/// Spring (Java):
/// ```java
/// // Registered by @EnableCaching (BeanFactoryCacheOperationSourceAdvisor).
/// ```
final class CacheAnnotationPointcut implements AopPointcut {
  /// Creates the pointcut.
  const CacheAnnotationPointcut();

  /// Whether [annotation] is one of the cache annotations.
  static bool isCacheAnnotation(Object annotation) =>
      AnnotationCacheOperationSource.isCacheAnnotation(annotation);

  @override
  bool matches(MethodSignature signature, String beanName) =>
      signature.annotations.any(isCacheAnnotation);

  @override
  String toString() => 'CacheAnnotationPointcut';
}

/// Applies the cache annotations around a call, like Spring's
/// `CacheInterceptor`: evicts marked `beforeInvocation`, then looks the
/// `@Cacheable` key up and returns a hit without running the method;
/// otherwise runs it, stores the result (`@Cacheable` unless `unless`,
/// `@CachePut`) and evicts (`@CacheEvict`).
///
/// For methods returning a `Future` the resolved value is cached when the
/// future completes (errors are never cached) and a hit returns a
/// completed future. Errors of the cache itself go to the
/// [errorHandler] (by default rethrown to the caller).
///
/// The defaults — [cacheManager], [cacheResolver], [keyGenerator],
/// [errorHandler] — are the ones passed in, else those of the
/// `CachingConfigurer` bean of [beanFactory], else the `CacheManager`
/// bean, a [SimpleCacheResolver], [SimpleKeyGenerator] and
/// [SimpleCacheErrorHandler].
///
/// The starter registers it with a [CacheAnnotationPointcut] advisor (and
/// checks the annotations of every proxied bean at startup, see
/// [CacheOperationValidator]); build one yourself to use caching without
/// the auto-configuration:
///
/// ```dart
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
  /// An interceptor with the given defaults (see the class documentation).
  /// `cacheManager:`, `cacheResolver:` and `keyGenerator:` names in
  /// annotations are looked up in [beanFactory]; [introspector] gives SpEL
  /// access to properties of `@Introspected` arguments (`#book.isbn`).
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

  /// Where named cache managers, resolvers and key generators (and the
  /// `CachingConfigurer`) come from.
  final BeanFactory? beanFactory;

  /// Reads the annotations of the members.
  final AnnotationCacheOperationSource cacheOperationSource;

  /// Introspection metadata for SpEL property access.
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

  /// The default cache manager: the one passed in, else the
  /// `CachingConfigurer`'s, else the `CacheManager` bean.
  CacheManager get cacheManager {
    _configure();
    return _cacheManager ??= switch (beanFactory) {
      final factory? => factory.getBean<CacheManager>(),
      null => throw StateError(
        'CacheInterceptor has no cache manager: pass one or a bean factory',
      ),
    };
  }

  /// The default cache resolver: the one passed in, else the
  /// `CachingConfigurer`'s, else a [SimpleCacheResolver] of
  /// [cacheManager].
  CacheResolver get cacheResolver {
    _configure();
    return _cacheResolver ??= SimpleCacheResolver(cacheManager);
  }

  /// The default key generator: the one passed in, else the
  /// `CachingConfigurer`'s, else [SimpleKeyGenerator].
  KeyGenerator get keyGenerator {
    _configure();
    return _keyGenerator ??= const SimpleKeyGenerator();
  }

  /// What happens when a cache throws: the handler passed in, else the
  /// `CachingConfigurer`'s, else [SimpleCacheErrorHandler] (rethrows).
  CacheErrorHandler get errorHandler {
    _configure();
    return _errorHandler ??= const SimpleCacheErrorHandler();
  }

  /// The validated cache operations of the member [signature] (empty when
  /// it has none), computed once. Throws a `StateError` naming the member
  /// for invalid annotations (see [AnnotationCacheOperationSource]) and for
  /// an operation without cache names that no resolver can complete.
  ///
  /// [CacheOperationValidator] calls it for every proxied member when the
  /// bean is created, so wrong annotations fail the startup.
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
    final call = _Call(this, invocation, operations);
    final isAsync = invocation is AsyncMethodInvocation;

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
    final hasPut = operations.any((o) => o is CachePutOperation);
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
    if (isAsync && result is Future) {
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
              _inFlight.remove(key);
            },
            onError: (Object _) {
              _inFlight.remove(key);
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

/// Checks the cache annotations of every member of a proxied bean when
/// the bean is created (before its proxy is), so a wrong annotation fails
/// the startup instead of the first call — as Spring does when it builds
/// the proxy. Registered by the starter's auto-configuration.
///
/// ```dart
/// // In the auto-configuration:
/// CacheOperationValidator(interceptor)
/// ```
final class CacheOperationValidator extends BeanPostProcessor
    implements BeanFactoryAware {
  /// A validator using the rules of [interceptor].
  CacheOperationValidator(this.interceptor);

  /// Validates the operations ([CacheInterceptor.cacheOperations]).
  final CacheInterceptor interceptor;

  BeanFactory? _beanFactory;

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  // Before initialization, so it runs ahead of the auto proxy creator
  // (which proxies after initialization) whatever the order.
  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    final factory = _beanFactory;
    if (factory is! BeanDefinitionRegistry ||
        !(factory as BeanDefinitionRegistry).containsBeanDefinition(beanName)) {
      return bean;
    }
    final definition = (factory as BeanDefinitionRegistry).getBeanDefinition(
      beanName,
    );
    for (final signature
        in definition.aopProxy?.signatures ?? const <MethodSignature>[]) {
      if (signature.annotations.any(
        CacheAnnotationPointcut.isCacheAnnotation,
      )) {
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

  bool unless(CacheOperation operation, _Result result) {
    final unless = switch (operation) {
      CacheableOperation(:final unless) ||
      CachePutOperation(:final unless) => unless,
      CacheEvictOperation() => null,
    };
    return unless != null && _evaluate(unless, operation, result) == true;
  }

  Object? key(CacheOperation operation, [_Result? result]) {
    if (operation.key case final key?) {
      return _evaluate(key, operation, result);
    }
    return _interceptor
        ._keyGeneratorFor(operation)
        .generate(_invocation.target, _invocation.signature, _invocation.args);
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
    } catch (error, stackTrace) {
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
    } catch (error, stackTrace) {
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
        } catch (error, stackTrace) {
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
      } catch (error, stackTrace) {
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

// A method result (wrapped, so `null` results differ from "no result").
final class _Result {
  _Result(this.value);

  final Object? value;
}
