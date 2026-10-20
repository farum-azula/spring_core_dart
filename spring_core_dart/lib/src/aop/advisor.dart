import 'dart:async';

import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// Holds advice, like Spring's `Advisor`.
///
/// Only [PointcutAdvisor]s are applied by the auto proxy creator; beans
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
///
/// ```dart
/// AspectAdvice<AuditAspect>(
///   kind: AdviceKind.afterReturning,
///   pointcut: 'execution(* Calculator.*(..))',
///   methodName: 'returned',
///   invoke: (aspect, joinPoint, value) =>
///       aspect.returned(joinPoint, value! as int),
///   accepts: (value) => value is int,
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// // Built reflectively by ReflectiveAspectJAdvisorFactory, e.g. an
/// // AspectJAfterReturningAdvice for
/// @AfterReturning(pointcut = "execution(* Calculator.*(..))",
///     returning = "value")
/// void returned(JoinPoint joinPoint, int value) { ... }
/// ```
final class AspectAdvice<A extends Object> {
  /// Creates the advice [methodName] of kind [kind] for [pointcut];
  /// `invoke` calls the method and the optional `accepts` checks the
  /// returned value or thrown error against the advice parameter type.
  AspectAdvice({
    required this.kind,
    required this.pointcut,
    required this.methodName,
    required this._invoke,
    this._accepts,
  });

  /// Which annotation declared the advice.
  final AdviceKind kind;

  /// Pointcut expression.
  final String pointcut;

  /// Name of the advice method, for diagnostics.
  final String methodName;
  final Object? Function(A aspect, JoinPoint joinPoint, Object? value) _invoke;

  /// For `@AfterReturning` / `@AfterThrowing`: whether the value or error
  /// has the type of the advice parameter.
  final bool Function(Object? value)? _accepts;

  /// Whether [value] (a result or error) has the advice parameter type;
  /// always `true` without a type check.
  bool accepts(Object? value) => _accepts?.call(value) ?? true;

  /// Calls the advice method on [aspect]; [value] is the result or error
  /// for `@AfterReturning` / `@AfterThrowing` and `null` otherwise.
  Object? invoke(Object aspect, JoinPoint joinPoint, Object? value) =>
      _invoke(aspect as A, joinPoint, value);

  @override
  String toString() => '@${kind.name}($pointcut) $methodName';
}

/// The advice and named pointcuts of an `@Aspect` bean.
///
/// Generated code attaches it to the aspect's bean definition (the
/// `aspect` field); the `AspectAutoProxyCreator` turns it into advisors.
///
/// ```dart
/// BeanDefinition<AuditAspect>(
///   name: 'auditAspect',
///   create: (_) => AuditAspect(),
///   aspect: AspectMetadata<AuditAspect>(
///     pointcuts: {'calculator': 'execution(* Calculator.*(..))'},
///     advice: [
///       AspectAdvice<AuditAspect>(
///         kind: AdviceKind.after,
///         pointcut: 'calculator()',
///         methodName: 'after',
///         invoke: (aspect, _, _) => aspect.after(),
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
  /// [pointcuts].
  AspectMetadata({
    List<AspectAdvice<A>> advice = const [],
    Map<String, String> pointcuts = const {},
  }) : advice = List.unmodifiable(advice),
       pointcuts = Map.unmodifiable(pointcuts);

  /// The advice methods, in declaration order.
  final List<AspectAdvice<A>> advice;

  /// Named `@Pointcut`s: method name → expression.
  final Map<String, String> pointcuts;
}

/// Runs one [AspectAdvice] of an aspect bean obtained per call (so lazy
/// and prototype aspects work).
///
/// Created by the `AspectAutoProxyCreator` for every advice method.
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

  // For a `Future` result, after-style advice must wait for completion:
  // the invocation's `chain` attaches the callbacks and keeps the
  // future's static type, so the proxy can still return `Future<T>`.
  @override
  Object? invoke(MethodInvocation invocation) {
    switch (advice.kind) {
      case AdviceKind.around:
        return advice.invoke(aspect(), invocation, null);
      case AdviceKind.before:
        advice.invoke(aspect(), invocation, null);
        return invocation.proceed();
      case AdviceKind.after:
        // Synchronous failure: run the advice, then rethrow.
        final Object? result;
        try {
          result = invocation.proceed();
        } catch (_) {
          advice.invoke(aspect(), invocation, null);
          rethrow;
        }
        if (result is Future && invocation is AsyncMethodInvocation) {
          return invocation.chain(
            result,
            always: () => advice.invoke(aspect(), invocation, null),
          );
        }
        advice.invoke(aspect(), invocation, null);
        return result;
      case AdviceKind.afterReturning:
        final result = invocation.proceed();
        if (result is Future && invocation is AsyncMethodInvocation) {
          return invocation.chain(
            result,
            onValue: (value) {
              if (advice.accepts(value)) {
                advice.invoke(aspect(), invocation, value);
              }
            },
          );
        }
        if (advice.accepts(result)) {
          advice.invoke(aspect(), invocation, result);
        }
        return result;
      case AdviceKind.afterThrowing:
        // Errors thrown synchronously are handled here, errors of a
        // returned future in `chain` below; both are rethrown.
        final Object? result;
        try {
          result = invocation.proceed();
        } catch (error) {
          if (advice.accepts(error)) {
            advice.invoke(aspect(), invocation, error);
          }
          rethrow;
        }
        if (result is Future && invocation is AsyncMethodInvocation) {
          return invocation.chain(
            result,
            onError: (error) {
              if (advice.accepts(error)) {
                advice.invoke(aspect(), invocation, error);
              }
            },
          );
        }
        return result;
    }
  }
}

/// A [MethodInvocation] of a method returning a `Future`; [chain] attaches
/// callbacks while keeping the future's type.
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
  /// or [onError], then [always]; errors are rethrown with their stack
  /// trace.
  Future<Object?> chain(
    Future<Object?> future, {
    void Function(Object? value)? onValue,
    void Function(Object error)? onError,
    void Function()? always,
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
