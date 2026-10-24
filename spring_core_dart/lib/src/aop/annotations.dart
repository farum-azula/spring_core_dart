/// Marks a bean as an aspect, like Spring's `@Aspect`. Its advice
/// methods apply to proxied beans whose methods match their pointcuts.
///
/// Like Spring, an aspect also needs `@Component()` to be picked up by
/// the component scan; `@Order` orders aspects (lower runs first, i.e.
/// outermost).
///
/// ```dart
/// @Aspect()
/// @Component()
/// @Order(1)
/// class AuditAspect {
///   @Before('execution(* Calculator.*(..))')
///   void before(JoinPoint joinPoint) =>
///       print('calling ${joinPoint.signature.name}${joinPoint.args}');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Aspect
/// @Component
/// @Order(1)
/// class AuditAspect {
///   @Before("execution(* Calculator.*(..))")
///   void before(JoinPoint joinPoint) {
///     System.out.println("calling " + joinPoint.getSignature().getName());
///   }
/// }
/// ```
///
/// [value] is the instantiation model, as in Spring: empty for one
/// (singleton) aspect, `perthis(pointcut)` for one aspect instance per
/// proxy, `pertarget(pointcut)` for one per target bean. A per-instance
/// aspect must be a prototype bean (`@Scope('prototype')`); its advice
/// applies where both the per-clause pointcut and the advice's pointcut
/// match.
///
/// ```dart
/// @Aspect('perthis(execution(* Orders.*(..)))')
/// @Component()
/// @Scope('prototype')
/// class CallCounter {
///   int calls = 0;
///
///   @Before('execution(* Orders.*(..))')
///   void count() => calls++;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Aspect("perthis(execution(* com.x.Orders.*(..)))")
/// @Component
/// @Scope("prototype")
/// class CallCounter { ... }
/// ```
class Aspect {
  /// Creates the `@Aspect()` annotation with the per-clause [value].
  const Aspect([this.value = '']);

  /// The instantiation model: empty (singleton), `perthis(...)` or
  /// `pertarget(...)`.
  final String value;
}

/// Makes the proxies of matching beans implement an interface, like
/// AspectJ's `@DeclareParents` in Spring AOP (an introduction).
///
/// Put it on a static field of an `@Aspect` whose type is the interface:
/// the proxy of every bean whose class matches the [value] type pattern
/// (`Orders`, `*Service`, `Repository+`) implements it, forwarding its
/// members to a [defaultImpl] instance created per proxy. Advice can reach
/// it with `this(tracked)`.
///
/// ```dart
/// @Aspect()
/// @Component()
/// class UsageTracking {
///   @DeclareParents('*Service+', defaultImpl: DefaultUsageTracked)
///   static UsageTracked? mixin;
///
///   @Before('execution(* *Service.*(..)) && this(usage)')
///   void count(UsageTracked usage) => usage.increment();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @DeclareParents(value = "com.x.service.*+",
///     defaultImpl = DefaultUsageTracked.class)
/// public static UsageTracked mixin;
/// ```
class DeclareParents {
  /// Introduces the field's interface into beans matching [value],
  /// implemented by [defaultImpl] (a class with a no-argument
  /// constructor).
  const DeclareParents(this.value, {required this.defaultImpl});

  /// Type pattern of the bean classes that get the interface.
  final String value;

  /// The implementation each proxy forwards the interface's members to.
  final Type defaultImpl;
}

/// A named pointcut on a method of an aspect, like Spring's `@Pointcut`.
/// Reference it as `name()` or `AspectClass.name()` in other pointcuts.
///
/// The annotated method's body is never called.
///
/// ```dart
/// @Aspect()
/// @Component()
/// class AuditAspect {
///   @Pointcut('execution(* Calculator.*(..))')
///   void calculator() {}
///
///   @After('calculator() && !execution(* *.slowAdd(..))')
///   void after() => print('done');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Aspect
/// @Component
/// class AuditAspect {
///   @Pointcut("execution(* Calculator.*(..))")
///   void calculator() {}
///
///   @After("calculator() && !execution(* *.slowAdd(..))")
///   void after() { System.out.println("done"); }
/// }
/// ```
class Pointcut {
  /// Creates a named pointcut for [expression].
  const Pointcut(this.expression);

  /// The pointcut expression (see `ExpressionPointcut` for the syntax).
  final String expression;
}

