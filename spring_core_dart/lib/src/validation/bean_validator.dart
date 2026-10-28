import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';
import 'package:spring_core_dart/src/validation/constraints.dart';
import 'package:spring_core_dart/src/validation/errors.dart';
import 'package:spring_core_dart/src/validation/message_escapes.dart';
import 'package:spring_core_dart/src/validation/validator.dart';

/// One broken rule: which constraint failed, where (the property path),
/// on which value, and the finished message.
///
/// Applications receive violations in two places: in a list from
/// [BeanValidator.validateObject] and the other `validate...` methods
/// when they check an object themselves, and in
/// [ConstraintViolationException.constraintViolations] when a
/// `@Validated()` bean rejects a call. Unlike a `FieldError`, the message
/// is already text (interpolated, not a list of message codes); use it for
/// logs, or map [propertyPath] to your own response.
///
/// ```dart
/// // Report each problem of an imported row.
/// for (final v in validator.validateObject(form)) {
///   log.warning('${v.propertyPath}: ${v.message}'); // name: must not be blank
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// for (ConstraintViolation<SignupForm> v : validator.validate(form)) {
///   log.warn(v.getPropertyPath() + ": " + v.getMessage());
/// }
/// ```
final class ConstraintViolation {
  /// A violation of [constraint] at [propertyPath]; the validator creates
  /// them, applications rarely do (in tests, say).
  const ConstraintViolation({
    required this.propertyPath,
    required this.constraint,
    required this.invalidValue,
    required this.message,
    this.rootBean,
    this.leafBean,
    this.messageTemplate,
  });

  /// Where the invalid value is, from the validated object: `name`,
  /// `address.city`, `items[0].sku`, `names[1].<list element>`; empty for
  /// a class-level constraint. In method validation it starts with the
  /// method name: `register.email`, `register.<return value>`.
  final String propertyPath;

  /// The constraint that failed; its `name` (`NotBlank`) tells the kind of
  /// problem and its attributes the limits.
  final Constraint constraint;

  /// The value that broke the constraint; the object itself for a
  /// class-level constraint.
  final Object? invalidValue;

  /// The finished message, placeholders filled in, such as `size must be
  /// between 0 and 20`.
  final String message;

  /// The message before interpolation, such as `size must be between
  /// {min} and {max}`.
  final String? messageTemplate;

  /// The object validation started from (the bean, for method
  /// validation); `null` for [BeanValidator.validateValue], where no
  /// instance exists, as in Jakarta.
  final Object? rootBean;

  /// The object that holds the invalid property, such as the `Address`
  /// for `address.city`; the validated object itself for a class-level
  /// constraint. Jakarta's `getLeafBean()`.
  final Object? leafBean;

  @override
  String toString() => '$propertyPath: $message';
}

/// The exception a `@Validated()` bean throws when a call's arguments or
/// its return value break their constraints.
///
/// It means the caller passed invalid data (or the method returned it),
/// and lists every violation. The method does not run when the arguments
/// are invalid. Catch it where you can tell the user; the web starter does
/// not turn it into a 400 by itself, so an uncaught one reaching a
/// controller is a 500. Add an `@ExceptionHandler` for it when clients can
/// cause it. A `@Valid()` request body is reported differently, with a
/// `MethodArgumentNotValidException`.
///
/// ```dart
/// // The service rejects the empty address before running.
/// try {
///   registration.register('');
/// } on ConstraintViolationException catch (e) {
///   log.warning(e.message); // register.email: must not be blank
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
  /// An exception for [constraintViolations]; [message] defaults to their
  /// `path: message` pairs joined with `, `, as Hibernate Validator writes
  /// it.
  ConstraintViolationException(
    List<ConstraintViolation> constraintViolations, [
    String? message,
  ]) : constraintViolations = List.unmodifiable(constraintViolations),
       message = message ?? constraintViolations.join(', ');

  /// Every violation found, in the order they were checked.
  final List<ConstraintViolation> constraintViolations;

  /// A one-line summary, such as `register.email: must not be blank`;
  /// fine for logs, not meant for end users.
  final String message;

  @override
  String toString() => 'ConstraintViolationException: $message';
}

