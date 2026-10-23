import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';
import 'package:spring_core_dart/src/validation/constraints.dart';
import 'package:spring_core_dart/src/validation/errors.dart';
import 'package:spring_core_dart/src/validation/validator.dart';

/// One failed constraint, like Jakarta's `ConstraintViolation`.
///
/// Returned by the Jakarta-style methods of [BeanValidator]
/// ([BeanValidator.validateObject], [BeanValidator.validateProperty],
/// [BeanValidator.validateValue], [BeanValidator.validateParameters],
/// [BeanValidator.validateReturnValue]).
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
    this.leafBean,
    this.messageTemplate,
  });

  /// `name`, `address.city`, `items[0].sku`; empty for class-level ones.
  /// Method validation paths start with the method name:
  /// `register.email`, `register.<return value>`.
  final String propertyPath;

  /// The constraint that failed.
  final Constraint constraint;

  /// The value that failed (the object itself for class-level ones).
  final Object? invalidValue;

  /// The interpolated message, e.g. `size must be between 0 and 20`.
  final String message;

  /// The message before interpolation, e.g. `size must be between {min}
  /// and {max}`.
  final String? messageTemplate;

  /// The object validation started from; `null` for [BeanValidator.validateValue],
  /// where no instance exists (Spring's `getRootBean()` is `null` there too).
  final Object? rootBean;

  /// The object holding the failed property (the validated object itself
  /// for class-level constraints), like Jakarta's `getLeafBean()`.
  final Object? leafBean;

  @override
  String toString() => '$propertyPath: $message';
}

/// Reports constraint violations, like Jakarta's
/// `ConstraintViolationException` — thrown by method validation (see
/// `MethodValidationInterceptor`).
///
/// ```dart
/// try {
///   registration.register('');
/// } on ConstraintViolationException catch (e) {
///   print(e.message); // register.email: must not be blank
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// } catch (ConstraintViolationException e) {
///   e.getConstraintViolations();
/// }
/// ```
class ConstraintViolationException implements Exception {
  /// Reports [constraintViolations]; [message] defaults to
  /// `path: message` pairs joined with `, ` (Hibernate Validator's form).
  ConstraintViolationException(
    List<ConstraintViolation> constraintViolations, [
    String? message,
  ]) : constraintViolations = List.unmodifiable(constraintViolations),
       message = message ?? constraintViolations.join(', ');

  /// The violations.
  final List<ConstraintViolation> constraintViolations;

  /// What failed.
  final String message;

  @override
  String toString() => 'ConstraintViolationException: $message';
}

/// A string attribute of a constraint passed as an error argument, so a
/// `MessageSource` may translate it (codes: the value itself), like
/// Spring's `SpringValidatorAdapter.ResolvableAttribute`.
///
/// ```dart
/// // For @Matches(r'\d{5}'): arguments [field, flags, ResolvableAttribute(r'\d{5}')]
/// ```
final class ResolvableAttribute implements MessageSourceResolvable {
  /// Wraps the attribute [value].
  const ResolvableAttribute(this.value);

  /// The attribute value.
  final String value;

  @override
  List<String> get codes => [value];

  @override
  List<Object?> get arguments => const [];

  @override
  String? get defaultMessage => value;

  @override
  bool operator ==(Object other) =>
      other is ResolvableAttribute && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Validates `@Introspected` objects against their [Constraint]
/// annotations, like Spring's `LocalValidatorFactoryBean` over Jakarta
/// Bean Validation.
///
/// Field errors use the constraint name as code (`NotBlank`) and, like
/// Spring, arguments `[field resolvable, ...attribute values sorted by
/// attribute name]` (string attributes as [ResolvableAttribute]s), so
/// messages can be customized in a `MessageSource`. A field that already
/// has a binding failure (`typeMismatch`) gets no constraint error on top.
///
/// Messages are interpolated like Jakarta: `{key}` placeholders are looked
/// up in [validationMessageSource] (recursively; the built-in messages also
/// under `jakarta.validation.constraints.<Name>.message`), then
/// `{attribute}` placeholders are replaced by the constraint's attributes.
/// Date constraints read the time from [clockProvider].
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
  ///
  /// [validationMessageSource] resolves `{key}` placeholders of messages
  /// (Spring's `setValidationMessageSource`); [clockProvider] gives "now"
  /// to the date constraints (Spring's `setClockProvider`).
  BeanValidator({
    BeanIntrospector? introspector,
    this.validationMessageSource,
    this.clockProvider = const DefaultClockProvider(),
  }) : introspector = introspector ?? BeanIntrospector.shared;

  /// Source of the constraint annotations and property values.
  final BeanIntrospector introspector;

  /// Resolves `{key}` placeholders in constraint messages; `null` leaves
  /// them as they are.
  final MessageSource? validationMessageSource;

  /// The clock of the date constraints.
  final ClockProvider clockProvider;

  @override
  bool supports(Object target) =>
      introspector.findIntrospection(target) != null;

  @override
  void validate(Object target, Errors errors) =>
      validateWithGroups(target, errors, const []);

