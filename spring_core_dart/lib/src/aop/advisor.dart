import 'dart:async';

import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/aop/proxy.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// A piece of advice packaged as an object: the [MethodInterceptor] to run
/// around calls of other beans.
///
/// Advisors are the form all advice takes at runtime: the container turns
/// each `@Aspect` advice method into one, and any bean that is an advisor
/// is applied too. Applications rarely implement this interface; they
/// write an `@Aspect`, or declare a [PointcutAdvisor] bean (usually a
/// [DefaultPointcutAdvisor]) to say which members the advice is for. An
/// advisor bean that is not a [PointcutAdvisor] applies to every member of
/// every proxied bean. Advisor beans are never proxied themselves.
///
/// ```dart
/// // Logs every call of every proxied bean.
/// @Configuration()
/// class AopConfig {
///   @Bean()
///   Advisor logging() =>
///       DefaultPointcutAdvisor(const TruePointcut(), LoggingInterceptor());
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// Advisor logging() {
///   return new DefaultPointcutAdvisor(
///       Pointcut.TRUE, new LoggingInterceptor());
/// }
/// ```
abstract interface class Advisor {
  /// The interceptor that runs around each advised call.
  MethodInterceptor get advice;
}

/// An [Advisor] that applies only to the members its [pointcut] selects.
///
/// It is the way to add advice without an `@Aspect` class: declare a bean
/// of this type, and the container wraps every proxied bean with a matching
/// member. Use it when the advice is a reusable [MethodInterceptor] (a
/// library's caching or security interceptor, say) or when the pointcut is
/// computed in code. [DefaultPointcutAdvisor] is the ready-made
/// implementation; starters declare such beans for `@Cacheable` and method
/// security.
///
/// ```dart
/// // Counts the calls of every controller method.
/// @Configuration()
/// class MetricsConfig {
///   @Bean()
///   PointcutAdvisor handlerMetricsAdvisor(HandlerMetrics metrics) =>
///       DefaultPointcutAdvisor(
///         ExpressionPointcut('within(*Controller)'),
///         CountingInterceptor(metrics),
///       );
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// class MetricsConfig {
///   @Bean
///   PointcutAdvisor handlerMetricsAdvisor(HandlerMetrics metrics) {
///     AspectJExpressionPointcut pointcut = new AspectJExpressionPointcut();
///     pointcut.setExpression("within(*Controller)");
///     return new DefaultPointcutAdvisor(
///         pointcut, new CountingInterceptor(metrics));
///   }
/// }
/// ```
abstract interface class PointcutAdvisor implements Advisor {
  /// Decides which members of which beans [advice] runs for.
  AopPointcut get pointcut;
}

/// The standard [PointcutAdvisor]: a pointcut, an interceptor and an
/// order.
///
/// Create one in a `@Bean` method to advise beans without an `@Aspect`.
/// When several advisors and aspects apply to one call, the lower [order]
/// is the outer one (it runs first on the way in, last on the way out).
/// The default is `Ordered.lowestPrecedence`, so it runs inside ordered
/// aspects. Set it here: since the advisor implements `Ordered`, an
/// `@Order` on its `@Bean` method is ignored, as in Spring.
///
/// ```dart
/// // Times every method marked @Timed(), outside advice of order > 10.
/// @Bean()
/// PointcutAdvisor timingAdvisor() => DefaultPointcutAdvisor(
///   const AnnotationMatchingPointcut<Timed>(),
///   TimingInterceptor(),
///   order: 10,
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// Advisor timingAdvisor() {
///   DefaultPointcutAdvisor advisor = new DefaultPointcutAdvisor(
///       AnnotationMatchingPointcut.forMethodAnnotation(Timed.class),
///       new TimingInterceptor());
///   advisor.setOrder(10);
///   return advisor;
/// }
/// ```
final class DefaultPointcutAdvisor implements PointcutAdvisor, Ordered {
  /// Runs [advice] around calls of the members [pointcut] matches, at
  /// [order] (default `Ordered.lowestPrecedence`, the innermost).
  DefaultPointcutAdvisor(
    this.pointcut,
    this.advice, {
    this.order = Ordered.lowestPrecedence,
  });

  @override
  final AopPointcut pointcut;

  @override
  final MethodInterceptor advice;

  @override
  final int order;

  @override
  String toString() => 'DefaultPointcutAdvisor($pointcut, order $order)';
}

