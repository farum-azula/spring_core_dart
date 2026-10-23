import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/core/order.dart';
import 'package:spring_core_dart/src/validation/bean_validator.dart';

/// Turns on method validation for a bean class (constraints and `@Valid`
/// on parameters and on methods for their return values), like Spring's
/// `@Validated`; on a method it selects the validation groups of that
/// method.
///
/// [value] lists the validation groups (empty: `Default`).
///
/// ```dart
/// @Service()
/// @Validated()
/// class Registration {
///   @NotBlank()
///   String register(@Email() @NotBlank() String email) => 'id-$email';
/// }
///
/// registration.register(''); // throws ConstraintViolationException
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// @Validated
/// class Registration {
///   @NotBlank String register(@Email @NotBlank String email) { ... }
/// }
/// ```
class Validated {
  /// Validates the annotated class's methods with the groups [value].
  const Validated([this.value = const []]);

  /// Validation groups; empty means `Default`.
  final List<Type> value;
}

/// Validates the arguments and the return value of calls, like Spring's
/// `MethodValidationInterceptor`: constraints on parameters and `@Valid`
/// parameters before the call, constraints on the method (and `@Valid` on
/// it) for the returned value after it. Violations throw a
/// [ConstraintViolationException] (for methods returning a `Future`, the
/// future completes with it).
///
/// Groups come from `@Validated` on the method, else on the class.
///
/// ```dart
/// final advisor = DefaultPointcutAdvisor(
///   const AnnotationMatchingPointcut<Validated>(onClass: true),
///   MethodValidationInterceptor(BeanValidator(introspector: introspector)),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// new DefaultPointcutAdvisor(
///     new AnnotationMatchingPointcut(Validated.class, true),
///     new MethodValidationInterceptor(validator));
/// ```
final class MethodValidationInterceptor implements MethodInterceptor {
  /// An interceptor validating with [validator] (a [BeanValidator] on the
  /// shared introspector by default).
  MethodValidationInterceptor([BeanValidator? validator])
    : validator = validator ?? BeanValidator();

  /// Checks the constraints.
  final BeanValidator validator;

  @override
  Object? invoke(MethodInvocation invocation) {
    final signature = invocation.signature;
    final groups = determineValidationGroups(signature);
    final arguments = validator.validateParameters(
      invocation.target,
      signature,
      invocation.args,
      groups: groups,
    );
    final async = invocation is AsyncMethodInvocation;
    if (arguments.isNotEmpty) {
      final error = ConstraintViolationException(arguments);
      return async ? Future<Object?>.error(error) : throw error;
    }
    final result = invocation.proceed();
    void checkResult(Object? value) {
      final violations = validator.validateReturnValue(
        invocation.target,
        signature,
        value,
        groups: groups,
      );
      if (violations.isNotEmpty) {
        throw ConstraintViolationException(violations);
      }
    }

    if (result is Future && invocation is AsyncMethodInvocation) {
      return invocation.chain(result, onValue: checkResult);
    }
    checkResult(result);
    return result;
  }

  /// The groups of `@Validated` on the method, else on the bean class.
  static List<Type> determineValidationGroups(MethodSignature signature) =>
      (signature.annotations.whereType<Validated>().firstOrNull ??
              signature.targetAnnotations.whereType<Validated>().firstOrNull)
          ?.value ??
      const [];
}

/// The advisor that applies a [MethodValidationInterceptor] to the beans
/// of classes annotated with `@Validated`, like Spring's
/// `MethodValidationPostProcessor` (Spring Boot registers one as
/// `methodValidationPostProcessor`).
///
/// Unlike Spring's, it is not a post-processor itself: proxies are
/// generated, so the context's auto proxy creator applies it like any
/// advisor bean (and also to beans that other advice proxies already).
///
/// ```dart
/// @Configuration()
/// class ValidationConfig {
///   @Bean()
///   MethodValidationPostProcessor methodValidationPostProcessor(
///     BeanIntrospector introspector,
///   ) => MethodValidationPostProcessor(BeanValidator(introspector: introspector));
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// static MethodValidationPostProcessor methodValidationPostProcessor() {
///   return new MethodValidationPostProcessor();
/// }
/// ```
final class MethodValidationPostProcessor implements PointcutAdvisor, Ordered {
  /// An advisor validating with [validator] (see
  /// [MethodValidationInterceptor]).
  MethodValidationPostProcessor([BeanValidator? validator])
    : advice = MethodValidationInterceptor(validator);

  @override
  final MethodValidationInterceptor advice;

  /// Members of `@Validated` bean classes.
  @override
  AopPointcut get pointcut =>
      const AnnotationMatchingPointcut<Validated>(onClass: true);

  /// Innermost, like Spring's validation advisor added after the existing
  /// ones.
  @override
  int get order => Ordered.lowestPrecedence;

  @override
  String toString() => 'MethodValidationPostProcessor';
}
