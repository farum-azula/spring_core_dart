import 'dart:async';

import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/aop_context.dart';
import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';

/// Implemented by AOP proxies, like Spring's `Advised`.
///
/// ```dart
/// final calculator = context.getBean<Calculator>();
/// if (calculator is Advised) {
///   print(calculator.aopTarget); // the SimpleCalculator
///   print(calculator.aopAdvisors);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// Calculator calculator = context.getBean(Calculator.class);
/// if (calculator instanceof Advised advised) {
///   System.out.println(advised.getTargetSource().getTarget());
///   System.out.println(Arrays.toString(advised.getAdvisors()));
/// }
/// ```
///
/// A generated subclass proxy (for a class that cannot be implemented) is
/// the bean itself: its [aopTarget] is the proxy.
abstract interface class Advised {
  /// The proxied bean.
  Object get aopTarget;

  /// Advisors that apply to the proxy.
  List<PointcutAdvisor> get aopAdvisors;
}

/// Unwraps AOP proxies, like Spring's `AopUtils` / `AopProxyUtils`.
///
/// ```dart
/// final calculator = context.getBean<Calculator>();
/// AopUtils.isAopProxy(calculator); // true
/// AopUtils.getTarget(calculator); // the SimpleCalculator
/// ```
///
/// Spring (Java):
/// ```java
/// Calculator calculator = context.getBean(Calculator.class);
/// AopUtils.isAopProxy(calculator);
/// AopProxyUtils.getSingletonTarget(calculator);
/// ```
abstract final class AopUtils {
  /// Whether [object] is an AOP proxy: a wrapper around a target, or a
  /// subclass proxy with advice attached.
  static bool isAopProxy(Object? object) =>
      object is Advised &&
      (!identical(object.aopTarget, object) || object.aopAdvisors.isNotEmpty);

  /// The innermost target of [object] (itself when not proxied, and for a
  /// subclass proxy, which is its own target).
  static Object getTarget(Object object) {
    var current = object;
    while (current is Advised) {
      final target = current.aopTarget;
      if (identical(target, current)) {
        break;
      }
      current = target;
    }
    return current;
  }
}

/// Creates the generated proxy for a bean class.
///
/// Generated code attaches one to the bean definition (`aopProxy`); the
/// proxy class implements the bean's interfaces and forwards every
/// member through a [ProxyInvoker]. Unlike Spring's JDK/CGLIB proxies it
/// is written at build time, so no reflection is needed at runtime.
///
/// ```dart
/// final factory = AopProxyFactory(
///   signatures: CalculatorProxy.signatures,
///   create: (target, invoker) =>
///       CalculatorProxy(target as SimpleCalculator, invoker),
/// );
/// final Calculator proxy = factory.createProxy(
///   SimpleCalculator(),
///   [DefaultPointcutAdvisor(const TruePointcut(), LoggingInterceptor())],
/// ) as Calculator;
/// ```
///
/// Spring (Java):
/// ```java
/// ProxyFactory factory = new ProxyFactory(new SimpleCalculator());
/// factory.addAdvisor(
///     new DefaultPointcutAdvisor(Pointcut.TRUE, new LoggingInterceptor()));
/// Calculator proxy = (Calculator) factory.getProxy();
/// ```
final class AopProxyFactory {
  /// Creates a factory for proxies of members [signatures]; `create`
  /// instantiates the generated proxy class.
  AopProxyFactory({
    required List<MethodSignature> signatures,
    required Object Function(Object target, ProxyInvoker invoker) this._create,
  }) : signatures = List.unmodifiable(signatures),
       _advise = null,
       unavailableReason = null;

  /// The members of a bean that cannot be proxied, and why: advice that
  /// matches one of [signatures] makes the bean fail to start with
  /// [reason] instead of being silently skipped (Spring fails the same way
  /// when it cannot create a proxy).
  AopProxyFactory.unavailable({
    required List<MethodSignature> signatures,
    required String reason,
  }) : signatures = List.unmodifiable(signatures),
       _create = null,
       _advise = null,
       unavailableReason = reason;

  /// For a bean whose class cannot be implemented but can be extended: the
  /// container already created an instance of the generated subclass,
  /// whose members call `super` through the advice chain once `advise`
  /// attached the invoker (like a CGLIB proxy). `advise` returns the
  /// advised bean, or `null` when the bean is not the generated subclass
  /// (another post-processor replaced it).
  ///
  /// ```dart
  /// AopProxyFactory.subclass(
  ///   signatures: const [MethodSignature(name: 'add', ...)],
  ///   advise: (bean, invoker) =>
  ///       bean is _$CalculatorProxy ? bean._$advise(invoker) : null,
  /// );
  /// ```
  AopProxyFactory.subclass({
    required List<MethodSignature> signatures,
    required Object? Function(Object bean, ProxyInvoker invoker) this._advise,
  }) : signatures = List.unmodifiable(signatures),
       _create = null,
       unavailableReason = null;