/// Advice run before the method, like Spring's `@Before`. The method may
/// take a `JoinPoint`.
///
/// ```dart
/// @Before('execution(* Calculator.*(..))')
/// void before(JoinPoint joinPoint) => log.add(joinPoint.toShortString());
/// ```
///
/// Spring (Java):
/// ```java
/// @Before("execution(* Calculator.*(..))")
/// void before(JoinPoint joinPoint) { log.add(joinPoint.toShortString()); }
/// ```
class Before {
  /// Creates `@Before` advice for the [pointcut] expression.
  const Before(this.pointcut);

  /// The pointcut expression selecting the advised methods.
  final String pointcut;
}

/// Advice run after the method however it completes, like `@After`.
///
/// For methods returning a `Future`, it runs when the future completes.
///
/// ```dart
/// @After('execution(* Calculator.*(..))')
/// void after() => log.add('after');
/// ```
///
/// Spring (Java):
/// ```java
/// @After("execution(* Calculator.*(..))")
/// void after() { log.add("after"); }
/// ```
class After {
  /// Creates `@After` advice for the [pointcut] expression.
  const After(this.pointcut);

  /// The pointcut expression selecting the advised methods.
  final String pointcut;
}

/// Advice run after the method returns, like `@AfterReturning`. The
/// parameter named [returning] (by default the first parameter that is
/// neither the `JoinPoint` nor bound by the pointcut) receives the return
/// value (or the completed value of a `Future`); the advice only runs when
/// the value has that parameter's type.
///
/// ```dart
/// @AfterReturning('execution(* Calculator.*(..))')
/// void returned(JoinPoint joinPoint, int result) =>
///     log.add('${joinPoint.signature.name}=$result');
///
/// @AfterReturning('@annotation(timed)', returning: 'result')
/// void timed(Timed timed, Object? result) => log.add('$timed: $result');
/// ```
///
/// Spring (Java):
/// ```java
/// @AfterReturning(
///     pointcut = "execution(* Calculator.*(..))", returning = "result")
/// void returned(JoinPoint joinPoint, int result) {
///   log.add(joinPoint.getSignature().getName() + "=" + result);
/// }
/// ```
class AfterReturning {
  /// Creates `@AfterReturning` advice for the [pointcut] expression.
  const AfterReturning(this.pointcut, {this.returning});

  /// The pointcut expression selecting the advised methods.
  final String pointcut;

  /// Name of the advice parameter that receives the return value.
  final String? returning;
}

/// Advice run when the method throws, like `@AfterThrowing`. The
/// parameter named [throwing] (by default the first parameter that is
/// neither the `JoinPoint` nor bound by the pointcut) receives the error;
/// the advice only runs for errors of that type. The error is rethrown
/// afterwards.
///
/// For methods returning a `Future`, it runs when the future fails.
///
/// ```dart
/// @AfterThrowing('execution(* Calculator.*(..))')
/// void failed(JoinPoint joinPoint, UnsupportedError error) =>
///     log.add('${joinPoint.signature.name} failed: $error');
/// ```
///
/// Spring (Java):
/// ```java
/// @AfterThrowing(
///     pointcut = "execution(* Calculator.*(..))", throwing = "error")
/// void failed(JoinPoint joinPoint, UnsupportedOperationException error) {
///   log.add(joinPoint.getSignature().getName() + " failed: " + error);
/// }
/// ```
class AfterThrowing {
  /// Creates `@AfterThrowing` advice for the [pointcut] expression.
  const AfterThrowing(this.pointcut, {this.throwing});

  /// The pointcut expression selecting the advised methods.
  final String pointcut;

  /// Name of the advice parameter that receives the error.
  final String? throwing;
}

/// Advice that wraps the method, like `@Around`. The method takes a
/// `ProceedingJoinPoint` and returns the result (usually
/// `joinPoint.proceed()`).
///
/// For methods returning a `Future`, `proceed()` returns that future;
/// return it (or another future) to keep the call asynchronous.
///
/// ```dart
/// @Around('@annotation(Timed)')
/// Object? time(ProceedingJoinPoint joinPoint) {
///   final watch = Stopwatch()..start();
///   try {
///     return joinPoint.proceed();
///   } finally {
///     print('${joinPoint.toShortString()} took ${watch.elapsed}');
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Around("@annotation(Timed)")
/// Object time(ProceedingJoinPoint joinPoint) throws Throwable {
///   long start = System.nanoTime();
///   try {
///     return joinPoint.proceed();
///   } finally {
///     System.out.println(joinPoint.toShortString() + " took "
///         + (System.nanoTime() - start));
///   }
/// }
/// ```
class Around {
  /// Creates `@Around` advice for the [pointcut] expression.
  const Around(this.pointcut);

  /// The pointcut expression selecting the advised methods.
  final String pointcut;
}
