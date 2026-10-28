/// Marks a bean class as an aspect: a bean whose advice methods run around
/// the calls of other beans.
///
/// Put it on a class whose methods carry `@Before`, `@After`,
/// `@AfterReturning`, `@AfterThrowing` or `@Around`. Each advice method
/// runs for the members its pointcut expression matches, in every bean the
/// generator wrote a proxy for. This is how an application adds logging,
/// timing, auditing or checks to many classes without editing them.
///
/// The aspect must also be a bean: add `@Component()` (or declare it with a
/// `@Bean` method). It can inject other beans as usual and is never
/// proxied itself. When several aspects advise the same call, `@Order` (or
/// implementing `Ordered`) decides: the lower value is the outer one, so its
/// `@Before` runs first and its `@After` last. Aspects without an order
/// come last.
///
/// ```dart
/// // Logs every call to the Calculator bean, before the other aspects.
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
/// [value] is the instantiation model, as in Spring. Empty (the default)
/// means one aspect instance for the whole application. `perthis(pointcut)`
/// gives one aspect instance per proxy, `pertarget(pointcut)` one per
/// target bean, so the aspect can keep state per advised object. Such an
/// aspect must be a prototype bean (`@Scope('prototype')`), and its advice
/// applies only where both the per-clause pointcut and the advice's own
/// pointcut match. A singleton per-instance aspect, `percflow` and
/// `pertypewithin` are rejected.
///
/// ```dart
/// // Counts the calls of each Orders proxy separately.
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
  /// Marks the class as an aspect with the instantiation model [value].
  const Aspect([this.value = '']);

  /// The instantiation model: empty for one shared instance (the default),
  /// `perthis(pointcut)` for one per proxy, `pertarget(pointcut)` for one
  /// per target bean.
  final String value;
}

/// Makes the proxies of matching beans implement an extra interface, with
/// an implementation the aspect supplies (an AspectJ "introduction").
///
/// Use it to add a capability to many beans without changing their
/// classes, for example a usage counter every service can report. Put it on
/// a static field of an `@Aspect` class: the field's type is the
/// interface to add. The proxy of every bean whose class matches the
/// [value] type pattern (`Orders`, `*Service`, `Repository+`) then
/// implements it and forwards its members to a [defaultImpl] instance,
/// created once per proxy on first use. Only beans of the aspect's own
/// module get the interface, and only while the aspect is registered.
/// Advice can receive the introduced object with `this(name)`.
///
/// ```dart
/// @Aspect()
/// @Component()
/// class UsageTracking {
///   // Every *Service bean also implements UsageTracked.
///   @DeclareParents('*Service+', defaultImpl: DefaultUsageTracked)
///   static UsageTracked? mixin;
///
///   // Each service call bumps that service's own counter.
///   @Before('execution(* *Service.*(..)) && this(usage)')
///   void count(UsageTracked usage) => usage.increment();
/// }
///
/// // Elsewhere: read the counter through the introduced interface.
/// final usage = context.getBean<OrderService>() as UsageTracked;
/// ```
///
/// Spring (Java):
/// ```java
/// @DeclareParents(value = "com.x.service.*+",
///     defaultImpl = DefaultUsageTracked.class)
/// public static UsageTracked mixin;
/// ```
class DeclareParents {
  /// Adds the field's interface to the proxies of beans matching [value],
  /// implemented by [defaultImpl].
  const DeclareParents(this.value, {required this.defaultImpl});

  /// The type pattern of the bean classes that get the interface: a name
  /// with `*` wildcards, and `+` for the type and its subtypes.
  final String value;

  /// The class implementing the interface; it needs a constructor without
  /// arguments. Each proxy gets its own instance.
  final Type defaultImpl;
}

/// Gives a pointcut expression a name, so several advice methods can share
/// it.
///
/// Put it on an empty method of an aspect; the method's body is never
/// called. Other pointcuts of the same aspect refer to it as `name()`;
/// pointcuts of another aspect write `AspectClass.name()`. Named pointcuts
/// of the aspect's superclasses and mixins are inherited.
///
/// ```dart
/// @Aspect()
/// @Component()
/// class AuditAspect {
///   // Every Calculator method, named once.
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
  /// Names [expression] after the annotated method.
  const Pointcut(this.expression);

  /// The pointcut expression, in the syntax `ExpressionPointcut` describes.
  final String expression;
}

