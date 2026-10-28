/// Whether an advised member is a method, a getter or a setter.
///
/// Dart has getters and setters as members of their own, and a public
/// field is an implicit getter (and setter, unless `final`); proxies advise
/// them like methods. Advice reads the kind from
/// [MethodSignature.kind] when it must treat property access differently.
/// Only methods match `execution(...)` pointcuts; getters and setters are
/// reached through `within`, `bean`, `target`, `@annotation`, ... or a
/// custom [MethodInterceptor].
///
/// ```dart
/// // Logs the calls to Account, but not the getter reads.
/// @Before('within(Account)')
/// void audit(JoinPoint joinPoint) {
///   if (joinPoint.signature.kind != MemberKind.getter) {
///     log.add(joinPoint.toShortString());
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// // No equivalent: Spring AOP intercepts methods only, and getters and
/// // setters are ordinary methods matched by name.
/// @Before("execution(* Account.get*())")
/// void beforeGetter(JoinPoint joinPoint) { ... }
/// ```
enum MemberKind {
  /// A method; the only kind `execution(...)` matches.
  method,

  /// A getter, explicit or the implicit one of a public field.
  getter,

  /// A setter, explicit or the implicit one of a non-final public field.
  /// Its name has no `=` (`count`, not `count=`).
  setter,
}

/// What is known about an advised member without calling it: its name,
/// its types, its annotations and those of its class.
///
/// Dart has no runtime reflection, so the generator writes one constant
/// per proxied member. Pointcuts match against it, and advice reads it
/// from [JoinPoint.signature] to know which member is being called: for
/// a log line, a metric name, or the member's annotations (a `@Timed`
/// threshold, a cache name). Applications read it, never create it.
///
/// Type names are simple class names without type arguments (`Future`,
/// not `Future<int>`), written at build time so they survive minified
/// builds.
///
/// ```dart
/// // Logs "int add(int, int)" style lines before each Calculator call.
/// @Before('execution(* Calculator.*(..))')
/// void before(JoinPoint joinPoint) {
///   final signature = joinPoint.signature;
///   log.info('${signature.returnType} ${signature.name}'
///       '(${signature.parameterTypes.join(', ')})');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Before("execution(* Calculator.*(..))")
/// void before(JoinPoint joinPoint) {
///   MethodSignature signature = (MethodSignature) joinPoint.getSignature();
///   log.info(signature.getReturnType() + " "
///       + signature.getName()
///       + Arrays.toString(signature.getParameterTypes()));
/// }
/// ```
final class MethodSignature {
  /// Describes the member [name]; written by the generator, one per
  /// proxied member.
  const MethodSignature({
    required this.name,
    required this.declaringType,
    required this.targetType,
    this.declaringTypes = const [],
    this.kind = MemberKind.method,
    this.returnType = 'dynamic',
    this.parameterTypes = const [],
    this.parameterNames = const [],
    this.parameterAnnotations = const [],
    this.annotations = const [],
    this._mergedAnnotations,
    this.targetTypes = const [],
    this.targetAnnotations = const [],
    this.annotationTypes = const [],
    this.targetAnnotationTypes = const [],
    this.implementingTypes = const [],
    this.implementingTypeAnnotations,
    this.implementingTypeAnnotationTypes,
    this.superclassAnnotations = const [],
    this.isProtected = false,
  });

  /// The member's name, such as `add`; a setter's name has no `=`.
  final String name;

  /// The most abstract type that declares the member, such as the
  /// interface `Calculator` rather than the class `SimpleCalculator`.
  final String declaringType;

  /// Every type of the bean that declares the member; the type part of an
  /// `execution` pattern matches any of them.
  final List<String> declaringTypes;

  /// The bean's class, such as `SimpleCalculator`.
  final String targetType;

  /// Whether the member is a method, a getter or a setter.
  final MemberKind kind;

  /// The return type's name without type arguments; `void` when it
  /// returns nothing, `dynamic` when unknown.
  final String returnType;

  /// The parameter types' names, without type arguments.
  final List<String> parameterTypes;

  /// The parameter names, in the order of [JoinPoint.args] (positional
  /// ones, then named ones). Expressions read arguments by these names,
  /// such as the cache key `'#isbn'`.
  final List<String> parameterNames;

  /// The annotations of each parameter, in the order of [parameterNames],
  /// taken from both the interface and the implementation. Method
  /// validation reads constraints and `@Valid` here. Empty when no
  /// parameter has annotations.
  final List<List<Object>> parameterAnnotations;

  /// The annotations on the member that `@annotation(...)` pointcuts match:
  /// those of the method that runs and of the interface methods it
  /// implements. As in AspectJ, an annotation that is only on a superclass
  /// or mixin method it overrides does not count; see [mergedAnnotations].
  final List<Object> annotations;

  final List<Object>? _mergedAnnotations;