  /// Proxied members, indexed like the generated proxy calls them.
  final List<MethodSignature> signatures;
  final Object Function(Object target, ProxyInvoker invoker)? _create;
  final Object? Function(Object bean, ProxyInvoker invoker)? _advise;

  /// Why no proxy can be generated for the bean; `null` when it can.
  final String? unavailableReason;

  /// Whether the bean is an instance of a generated subclass that advice
  /// is attached to (instead of being wrapped).
  bool get isSubclass => _advise != null;

  /// Advisors among [advisors] that match at least one member of the bean
  /// named [beanName] ([beanAliases]: its aliases and qualifier values,
  /// for `bean(...)` pointcuts).
  List<PointcutAdvisor> eligibleAdvisors(
    List<PointcutAdvisor> advisors,
    String beanName, {
    List<String> beanAliases = const [],
  }) => [
    for (final advisor in advisors)
      if (signatures.any(
        (s) => _pointcutMatches(advisor.pointcut, s, beanName, beanAliases),
      ))
        advisor,
  ];

  /// A proxy of [target] applying [advisors] (in order).
  Object createProxy(
    Object target,
    List<PointcutAdvisor> advisors, {
    String beanName = '',
    List<String> beanAliases = const [],
  }) {
    final invoker = ProxyInvoker(
      signatures,
      advisors,
      beanName,
      beanAliases: beanAliases,
    );
    if (_advise case final advise?) {
      return advise(target, invoker) ??
          (throw AopConfigException(
            "Bean '$beanName' was replaced by a ${target.runtimeType} before "
            'the auto proxy creator ran, so advice cannot be attached to its '
            'generated subclass. Return the bean itself from '
            'postProcessBeforeInitialization / '
            'postProcessAfterInitialization of the other post-processors.',
          ));
    }
    final create = _create;
    if (create == null) {
      throw AopConfigException(
        "Advice matches bean '$beanName', but it cannot be proxied: "
        '$unavailableReason',
      );
    }
    return create(target, invoker);
  }
}

// Whether [pointcut] matches [signature] of the bean named [beanName]
// (with its aliases and qualifier values for an [ExpressionPointcut]).
bool _pointcutMatches(
  AopPointcut pointcut,
  MethodSignature signature,
  String beanName,
  List<String> beanAliases,
) => pointcut is ExpressionPointcut
    ? pointcut.matchesBean(signature, beanName, beanAliases)
    : pointcut.matches(signature, beanName);

/// A proxy could not be created, like Spring's `AopConfigException`.
class AopConfigException implements Exception {
  /// Creates the exception.
  const AopConfigException(this.message);

  /// What went wrong and how to fix it.
  final String message;

  @override
  String toString() => 'AopConfigException: $message';
}

/// An advised call failed because of a misconfiguration, like Spring's
/// `AopInvocationException` (e.g. an `async` `@Before` advice on a
/// synchronous method, which the call cannot wait for).
class AopInvocationException implements Exception {
  /// Creates the exception.
  const AopInvocationException(this.message);

  /// What went wrong and how to fix it.
  final String message;

  @override
  String toString() => 'AopInvocationException: $message';
}

/// Runs calls of a generated proxy through the matching advice.
///
/// Each proxied member forwards to [invoke] (or [invokeAsync] for
/// `Future`-returning members, [invokeFutureOr] for `FutureOr` ones) with
/// its index in [signatures] and a closure calling the target.
///
/// ```dart
/// class CalculatorProxy implements Calculator, Advised {
///   CalculatorProxy(this._target, this._invoker);
///
///   final SimpleCalculator _target;
///   final ProxyInvoker _invoker;
///
///   @override
///   Object get aopTarget => _target;
///
///   @override
///   List<PointcutAdvisor> get aopAdvisors => _invoker.advisors;
///
///   @override
///   int add(int a, int b) => _invoker.invoke(this, _target, 0, [a, b],
///       (args) => _target.add(args[0]! as int, args[1]! as int))! as int;
///
///   @override
///   Future<int> slowAdd(int a, int b) => _invoker.invokeAsync<int>(
///       this, _target, 1, [a, b],
///       (args) => _target.slowAdd(args[0]! as int, args[1]! as int));
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// // The runtime equivalent is JdkDynamicAopProxy.invoke(), which builds
/// // a ReflectiveMethodInvocation over the advisor chain:
/// List<Object> chain = advised
///     .getInterceptorsAndDynamicInterceptionAdvice(method, targetClass);
/// new ReflectiveMethodInvocation(proxy, target, method, args,
///     targetClass, chain).proceed();
/// ```
final class ProxyInvoker {
  /// Creates an invoker applying [advisors] (in order) to the members
  /// [signatures] of the bean named [beanName]; [beanAliases] (aliases and
  /// qualifier values) also count for `bean(...)` pointcuts.
  ProxyInvoker(
    this.signatures,
    List<PointcutAdvisor> advisors,
    this.beanName, {
    List<String> beanAliases = const [],
  }) : advisors = List.unmodifiable(advisors),
       beanAliases = List.unmodifiable(beanAliases);