/// A string attribute of a constraint, such as the regular expression of
/// `@Matches`, passed as an argument of a field error.
///
/// It is a message code of its own (the string itself), so a
/// `MessageSource` may translate it: the key `\d{5}=five digits` turns
/// `must match {2}` into `must match five digits`. When no key matches,
/// the plain string is used. The validator creates it; applications never
/// do. Spring's `SpringValidatorAdapter.ResolvableAttribute`.
///
/// ```dart
/// // The arguments of an @Matches(r'\d{5}') error:
/// // [field, flags, ResolvableAttribute(r'\d{5}')]
/// ```
final class ResolvableAttribute implements MessageSourceResolvable {
  /// An argument for the attribute [value].
  const ResolvableAttribute(this.value);

  /// The attribute string, both message code and default message.
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

/// The validator: it checks an object against the constraint annotations
/// on its class (`@NotBlank()`, `@Min(18)`, custom [Constraint]s) and
/// reports what is broken.
///
/// Spring Boot registers one as the `defaultValidator` bean, with the
/// context's introspector, and uses it for `@Valid()` request bodies and
/// `@Validated()` beans (`@ConfigurationProperties` classes get a plain
/// validator of their own). Inject it
/// (`BeanValidator` or `Validator`) when you check an object yourself:
/// a batch import, a message from a queue, data that does not come
/// through a controller. Declare your own `BeanValidator` bean to set a
/// [validationMessageSource], a [clockProvider] or [groupSequences]; Boot
/// then backs off. The class must be `@Introspected` (the generator
/// describes its properties); other objects are not checked.
///
/// It answers in two forms:
///
/// - As a [Validator], it records errors in an [Errors]: each violation
///   becomes a `FieldError` with the constraint's name as code
///   (`NotBlank.signup.name`, ..., `NotBlank`), so `messages.properties`
///   can word it. The arguments follow Spring: `{0}` is the field, then
///   the constraint's attributes sorted by name (`{1}` is the limit of
///   `@Min`); string attributes come as [ResolvableAttribute]s. A field
///   that already has a binding failure (`typeMismatch`) gets no
///   constraint error on top.
/// - [validateObject] and its siblings return [ConstraintViolation]s with
///   finished messages.
///
/// Messages are interpolated as in Jakarta Bean Validation: `{key}`
/// placeholders are looked up in [validationMessageSource], repeatedly
/// while the result has placeholders; the built-in messages are also
/// available under `jakarta.validation.constraints.<Name>.message`, with
/// Hibernate's English defaults when no message source defines them. Then
/// `{attribute}` placeholders take the constraint's attributes, and
/// `${validatedValue}` the invalid value; `\{`, `\}`, `\$` and `\\`
/// stay literal characters. Date constraints read "now" from
/// [clockProvider].
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
/// // A 17-year-old signs up: the form binds, but @Min(18) fails.
/// final form = SignupForm();
/// final binder = DataBinder(form, objectName: 'signup')
///   ..validators.add(validator) // the injected BeanValidator
///   ..bind({'name': 'Ada', 'age': '17'})
///   ..validate();
/// final error = binder.bindingResult.fieldError('age')!;
/// error.defaultMessage; // 'must be greater than or equal to 18'
///
/// // With `Min={0} must be at least {1}` in messages.properties, the
/// // application's message source words it: 'age must be at least 18'.
/// messageSource.getMessageFromResolvable(error);
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
  /// A validator that reads the constraints through [introspector], by
  /// default `BeanIntrospector.shared`; inside an application pass the
  /// context's `BeanIntrospector`, which knows the application's classes.
  ///
  /// [validationMessageSource] resolves `{key}` placeholders in messages
  /// (Spring's `setValidationMessageSource`); [clockProvider] gives "now"
  /// to the date constraints, the system clock by default (Spring's
  /// `setClockProvider`).
  ///
  /// [groupSequences] defines group sequences (Jakarta's `@GroupSequence`
  /// on a group interface): validating with a key group checks the listed
  /// groups in order and stops at the first group with a violation, so the
  /// expensive checks only run on otherwise valid data.
  ///
  /// ```dart
  /// // `Complete` checks the plain rules, then the strict ones.
  /// abstract final class Complete {}
  ///
  /// BeanValidator(groupSequences: {Complete: [Default, Strict]})
  ///     .validateObject(form, groups: [Complete]);
  /// ```
  BeanValidator({
    BeanIntrospector? introspector,
    this.validationMessageSource,
    this.clockProvider = const DefaultClockProvider(),
    Map<Type, List<Type>> groupSequences = const {},
  }) : introspector = introspector ?? BeanIntrospector.shared,
       groupSequences = Map.unmodifiable(groupSequences);

