import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';

/// Implemented by AOP proxies, like Spring's `Advised`.
///
/// ```dart
/// final calculator = context.getBean<Calculator>();
/// if (calculator is Advised) {
///   print(calculator.targetObject); // the SimpleCalculator
///   print(calculator.advisors);
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
abstract interface class Advised {
  /// The proxied bean.
  Object get targetObject;

  /// Advisors that apply to the proxy.
  List<PointcutAdvisor> get advisors;
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
  /// Whether [object] is an AOP proxy.
  static bool isAopProxy(Object? object) => object is Advised;

  /// The innermost target of [object] (itself when not proxied).
  static Object getTarget(Object object) {
    var current = object;
    while (current is Advised) {
      current = current.targetObject;
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
    required this._create,
  }) : signatures = List.unmodifiable(signatures);

  /// Proxied members, indexed like the generated proxy calls them.
  final List<MethodSignature> signatures;
  final Object Function(Object target, ProxyInvoker invoker) _create;

  /// Advisors among [advisors] that match at least one member.
  List<PointcutAdvisor> eligibleAdvisors(
    List<PointcutAdvisor> advisors,
    String beanName,
  ) => [
    for (final advisor in advisors)
      if (signatures.any((s) => advisor.pointcut.matches(s, beanName))) advisor,
  ];

  /// A proxy of [target] applying [advisors] (in order).
  Object createProxy(
    Object target,
    List<PointcutAdvisor> advisors, {
    String beanName = '',
  }) => _create(target, ProxyInvoker(signatures, advisors, beanName));
}

/// Runs calls of a generated proxy through the matching advice.
///
/// Each proxied member forwards to [invoke] (or [invokeAsync] for
/// `Future`-returning members) with its index in [signatures] and a
/// closure calling the target.
///
/// ```dart
/// class CalculatorProxy implements Calculator, Advised {
///   CalculatorProxy(this._target, this._invoker);
///
///   final SimpleCalculator _target;
///   final ProxyInvoker _invoker;
///
///   @override
///   Object get targetObject => _target;
///
///   @override
///   List<PointcutAdvisor> get advisors => _invoker.advisors;
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
  /// [signatures] of the bean named [beanName].
  ProxyInvoker(this.signatures, List<PointcutAdvisor> advisors, this.beanName)
    : advisors = List.unmodifiable(advisors);

  /// Proxied members, by index.
  final List<MethodSignature> signatures;

  /// Advisors that apply to the proxy, outermost first.
  final List<PointcutAdvisor> advisors;

  /// Name of the proxied bean, for `bean(...)` pointcuts.
  final String beanName;

  // Interceptor chains per member index, computed on first call.
  final _chains = <int, List<MethodInterceptor>>{};

  /// Interceptors for member [index], in invocation order.
  List<MethodInterceptor> chainFor(int index) => _chains.putIfAbsent(
    index,
    () => [
      for (final advisor in advisors)
        if (advisor.pointcut.matches(signatures[index], beanName))
          advisor.advice,
    ],
  );

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
  ) {
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
  }

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
  ) {
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
    void Function(Object? value)? onValue,
    void Function(Object error)? onError,
    void Function()? always,
  }) => retypeFuture<T>(future).then<T>(
    (value) {
      onValue?.call(value);
      always?.call();
      return value;
    },
    // Run the callbacks, then rethrow keeping the original stack trace.
    onError: (Object error, StackTrace stackTrace) {
      onError?.call(error);
      always?.call();
      Error.throwWithStackTrace(error, stackTrace);
    },
  );
}
