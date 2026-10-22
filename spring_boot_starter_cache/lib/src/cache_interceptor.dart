import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/annotations.dart';
import 'package:spring_boot_starter_cache/src/cache.dart';
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
      annotation is Cacheable ||
      annotation is CachePut ||
      annotation is CacheEvict ||
      annotation is Caching;

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
/// completed future. Errors of the cache itself propagate to the caller.
///
/// The starter registers it with a [CacheAnnotationPointcut] advisor;
/// build one yourself to use caching without the auto-configuration:
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
  /// An interceptor using [cacheManager] (or the `CacheManager` bean of
  /// [beanFactory]) and [keyGenerator] by default. `cacheManager:` and
  /// `keyGenerator:` names in annotations are looked up in [beanFactory];
  /// [introspector] gives SpEL access to properties of `@Introspected`
  /// arguments (`#book.isbn`).
  CacheInterceptor({
    this._cacheManager,
    this.keyGenerator = const SimpleKeyGenerator(),
    this.beanFactory,
    BeanIntrospector? introspector,
    ExpressionParser? parser,
  }) : introspector = introspector ?? BeanIntrospector.shared,
       _parser = parser ?? SpelExpressionParser();

  /// The default key generator.
  final KeyGenerator keyGenerator;

  /// Where named cache managers and key generators come from.
  final BeanFactory? beanFactory;

  /// Introspection metadata for SpEL property access.
  final BeanIntrospector introspector;

  final ExpressionParser _parser;
  CacheManager? _cacheManager;
  final _expressions = <String, Expression>{};
  final _operations = Map<MethodSignature, List<_Operation>>.identity();
  final _inFlight = <(String, Object?), Future<Object?>>{};

  /// The default cache manager: the one passed in, else the
  /// `CacheManager` bean.
  CacheManager get cacheManager => _cacheManager ??= switch (beanFactory) {
    final factory? => factory.getBean<CacheManager>(),
    null => throw StateError(
      'CacheInterceptor has no cache manager: pass one or a bean factory',
    ),
  };

  @override
  Object? invoke(MethodInvocation invocation) {
    final operations = _operationsOf(invocation.signature);
    if (operations.isEmpty) {
      return invocation.proceed();
    }
    final call = _Call(this, invocation);
    final isAsync = invocation is AsyncMethodInvocation;

    for (final operation in operations) {
      if (operation.kind == _Kind.evict &&
          operation.beforeInvocation &&
          call.condition(operation)) {
        call.evict(operation);
      }
    }

    final cacheables = [
      for (final operation in operations)
        if (operation.kind == _Kind.cacheable && call.condition(operation))
          operation,
    ];
    final keys = {
      for (final operation in cacheables) operation: call.key(operation),
    };
    ValueWrapper? hit;
    search:
    for (final operation in cacheables) {
      for (final cache in call.caches(operation)) {
        hit = cache.get(keys[operation]);
        if (hit != null) {
          break search;
        }
      }
    }
    final hasPut = operations.any((o) => o.kind == _Kind.put);
    if (hit != null && !hasPut) {
      call.afterInvocation(hit.value, const {});
      return isAsync ? Future<Object?>.value(hit.value) : hit.value;
    }

    final missed = hit == null ? keys : const <_Operation, Object?>{};
    (String, Object?)? inFlightKey;
    final single = cacheables.singleOrNull;
    if (isAsync && hit == null && single != null && single.sync) {
      inFlightKey = (single.names.single, keys[single]);
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

  List<_Operation> _operationsOf(MethodSignature signature) =>
      _operations[signature] ??= _parse(signature);

  // The operations of every cache annotation on the member, with the
  // defaults of the class's @CacheConfig, validated like Spring does.
  static List<_Operation> _parse(MethodSignature signature) {
    final config = signature.targetAnnotations.whereType<CacheConfig>();
    final defaults = config.isEmpty ? const CacheConfig() : config.first;
    final member = '${signature.declaringType}.${signature.name}';
    final operations = <_Operation>[];

    void add(
      _Kind kind,
      String? value,
      List<String> cacheNames, {
      String? key,
      String? condition,
      String? unless,
      bool sync = false,
      String? keyGenerator,
      String? cacheManager,
      bool allEntries = false,
      bool beforeInvocation = false,
    }) {
      final description = '@${kind.annotation} on $member';
      var names = [?value, ...cacheNames];
      if (names.isEmpty) {
        names = defaults.cacheNames;
      }
      if (names.isEmpty) {
        throw StateError(
          'No cache names for $description: name them in the annotation '
          "(@${kind.annotation}('books')) or in @CacheConfig on the class",
        );
      }
      final generator = keyGenerator ?? defaults.keyGenerator;
      if (key != null && generator != null) {
        throw StateError(
          'Both key and keyGenerator are set for $description; use one',
        );
      }
      operations.add(
        _Operation(
          kind: kind,
          description: description,
          names: List.unmodifiable(names),
          key: key,
          condition: condition,
          unless: unless,
          sync: sync,
          keyGenerator: generator,
          cacheManager: cacheManager ?? defaults.cacheManager,
          allEntries: allEntries,
          beforeInvocation: beforeInvocation,
        ),
      );
    }

    void cacheable(Cacheable a) => add(
      _Kind.cacheable,
      a.value,
      a.cacheNames,
      key: a.key,
      condition: a.condition,
      unless: a.unless,
      sync: a.sync,
      keyGenerator: a.keyGenerator,
      cacheManager: a.cacheManager,
    );
    void put(CachePut a) => add(
      _Kind.put,
      a.value,
      a.cacheNames,
      key: a.key,
      condition: a.condition,
      unless: a.unless,
      keyGenerator: a.keyGenerator,
      cacheManager: a.cacheManager,
    );
    void evict(CacheEvict a) => add(
      _Kind.evict,
      a.value,
      a.cacheNames,
      key: a.key,
      condition: a.condition,
      keyGenerator: a.keyGenerator,
      cacheManager: a.cacheManager,
      allEntries: a.allEntries,
      beforeInvocation: a.beforeInvocation,
    );

    for (final annotation in signature.annotations) {
      switch (annotation) {
        case final Cacheable a:
          cacheable(a);
        case final CachePut a:
          put(a);
        case final CacheEvict a:
          evict(a);
        case final Caching a:
          a.cacheable.forEach(cacheable);
          a.put.forEach(put);
          a.evict.forEach(evict);
      }
    }

    for (final operation in operations.where((o) => o.sync)) {
      if (operations.length > 1) {
        throw StateError(
          '${operation.description} with sync: true cannot be combined with '
          'other cache operations',
        );
      }
      if (operation.names.length > 1) {
        throw StateError(
          '${operation.description} with sync: true allows a single cache',
        );
      }
      if (operation.unless != null) {
        throw StateError(
          '${operation.description}: sync: true does not support unless',
        );
      }
    }
    return List.unmodifiable(operations);
  }
}

enum _Kind {
  cacheable('Cacheable'),
  put('CachePut'),
  evict('CacheEvict');

  const _Kind(this.annotation);

  final String annotation;
}

final class _Operation {
  _Operation({
    required this.kind,
    required this.description,
    required this.names,
    required this.key,
    required this.condition,
    required this.unless,
    required this.sync,
    required this.keyGenerator,
    required this.cacheManager,
    required this.allEntries,
    required this.beforeInvocation,
  });

  final _Kind kind;
  final String description;
  final List<String> names;
  final String? key;
  final String? condition;
  final String? unless;
  final bool sync;
  final String? keyGenerator;
  final String? cacheManager;
  final bool allEntries;
  final bool beforeInvocation;
}

// One intercepted call: evaluates the SpEL of its operations and resolves
// their caches.
final class _Call {
  _Call(this._interceptor, this._invocation);

  final CacheInterceptor _interceptor;
  final MethodInvocation _invocation;

  bool condition(_Operation operation, [_Result? result]) =>
      operation.condition == null ||
      _evaluate(operation.condition!, operation, result) == true;

  bool unless(_Operation operation, _Result result) =>
      operation.unless != null &&
      _evaluate(operation.unless!, operation, result) == true;

  Object? key(_Operation operation, [_Result? result]) {
    if (operation.key case final key?) {
      return _evaluate(key, operation, result);
    }
    final generator = switch (operation.keyGenerator) {
      final name? => _bean<KeyGenerator>(name, 'KeyGenerator'),
      null => _interceptor.keyGenerator,
    };
    return generator.generate(
      _invocation.target,
      _invocation.signature,
      _invocation.args,
    );
  }

  List<Cache> caches(_Operation operation) {
    final manager = switch (operation.cacheManager) {
      final name? => _bean<CacheManager>(name, 'CacheManager'),
      null => _interceptor.cacheManager,
    };
    return [
      for (final name in operation.names)
        manager.getCache(name) ??
            (throw StateError(
              "Cannot find cache named '$name' for ${operation.description}",
            )),
    ];
  }

  void evict(_Operation operation, [_Result? result]) {
    final caches = this.caches(operation);
    if (operation.allEntries) {
      for (final cache in caches) {
        cache.clear();
      }
      return;
    }
    final key = this.key(operation, result);
    for (final cache in caches) {
      cache.evict(key);
    }
  }

  // After the method returned [value] (or a hit was found): stores it for
  // the @Cacheable operations that missed and for @CachePut, then evicts.
  void afterInvocation(Object? value, Map<_Operation, Object?> missed) {
    final result = _Result(value);
    for (final MapEntry(key: operation, value: key) in missed.entries) {
      if (!unless(operation, result)) {
        for (final cache in caches(operation)) {
          cache.put(key, value);
        }
      }
    }
    for (final operation in _interceptor._operationsOf(_invocation.signature)) {
      switch (operation.kind) {
        case _Kind.put
            when condition(operation, result) && !unless(operation, result):
          final key = this.key(operation, result);
          for (final cache in caches(operation)) {
            cache.put(key, value);
          }
        case _Kind.evict
            when !operation.beforeInvocation && condition(operation, result):
          evict(operation, result);
        default:
          break;
      }
    }
  }

  T _bean<T extends Object>(String name, String kind) {
    final factory = _interceptor.beanFactory;
    if (factory == null) {
      throw StateError("No bean factory to look up the $kind bean '$name'");
    }
    final bean = factory.getBeanByName(name);
    if (bean is! T) {
      throw StateError("Bean '$name' is not a $kind");
    }
    return bean;
  }

  Object? _evaluate(String text, _Operation operation, _Result? result) {
    final signature = _invocation.signature;
    final args = _invocation.args;
    final context =
        StandardEvaluationContext({
            'methodName': signature.name,
            'method': signature,
            'args': args,
            'target': _invocation.target,
            'targetClass': signature.targetType,
            'caches': operation.names,
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