/// The five kinds of aspect advice, one per annotation, listed in the order
/// they nest inside one aspect.
///
/// Generated code tags each [AspectAdvice] with its kind, and the
/// container uses it to decide how the advice runs (before the call, after
/// it, around it) and in which order. Within one aspect, an earlier kind
/// wraps a later one: around, then before, after, afterReturning,
/// afterThrowing; advice of the same kind keeps declaration order.
/// Applications meet it only when reading the advice of an aspect or
/// writing an [AspectAdvice] by hand.
///
/// ```dart
/// // The @Before advice method `before` of AuditAspect.
/// AspectAdvice<AuditAspect>(
///   kind: AdviceKind.before,
///   pointcut: 'calculator()',
///   methodName: 'before',
///   invoke: (aspect, joinPoint, _, _) => aspect.before(joinPoint),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// // ReflectiveAspectJAdvisorFactory sorts advice methods by
/// // Around, Before, After, AfterReturning, AfterThrowing.
/// ```
enum AdviceKind {
  /// `@Around`: runs instead of the call and decides whether it proceeds.
  around,

  /// `@Before`: runs before the call.
  before,

  /// `@After`: runs after the call, whether it returned or threw.
  after,

  /// `@AfterReturning`: runs after the call returned, with the result.
  afterReturning,

  /// `@AfterThrowing`: runs after the call threw, with the error.
  afterThrowing,
}

/// One advice method of an `@Aspect` class, described so it can be called
/// without reflection.
///
/// Dart cannot look up and call an annotated method at runtime, so the
/// generator writes one of these for every advice method, inside the
/// aspect's [AspectMetadata]: its kind, its pointcut, and a closure that
/// calls the method with the right arguments. Applications do not create
/// them; writing one by hand is useful only in tests or in bean
/// definitions written without the generator.
///
/// The `invoke` closure receives the aspect, the join point, the returned
/// value or thrown error (for `@AfterReturning` / `@AfterThrowing`, else
/// `null`) and the advice parameters the pointcut bound ([bindings]), by
/// name. The optional `accepts` closure tests the result or error against
/// the advice parameter's type.
///
/// ```dart
/// // The generated form of
/// // @AfterReturning('execution(* Calculator.*(..)) && @annotation(timed)')
/// // void returned(JoinPoint joinPoint, Timed timed, int value)
/// AspectAdvice<AuditAspect>(
///   kind: AdviceKind.afterReturning,
///   pointcut: 'execution(* Calculator.*(..)) && @annotation(timed)',
///   methodName: 'returned',
///   invoke: (aspect, joinPoint, value, bindings) => aspect.returned(
///     joinPoint,
///     bindings['timed']! as Timed,
///     value! as int,
///   ),
///   accepts: (value) => value is int,
///   bindings: {'timed': AdviceBinding('Timed', (v) => v is Timed)},
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// // Built reflectively by ReflectiveAspectJAdvisorFactory, e.g. an
/// // AspectJAfterReturningAdvice for
/// @AfterReturning(pointcut = "execution(* Calculator.*(..)) && "
///     + "@annotation(timed)", returning = "value")
/// void returned(JoinPoint joinPoint, Timed timed, int value) { ... }
/// ```
final class AspectAdvice<A extends Object> {
  /// Describes the advice method [methodName] of kind [kind] for
  /// [pointcut].
  ///
  /// `invoke` calls the method; `accepts`, when given, tells whether a
  /// returned value or thrown error has the advice parameter's type
  /// (without it every value is accepted); [bindings] are the advice
  /// parameters the pointcut may bind.
  AspectAdvice({
    required this.kind,
    required this.pointcut,
    required this.methodName,
    required this._invoke,
    this._accepts,
    Map<String, AdviceBinding> bindings = const {},
  }) : bindings = Map.unmodifiable(bindings);

  /// Which annotation declared the advice, and so when it runs.
  final AdviceKind kind;

  /// The pointcut expression from the annotation, as written (it may refer
  /// to named pointcuts).
  final String pointcut;

  /// The name of the advice method, shown in error messages.
  final String methodName;

  /// The advice parameters the pointcut fills (`@annotation(timed)`,
  /// `args(id, ..)`, `this(service)`, ...), by parameter name, each with
  /// its type check.
  final Map<String, AdviceBinding> bindings;

  final Object? Function(
    A aspect,
    JoinPoint joinPoint,
    Object? value,
    Map<String, Object?> bindings,
  )
  _invoke;

  /// For `@AfterReturning` / `@AfterThrowing`: whether the value or error
  /// has the type of the advice parameter.
  final bool Function(Object? value)? _accepts;