  @override
  void validateWithGroups(Object target, Errors errors, List<Type> groups) {
    for (final violation in validateObject(target, groups: groups)) {
      final field = violation.propertyPath;
      // Like Spring's SpringValidatorAdapter: no constraint error on top of
      // a binding failure (the type mismatch says it all).
      if (field.isNotEmpty &&
          errors.fieldError(field)?.bindingFailure == true) {
        continue;
      }
      final constraint = violation.constraint;
      final attributes = constraint.attributes;
      final nestedField = '${errors.nestedPath}$field';
      // Argument {0} resolves the field name itself (codes `signup.name`,
      // `name`), followed by the constraint attributes in alphabetical
      // order ({1}, {2}, ...); strings may be translated too.
      final args = [
        if (nestedField.isNotEmpty)
          DefaultMessageSourceResolvable([
            '${errors.objectName}.$nestedField',
            nestedField,
          ], defaultMessage: nestedField),
        for (final name in attributes.keys.toList()..sort())
          switch (attributes[name]) {
            final String text => ResolvableAttribute(text),
            final value => value,
          },
      ];
      // Like Spring's ViolationFieldError: the violation message is shown
      // as-is unless it contains `{0}`-style placeholders.
      final render = _springPlaceholder.hasMatch(violation.message);
      if (nestedField.isEmpty) {
        // Class-level violations without a property are global errors.
        errors.reject(
          constraint.name,
          args: args,
          defaultMessage: violation.message,
          renderDefaultMessage: render,
        );
      } else if (errors is BindingResult) {
        // The rejected value is the invalid one, except for class-level
        // violations reported on a property and nested paths, where it is
        // the property's current value (Spring's getRejectedValue).
        final rejected =
            (field.isNotEmpty &&
                (identical(violation.invalidValue, violation.leafBean) ||
                    field.contains('[') ||
                    field.contains('.')))
            ? errors.getRawFieldValue(nestedField)
            : violation.invalidValue;
        errors.addError(
          FieldError(
            errors.objectName,
            nestedField,
            rejected,
            errors.resolveMessageCodes(constraint.name, field),
            arguments: args,
            defaultMessage: violation.message,
            shouldRenderDefaultMessage: render,
          ),
        );
      } else {
        errors.rejectValue(
          field,
          constraint.name,
          args: args,
          defaultMessage: violation.message,
          renderDefaultMessage: render,
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
    _checkValue(
      root: target,
      leaf: target,
      constraints: beanProperty.annotationsOf<Constraint>(),
      value: beanProperty.getValue(target),
      path: beanProperty.name,
      groups: groups,
      violations: violations,
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
    _checkValue(
      root: null,
      leaf: null,
      constraints: beanProperty.annotationsOf<Constraint>(),
      value: value,
      path: property,
      groups: groups,
      violations: violations,
    );
    return violations;
  }

  /// Violations of the [arguments] of a call to [method] of [target]:
  /// constraints on the parameters and `@Valid` parameters cascaded, like
  /// Jakarta's `ExecutableValidator.validateParameters`. Paths are
  /// `method.parameter` (`register.email`, `save.order.items[0].sku`).
  ///
  /// [arguments] are in the order of `method.parameterNames` (positional,
  /// then named), as an AOP invocation passes them.
  ///
  /// ```dart
  /// validator.validateParameters(service, signature, ['']);
  /// ```
  List<ConstraintViolation> validateParameters(
    Object target,
    MethodSignature method,
    List<Object?> arguments, {
    List<Type> groups = const [],
  }) {
    final violations = <ConstraintViolation>[];
    final annotations = method.parameterAnnotations;
    for (var i = 0; i < arguments.length && i < annotations.length; i++) {
      final name = i < method.parameterNames.length
          ? method.parameterNames[i]
          : 'arg$i';
      final path = '${method.name}.$name';
      final value = arguments[i];
      _checkValue(
        root: target,
        leaf: target,
        constraints: annotations[i].whereType<Constraint>(),
        value: value,
        path: path,
        groups: groups,
        violations: violations,
      );
      if (value != null && annotations[i].whereType<Valid>().isNotEmpty) {
        _cascade(target, value, path, groups, violations, Set.identity());
      }
    }
    return violations;
  }

  /// Violations of [returnValue] of [method]: the constraints on the
  /// method and, with `@Valid` on it, the returned object, like Jakarta's
  /// `ExecutableValidator.validateReturnValue`. Paths start with
  /// `method.<return value>`.
  ///
  /// ```dart
  /// validator.validateReturnValue(service, signature, result);
  /// ```
  List<ConstraintViolation> validateReturnValue(
    Object target,
    MethodSignature method,
    Object? returnValue, {
    List<Type> groups = const [],
  }) {
    final violations = <ConstraintViolation>[];
    final path = '${method.name}.<return value>';
    _checkValue(
      root: target,
      leaf: target,
      constraints: method.annotations.whereType<Constraint>(),
      value: returnValue,
      path: path,
      groups: groups,
      violations: violations,
    );
    if (returnValue != null &&
        method.annotations.whereType<Valid>().isNotEmpty) {
      _cascade(target, returnValue, path, groups, violations, Set.identity());
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
    Set<Object> ancestors,
  ) {
    // Like Hibernate Validator, an object reachable on several paths is
    // validated on each of them; only an object containing itself (a
    // cycle) is skipped.
    if (!ancestors.add(target)) {
      return;
    }
    try {
      final introspection = introspector.findIntrospection(target);
      if (introspection == null) {
        return;
      }
      final objectPath = path.replaceFirst(RegExp(r'\.$'), '');
      // Class-level constraints; their path is the object's own path, or a
      // property node the constraint added.
      for (final constraint
          in introspection.annotations.whereType<Constraint>()) {
        if (constraint.appliesTo(groups)) {
          _check(
            root: root,
            leaf: target,
            constraint: constraint,
            value: target,
            path: objectPath,
            violations: violations,
          );
        }
      }
      for (final property in introspection.properties) {
        final value = property.getValue(target);
        _checkValue(
          root: root,
          leaf: target,
          constraints: property.annotationsOf<Constraint>(),
          value: value,
          path: '$path${property.name}',
          groups: groups,
          violations: violations,
        );
        if (value != null && property.annotationsOf<Valid>().isNotEmpty) {
          _cascade(
            root,
            value,
            '$path${property.name}',
            groups,
            violations,
            ancestors,
          );
        }
      }
    } finally {
      ancestors.remove(target);
    }
  }

  // Checks the [constraints] of the applicable groups on one value.
  void _checkValue({
    required Object? root,
    required Object? leaf,
    required Iterable<Constraint> constraints,
    required Object? value,
    required String path,
    required List<Type> groups,
    required List<ConstraintViolation> violations,
  }) {
    for (final constraint in constraints) {
      if (constraint.appliesTo(groups)) {
        _check(
          root: root,
          leaf: leaf,
          constraint: constraint,
          value: value,
          path: path,
          violations: violations,
        );
      }
    }
  }

  // Runs one constraint; records the default violation and those the
  // constraint added to its context (with property nodes under [path]).
  void _check({
    required Object? root,
    required Object? leaf,
    required Constraint constraint,
    required Object? value,
    required String path,
    required List<ConstraintViolation> violations,
  }) {
    final template = _template(constraint);
    final context = ConstraintValidatorContext(
      defaultConstraintMessageTemplate: template,
      clockProvider: clockProvider,
    );
    if (constraint.isValidWithContext(value, context)) {
      return;
    }
    ConstraintViolation violation(String template, String path) =>
        ConstraintViolation(
          propertyPath: path,
          constraint: constraint,
          invalidValue: value,
          message: _interpolate(constraint, template),
          messageTemplate: template,
          rootBean: root,
          leafBean: leaf,
        );
    if (!context.defaultConstraintViolationDisabled) {
      violations.add(violation(template, path));
    }
    for (final custom in context.customViolations) {
      final nodes = custom.nodes.join('.');
      violations.add(
        violation(
          custom.messageTemplate,
          nodes.isEmpty
              ? path
              : path.isEmpty
              ? nodes
              : '$path.$nodes',
        ),
      );
    }
  }

  // The message template: the constraint's `message`, else the built-in
  // message as overridden under Jakarta's key, else the default message.
  String _template(Constraint constraint) {
    final message = constraint.message;
    if (message != null) {
      return message;
    }
    final source = validationMessageSource;
    if (source != null) {
      final key = 'jakarta.validation.constraints.${constraint.name}.message';
      final custom = _lookUp(source, key);
      if (custom != null) {
        return custom;
      }
    }
    return constraint.defaultMessage;
  }

  // Jakarta's interpolation: `{key}` placeholders from the message source
  // (resolved again while they keep producing placeholders), then
  // `{attribute}` placeholders.
  String _interpolate(Constraint constraint, String template) {
    var message = template;
    final source = validationMessageSource;
    if (source != null) {
      for (var depth = 0; depth < 10; depth++) {
        var changed = false;
        message = message.replaceAllMapped(_parameter, (match) {
          final resolved = _lookUp(source, match[1]!);
          if (resolved == null) {
            return match[0]!;
          }
          changed = true;
          return resolved;
        });
        if (!changed) {
          break;
        }
      }
    }
    return constraint.interpolate(message);
  }

  static String? _lookUp(MessageSource source, String key) {
    try {
      return source.getMessage(key);
    } on NoSuchMessageException {
      return null;
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
    Set<Object> ancestors,
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
              ancestors,
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
              ancestors,
            );
          }
          index++;
        }
      default:
        _validate(root, value, '$path.', groups, violations, ancestors);
    }
  }
}

// `{0}` or `{0,number,...}` — not a regex quantifier such as `{2,3}`.
final _springPlaceholder = RegExp(r'\{\d+(\}|,\s*[a-zA-Z])');

// A Jakarta message parameter: `{key}` (no nested braces).
final _parameter = RegExp(r'\{([^{}\s]+)\}');