/// Marks an aspect method to run before each matched call.
///
/// Use it for checks and logging that must happen before the method body.
/// The advice may take a `JoinPoint` to read the method and its arguments.
/// It cannot change the arguments or the result; throwing an error stops
/// the call, and the caller gets that error. On a method returning a
/// `Future` the advice may be `async`: the call waits for it before the
/// method runs. On a synchronous method an `async` advice fails the call
/// with an `AopInvocationException`.
///
/// ```dart
/// // Records each Calculator call before it runs.
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
  /// Runs the annotated method before calls matching [pointcut].
  const Before(this.pointcut);

  /// The pointcut expression selecting the advised methods.
  final String pointcut;
}

/// Marks an aspect method to run after each matched call, whether it
/// returned or threw, like a `finally` block.
///
/// Use it for clean-up and "call finished" logging. It cannot change the
/// result or the error. For a method returning a `Future`, it runs when the
/// future completes, not when the method returns.
///
/// ```dart
/// // Records the end of every Calculator call, even a failed one.
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
  /// Runs the annotated method after calls matching [pointcut].
  const After(this.pointcut);

  /// The pointcut expression selecting the advised methods.
  final String pointcut;
}

/// Marks an aspect method to run after each matched call that returned
/// normally, with the returned value.
///
/// Use it to inspect or log results. The parameter named [returning]
/// receives the value; without it, the first parameter that is neither the
/// `JoinPoint` nor bound by the pointcut does. The parameter's type
/// filters: the advice runs only when the value has that type. For a method
/// returning a `Future`, it runs when the future completes, with the
/// completed value. It cannot replace the result (use `@Around` for that).
///
/// ```dart
/// // Logs results that are ints; other results pass by.
/// @AfterReturning('execution(* Calculator.*(..))')
/// void returned(JoinPoint joinPoint, int result) =>
///     log.add('${joinPoint.signature.name}=$result');
///
/// // `timed` is bound by the pointcut, so `returning` names the result.
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
  /// Runs the annotated method after calls matching [pointcut] return.
  const AfterReturning(this.pointcut, {this.returning});

  /// The pointcut expression selecting the advised methods.
  final String pointcut;

  /// The name of the advice parameter that receives the returned value;
  /// `null` picks the first parameter that is neither the `JoinPoint` nor
  /// bound by the pointcut.
  final String? returning;
}

/// Marks an aspect method to run after each matched call that threw, with
/// the error.
///
/// Use it to log or count failures. The parameter named [throwing]
/// receives the error; without it, the first parameter that is neither the
/// `JoinPoint` nor bound by the pointcut does. The parameter's type
/// filters: the advice runs only for errors of that type. The error is
/// always rethrown afterwards, so the caller still sees it. For a method
/// returning a `Future`, it runs when the future fails.
///
/// ```dart
/// // Logs UnsupportedErrors of the Calculator; other errors pass by.
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
  /// Runs the annotated method after calls matching [pointcut] throw.
  const AfterThrowing(this.pointcut, {this.throwing});

  /// The pointcut expression selecting the advised methods.
  final String pointcut;

  /// The name of the advice parameter that receives the error; `null`
  /// picks the first parameter that is neither the `JoinPoint` nor bound by
  /// the pointcut.
  final String? throwing;
}

/// Marks an aspect method to run instead of each matched call, deciding
/// whether and how the real method runs.
///
/// It is the most powerful advice: it can time the call, change the
/// arguments, replace the result, retry, or skip the method entirely. The
/// advice takes a `ProceedingJoinPoint` and returns the call's result,
/// usually what `joinPoint.proceed()` returns; `proceed(args)` runs the
/// method with other arguments. For a method returning a `Future`,
/// `proceed()` returns that future: return it (or another future, for
/// example from an `async` advice that awaits it) so the call stays
/// asynchronous.
///
/// ```dart
/// // Prints how long each method marked @Timed() takes.
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
  /// Runs the annotated method instead of calls matching [pointcut].
  const Around(this.pointcut);

  /// The pointcut expression selecting the advised methods.
  final String pointcut;
}