  /// The annotations on the member and on every declaration it overrides
  /// or implements (superclasses, mixins, interfaces), most specific
  /// first, as Spring's `AnnotatedElementUtils` finds them.
  ///
  /// Annotation-driven advisors read these, so `@Cacheable` on a
  /// superclass method still applies to an override without it, as with
  /// Spring's `AnnotationCacheOperationSource`. `@annotation(...)`
  /// pointcuts match [annotations] only.
  List<Object> get mergedAnnotations => _mergedAnnotations ?? annotations;

  /// The names of the bean class and all its supertypes, for
  /// `target(Type)` and `this(Type)`.
  final List<String> targetTypes;

  /// The annotations on the bean class, for `@target(...)`.
  final List<Object> targetAnnotations;

  /// The class names of [annotations], written by the generator.
  /// `@annotation(Timed)` matches these names rather than
  /// `runtimeType.toString()`, which is minified in release builds
  /// (dart2js, `--obfuscate`).
  final List<String> annotationTypes;

  /// The class names of [targetAnnotations], for the same reason as
  /// [annotationTypes].
  final List<String> targetAnnotationTypes;

  /// The class whose body runs for the member (the bean class, or the
  /// superclass or mixin it inherits the member from), then its
  /// supertypes. Empty means `[targetType, ...targetTypes]`.
  ///
  /// `within(Base)` matches a member whose body is in `Base`, as AspectJ's
  /// `within` selects join points by lexical scope: an inherited method of
  /// `Base` matches `within(Base)`, not `within(Sub)`.
  final List<String> implementingTypes;

  /// The annotations on [implementingType], for `@within(...)`; `null`
  /// when that is the bean class, whose annotations are
  /// [targetAnnotations].
  final List<Object>? implementingTypeAnnotations;

  /// The class names of [implementingTypeAnnotations]; `null` when that is
  /// the bean class ([targetAnnotationTypes]).
  final List<String>? implementingTypeAnnotationTypes;

  /// The annotations of each superclass and mixin of [implementingType]
  /// that has some, nearest first. Read them through
  /// [implementingTypeHierarchyAnnotations].
  final List<List<Object>> superclassAnnotations;

  /// The annotations on [implementingType], then on its superclasses and
  /// mixins, nearest first.
  ///
  /// Advisors that honour class-level annotations read this, such as
  /// `@CacheConfig` or a `@Cacheable` on the class: it is the hierarchy
  /// Spring's `AnnotationUtils.findAnnotation` searches from
  /// `method.getDeclaringClass()`.
  List<Object> get implementingTypeHierarchyAnnotations => [
    ...(implementingTypeAnnotations ?? targetAnnotations),
    for (final level in superclassAnnotations) ...level,
  ];

  /// Whether the member is annotated `@protected` (`package:meta`), the
  /// closest Dart has to Java's `protected`; `execution(protected ...)`
  /// matches it.
  final bool isProtected;

  /// The class whose body runs for the member: the bean class, or the
  /// superclass or mixin it inherits the member from. `within(...)`
  /// matches it.
  String get implementingType =>
      implementingTypes.isEmpty ? targetType : implementingTypes.first;

  /// [implementingType] and its supertypes, for `within(Type+)`.
  List<String> get implementingTypeHierarchy => implementingTypes.isEmpty
      ? [targetType, ...targetTypes]
      : implementingTypes;

  /// The declaring type and the member name for logs, such as
  /// `Greeter.greet(..)`.
  String toShortString() => '$declaringType.$name(..)';

  @override
  String toString() =>
      '$returnType $declaringType.$name(${parameterTypes.join(', ')})';
}

/// One intercepted call, as advice sees it: which member is called, on
/// which bean, with which arguments.
///
/// Advice methods receive it when they declare a parameter of this type;
/// `@Before`, `@After`, `@AfterReturning` and `@AfterThrowing` advice may,
/// `@Around` advice takes a [ProceedingJoinPoint] instead. Use it to log
/// the call, to name a metric after the member, or to read the member's
/// annotations through [signature]. Its [args] are a copy: changing them
/// does not change the call.
///
/// ```dart
/// // Logs each call to the `calculator` bean with its arguments.
/// @Before('bean(calculator)')
/// void before(JoinPoint joinPoint) =>
///     log.info('${joinPoint.toShortString()} with ${joinPoint.args}');
/// ```
///
/// Spring (Java):
/// ```java
/// @Before("bean(calculator)")
/// void before(JoinPoint joinPoint) {
///   log.info(joinPoint.toShortString() + " with "
///       + Arrays.toString(joinPoint.getArgs()));
/// }
/// ```
abstract interface class JoinPoint {
  /// The proxy the caller called, the object other beans hold. For a
  /// generated subclass proxy it is the bean itself, like [target].
  Object get proxy;

  /// The bean whose member runs: the object behind the proxy.
  Object get target;

  /// The called member: its name, types and annotations.
  MethodSignature get signature;

  /// The arguments in declaration order: positional ones, then named ones
  /// (in the order of [MethodSignature.parameterNames]).
  List<Object?> get args;