  /// Whether [value], a returned value or a thrown error, has the type of
  /// the advice parameter, so the advice should run; always `true` when no
  /// type check was given.
  bool accepts(Object? value) => _accepts?.call(value) ?? true;

  /// Calls the advice method on [aspect] and returns what it returns (the
  /// call's result, for `@Around`).
  ///
  /// [value] is the result or error for `@AfterReturning` /
  /// `@AfterThrowing` and `null` otherwise; [bindings] are the values the
  /// pointcut bound for this call.
  Object? invoke(
    Object aspect,
    JoinPoint joinPoint,
    Object? value, [
    Map<String, Object?> bindings = const {},
  ]) => _invoke(aspect as A, joinPoint, value, bindings);

  @override
  String toString() => '@${kind.name}($pointcut) $methodName';
}

/// Everything the container needs to know about an `@Aspect` class: its
/// advice methods, its named pointcuts and its instantiation model.
///
/// The generator reads the aspect's annotations at build time and writes
/// this object into the aspect's bean definition (its `aspect` field). At
/// startup the `AspectAutoProxyCreator` finds the bean definitions that
/// have one and turns each [AspectAdvice] into an advisor. Applications
/// never write it, except for bean definitions written by hand and for
/// `AspectJProxyFactory.addAspect`, which takes one.
///
/// ```dart
/// // What the generator writes for an aspect with one named pointcut
/// // `calculator()` and one @After advice method `after`.
/// BeanDefinition<AuditAspect>(
///   name: 'auditAspect',
///   create: (_) => AuditAspect(),
///   aspect: AspectMetadata<AuditAspect>(
///     typeName: 'AuditAspect',
///     pointcuts: {'calculator': 'execution(* Calculator.*(..))'},
///     advice: [
///       AspectAdvice<AuditAspect>(
///         kind: AdviceKind.after,
///         pointcut: 'calculator()',
///         methodName: 'after',
///         invoke: (aspect, _, _, _) => aspect.after(),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring reads the same information reflectively:
/// AspectMetadata metadata =
///     new AspectMetadata(AuditAspect.class, "auditAspect");
/// ```
final class AspectMetadata<A extends Object> {
  /// Describes an aspect with its [advice] methods and named [pointcuts].
  ///
  /// [typeName] is the aspect's class name as written in qualified
  /// references (`AuditAspect.calculator()`); it defaults to `'$A'`, which
  /// is not reliable in minified builds, so the generator always passes
  /// it. [typeTests] and [argumentAnnotations] are the runtime type tests
  /// the aspect's pointcuts need for `args(String)` and `@args(Audited)`
  /// (see `ExpressionPointcut`). [perClause] is the `@Aspect` value
  /// (`perthis(...)` / `pertarget(...)`), `null` for one shared instance.
  AspectMetadata({
    List<AspectAdvice<A>> advice = const [],
    Map<String, String> pointcuts = const {},
    String? typeName,
    Map<String, bool Function(Object? value)> typeTests = const {},
    Map<String, Object? Function(Object? value)> argumentAnnotations = const {},
    this.perClause,
  }) : advice = List.unmodifiable(advice),
       pointcuts = Map.unmodifiable(pointcuts),
       typeTests = Map.unmodifiable(typeTests),
       argumentAnnotations = Map.unmodifiable(argumentAnnotations),
       typeName = typeName ?? '$A';

  /// The advice methods, in declaration order.
  final List<AspectAdvice<A>> advice;

  /// The aspect's named `@Pointcut`s, method name to expression. It also
  /// holds the pointcuts of other classes the aspect refers to, under a
  /// qualified key (`'CommonPointcuts.inWeb'`).
  final Map<String, String> pointcuts;

  /// The aspect's class name, as written by the generator so that it
  /// survives minified release builds.
  final String typeName;

  /// Type tests by simple type name (`'String': (v) => v is String`), so
  /// `args(String)` can test the runtime type of an argument, as AspectJ's
  /// `instanceof` does.
  final Map<String, bool Function(Object? value)> typeTests;

  /// For `@args(Annotation)`: by annotation name, a function returning
  /// that annotation when a value's runtime class carries it, else `null`.
  final Map<String, Object? Function(Object? value)> argumentAnnotations;

  /// `perthis(pointcut)` for one aspect instance per proxy,
  /// `pertarget(pointcut)` for one per target bean (the aspect bean must
  /// then be a prototype); `null` for one shared instance.
  final String? perClause;
}