  /// Proxied members, by index.
  final List<MethodSignature> signatures;

  /// Advisors that apply to the proxy, outermost first.
  final List<PointcutAdvisor> advisors;

  /// Name of the proxied bean, for `bean(...)` pointcuts.
  final String beanName;

  /// Aliases and qualifier values of the proxied bean, for `bean(...)`.
  final List<String> beanAliases;

  // Interceptor chains per member index, computed on first call.
  final _chains = <int, List<MethodInterceptor>>{};

  /// Interceptors for member [index], in invocation order. Advice whose
  /// pointcut depends on the call (bindings, `args(...)`) is decided per
  /// call.
  List<MethodInterceptor> chainFor(int index) => _chains.putIfAbsent(index, () {
    final signature = signatures[index];
    return [
      for (final advisor in advisors)
        if (_pointcutMatches(
          advisor.pointcut,
          signature,
          beanName,
          beanAliases,
        ))
          switch (advisor.pointcut) {
            final ExpressionPointcut pointcut when pointcut.isRuntime =>
              _DynamicInterceptor(pointcut, advisor.advice, this),
            _ => advisor.advice,
          },
    ];
  });

  /// Invokes member [index] synchronously.
  ///
  /// [call] invokes the target with the (possibly replaced) arguments; it
  /// is called directly when no advice matches.
  Object? invoke(
    Object proxy,
    Object target,
    int index,
    List<Object?> arguments,
    Object? Function(List<Object?> arguments) call,
  ) => runWithCurrentProxy(proxy, () {
    final chain = chainFor(index);
    if (chain.isEmpty) {
      return call(arguments);
    }
    return _Invocation(
      proxy,
      target,
      signatures[index],
      [...arguments],
      chain,
      0,
      call,
    ).proceed();
  });

  /// Invokes member [index] that returns `Future<T>`.
  ///
  /// After-style advice runs when the future completes; the result is
  /// retyped to `Future<T>` because `@Around` advice may return an
  /// untyped future.
  Future<T> invokeAsync<T>(
    Object proxy,
    Object target,
    int index,
    List<Object?> arguments,
    Future<T> Function(List<Object?> arguments) call,
  ) => runAsyncWithCurrentProxy(proxy, () {
    final chain = chainFor(index);
    if (chain.isEmpty) {
      return call(arguments);
    }
    return retypeFuture<T>(
      _AsyncInvocation<T>(
        proxy,
        target,
        signatures[index],
        [...arguments],
        chain,
        0,
        call,
      ).proceed(),
    );
  });

  /// Invokes member [index] that returns `FutureOr<T>`.
  ///
  /// When the result is a `Future`, after-style advice runs when it
  /// completes (and the result is retyped to `Future<T>`); otherwise
  /// synchronously.
  FutureOr<T> invokeFutureOr<T>(
    Object proxy,
    Object target,
    int index,
    List<Object?> arguments,
    FutureOr<T> Function(List<Object?> arguments) call,
  ) => runAsyncWithCurrentProxy(proxy, () {
    final chain = chainFor(index);
    if (chain.isEmpty) {
      return call(arguments);
    }
    final result = _FutureOrInvocation<T>(
      proxy,
      target,
      signatures[index],
      [...arguments],
      chain,
      0,
      call,
    ).proceed();
    return result is Future ? retypeFuture<T>(result) : result as T;
  });
}

// Advice whose pointcut must be evaluated per call: skipped when the call
// does not match, otherwise run with the values the pointcut bound.
final class _DynamicInterceptor implements MethodInterceptor {
  _DynamicInterceptor(this.pointcut, this.advice, this.invoker);

  final ExpressionPointcut pointcut;
  final MethodInterceptor advice;
  final ProxyInvoker invoker;

