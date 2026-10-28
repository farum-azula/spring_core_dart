import 'dart:async';
import 'dart:collection';

import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/aop_context.dart';
import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';

/// The interface every generated AOP proxy implements: it exposes the
/// bean behind the proxy and the advice applied to it.
///
/// A bean that some advice matches is replaced by its proxy, so the object
/// `getBean` returns or another bean receives may be an `Advised`. Check
/// for it to find out which advisors apply (in a test or a diagnostic
/// page), to reach the real object, or to change the advice of a live
/// proxy. Most applications never touch it; [AopUtils] covers the common
/// "is this a proxy, what is behind it" questions.
///
/// ```dart
/// // In a test: is the Calculator advised, and by what?
/// final calculator = context.getBean<Calculator>();
/// if (calculator is Advised) {
///   log.info(calculator.aopTarget); // the SimpleCalculator
///   log.info(calculator.aopAdvisors);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// Calculator calculator = context.getBean(Calculator.class);
/// if (calculator instanceof Advised advised) {
///   log.info("{}", advised.getTargetSource().getTarget());
///   log.info(Arrays.toString(advised.getAdvisors()));
/// }
/// ```
///
/// A generated subclass proxy (for a class that cannot be implemented) is
/// the bean itself: its [aopTarget] is the proxy. Such a bean implements
/// `Advised` even when no advice matched it; then it has no advisors, and
/// the methods that change them throw an [AopConfigException].
///
/// Advisors can be added and removed at runtime, like Spring's
/// `Advised.addAdvisor` / `removeAdvisor`: the next call of an affected
/// member uses the new chain.
///
/// ```dart
/// // Turn on call logging for a live bean, for example while debugging.
/// (calculator as Advised).addAdvice(LoggingInterceptor());
/// ```
///
/// Spring (Java):
/// ```java
/// ((Advised) calculator).addAdvice(new LoggingInterceptor());
/// ```
abstract interface class Advised {
  /// The bean behind the proxy; the proxy itself for a generated
  /// subclass proxy.
  Object get aopTarget;

  /// The advisors that apply to this proxy, outermost first; empty for a
  /// subclass proxy no advice matched.
  List<PointcutAdvisor> get aopAdvisors;

  /// Appends [advisor] as the innermost one; the next calls of the members
  /// its pointcut matches run it.
  void addAdvisor(PointcutAdvisor advisor);

  /// Removes [advisor]; returns `false` when it was not there.
  bool removeAdvisor(PointcutAdvisor advisor);

  /// Appends [advice] as the innermost advice of every member, wrapped in
  /// a `DefaultPointcutAdvisor` with a `TruePointcut` (as Spring's
  /// `addAdvice` does).
  void addAdvice(MethodInterceptor advice);

  /// Removes the first advisor whose advice is [advice] (the same object);
  /// returns `false` when there is none.
  bool removeAdvice(MethodInterceptor advice);
}

/// An extra interface that a `@DeclareParents` field adds to the proxies of
/// matching beans, with the way to create its implementation.
///
/// The generator writes one into the proxy factory of each bean that a
/// `@DeclareParents` pattern matches. The generated proxy class implements
/// [interfaceName] and forwards its members to the object [create]
/// returns, one per proxy, created on first use. Applications never write
/// it; they declare the `@DeclareParents` field.
///
/// ```dart
/// // Generated for: @DeclareParents('*Service+',
/// //   defaultImpl: DefaultUsageTracked) static UsageTracked? mixin;
/// Introduction(
///   interfaceName: 'UsageTracked',
///   aspectType: 'UsageTracking',
///   create: DefaultUsageTracked.new,
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// @DeclareParents(value = "com.x.service.*+",
///     defaultImpl = DefaultUsageTracked.class)
/// public static UsageTracked mixin;
/// ```
final class Introduction {
  /// Describes the interface [interfaceName] introduced by the aspect
  /// named [aspectType]; `create` makes a new implementation.
  Introduction({
    required this.interfaceName,
    required this.aspectType,
    required this._create,
  });

  /// The simple name of the introduced interface; `this(Name)` pointcuts
  /// match it.
  final String interfaceName;

