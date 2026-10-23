import 'dart:async';

import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/aop/proxy.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// Holds advice, like Spring's `Advisor`.
///
/// An advisor bean is applied by the auto proxy creator: a
/// [PointcutAdvisor] to the members its pointcut matches, any other
/// advisor to every member of every proxied bean (like Spring). Beans
/// that are advisors are never proxied themselves.
///
/// ```dart
/// final Advisor advisor = DefaultPointcutAdvisor(
///   const TruePointcut(),
///   LoggingInterceptor(),
/// );
/// advisor.advice; // the LoggingInterceptor
/// ```
///
/// Spring (Java):
/// ```java
/// Advisor advisor =
///     new DefaultPointcutAdvisor(Pointcut.TRUE, new LoggingInterceptor());
/// advisor.getAdvice();
/// ```
abstract interface class Advisor {
  /// The interceptor run for matching calls.
  MethodInterceptor get advice;
}

/// An [Advisor] restricted by a pointcut, like Spring's `PointcutAdvisor`.
/// Register one as a bean to advise matching proxied beans.
///
/// ```dart
/// @Configuration()
/// class AopConfig {
///   @Bean()
///   PointcutAdvisor upperCaseAdvisor() => DefaultPointcutAdvisor(
///     ExpressionPointcut('bean(echoShouter)'),
///     UpperCaseInterceptor(),
///   );
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// class AopConfig {
///   @Bean
///   PointcutAdvisor upperCaseAdvisor() {
///     AspectJExpressionPointcut pointcut = new AspectJExpressionPointcut();
///     pointcut.setExpression("bean(echoShouter)");
///     return new DefaultPointcutAdvisor(pointcut, new UpperCaseInterceptor());
///   }
/// }
/// ```
abstract interface class PointcutAdvisor implements Advisor {
  /// Selects the members [advice] applies to.
  AopPointcut get pointcut;
}

/// A plain [PointcutAdvisor], like Spring's `DefaultPointcutAdvisor`.
///
/// Advisors are applied in [order] (lower first, i.e. outermost); an
/// `@Order` on the advisor bean definition also counts.
///
/// ```dart
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
  /// Creates an advisor running [advice] for members matching
  /// [pointcut].
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

/// Advice kinds in the precedence Spring uses within one aspect.
///
/// Within one aspect, advice is ordered by kind (earlier kinds wrap later
/// ones), then by declaration order.
///
/// ```dart
/// AspectAdvice<AuditAspect>(
///   kind: AdviceKind.before,
///   pointcut: 'calculator()',
///   methodName: 'before',
///   invoke: (aspect, joinPoint, _) => aspect.before(joinPoint),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// // ReflectiveAspectJAdvisorFactory sorts advice methods by
/// // Around, Before, After, AfterReturning, AfterThrowing.
/// ```
enum AdviceKind {
  /// `@Around` advice.
  around,

  /// `@Before` advice.
  before,

  /// `@After` advice.
  after,

  /// `@AfterReturning` advice.
  afterReturning,

  /// `@AfterThrowing` advice.
  afterThrowing,
}

/// One advice method of an `@Aspect`, prepared by generated code.
///
/// Normally only generated code creates these (see [AspectMetadata]);
/// writing one by hand is useful for tests or manual bean definitions.
/// `invoke` receives the aspect, the join point, the returned value or
/// thrown error (`@AfterReturning` / `@AfterThrowing`, else `null`) and
/// the advice parameters bound by the pointcut ([bindings]), by name.
///
/// ```dart
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
  /// Creates the advice [methodName] of kind [kind] for [pointcut];
  /// `invoke` calls the method, the optional `accepts` checks the
  /// returned value or thrown error against the advice parameter type and
  /// [bindings] are the advice parameters the pointcut may bind.
  AspectAdvice({
    required this.kind,
    required this.pointcut,
    required this.methodName,
    required this._invoke,
    this._accepts,
    Map<String, AdviceBinding> bindings = const {},
  }) : bindings = Map.unmodifiable(bindings);

  /// Which annotation declared the advice.
  final AdviceKind kind;

  /// Pointcut expression.
  final String pointcut;

  /// Name of the advice method, for diagnostics.
  final String methodName;

  /// Advice parameters bound by the pointcut (`@annotation(timed)`,
  /// `args(id, ..)`, ...), by parameter name.
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

  /// Whether [value] (a result or error) has the advice parameter type;
  /// always `true` without a type check.
  bool accepts(Object? value) => _accepts?.call(value) ?? true;

  /// Calls the advice method on [aspect]; [value] is the result or error
  /// for `@AfterReturning` / `@AfterThrowing` and `null` otherwise;
  /// [bindings] are the values the pointcut bound for this call.
  Object? invoke(
    Object aspect,
    JoinPoint joinPoint,
    Object? value, [
    Map<String, Object?> bindings = const {},
  ]) => _invoke(aspect as A, joinPoint, value, bindings);

  @override
  String toString() => '@${kind.name}($pointcut) $methodName';
}

