import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/core/order.dart';
import 'package:spring_core_dart/src/validation/bean_validator.dart';

/// An annotation that asks for validation, optionally with validation
/// groups.
///
/// Where you put it decides what is checked:
///
/// - On a bean class (`@Service()`, `@Component()`, ...): every call to its
///   methods is checked. Constraints on a parameter check the argument,
///   constraints on the method check the returned value, and `@Valid()`
///   checks the constraints inside an argument or result object. A
///   violation throws a [ConstraintViolationException] before the method
///   runs (or after it, for the result). This is how a service guards its
///   inputs whoever calls it; Spring Boot's auto-configuration provides
///   the [MethodValidationPostProcessor] that does it.
/// - On a method of such a class: only picks the groups for that method.
///   On its own, without `@Validated()` on the class, it turns nothing on.
/// - On a controller's `@RequestBody` or `@RequestPart` parameter: like
///   `@Valid()`, the object is checked and a violation is answered with a
///   400, but with the groups in [value].
/// - On a `@ConfigurationProperties` class: the bound values are checked
///   at startup, and an invalid one stops the application with a report.
///
/// A [ConstraintViolationException] from a service is not turned into a
/// 400 by the web starter: catch it in an `@ExceptionHandler` if a client
/// can cause it.
///
/// ```dart
/// // Callers cannot register an empty or malformed address, and the
/// // service never returns a blank id.
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
  /// Asks for validation with the groups [value] (none: the `Default`
  /// group).
  const Validated([this.value = const []]);

  /// The validation groups to check, such as `[OnUpdate]`; empty means
  /// only the constraints without groups (the `Default` group).
  final List<Type> value;
}

/// The AOP advice that checks the arguments and the return value of a
/// call against the method's constraints.
///
/// Before the call it checks the constraints on the parameters and the
/// insides of `@Valid()` parameters; after it, the constraints on the
/// method and, with `@Valid()` on the method, the inside of the result.
/// Violations throw a [ConstraintViolationException]; for a method that
/// returns a `Future`, the future completes with it. The groups come from
/// `@Validated` on the method, else on the class.
///
/// Applications do not create it: [MethodValidationPostProcessor] wraps
/// one, and Spring Boot registers that. Build one yourself only to apply
/// method validation with your own pointcut.
///
/// ```dart
/// // Method validation for the beans of classes annotated @Validated.
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
  /// An interceptor that checks with [validator]; by default a new
  /// [BeanValidator] on `BeanIntrospector.shared`.
  MethodValidationInterceptor([BeanValidator? validator])
    : validator = validator ?? BeanValidator();

  /// The validator that checks the arguments and results; its message
  /// source and clock apply.
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

  /// The validation groups for a call of [signature]: those of
  /// `@Validated` on the method, else on a declaration it overrides (the
  /// nearest first), else on the bean class; empty when none names any.
  ///
  /// Spring finds them the same way, with
  /// `AnnotationUtils.findAnnotation`.
  static List<Type> determineValidationGroups(MethodSignature signature) =>
      (signature.mergedAnnotations.whereType<Validated>().firstOrNull ??
              signature.targetAnnotations.whereType<Validated>().firstOrNull)
          ?.value ??
      const [];
}

/// The bean that turns on method validation: it applies a
/// [MethodValidationInterceptor] to every bean whose class is annotated
/// `@Validated()`.
///
/// Spring Boot's auto-configuration registers one as
/// `methodValidationPostProcessor`, using the application's
/// [BeanValidator] bean and leaving `@ConfigurationProperties` classes
/// out. Declare your own only without Spring Boot, or to change the
/// validator or the exclusions; Boot then backs off.
///
/// Despite its name it is an advisor, not a post-processor: proxies are
/// generated at build time, so the context's auto proxy creator applies it
/// like any advisor bean, also to beans that other advice already proxies.
///
/// ```dart
/// // Method validation in a context without Spring Boot.
/// @Configuration()
/// class ValidationConfig {
///   @Bean()
///   MethodValidationPostProcessor methodValidationPostProcessor(
///     BeanIntrospector introspector,
///   ) => MethodValidationPostProcessor(
///       BeanValidator(introspector: introspector));
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
  /// An advisor that checks with [validator] (by default a new
  /// [BeanValidator] on `BeanIntrospector.shared`).
  ///
  /// Beans whose class annotations make one of [excludeFilters] return
  /// `true` are left alone; Spring Boot passes one that excludes
  /// `@ConfigurationProperties` classes (Spring Boot's
  /// `MethodValidationExcludeFilter`).
  MethodValidationPostProcessor([
    BeanValidator? validator,
    List<bool Function(List<Object> classAnnotations)> excludeFilters =
        const [],
  ]) : advice = MethodValidationInterceptor(validator),
       excludeFilters = List.unmodifiable(excludeFilters);

  @override
  final MethodValidationInterceptor advice;

  /// Tests on the annotations of a bean class; a bean is not validated
  /// when one returns `true`.
  final List<bool Function(List<Object> classAnnotations)> excludeFilters;

  /// Matches the methods of beans whose class is annotated `@Validated()`
  /// and not excluded by [excludeFilters].
  @override
  AnnotationPointcut get pointcut => _ValidatedPointcut(excludeFilters);

  /// [Ordered.lowestPrecedence]: validation runs innermost, after other
  /// advice such as caching, like Spring's validation advisor, which is
  /// added after the existing ones.
  @override
  int get order => Ordered.lowestPrecedence;

  @override
  String toString() => 'MethodValidationPostProcessor';
}

final class _ValidatedPointcut implements AnnotationPointcut {
  const _ValidatedPointcut(this.excludeFilters);

  final List<bool Function(List<Object> classAnnotations)> excludeFilters;

  @override
  bool matches(MethodSignature signature, String beanName) =>
      const AnnotationMatchingPointcut<Validated>(onClass: true)
          .matches(signature, beanName) &&
      !excludeFilters.any((exclude) => exclude(signature.targetAnnotations));
}