  /// Describes the classes: where the constraints are and how to read the
  /// property values.
  final BeanIntrospector introspector;

  /// Resolves `{key}` placeholders in constraint messages, such as
  /// `@NotBlank(message: '{signup.name.missing}')`, and may replace a
  /// built-in message under `jakarta.validation.constraints.<Name>.message`.
  /// `null` (the default, also for Boot's `defaultValidator`) leaves
  /// unknown keys as they are.
  ///
  /// It is not needed for `messages.properties` keys such as
  /// `NotBlank.signup.name`: those word the field errors when they are
  /// shown, through the application's message source.
  final MessageSource? validationMessageSource;

  /// Gives "now" to `@Past`, `@FutureDate` and the other date constraints;
  /// replace it in tests to fix the date.
  final ClockProvider clockProvider;

  /// The group sequences: each key group stands for the listed groups,
  /// checked in order until one has a violation. Empty by default.
  final Map<Type, List<Type>> groupSequences;

  @override
  bool supports(Object target) =>
      introspector.findIntrospection(target) != null;

  @override
  void validate(Object target, Errors errors) =>
      validateWithGroups(target, errors, const []);

  @override
  void validateWithGroups(Object target, Errors errors, List<Type> groups) {
    for (final violation in validateObject(target, groups: groups)) {
      // Spring's determineField: container element nodes
      // (`names[1].<list element>`) end at their index (`names[1]`).
      final field = violation.propertyPath.replaceAll(_elementNode, '');
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
        // the property's current value (Spring's getRejectedValue); not for
        // `lucky[].city` paths, which cannot be read back.
        final rejected =
            (field.isNotEmpty &&
                !field.contains('[]') &&
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

  /// Every violation of [target], including those inside `@Valid()`
  /// properties; an empty list when it is valid or not `@Introspected`.
  ///
  /// Use it to check an object in code and decide what to do with the
  /// problems. [groups] selects the constraints, by default those of the
  /// [Default] group. A group of [groupSequences] is checked group by
  /// group, stopping at the first group with a violation, and a class's
  /// `@GroupSequence` replaces its [Default] group. Throws a
  /// [ValidationException] when a constraint or group is declared wrongly.
  /// Jakarta's `Validator.validate(object, groups...)`.
  ///
  /// ```dart
  /// // An edit: only the constraints of the OnUpdate group.
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
    _inGroups(
      groups,
      violations,
      (groups) =>
          _validate(target, target, '', groups, violations, Set.identity()),
    );
    return violations;
  }

  /// The violations of the single [property] of [target], without going
  /// into `@Valid()` values; useful to check one form field as the user
  /// leaves it. Jakarta's `validateProperty`.
  ///
  /// Throws an [ArgumentError] when [target] has no such property, or is
  /// not `@Introspected`.
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
    final value = beanProperty.getValue(target);
    _inGroups(
      groups,
      violations,
      (groups) => _ownGroups(
        introspection,
        groups,
        violations,
        (applies) => _checkValue(
          root: target,
          leaf: target,
          annotations: beanProperty.annotations,
          value: value,
          path: beanProperty.name,
          applies: applies,
          violations: violations,
        ),
      ),
    );
    return violations;
  }

  /// The violations [value] would cause as [property] of the class [type],
  /// without an instance; useful to check input before creating the
  /// object. Jakarta's `validateValue`.
  ///
  /// Throws an [ArgumentError] when [type] is not `@Introspected` or has no
  /// such property.
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
    _inGroups(
      groups,
      violations,
      (groups) => _ownGroups(
        introspection,
        groups,
        violations,
        (applies) => _checkValue(
          root: null,
          leaf: null,
          annotations: beanProperty.annotations,
          value: value,
          path: property,
          applies: applies,
          violations: violations,
        ),
      ),
    );
    return violations;
  }