/// The [MethodInterceptor] that runs one aspect advice method: it turns the
/// advice kind (before, after, around, ...) into the right place in the
/// call.
///
/// The `AspectAutoProxyCreator` and `AspectJProxyFactory` create one for
/// every [AspectAdvice]; applications do not. It looks the aspect up for
/// every call, so lazy and prototype aspects work, and per-instance
/// aspects (`perthis` / `pertarget`) get the instance of the proxy or
/// target. The advice method gets its own join point whose `args` are a
/// copy (like Spring's `JoinPoint.getArgs()`): changing that list does
/// nothing, only `proceed(args)` changes the arguments.
///
/// For a method returning a `Future` (or a `FutureOr` that is one),
/// `@After`, `@AfterReturning` and `@AfterThrowing` run when the future
/// completes. An advice method other than `@Around` may be `async`: on such
/// a method the call waits for it; on a synchronous method the call fails
/// with an [AopInvocationException], since nothing could wait.
///
/// ```dart
/// // Runs `advice` on the auditAspect bean, looked up for every call.
/// final interceptor = AspectAdviceInterceptor(
///   advice,
///   () => beanFactory.getBeanByName('auditAspect'),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// // One advice class per kind, e.g. AspectJMethodBeforeAdvice, with the
/// // aspect obtained from a BeanFactoryAspectInstanceFactory.
/// new AspectJMethodBeforeAdvice(method, pointcut, aspectInstanceFactory);
/// ```
final class AspectAdviceInterceptor implements MethodInterceptor {
  /// Runs [advice] on the aspect that `aspect` returns, called for every
  /// advised call.
  AspectAdviceInterceptor(this.advice, Object Function() aspect)
    : _aspectFor = ((_) => aspect());

  /// Runs [advice] on the aspect `aspectFor` returns for the call, so the
  /// instance can depend on the proxy or target (`perthis` / `pertarget`
  /// aspects).
  AspectAdviceInterceptor.forInvocation(
    this.advice,
    Object Function(MethodInvocation invocation) aspectFor,
  ) : _aspectFor = aspectFor;

  /// The advice method to run.
  final AspectAdvice<Object> advice;

  // Looks up the aspect for a call (on every invocation).
  final Object Function(MethodInvocation invocation) _aspectFor;

  /// The aspect instance the advice runs on for [invocation].
  Object aspectFor(MethodInvocation invocation) => _aspectFor(invocation);

  /// Runs the advice around [invocation] and returns the call's result.
  ///
  /// [bindings] are the advice parameters the pointcut bound for this
  /// call. Throws an [AopInvocationException] when a non-`@Around` advice
  /// returns a `Future` on a synchronous method.
  // For a `Future` result, after-style advice must wait for completion:
  // the invocation's `chain` attaches the callbacks and keeps the
  // future's static type, so the proxy can still return `Future<T>`.
  @override
  Object? invoke(
    MethodInvocation invocation, [
    Map<String, Object?> bindings = const {},
  ]) {
    final joinPoint = _AdviceJoinPoint(invocation);
    Object? run(Object? value) =>
        advice.invoke(_aspectFor(invocation), joinPoint, value, bindings);
    switch (advice.kind) {
      case AdviceKind.around:
        return run(null);
      case AdviceKind.before:
        return _then(run(null), invocation, invocation.proceed);
      case AdviceKind.after:
        final Object? result;
        try {
          result = invocation.proceed();
        } catch (error, stackTrace) {
          // Synchronous failure: run the advice, then rethrow.
          return _then(
            run(null),
            invocation,
            () => Error.throwWithStackTrace(error, stackTrace),
          );
        }
        if (result is Future && invocation is AsyncMethodInvocation) {
          return invocation.chain(result, always: () => run(null));
        }
        return _then(run(null), invocation, () => result);
      case AdviceKind.afterReturning:
        final result = invocation.proceed();
        if (result is Future && invocation is AsyncMethodInvocation) {
          return invocation.chain(
            result,
            onValue: (value) => advice.accepts(value) ? run(value) : null,
          );
        }
        if (!advice.accepts(result)) {
          return result;
        }
        return _then(run(result), invocation, () => result);
      case AdviceKind.afterThrowing:
        // Errors thrown synchronously are handled here, errors of a
        // returned future in `chain` below; both are rethrown.
        final Object? result;
        try {
          result = invocation.proceed();
        } catch (error, stackTrace) {
          if (!advice.accepts(error)) {
            rethrow;
          }
          return _then(
            run(error),
            invocation,
            () => Error.throwWithStackTrace(error, stackTrace),
          );
        }
        if (result is Future && invocation is AsyncMethodInvocation) {
          return invocation.chain(
            result,
            onError: (error) => advice.accepts(error) ? run(error) : null,
          );
        }
        return result;
    }
  }