  @override
  Object? invoke(MethodInvocation invocation) {
    final bindings = pointcut.bind(
      invocation,
      beanName: invoker.beanName,
      beanAliases: invoker.beanAliases,
    );
    if (bindings == null) {
      return invocation.proceed();
    }
    final advice = this.advice;
    return advice is AspectAdviceInterceptor
        ? advice.invoke(invocation, bindings)
        : advice.invoke(invocation);
  }
}

// One step of the interceptor chain: proceeding runs interceptor
// [_index] with a fresh invocation for the next step (so arguments passed
// to `proceed` flow on), and the target call after the last interceptor.
class _Invocation implements MethodInvocation {
  _Invocation(
    this.proxy,
    this.target,
    this.signature,
    this.args,
    this._chain,
    this._index,
    this._call,
  );

  @override
  final Object proxy;

  @override
  final Object target;

  @override
  final MethodSignature signature;

  @override
  final List<Object?> args;

  final List<MethodInterceptor> _chain;
  final int _index;
  final Object? Function(List<Object?> arguments) _call;

  _Invocation _next(List<Object?> arguments) => _Invocation(
    proxy,
    target,
    signature,
    arguments,
    _chain,
    _index + 1,
    _call,
  );

  @override
  Object? proceed([List<Object?>? arguments]) {
    // Like Spring's MethodInvocationProceedingJoinPoint.proceed(Object[]).
    if (arguments != null && arguments.length != args.length) {
      throw ArgumentError(
        'Expecting ${args.length} arguments to proceed, but was passed '
        '${arguments.length} arguments',
      );
    }
    final effective = arguments ?? args;
    if (_index < _chain.length) {
      return _chain[_index].invoke(_next(effective));
    }
    return _call(effective);
  }

  @override
  String toShortString() => 'execution(${signature.toShortString()})';

  @override
  String toString() => 'execution($signature)';
}

// A chain step for `Future<T>` members. Every step retypes the result of
// the next one to `Future<T>`, so interceptors and `chain` always see a
// properly typed future even when `@Around` advice returned another one.
final class _AsyncInvocation<T> extends _Invocation
    implements AsyncMethodInvocation {
  _AsyncInvocation(
    super.proxy,
    super.target,
    super.signature,
    super.args,
    super._chain,
    super._index,
    Future<T> Function(List<Object?> arguments) super._call,
  );

  @override
  _Invocation _next(List<Object?> arguments) => _AsyncInvocation<T>(
    proxy,
    target,
    signature,
    arguments,
    _chain,
    _index + 1,
    (args) => retypeFuture<T>(_call(args)),
  );

  @override
  Future<Object?> chain(
    Future<Object?> future, {
    FutureOr<void> Function(Object? value)? onValue,
    FutureOr<void> Function(Object error)? onError,
    FutureOr<void> Function()? always,
  }) => _chainFuture<T>(future, onValue, onError, always);
}

// A chain step for `FutureOr<T>` members: results stay as they are (a
// value or a future); `chain` handles the future ones.
final class _FutureOrInvocation<T> extends _Invocation
    implements AsyncMethodInvocation {
  _FutureOrInvocation(
    super.proxy,
    super.target,
    super.signature,
    super.args,
    super._chain,
    super._index,
    super._call,
  );

  @override
  _Invocation _next(List<Object?> arguments) => _FutureOrInvocation<T>(
    proxy,
    target,
    signature,
    arguments,
    _chain,
    _index + 1,
    _call,
  );

  @override
  Future<Object?> chain(
    Future<Object?> future, {
    FutureOr<void> Function(Object? value)? onValue,
    FutureOr<void> Function(Object error)? onError,
    FutureOr<void> Function()? always,
  }) => _chainFuture<T>(future, onValue, onError, always);
}

// Completes like [future] after the callbacks (waiting for those that
// return a Future); errors are rethrown with their original stack trace.
Future<T> _chainFuture<T>(
  Future<Object?> future,
  FutureOr<void> Function(Object? value)? onValue,
  FutureOr<void> Function(Object error)? onError,
  FutureOr<void> Function()? always,
) => retypeFuture<T>(future).then<T>(
  (value) =>
      _after(onValue?.call(value), () => _after(always?.call(), () => value)),
  onError: (Object error, StackTrace stackTrace) => _after(
    onError?.call(error),
    () => _after(
      always?.call(),
      () => Error.throwWithStackTrace(error, stackTrace),
    ),
  ),
);

// [next] right away, or after [pending] when it is a Future.
FutureOr<R> _after<R>(FutureOr<void> pending, FutureOr<R> Function() next) =>
    pending is Future ? pending.then((_) => next()) : next();
