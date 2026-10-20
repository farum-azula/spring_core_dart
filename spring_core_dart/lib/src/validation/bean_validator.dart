import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';
import 'package:spring_core_dart/src/validation/constraints.dart';
import 'package:spring_core_dart/src/validation/errors.dart';
import 'package:spring_core_dart/src/validation/validator.dart';

/// One failed constraint, like Jakarta's `ConstraintViolation`.
///
/// Returned by the Jakarta-style methods of [BeanValidator]
/// ([BeanValidator.validateObject], [BeanValidator.validateProperty],
/// [BeanValidator.validateValue]).
///
/// ```dart
/// for (final v in BeanValidator().validateObject(form)) {
///   print('${v.propertyPath}: ${v.message}'); // name: must not be blank
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// for (ConstraintViolation<SignupForm> v : validator.validate(form)) {
///   System.out.println(v.getPropertyPath() + ": " + v.getMessage());
/// }
/// ```
final class ConstraintViolation {
  /// Creates a violation of [constraint] at [propertyPath].
  const ConstraintViolation({
    required this.propertyPath,
    required this.constraint,
    required this.invalidValue,
    required this.message,
    this.rootBean,
  });

  /// `name`, `address.city`, `items[0].sku`; empty for class-level ones.
  final String propertyPath;

  /// The constraint that failed.
  final Constraint constraint;

  /// The value that failed (the object itself for class-level ones).
  final Object? invalidValue;

  /// The interpolated message, e.g. `size must be between 0 and 20`.
  final String message;

  /// The object validation started from; `null` for [BeanValidator.validateValue],
  /// where no instance exists (Spring's `getRootBean()` is `null` there too).
  final Object? rootBean;

  @override
  String toString() => '$propertyPath: $message';
}

/// Validates `@Introspected` objects against their [Constraint]
/// annotations, like Spring's `LocalValidatorFactoryBean` over Jakarta
/// Bean Validation.
///
/// Field errors use the constraint name as code (`NotBlank`) and, like
/// Spring, arguments `[field resolvable, ...attribute values sorted by
/// attribute name]`, so messages can be customized in a `MessageSource`.
///
/// ```dart
/// @Introspected()
/// class SignupForm {
///   @NotBlank()
///   @Size(max: 20)
///   String name = '';
///
///   @Min(18)
///   int age = 0;
/// }
///
/// final form = SignupForm();
/// final binder = DataBinder(form, objectName: 'signup')
///   ..validators.add(BeanValidator())
///   ..bind({'name': 'Ada', 'age': '17'})
///   ..validate();
/// binder.bindingResult.fieldError('age')!.defaultMessage;
/// // 'must be greater than or equal to 18'
///
/// // {0} is the field, {1} the `value` attribute.
/// final messages = StaticMessageSource()
///   ..addMessage('Min', '', '{0} must be at least {1}');
/// ```
///
/// Spring (Java):
/// ```java
/// class SignupForm {
///   @NotBlank @Size(max = 20) private String name;
///   @Min(18) private int age;
/// }
///
/// LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
/// validator.afterPropertiesSet();
/// DataBinder binder = new DataBinder(form, "signup");
/// binder.setValidator(validator);
/// binder.bind(new MutablePropertyValues(Map.of("name", "Ada", "age", "17")));
/// binder.validate();
/// ```
class BeanValidator implements SmartValidator {
  /// Creates a validator reading constraints through [introspector]
  /// (the shared one by default).
  BeanValidator({BeanIntrospector? introspector})
    : introspector = introspector ?? BeanIntrospector.shared;

  /// Source of the constraint annotations and property values.
  final BeanIntrospector introspector;

  @override
  bool supports(Object target) =>
      introspector.findIntrospection(target) != null;

  @override
  void validate(Object target, Errors errors) =>
      validateWithGroups(target, errors, const []);

  @override
  void validateWithGroups(Object target, Errors errors, List<Type> groups) {
    for (final violation in validateObject(target, groups: groups)) {
      final constraint = violation.constraint;
      final attributes = constraint.attributes;
      // Like Spring's SpringValidatorAdapter: argument {0} resolves the
      // field name itself (codes `signup.name`, `name`), followed by the
      // constraint attributes in alphabetical order ({1}, {2}, ...).
      final args = [
        if (violation.propertyPath.isNotEmpty)
          DefaultMessageSourceResolvable([
            '${errors.objectName}.${violation.propertyPath}',
            violation.propertyPath,
          ], defaultMessage: violation.propertyPath),
        for (final name in attributes.keys.toList()..sort()) attributes[name],
      ];
      // Class-level violations have no path and become global errors.
      if (violation.propertyPath.isEmpty) {
        errors.reject(
          constraint.name,
          args: args,
          defaultMessage: violation.message,
        );
      } else {
        errors.rejectValue(
          violation.propertyPath,
          constraint.name,
          args: args,
          defaultMessage: violation.message,
        );
      }
    }
  }