  // [pending] is what the advice method returned: a Future is waited for
  // before [next] on an asynchronous join point, and an error on a
  // synchronous one (it could not be waited for).
  Object? _then(
    Object? pending,
    MethodInvocation invocation,
    Object? Function() next,
  ) {
    if (pending is! Future) {
      return next();
    }
    if (invocation is AsyncMethodInvocation) {
      return pending.then((_) => next());
    }
    pending.ignore();
    throw AopInvocationException(
      'Advice $advice returned a Future, but '
      '${invocation.signature.toShortString()} is synchronous, so the '
      'call cannot wait for it. Make the advice method synchronous, or the '
      'advised method return a Future.',
    );
  }
}

// The join point an advice method sees: `args` is a copy, as Spring's
// `MethodInvocationProceedingJoinPoint.getArgs()` clones the arguments.
final class _AdviceJoinPoint implements ProceedingJoinPoint {
  _AdviceJoinPoint(this._invocation);

  final MethodInvocation _invocation;
  List<Object?>? _args;

  @override
  Object get proxy => _invocation.proxy;

  @override
  Object get target => _invocation.target;

  @override
  MethodSignature get signature => _invocation.signature;

  @override
  List<Object?> get args => _args ??= List.of(_invocation.args);

  @override
  Object? proceed([List<Object?>? args]) => _invocation.proceed(args);

  @override
  String toShortString() => _invocation.toShortString();

  @override
  String toString() => _invocation.toString();
}

/// The [MethodInvocation] of a method that returns a `Future` (or
/// `FutureOr`), with a way to run code when that future completes.
///
/// An interceptor that wants to act on the outcome of an asynchronous call
/// (log the value, count failures) cannot just wrap `proceed()`: the call
/// returns at once with a future. It needs [chain], which attaches the
/// callbacks and still returns a future of the method's own type, so the
/// generated proxy can return it as `Future<T>`. Write your own
/// [MethodInterceptor] with it; aspects do not need it, since `@After`,
/// `@AfterReturning` and `@AfterThrowing` already wait for the future.
///
/// Spring has no equivalent: it advises the call that creates a
/// `CompletableFuture`, not its completion.
///
/// ```dart
/// // Logs the value of every async call once it is there.
/// class AsyncLoggingInterceptor implements MethodInterceptor {
///   @override
///   Object? invoke(MethodInvocation invocation) {
///     final result = invocation.proceed();
///     if (result is Future && invocation is AsyncMethodInvocation) {
///       return invocation.chain(result, onValue: (v) => print('got $v'));
///     }
///     return result;
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// Object result = invocation.proceed();
/// if (result instanceof CompletableFuture<?> future) {
///   return future.thenApply(v -> { System.out.println(v); return v; });
/// }
/// return result;
/// ```
abstract interface class AsyncMethodInvocation implements MethodInvocation {
  /// Returns a future that completes like [future], after the callbacks.
  ///
  /// When [future] completes, [onValue] (with the value) or [onError] (with
  /// the error) runs, then [always]. A callback that returns a `Future` is
  /// waited for. The error of [future] is then rethrown with its original
  /// stack trace; an error thrown by a callback replaces it.
  Future<Object?> chain(
    Future<Object?> future, {
    FutureOr<void> Function(Object? value)? onValue,
    FutureOr<void> Function(Object error)? onError,
    FutureOr<void> Function()? always,
  });
}

/// Turns the result of an advised call into a `Future<T>`.
///
/// An `@Around` advice of a `Future<int>` method may return a
/// `Future<Object?>` (an `async` advice does), which is not a
/// `Future<int>`. Generated proxies call this to give the caller the type
/// the method declares: a `Future<T>` is returned as it is, another future
/// is cast value by value, and a plain value is wrapped in a completed
/// future. A value of the wrong type fails with a `TypeError`. Application
/// code does not need it.
///
/// ```dart
/// final Future<int> typed = retypeFuture<int>(Future<Object?>.value(1));
/// ```
Future<T> retypeFuture<T>(Object? value) {
  if (value is Future<T>) {
    return value;
  }
  // `Future<Object?>` is not a `Future<T>`; cast each completed value.
  if (value is Future) {
    return value.then((v) => v as T);
  }
  return Future<T>.value(value as FutureOr<T>);
}
