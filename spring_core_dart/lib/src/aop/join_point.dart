/// Kind of proxied member.
///
/// Only [MemberKind.method]s match `execution(...)` pointcuts; getters and
/// setters can still be advised through other designators (`bean`,
/// `@annotation`, ...) or custom [MethodInterceptor] advisors.
///
/// ```dart
/// if (joinPoint.signature.kind == MemberKind.getter) { ... }
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
  /// A regular method.
  method,

  /// A getter.
  getter,

  /// A setter.
  setter,
}

/// Static description of a proxied member, like Spring's
/// `MethodSignature`.
///
/// Instances are created by generated proxy code; advice reads them from
/// [JoinPoint.signature].
///
/// ```dart
/// @Before('execution(* Calculator.*(..))')
/// void before(JoinPoint joinPoint) {
///   final signature = joinPoint.signature;
///   print('${signature.returnType} ${signature.name}'
///       '(${signature.parameterTypes.join(', ')})');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Before("execution(* Calculator.*(..))")
/// void before(JoinPoint joinPoint) {
///   MethodSignature signature = (MethodSignature) joinPoint.getSignature();
///   System.out.println(signature.getReturnType() + " "
///       + signature.getName()
///       + Arrays.toString(signature.getParameterTypes()));
/// }
/// ```
final class MethodSignature {
  /// Creates the description of member [name] (used by generated code).
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

  /// The member name, e.g. `add`.
  final String name;

  /// The (most abstract) type that declares the member.
  final String declaringType;

  /// Every type of the bean that declares the member; `execution` type
  /// patterns match any of them.
  final List<String> declaringTypes;

  /// The bean class.
  final String targetType;

  /// Whether the member is a method, getter or setter.
  final MemberKind kind;

  /// Return type name (`void` for none), without type arguments.
  final String returnType;

  /// Parameter type names, without type arguments.
  final List<String> parameterTypes;

  /// Parameter names, in the order of `JoinPoint.args` (positional, then
  /// named); used e.g. by cache keys such as `key: '#isbn'`.
  final List<String> parameterNames;

  /// Const annotations of each parameter, in the order of [parameterNames]
  /// (interface and implementation); used e.g. by method validation
  /// (constraints and `@Valid` on parameters). Empty when no parameter
  /// has annotations.
  final List<List<Object>> parameterAnnotations;

  /// Const annotations on the member: those of the method that runs and of
  /// its interface declarations, what `@annotation(...)` pointcuts match
  /// (like AspectJ, not those of a superclass or mixin method it
  /// overrides; see [mergedAnnotations]).
  final List<Object> annotations;

  final List<Object>? _mergedAnnotations;

  /// Const annotations on the member and on every declaration it
  /// overrides or implements (superclasses, mixins, interfaces), most
  /// specific first, like Spring's `AnnotatedElementUtils` find semantics.
  ///
  /// Annotation-driven advisors read these (`@Cacheable` on a superclass
  /// method still applies to an override without it, as with Spring's
  /// `AnnotationCacheOperationSource`); `@annotation(...)` matches
  /// [annotations] only.
  List<Object> get mergedAnnotations => _mergedAnnotations ?? annotations;

  /// Names of the bean class and all its supertypes.
  final List<String> targetTypes;

  /// Const annotations on the bean class.
  final List<Object> targetAnnotations;

  /// Class names of [annotations], written by the generator. Pointcuts
  /// such as `@annotation(Timed)` match these names, because
  /// `runtimeType.toString()` is minified in release builds (dart2js,
  /// `--obfuscate`).
  final List<String> annotationTypes;

  /// Class names of [targetAnnotations] (see [annotationTypes]).
  final List<String> targetAnnotationTypes;

  /// The class whose body runs for the member (the bean class, or the
  /// superclass or mixin it inherits the member from), then its
  /// supertypes. Empty means `[targetType, ...targetTypes]`.
  ///
  /// `within(Base)` matches a member whose body is in `Base`, as AspectJ's
  /// `within` selects join points by lexical scope: an inherited method of
  /// `Base` matches `within(Base)`, not `within(Sub)`.
  final List<String> implementingTypes;

  /// Const annotations on the class of [implementingTypes] (for
  /// `@within`); `null` when it is the bean class ([targetAnnotations]).
  final List<Object>? implementingTypeAnnotations;