  /// All violations of [target] (and nested `@Valid` values).
  ///
  /// Jakarta's `Validator.validate(object, groups...)`.
  ///
  /// ```dart
  /// final violations = BeanValidator().validateObject(
  ///   form,
  ///   groups: [OnUpdate],
  /// );
  /// ```
  List<ConstraintViolation> validateObject(
    Object target, {
    List<Type> groups = const [],
  }) {
    final violations = <ConstraintViolation>[];
    _validate(target, target, '', groups, violations, Set.identity());
    return violations;
  }

  /// Violations of one property of [target] (no cascading), like
  /// Jakarta's `validateProperty`; throws [ArgumentError] for unknown
  /// properties.
  ///
  /// ```dart
  /// validator.validateProperty(form, 'name');
  /// ```
  List<ConstraintViolation> validateProperty(
    Object target,
    String property, {
    List<Type> groups = const [],
  }) {
    final introspection = introspector.getIntrospection(target);
    final beanProperty = introspection.getProperty(property);
    if (beanProperty == null) {
      throw ArgumentError.value(
        property,
        'property',
        'Unknown property of ${target.runtimeType}',
      );
    }
    final violations = <ConstraintViolation>[];
    _checkProperty(
      target,
      target,
      beanProperty,
      beanProperty.getValue(target),
      '',
      groups,
      violations,
    );
    return violations;
  }

  /// Violations [value] would cause as [property] of [type], like
  /// Jakarta's `validateValue`; throws [ArgumentError] for unknown
  /// properties or types that are not introspected.
  ///
  /// ```dart
  /// validator.validateValue(SignupForm, 'age', 12); // one Min violation
  /// ```
  List<ConstraintViolation> validateValue(
    Type type,
    String property,
    Object? value, {
    List<Type> groups = const [],
  }) {
    final introspection = introspector.forType(type);
    final beanProperty = introspection?.getProperty(property);
    if (beanProperty == null) {
      throw ArgumentError.value(
        property,
        'property',
        'Unknown property of $type',
      );
    }
    final violations = <ConstraintViolation>[];
    for (final constraint in beanProperty.annotationsOf<Constraint>()) {
      if (constraint.appliesTo(groups) && !constraint.isValid(value)) {
        violations.add(
          ConstraintViolation(
            propertyPath: property,
            constraint: constraint,
            invalidValue: value,
            message: constraint.interpolatedMessage(),
          ),
        );
      }
    }
    return violations;
  }

  // Validates [target] (reached from [root] at [path], which is empty or
  // ends with '.'), then cascades into `@Valid` properties.
  void _validate(
    Object root,
    Object target,
    String path,
    List<Type> groups,
    List<ConstraintViolation> violations,
    Set<Object> visited,
  ) {
    // Identity set: each object is validated once, which also stops
    // cycles in object graphs.
    if (!visited.add(target)) {
      return;
    }
    final introspection = introspector.findIntrospection(target);
    if (introspection == null) {
      return;
    }
    // Class-level constraints; their path is the object's own path.
    for (final constraint
        in introspection.annotations.whereType<Constraint>()) {
      if (constraint.appliesTo(groups) && !constraint.isValid(target)) {
        violations.add(
          ConstraintViolation(
            propertyPath: path.replaceFirst(RegExp(r'\.$'), ''),
            constraint: constraint,
            invalidValue: target,
            message: constraint.interpolatedMessage(),
            rootBean: root,
          ),
        );
      }
    }
    for (final property in introspection.properties) {
      final value = property.getValue(target);
      _checkProperty(root, target, property, value, path, groups, violations);
      if (value != null && property.annotationsOf<Valid>().isNotEmpty) {
        _cascade(
          root,
          value,
          '$path${property.name}',
          groups,
          violations,
          visited,
        );
      }
    }
  }

  // Checks the constraints declared on one property value.
  void _checkProperty(
    Object root,
    Object target,
    BeanProperty<Object> property,
    Object? value,
    String path,
    List<Type> groups,
    List<ConstraintViolation> violations,
  ) {
    for (final constraint in property.annotationsOf<Constraint>()) {
      if (constraint.appliesTo(groups) && !constraint.isValid(value)) {
        violations.add(
          ConstraintViolation(
            propertyPath: '$path${property.name}',
            constraint: constraint,
            invalidValue: value,
            message: constraint.interpolatedMessage(),
            rootBean: root,
          ),
        );
      }
    }
  }

  // Cascades `@Valid`: map values become `path[key].`, iterable elements
  // `path[index].` and plain objects `path.`; null elements are skipped.
  void _cascade(
    Object root,
    Object value,
    String path,
    List<Type> groups,
    List<ConstraintViolation> violations,
    Set<Object> visited,
  ) {
    switch (value) {
      case Map<Object?, Object?>():
        for (final MapEntry(:key, value: element) in value.entries) {
          if (element != null) {
            _validate(
              root,
              element,
              '$path[$key].',
              groups,
              violations,
              visited,
            );
          }
        }
      case Iterable<Object?>():
        var index = 0;
        for (final element in value) {
          if (element != null) {
            _validate(
              root,
              element,
              '$path[$index].',
              groups,
              violations,
              visited,
            );
          }
          index++;
        }
      default:
        _validate(root, value, '$path.', groups, violations, visited);
    }
  }
}