  /// The aspect declaring it (its `AspectMetadata.typeName`). The bean is
  /// proxied for the introduction only while that aspect is registered in
  /// the context, so a condition or profile can turn it off.
  final String aspectType;

  final Object Function() _create;

  /// Creates a new object implementing the interface; the proxy calls it
  /// once, on first use.
  Object create() => _create();

  @override
  String toString() => 'Introduction($interfaceName by $aspectType)';
}

/// Helpers that tell whether an object is an AOP proxy and find the bean
/// behind it.
///
/// Code that needs the real object rather than its proxy uses them: a
/// test that checks advice was applied, code that compares a bean's
/// runtime class, or a library that inspects beans. Proxying is invisible
/// to most application code, which never needs this.
///
/// ```dart
/// // In a test: the Calculator bean is advised, and this is its target.
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
  /// Whether [object] is an AOP proxy: a wrapper around another object, or
  /// a generated subclass proxy with advice attached. A subclass proxy no
  /// advice matched is not one.
  static bool isAopProxy(Object? object) =>
      object is Advised &&
      (!identical(object.aopTarget, object) || object.aopAdvisors.isNotEmpty);

  /// The object behind [object], unwrapping nested proxies; [object]
  /// itself when it is not a proxy or is a subclass proxy (its own
  /// target).
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

/// Knows how to wrap one bean class in its generated proxy class, and which
/// of its members can be advised.
///
/// Dart cannot create classes at runtime, so the generator writes a proxy
/// class for each bean class and attaches one of these factories to the
/// bean definition (its `aopProxy` field). When the context starts, the
/// `AspectAutoProxyCreator` asks it which advisors match the bean and has
/// it create the proxy. There are three forms: a wrapper class that
/// implements the bean's class or interfaces and forwards to it (the main
/// constructor), a generated subclass the bean is created as
/// ([AopProxyFactory.subclass]), and a placeholder for beans that cannot be
/// proxied ([AopProxyFactory.unavailable]). Applications do not create it;
/// `ProxyFactory.forBean` uses it to make more proxies of a bean.
///
/// Unlike Spring's JDK and CGLIB proxies, the proxy class is written at
/// build time, so no reflection is needed at runtime.
///
/// ```dart
/// // In a test, with a proxy class CalculatorProxy written by hand:
/// // wrap a SimpleCalculator so every call is logged.
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
  /// A factory for a wrapper proxy class whose advisable members are
  /// [signatures]; `create` instantiates the generated class around a
  /// target.
  ///
  /// [introductions] are the interfaces `@DeclareParents` adds to the
  /// proxy class.
  AopProxyFactory({
    required List<MethodSignature> signatures,
    required Object Function(Object target, ProxyInvoker invoker) this._create,
    List<Introduction> introductions = const [],
  }) : signatures = List.unmodifiable(signatures),
       introductions = List.unmodifiable(introductions),
       _advise = null,
       unavailableReason = null;

  /// A placeholder for a bean whose class cannot be proxied, with the
  /// [reason].
  ///
  /// [signatures] are the bean's members. Advice that matches one of them
  /// makes the bean fail at startup with an [AopConfigException] carrying
  /// [reason], instead of the advice being silently skipped. Spring fails
  /// the same way when it cannot create a proxy.
  AopProxyFactory.unavailable({
    required List<MethodSignature> signatures,
    required String reason,
  }) : signatures = List.unmodifiable(signatures),
       introductions = const [],
       _create = null,
       _advise = null,
       unavailableReason = reason;

  /// A factory for a bean whose class cannot be implemented but can be
  /// extended, which the container creates as a generated subclass.
  ///
  /// The subclass's members call `super` directly until `advise` attaches
  /// a [ProxyInvoker]; from then on they run through the advice, like a
  /// CGLIB proxy in Spring. `advise` returns the advised bean, or `null`
  /// when the bean is not the generated subclass (another post-processor
  /// replaced it).
  ///
  /// ```dart
  /// AopProxyFactory.subclass(
  ///   signatures: const [MethodSignature(name: 'add', ...)],
  ///   advise: (bean, invoker) =>
  ///       bean is _$CalculatorProxy ? bean._$advise(invoker) : null,
  /// );
  /// ```
  ///
  /// [introductions] are the interfaces `@DeclareParents` adds to the
  /// subclass; their members work once the aspect declaring them is
  /// registered, which attaches the invoker.
  AopProxyFactory.subclass({
    required List<MethodSignature> signatures,
    required Object? Function(Object bean, ProxyInvoker invoker) this._advise,
    List<Introduction> introductions = const [],
  }) : signatures = List.unmodifiable(signatures),
       introductions = List.unmodifiable(introductions),
       _create = null,
       unavailableReason = null;

  /// The bean's advisable members; the generated proxy refers to each by
  /// its index in this list.
  final List<MethodSignature> signatures;

  /// The interfaces the proxy class implements for `@DeclareParents`; the
  /// proxy refers to each by its index in [ProxyInvoker.introduction].
  final List<Introduction> introductions;

  final Object Function(Object target, ProxyInvoker invoker)? _create;
  final Object? Function(Object bean, ProxyInvoker invoker)? _advise;

  /// Why the bean cannot be proxied; `null` when it can.
  final String? unavailableReason;

  /// Whether the bean is created as a generated subclass that advice is
  /// attached to, instead of being wrapped.
  bool get isSubclass => _advise != null;

  /// The advisors among [advisors] that match at least one member of the
  /// bean named [beanName], in their order. [beanAliases] (the bean's
  /// aliases and qualifier values) also count for `bean(...)` pointcuts.
  /// An empty result means the bean needs no proxy.
  List<PointcutAdvisor> eligibleAdvisors(
    List<PointcutAdvisor> advisors,
    String beanName, {
    List<String> beanAliases = const [],
  }) => [
    for (final advisor in advisors)
      if (signatures.any(
        (s) => pointcutMatchesBean(
          advisor.pointcut,
          s,
          beanName,
          beanAliases,
          introducedTypes: [
            for (final introduction in introductions)
              introduction.interfaceName,
          ],
        ),
      ))
        advisor,
  ];

  /// Returns the proxy of [target] that runs [advisors], outermost first.
  ///
  /// For a subclass factory, [target] is the generated subclass instance
  /// and is returned advised. Throws an [AopConfigException] when the bean
  /// cannot be proxied ([unavailableReason]) or, for a subclass factory,
  /// when [target] is not the generated subclass.
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
      introductions: introductions,
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