  /// Class names of [implementingTypeAnnotations]; `null` when it is the
  /// bean class ([targetAnnotationTypes]).
  final List<String>? implementingTypeAnnotationTypes;

  /// Const annotations on each superclass and mixin (those that have some)
  /// of the class whose body runs for the member ([implementingType]),
  /// nearest first; see [implementingTypeHierarchyAnnotations].
  final List<List<Object>> superclassAnnotations;

  /// Const annotations on the class whose body runs for the member (the
  /// bean class, or the superclass or mixin it inherits the member from),
  /// then on its superclasses and mixins, nearest first: the class
  /// hierarchy Spring's `AnnotationUtils.findAnnotation` searches from
  /// `method.getDeclaringClass()` (`@CacheConfig`, class-level
  /// `@Cacheable`).
  List<Object> get implementingTypeHierarchyAnnotations => [
    ...(implementingTypeAnnotations ?? targetAnnotations),
    for (final level in superclassAnnotations) ...level,
  ];

  /// Whether the member is annotated `@protected` (`package:meta`), the
  /// closest Dart has to Java's `protected` (`execution(protected ...)`).
  final bool isProtected;

  /// The class whose body runs for the member, for `within`.
  String get implementingType =>
      implementingTypes.isEmpty ? targetType : implementingTypes.first;

  /// [implementingType] and its supertypes, for `within(Type+)`.
  List<String> get implementingTypeHierarchy => implementingTypes.isEmpty
      ? [targetType, ...targetTypes]
      : implementingTypes;

  /// `Greeter.greet(..)`.
  String toShortString() => '$declaringType.$name(..)';

  @override
  String toString() =>
      '$returnType $declaringType.$name(${parameterTypes.join(', ')})';
}

/// A method call intercepted by AOP, like Spring's `JoinPoint`.
///
/// `@Before`, `@After`, `@AfterReturning` and `@AfterThrowing` advice may
/// take it as their first parameter.
///
/// ```dart
/// @Before('bean(calculator)')
/// void before(JoinPoint joinPoint) =>
///     print('${joinPoint.toShortString()} with ${joinPoint.args}');
/// ```
///
/// Spring (Java):
/// ```java
/// @Before("bean(calculator)")
/// void before(JoinPoint joinPoint) {
///   System.out.println(joinPoint.toShortString() + " with "
///       + Arrays.toString(joinPoint.getArgs()));
/// }
/// ```
abstract interface class JoinPoint {
  /// The proxy.
  Object get proxy;

  /// The proxied bean.
  Object get target;

  /// Static description of the called member.
  MethodSignature get signature;

  /// Arguments in declaration order (positional, then named).
  List<Object?> get args;

  /// `execution(Greeter.greet(..))`.
  String toShortString();
}

/// A [JoinPoint] that `@Around` advice uses to continue the call.
///
/// ```dart
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
  /// Calls the next advice or the target; [args] replaces the arguments.
  ///
  /// For a method returning a `Future`, the result is that future.
  Object? proceed([List<Object?>? args]);
}

/// A call travelling through the interceptor chain, like AOP Alliance's
/// `MethodInvocation`.
///
/// ```dart
/// class LoggingInterceptor implements MethodInterceptor {
///   @override
///   Object? invoke(MethodInvocation invocation) {
///     print('-> ${invocation.signature.name}${invocation.args}');
///     return invocation.proceed();
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class LoggingInterceptor implements MethodInterceptor {
///   public Object invoke(MethodInvocation invocation) throws Throwable {
///     System.out.println("-> " + invocation.getMethod().getName());
///     return invocation.proceed();
///   }
/// }
/// ```
abstract interface class MethodInvocation implements ProceedingJoinPoint {
  /// Arguments; interceptors may change them before [proceed].
  @override
  List<Object?> get args;
}

/// Wraps calls, like AOP Alliance's `MethodInterceptor`.
///
/// Combine it with a pointcut in a `DefaultPointcutAdvisor` bean to
/// advise matching beans without an `@Aspect`.
///
/// ```dart
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
  /// Handles [invocation]; call `invocation.proceed()` to continue the
  /// chain and return (or replace) its result.
  Object? invoke(MethodInvocation invocation);
}