  /// A short description for logs, such as `execution(Greeter.greet(..))`.
  String toShortString();
}

/// The [JoinPoint] of `@Around` advice, which can also run the call.
///
/// An `@Around` advice replaces the call, so it needs a way to run the
/// real method (or the next advice) when it chooses to: [proceed]. Calling
/// it with new arguments changes what the method receives; not calling it
/// skips the method; calling it again retries. An `@Around` advice method
/// must take one.
///
/// ```dart
/// // Keeps the second factor of `multiply` between 0 and 10.
/// @Around('execution(* Calculator.multiply(..))')
/// Object? clamp(ProceedingJoinPoint joinPoint) {
///   final [a, b] = joinPoint.args;
///   return joinPoint.proceed([a, (b! as int).clamp(0, 10)]);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Around("execution(* Calculator.multiply(..))")
/// Object clamp(ProceedingJoinPoint joinPoint) throws Throwable {
///   Object[] args = joinPoint.getArgs();
///   args[1] = Math.min(Math.max((int) args[1], 0), 10);
///   return joinPoint.proceed(args);
/// }
/// ```
abstract interface class ProceedingJoinPoint implements JoinPoint {
  /// Runs the next advice, or the member itself after the last one, and
  /// returns its result.
  ///
  /// [args] replaces the arguments and must have as many elements as the
  /// call has arguments, else an [ArgumentError] is thrown. Without it the
  /// current arguments are used. Errors of the call propagate. For a
  /// member returning a `Future`, the result is that future, not its value.
  Object? proceed([List<Object?>? args]);
}

/// One intercepted call as a [MethodInterceptor] sees it: the call's
/// details plus a way to continue it.
///
/// Every advised call passes through a chain of interceptors, outermost
/// first, and each one receives a `MethodInvocation`. An interceptor
/// written by hand (for a `PointcutAdvisor` bean) gets it in
/// [MethodInterceptor.invoke]; aspect advice sees a [JoinPoint] instead.
/// Unlike a join point, its [args] are the live arguments: an interceptor
/// may change them in place before calling [proceed]. For a member
/// returning a `Future`, it is also an `AsyncMethodInvocation`.
///
/// ```dart
/// // Logs each call on the way in.
/// class LoggingInterceptor implements MethodInterceptor {
///   @override
///   Object? invoke(MethodInvocation invocation) {
///     log.info('-> ${invocation.signature.name}${invocation.args}');
///     return invocation.proceed();
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class LoggingInterceptor implements MethodInterceptor {
///   public Object invoke(MethodInvocation invocation) throws Throwable {
///     log.info("-> " + invocation.getMethod().getName());
///     return invocation.proceed();
///   }
/// }
/// ```
abstract interface class MethodInvocation implements ProceedingJoinPoint {
  /// The arguments the next step receives; an interceptor may change
  /// them in place before calling [proceed].
  @override
  List<Object?> get args;
}

/// Code that runs around calls of other beans, written as a class instead
/// of an `@Aspect` method.
///
/// Implement it when the advice should be a reusable object: a library's
/// cache or security check, or advice configured in code. Pair it with a
/// pointcut in a `DefaultPointcutAdvisor` bean, and the container applies
/// it to every proxied bean member the pointcut matches. In [invoke] it
/// decides everything an `@Around` advice can: call
/// `invocation.proceed()` or not, change the arguments, replace the result.
/// Applications with one-off advice usually write an `@Aspect` instead.
///
/// ```dart
/// // Upper-cases every String the echoShouter bean returns.
/// class UpperCaseInterceptor implements MethodInterceptor {
///   @override
///   Object? invoke(MethodInvocation invocation) =>
///       (invocation.proceed()! as String).toUpperCase();
/// }
///
/// @Configuration()
/// class AopConfig {
///   @Bean()
///   PointcutAdvisor upperCase() => DefaultPointcutAdvisor(
///     ExpressionPointcut('bean(echoShouter)'),
///     UpperCaseInterceptor(),
///   );
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class UpperCaseInterceptor implements MethodInterceptor {
///   public Object invoke(MethodInvocation invocation) throws Throwable {
///     return ((String) invocation.proceed()).toUpperCase();
///   }
/// }
///
/// @Configuration
/// class AopConfig {
///   @Bean
///   Advisor upperCase() {
///     AspectJExpressionPointcut pointcut = new AspectJExpressionPointcut();
///     pointcut.setExpression("bean(echoShouter)");
///     return new DefaultPointcutAdvisor(pointcut, new UpperCaseInterceptor());
///   }
/// }
/// ```
abstract interface class MethodInterceptor {
  /// Runs around [invocation] and returns the call's result.
  ///
  /// Call `invocation.proceed()` to run the next interceptor or the member
  /// itself, and return its result or a replacement. Not calling it skips
  /// the member. An error thrown here reaches the caller.
  Object? invoke(MethodInvocation invocation);
}