/// Thrown when AOP is set up in a way that cannot work, usually at
/// startup: advice matches a bean that cannot be proxied, an aspect has an
/// unsupported instantiation model, or a proxy's advisors are changed
/// although it has none.
///
/// The message says what is wrong and how to fix it, such as adding an
/// interface with the advised methods. Applications do not catch it; they
/// fix the configuration.
class AopConfigException implements Exception {
  /// Creates the exception with [message].
  const AopConfigException(this.message);

  /// What went wrong and how to fix it.
  final String message;

  @override
  String toString() => 'AopConfigException: $message';
}

/// Thrown by an advised call when the advice cannot run as written, like
/// Spring's `AopInvocationException`.
///
/// The case today: a `@Before`, `@After`, `@AfterReturning` or
/// `@AfterThrowing` advice that is `async` (returns a `Future`) on a
/// synchronous method, which cannot wait for it. Make the advice
/// synchronous, or the advised method return a `Future`.
class AopInvocationException implements Exception {
  /// Creates the exception with [message].
  const AopInvocationException(this.message);

  /// What went wrong and how to fix it.
  final String message;

  @override
  String toString() => 'AopInvocationException: $message';
}

/// The runtime engine behind one proxy: it runs each call of a proxied
/// member through the advice that matches that member.
///
/// Generated proxy classes contain no advice logic. Each member forwards to
/// [invoke] (or [invokeAsync] for members returning a `Future`,
/// [invokeFutureOr] for `FutureOr` ones) with its index in [signatures],
/// its arguments and a closure that calls the real member. The invoker
/// works out, once per member, which advisors match, runs them in order,
/// and also handles self-calls, `AopContext.currentProxy()` and the
/// `@DeclareParents` delegates. It also stores the proxy's advisors, so
/// [Advised] methods forward to it. Only generated code uses it.
///
/// ```dart
/// // The shape of a generated wrapper proxy.
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
  /// An invoker running `advisors` (outermost first) on the members
  /// [signatures] of the bean named [beanName]; [beanAliases] (aliases and
  /// qualifier values) also count for `bean(...)` pointcuts.
  ///
  /// [introductions] are the `@DeclareParents` interfaces of the proxy.
  ProxyInvoker(
    this.signatures,
    List<PointcutAdvisor> advisors,
    this.beanName, {
    List<String> beanAliases = const [],
    List<Introduction> introductions = const [],
  }) : _advisors = [...advisors],
       beanAliases = List.unmodifiable(beanAliases),
       introductions = List.unmodifiable(introductions),
       _delegates = List.filled(introductions.length, null);

  /// Throws the [AopConfigException] for a call of an [Advised] method on
  /// a generated subclass proxy that no advice matched when the bean was
  /// created, so it has no invoker and no advisors to change.
  static Never notAdvised(Object proxy) => throw AopConfigException(
    'The ${proxy.runtimeType} bean is not advised: no advice matched it when '
    'it was created, so it has no advisors to change. Declare advice that '
    'matches it (or a PointcutAdvisor bean) to have it proxied.',
  );

  /// Throws the [AopConfigException] for a call of a member of the
  /// introduced interface [interfaceName] on a generated subclass proxy
  /// without an invoker: the aspect declaring the introduction is not
  /// registered (a condition or profile left it out).
  static Never notIntroduced(Object proxy, String interfaceName) =>
      throw AopConfigException(
        'The ${proxy.runtimeType} bean implements $interfaceName through a '
        '@DeclareParents introduction, but the aspect declaring it is not '
        'registered in the context, so there is no $interfaceName '
        'implementation to call.',
      );

  /// The proxied members; generated code refers to each by its index.
  final List<MethodSignature> signatures;

  final List<PointcutAdvisor> _advisors;

  /// The advisors of the proxy, outermost first. It is a read-only view
  /// that follows [addAdvisor] and [removeAdvisor].
  late final List<PointcutAdvisor> advisors = UnmodifiableListView(_advisors);

  /// The `@DeclareParents` interfaces of the proxy; generated code refers
  /// to each by its index.
  final List<Introduction> introductions;

  /// The names of the [introductions] interfaces, which `this(...)`
  /// pointcuts match.
  late final List<String> introducedTypes = [
    for (final introduction in introductions) introduction.interfaceName,
  ];

  final List<Object?> _delegates;

  /// The object implementing introduction [index] for this proxy, created
  /// on first use and reused afterwards.
  Object introduction(int index) =>
      _delegates[index] ??= introductions[index].create();

  /// Appends [advisor] as the innermost one; the next calls use it.
  void addAdvisor(PointcutAdvisor advisor) {
    _advisors.add(advisor);
    _chains.clear();
  }

  /// Removes [advisor]; returns `false` when it was not there.
  bool removeAdvisor(PointcutAdvisor advisor) {
    final removed = _advisors.remove(advisor);
    if (removed) {
      _chains.clear();
    }
    return removed;
  }

  /// Appends [advice] as the innermost advice of every member.
  void addAdvice(MethodInterceptor advice) =>
      addAdvisor(DefaultPointcutAdvisor(const TruePointcut(), advice));

  /// Removes the first advisor whose advice is [advice] (the same object);
  /// returns `false` when there is none.
  bool removeAdvice(MethodInterceptor advice) {
    for (final advisor in _advisors) {
      if (identical(advisor.advice, advice)) {
        return removeAdvisor(advisor);
      }
    }
    return false;
  }

  /// The name of the proxied bean, which `bean(...)` pointcuts match.
  final String beanName;

  /// The aliases and qualifier values of the proxied bean, which
  /// `bean(...)` pointcuts also match.
  final List<String> beanAliases;

  // Interceptor chains per member index, computed on first call.
  final _chains = <int, List<MethodInterceptor>>{};

  /// The interceptors for member [index], outermost first, computed on
  /// the first call and cached until the advisors change.
  ///
  /// Advice whose pointcut depends on the call (bound parameters,
  /// `args(...)` type tests) is included wrapped, and skipped for the calls
  /// it does not match.
  List<MethodInterceptor> chainFor(int index) => _chains.putIfAbsent(index, () {
    final signature = signatures[index];
    return [
      for (final advisor in _advisors)
        if (pointcutMatchesBean(
          advisor.pointcut,
          signature,
          beanName,
          beanAliases,
          introducedTypes: introducedTypes,
        ))
          switch (advisor.pointcut) {
            final ExpressionPointcut pointcut when pointcut.isRuntime =>
              _DynamicInterceptor(pointcut, advisor.advice, this),
            _ => advisor.advice,
          },
    ];
  });

  // A subclass proxy (the bean is its own proxy, [target] is [proxy])
  // calling itself from its own code: like a `this.` call on Spring's
  // target, the call skips the advice (unless made through
  // `AopContext.currentProxy()`).
  static bool _isSelfCall(Object proxy, Object target) =>
      identical(proxy, target) &&
      isInProxyBody(proxy) &&
      !takeCallThroughProxy(proxy);

  /// Calls the synchronous member [index] through its advice and returns
  /// the result.
  ///
  /// [arguments] are the caller's arguments; [call] runs the real member
  /// with the arguments the advice passes on. Without matching advice,
  /// [call] runs directly. A call a subclass proxy makes on itself from its
  /// own code skips the advice, as a `this` call does in Spring.
  Object? invoke(
    Object proxy,
    Object target,
    int index,
    List<Object?> arguments,
    Object? Function(List<Object?> arguments) call,
  ) {
    if (_isSelfCall(proxy, target)) {
      return call(arguments);
    }
    final body = identical(proxy, target)
        ? (List<Object?> args) => runProxyBody(proxy, () => call(args))
        : call;
    return runWithCurrentProxy(proxy, () {
      final chain = chainFor(index);
      if (chain.isEmpty) {
        return body(arguments);
      }
      return _Invocation(
        proxy,
        target,
        signatures[index],
        [...arguments],
        chain,
        0,
        body,
      ).proceed();
    });
  }

  /// Calls member [index], which returns `Future<T>`, through its advice.
  ///
  /// `@After`, `@AfterReturning` and `@AfterThrowing` run when the future
  /// completes. The result is retyped to `Future<T>`, since `@Around`
  /// advice may return a future of another type. The proxy stays current
  /// for `AopContext.currentProxy()` in the asynchronous code the call
  /// starts.
  Future<T> invokeAsync<T>(
    Object proxy,
    Object target,
    int index,
    List<Object?> arguments,
    Future<T> Function(List<Object?> arguments) call,
  ) {
    if (_isSelfCall(proxy, target)) {
      return call(arguments);
    }
    final body = identical(proxy, target)
        ? (List<Object?> args) =>
              runProxyBody(proxy, () => call(args), async: true)
        : call;
    return runAsyncWithCurrentProxy(proxy, () {
      final chain = chainFor(index);
      if (chain.isEmpty) {
        return body(arguments);
      }
      return retypeFuture<T>(
        _AsyncInvocation<T>(
          proxy,
          target,
          signatures[index],
          [...arguments],
          chain,
          0,
          body,
        ).proceed(),
      );
    });
  }

  /// Calls member [index], which returns `FutureOr<T>`, through its
  /// advice.
  ///
  /// When the result is a `Future`, `@After`, `@AfterReturning` and
  /// `@AfterThrowing` run when it completes and it is retyped to
  /// `Future<T>`; a plain value is handled synchronously.
  FutureOr<T> invokeFutureOr<T>(
    Object proxy,
    Object target,
    int index,
    List<Object?> arguments,
    FutureOr<T> Function(List<Object?> arguments) call,
  ) {
    if (_isSelfCall(proxy, target)) {
      return call(arguments);
    }
    final body = identical(proxy, target)
        ? (List<Object?> args) =>
              runProxyBody(proxy, () => call(args), async: true)
        : call;
    return runAsyncWithCurrentProxy(proxy, () {
      final chain = chainFor(index);
      if (chain.isEmpty) {
        return body(arguments);
      }
      final result = _FutureOrInvocation<T>(
        proxy,
        target,
        signatures[index],
        [...arguments],
        chain,
        0,
        body,
      ).proceed();
      return result is Future ? retypeFuture<T>(result) : result as T;
    });
  }
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
      introducedTypes: invoker.introducedTypes,
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