  /// The violations of the [arguments] of a call to [method] of [target]:
  /// the constraints on each parameter, and those inside `@Valid()`
  /// arguments. Paths are `method.parameter` (`register.email`,
  /// `save.order.items[0].sku`). Jakarta's
  /// `ExecutableValidator.validateParameters`.
  ///
  /// `MethodValidationInterceptor` calls it before each call of a
  /// `@Validated()` bean; applications rarely do. [arguments] are in the
  /// order of `method.parameterNames` (positional, then named), as an AOP
  /// invocation passes them.
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
    _inGroups(groups, violations, (groups) {
      for (var i = 0; i < arguments.length && i < annotations.length; i++) {
        final name = i < method.parameterNames.length
            ? method.parameterNames[i]
            : 'arg$i';
        final path = '${method.name}.$name';
        final value = arguments[i];
        _checkValue(
          root: target,
          leaf: target,
          annotations: annotations[i],
          value: value,
          path: path,
          applies: (constraint) => constraint.appliesTo(groups),
          violations: violations,
        );
        _cascade(
          target,
          value,
          path,
          annotations[i],
          groups,
          violations,
          Set.identity(),
        );
      }
    });
    return violations;
  }

  /// The violations of the [returnValue] of [method]: the constraints on
  /// the method and, with `@Valid()` on it, those inside the returned
  /// object. Paths start with `method.<return value>`. Jakarta's
  /// `ExecutableValidator.validateReturnValue`.
  ///
  /// `MethodValidationInterceptor` calls it after each call of a
  /// `@Validated()` bean; applications rarely do.
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
    _inGroups(groups, violations, (groups) {
      _checkValue(
        root: target,
        leaf: target,
        annotations: method.annotations,
        value: returnValue,
        path: path,
        applies: (constraint) => constraint.appliesTo(groups),
        violations: violations,
      );
      _cascade(
        target,
        returnValue,
        path,
        method.annotations,
        groups,
        violations,
        Set.identity(),
      );
    });
    return violations;
  }

  // Runs [validate] for the requested [groups], like Hibernate Validator's
  // ValidationOrder: the plain groups together, then each sequence group by
  // group, stopping at the first group that adds a violation.
  void _inGroups(
    List<Type> groups,
    List<ConstraintViolation> violations,
    void Function(List<Type> groups) validate,
  ) {
    final requested = groups.isEmpty ? const <Type>[Default] : groups;
    final plain = [
      for (final group in requested)
        if (!groupSequences.containsKey(group)) group,
    ];
    if (plain.isNotEmpty) {
      validate(plain);
    }
    for (final group in requested) {
      if (!groupSequences.containsKey(group)) {
        continue;
      }
      for (final step in _expand(group, const [])) {
        final before = violations.length;
        validate([step]);
        if (violations.length > before) {
          break;
        }
      }
    }
  }

  // The plain groups of the sequence [group], nested sequences expanded.
  List<Type> _expand(Type group, List<Type> visiting) {
    if (visiting.contains(group)) {
      throw GroupDefinitionException(
        'Cyclic dependency in groups definition: '
        '${[...visiting, group].join(' -> ')}',
      );
    }
    final members = groupSequences[group];
    if (members == null) {
      return [group];
    }
    if (group == Default) {
      throw const GroupDefinitionException(
        'Default cannot be a group sequence; use @GroupSequence on the '
        'class to redefine it',
      );
    }
    return [
      for (final member in members) ..._expand(member, [...visiting, group]),
    ];
  }

  // The class's `@GroupSequence` (its redefined Default group), checked
  // like Hibernate Validator's BeanMetaDataImpl.
  static GroupSequence? _defaultSequence(
    BeanIntrospection<Object>? introspection,
  ) {
    if (introspection == null) {
      return null;
    }
    final sequence = introspection.annotations
        .whereType<GroupSequence>()
        .firstOrNull;
    if (sequence == null) {
      return null;
    }
    final type = introspection.beanType;
    if (sequence.value.contains(Default)) {
      throw GroupDefinitionException(
        'Default cannot appear in the default group sequence of $type.',
      );
    }
    if (!sequence.value.contains(type)) {
      throw GroupDefinitionException(
        '$type must be part of the redefined default group sequence.',
      );
    }
    return sequence;
  }

  // Runs [check] on the constraints of a bean of [introspection] for
  // [groups]; with a redefined Default group (`@GroupSequence` on the
  // class), Default runs as that sequence: the class itself stands for its
  // Default constraints and the sequence stops at the first group with a
  // violation.
  void _ownGroups(
    BeanIntrospection<Object>? introspection,
    List<Type> groups,
    List<ConstraintViolation> violations,
    void Function(bool Function(Constraint) applies) check,
  ) {
    final sequence = _defaultSequence(introspection);
    if (sequence == null || (groups.isNotEmpty && !groups.contains(Default))) {
      check((constraint) => constraint.appliesTo(groups));
      return;
    }
    final type = introspection!.beanType;
    final others = [
      for (final group in groups)
        if (group != Default) group,
    ];
    if (others.isNotEmpty) {
      check((constraint) => constraint.appliesTo(others));
    }
    for (final group in sequence.value) {
      final before = violations.length;
      check(
        group == type
            ? (constraint) =>
                  constraint.appliesTo(const [Default]) ||
                  constraint.groups.contains(type)
            : (constraint) => constraint.appliesTo([group]),
      );
      if (violations.length > before) {
        break;
      }
    }
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
      final redefined = _defaultSequence(introspection) != null;
      void checkOwn(bool Function(Constraint) applies, {bool cascade = false}) {
        // Class-level constraints; their path is the object's own path, or
        // a property node the constraint added.
        for (final constraint
            in introspection.annotations.whereType<Constraint>()) {
          if (applies(constraint)) {
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
            annotations: property.annotations,
            value: value,
            path: '$path${property.name}',
            applies: applies,
            violations: violations,
          );
          if (cascade) {
            _cascade(
              root,
              value,
              '$path${property.name}',
              property.annotations,
              groups,
              violations,
              ancestors,
            );
          }
        }
      }

      if (!redefined) {
        checkOwn((constraint) => constraint.appliesTo(groups), cascade: true);
        return;
      }
      _ownGroups(introspection, groups, violations, checkOwn);
      for (final property in introspection.properties) {
        _cascade(
          root,
          property.getValue(target),
          '$path${property.name}',
          property.annotations,
          groups,
          violations,
          ancestors,
        );
      }
    } finally {
      ancestors.remove(target);
    }
  }

  // Checks the constraints in [annotations] that [applies] accepts on one
  // value, and the element constraints (`@Each`, `@EachKey`) on its
  // elements.
  void _checkValue({
    required Object? root,
    required Object? leaf,
    required List<Object> annotations,
    required Object? value,
    required String path,
    required bool Function(Constraint) applies,
    required List<ConstraintViolation> violations,
  }) {
    for (final constraint in annotations.whereType<Constraint>()) {
      if (applies(constraint)) {
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
    for (final annotation in annotations) {
      final (constraints, keys) = switch (annotation) {
        Each(:final constraints) => (constraints, false),
        EachKey(:final constraints) => (constraints, true),
        _ => (const <Constraint>[], false),
      };
      final applicable = constraints.where(applies).toList();
      if (applicable.isEmpty || value == null) {
        continue;
      }
      for (final (elementPath, element) in _elements(value, path, keys)) {
        for (final constraint in applicable) {
          _check(
            root: root,
            leaf: leaf,
            constraint: constraint,
            value: element,
            path: elementPath,
            violations: violations,
          );
        }
      }
    }
  }

  // The elements of a container with Hibernate Validator's paths:
  // `names[1].<list element>`, `tags[].<iterable element>`,
  // `scores[math].<map value>`, `scores<K>[math].<map key>`.
  static Iterable<(String, Object?)> _elements(
    Object value,
    String path,
    bool keys,
  ) sync* {
    switch (value) {
      case Map<Object?, Object?>():
        for (final MapEntry(:key, value: element) in value.entries) {
          yield keys
              ? ('$path<K>[$key].<map key>', key)
              : ('$path[$key].<map value>', element);
        }
      case List<Object?>() when !keys:
        for (var i = 0; i < value.length; i++) {
          yield ('$path[$i].<list element>', value[i]);
        }
      case Iterable<Object?>() when !keys:
        for (final element in value) {
          yield ('$path[].<iterable element>', element);
        }
      default:
        throw ConstraintDeclarationException(
          '${keys ? '@EachKey' : '@Each'} on $path: '
          '${value.runtimeType} is not a '
          '${keys ? 'map' : 'collection or map'}',
        );
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
    if (_checkedParameters[constraint] == null) {
      constraint.checkParameters();
      _checkedParameters[constraint] = true;
    }
    if (value != null && !constraint.supports(value)) {
      throw UnexpectedTypeException(
        "No validator could be found for constraint '${constraint.name}' "
        "validating type '${value.runtimeType}'. Check configuration for "
        "'$path'",
      );
    }
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
          message: _interpolate(constraint, template, value),
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

  // Jakarta's interpolation: `{key}` placeholders from the message source,
  // else Hibernate's built-in messages for
  // `{jakarta.validation.constraints.<Name>.message}` (resolved again while
  // they keep producing placeholders), then `{attribute}` placeholders,
  // then the expressions `${validatedValue}` and `${attribute}`. Escaped
  // `\{`, `\}`, `\$` and `\\` stay literal characters.
  String _interpolate(Constraint constraint, String template, Object? value) {
    var message = hideMessageEscapes(template);
    final source = validationMessageSource;
    String? resolve(String key) {
      if (source != null) {
        if (_lookUp(source, key) case final found?) {
          return found;
        }
      }
      return _builtInMessage(constraint, key);
    }

    for (var depth = 0; depth < 10; depth++) {
      var changed = false;
      message = message.replaceAllMapped(_parameter, (match) {
        final resolved = resolve(match[1]!);
        if (resolved == null) {
          return match[0]!;
        }
        changed = true;
        return hideMessageEscapes(resolved);
      });
      if (!changed) {
        break;
      }
    }
    final attributes = constraint.attributes;
    return revealMessageEscapes(
      interpolateAttributes(message, attributes).replaceAllMapped(
        _expression,
        (match) => switch (match[1]!) {
          'validatedValue' => '$value',
          final name when attributes.containsKey(name) => '${attributes[name]}',
          _ => match[0]!,
        },
      ),
    );
  }

  static const _jakartaPrefix = 'jakarta.validation.constraints.';

  // `jakarta.validation.constraints.<Name>.message` without a message
  // source: the constraint's own default message (it knows its attributes,
  // e.g. `inclusive`), else Hibernate's English one.
  static String? _builtInMessage(Constraint constraint, String key) {
    if (!key.startsWith(_jakartaPrefix) || !key.endsWith('.message')) {
      return null;
    }
    final name = key.substring(
      _jakartaPrefix.length,
      key.length - '.message'.length,
    );
    return name == constraint.name
        ? constraint.defaultMessage
        : builtInConstraintMessages[name];
  }

  static String? _lookUp(MessageSource source, String key) {
    try {
      return source.getMessage(key);
    } on NoSuchMessageException {
      return null;
    }
  }

  // Cascades `@Valid` (from [annotations]): map values become `path[key].`,
  // list elements `path[index].`, other iterables (sets) `path[].` and plain
  // objects `path.`; null elements are skipped. `@ConvertGroup` changes the
  // groups of the nested validation.
  void _cascade(
    Object root,
    Object? value,
    String path,
    List<Object> annotations,
    List<Type> groups,
    List<ConstraintViolation> violations,
    Set<Object> ancestors,
  ) {
    final conversions = annotations.whereType<ConvertGroup>().toList();
    if (annotations.whereType<Valid>().isEmpty) {
      if (conversions.isNotEmpty) {
        throw ConstraintDeclarationException(
          '@ConvertGroup on $path without @Valid: group conversions are '
          'only allowed on cascaded elements',
        );
      }
      return;
    }
    if (value == null) {
      return;
    }
    final nested = _convert(groups, conversions, path);
    _inGroups(nested, violations, (groups) {
      void validate(Object element, String elementPath) =>
          _validate(root, element, elementPath, groups, violations, ancestors);
      switch (value) {
        case Map<Object?, Object?>():
          for (final MapEntry(:key, value: element) in value.entries) {
            if (element != null) {
              validate(element, '$path[$key].');
            }
          }
        case List<Object?>():
          for (var i = 0; i < value.length; i++) {
            if (value[i] case final element?) {
              validate(element, '$path[$i].');
            }
          }
        case Iterable<Object?>():
          for (final element in value) {
            if (element != null) {
              validate(element, '$path[].');
            }
          }
        default:
          validate(value, '$path.');
      }
    });
  }

  // [groups] with the `@ConvertGroup` conversions applied.
  static List<Type> _convert(
    List<Type> groups,
    List<ConvertGroup> conversions,
    String path,
  ) {
    if (conversions.isEmpty) {
      return groups;
    }
    final targets = <Type, Type>{};
    for (final conversion in conversions) {
      if (targets.containsKey(conversion.from)) {
        throw ConstraintDeclarationException(
          '@ConvertGroup on $path: ${conversion.from} is converted more '
          'than once',
        );
      }
      targets[conversion.from] = conversion.to;
    }
    return [
      for (final group in groups.isEmpty ? const <Type>[Default] : groups)
        targets[group] ?? group,
    ];
  }
}

// `{0}` or `{0,number,...}` — not a regex quantifier such as `{2,3}`.
final _springPlaceholder = RegExp(r'\{\d+(\}|,\s*[a-zA-Z])');

// A Jakarta message parameter: `{key}` (no nested braces), not the body of
// an expression `${...}`.
final _parameter = RegExp(r'(?<!\$)\{([^{}\s]+)\}');

// A Jakarta EL expression naming a value: `${validatedValue}`, `${max}`.
final _expression = RegExp(r'\$\{\s*(\w+)\s*\}');

// Constraints whose parameters were checked.
final _checkedParameters = Expando<bool>();

// A container element node of a property path (`.<list element>`) or the
// type argument of a map key node (`<K>`).
final _elementNode = RegExp(r'\.?<[^>]*>');