/// The advice and named pointcuts of an `@Aspect` bean.
///
/// Generated code attaches it to the aspect's bean definition (the
/// `aspect` field); the `AspectAutoProxyCreator` turns it into advisors.
/// [pointcuts] holds the aspect's own `@Pointcut` methods by name and the
/// pointcuts of holder classes it references, qualified
/// (`'CommonPointcuts.inWeb'`).
///
/// ```dart
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
  /// Creates metadata with the aspect's [advice] methods and named
  /// [pointcuts]; [typeName] is the aspect's class name as written in
  /// qualified references (`AuditAspect.calculator()`), `'$A'` by default.
  AspectMetadata({
    List<AspectAdvice<A>> advice = const [],
    Map<String, String> pointcuts = const {},
    String? typeName,
  }) : advice = List.unmodifiable(advice),
       pointcuts = Map.unmodifiable(pointcuts),
       typeName = typeName ?? '$A';

  /// The advice methods, in declaration order.
  final List<AspectAdvice<A>> advice;

  /// Named `@Pointcut`s: method name → expression, plus qualified
  /// pointcuts of holder classes (`Type.method` → expression).
  final Map<String, String> pointcuts;

  /// The aspect's class name (written by the generator, so it survives
  /// minified release builds).
  final String typeName;
}

/// Runs one [AspectAdvice] of an aspect bean obtained per call (so lazy
/// and prototype aspects work).
///
/// Created by the `AspectAutoProxyCreator` for every advice method. The
/// advice method gets its own join point: its `args` are a copy (Spring's
/// `JoinPoint.getArgs()`), so only `proceed(args)` changes the arguments.
///
/// An advice method other than `@Around` may be `async`: for a method
/// returning a `Future` (or `FutureOr`), the call waits for it; for a
/// synchronous method that is an [AopInvocationException].
///
/// ```dart
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
  /// Creates an interceptor running [advice] on the bean that [aspect]
  /// returns.
  AspectAdviceInterceptor(this.advice, this.aspect);

  /// The advice method to run.
  final AspectAdvice<Object> advice;

  /// Looks up the aspect bean (called on every invocation).
  final Object Function() aspect;

  /// Runs the advice for [invocation]; [bindings] are the advice
  /// parameters the pointcut bound for this call.
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
        advice.invoke(aspect(), joinPoint, value, bindings);
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

/// A [MethodInvocation] of a method returning a `Future` (or `FutureOr`);
/// [chain] attaches callbacks while keeping the future's type.
///
/// Spring has no equivalent: it advises the call that creates a
/// `CompletableFuture`, not its completion.
///
/// ```dart
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
  /// Returns a future completing like [future] after running [onValue]
  /// or [onError], then [always]; a callback returning a Future is waited
  /// for. Errors are rethrown with their stack trace.
  Future<Object?> chain(
    Future<Object?> future, {
    FutureOr<void> Function(Object? value)? onValue,
    FutureOr<void> Function(Object error)? onError,
    FutureOr<void> Function()? always,
  });
}

/// Converts any future to `Future<T>` (an `@Around` advice may return an
/// untyped future).
///
/// Non-future values are wrapped in a completed future; used by
/// generated proxies for `Future<T>` members.
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
