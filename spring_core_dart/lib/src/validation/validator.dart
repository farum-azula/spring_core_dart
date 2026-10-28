import 'package:spring_core_dart/src/validation/errors.dart';

/// A check of an object written in code: it looks at the object and
/// records each problem in an [Errors].
///
/// Most rules fit the constraint annotations (`@NotBlank()`, `@Size`), which
/// `BeanValidator`, the validator the framework uses, checks for you. Write
/// a [Validator] for the rules that do not: two fields that must agree, a
/// value that depends on another one, a lookup. Add it to
/// `DataBinder.validators`, or call it with [ValidationUtils.invokeValidator].
/// The errors it records get the same message codes as constraint errors, so
/// their text can come from `messages.properties`.
///
/// When it is a bean, keep in mind that the web starter checks `@Valid()`
/// arguments with the one `Validator` bean: with a second one and neither
/// `@Primary`, those arguments are not checked at all.
///
/// [supports] receives the object itself rather than its class, since Dart
/// cannot test a `Type` for subtypes.
///
/// ```dart
/// // Two fields that must be equal: not expressible as an annotation.
/// class SignupValidator implements Validator {
///   @override
///   bool supports(Object target) => target is SignupForm;
///
///   @override
///   void validate(Object target, Errors errors) {
///     ValidationUtils.rejectIfEmptyOrWhitespace(errors, 'name', 'required');
///     final form = target as SignupForm;
///     if (form.password != form.confirmPassword) {
///       errors.rejectValue('confirmPassword', 'mismatch');
///     }
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class SignupValidator implements Validator {
///   public boolean supports(Class<?> clazz) {
///     return SignupForm.class.isAssignableFrom(clazz);
///   }
///
///   public void validate(Object target, Errors errors) {
///     ValidationUtils.rejectIfEmptyOrWhitespace(errors, "name", "required");
///     SignupForm form = (SignupForm) target;
///     if (!form.getPassword().equals(form.getConfirmPassword())) {
///       errors.rejectValue("confirmPassword", "mismatch");
///     }
///   }
/// }
/// ```
abstract interface class Validator {
  /// Whether this validator knows how to check [target]; usually a type
  /// test such as `target is SignupForm`.
  ///
  /// `DataBinder.validate` skips validators that return `false`, and
  /// [ValidationUtils.invokeValidator] throws for them. Spring's
  /// `supports(Class)` takes the class instead.
  bool supports(Object target);

  /// Checks [target] and records every problem in [errors], with
  /// [Errors.rejectValue] for a field or [Errors.reject] for the whole
  /// object. Records nothing when [target] is valid; does not throw for
  /// invalid data.
  void validate(Object target, Errors errors);
}

/// A [Validator] that can check only the constraints of some validation
/// groups.
///
/// Groups let one class carry rules for different situations: an `id` that
/// must be empty on create and set on update, checks that only run before
/// an order is shipped. `BeanValidator` is the implementation;
/// applications receive it rather than write one. The framework calls
/// [validateWithGroups] when `@Validated([OnUpdate])` names groups, and so
/// do `DataBinder.validate` and [ValidationUtils.invokeValidator] when
/// they are given groups.
///
/// ```dart
/// // Check only the constraints declared with groups: [OnUpdate].
/// final errors = BeanPropertyBindingResult(form, 'signup');
/// validator.validateWithGroups(form, errors, [OnUpdate]);
/// ```
///
/// Spring (Java):
/// ```java
/// SmartValidator validator = new LocalValidatorFactoryBean();
/// Errors errors = new BeanPropertyBindingResult(form, "signup");
/// validator.validate(form, errors, OnUpdate.class);
/// ```
abstract interface class SmartValidator implements Validator {
  /// Checks [target] against the constraints of [groups] only and records
  /// the problems in [errors].
  ///
  /// An empty list means the `Default` group, as in [validate]. Spring's
  /// `validate(target, errors, validationHints...)`.
  void validateWithGroups(Object target, Errors errors, List<Type> groups);
}

/// Static helpers for writing and running a [Validator].
///
/// The two `reject...` helpers save the most common check of a hand-written
/// validator, a required field. [invokeValidator] runs a validator with the
/// checks a caller would otherwise repeat.
///
/// ```dart
/// // A blank name is rejected with the code `required`.
/// final errors = MapBindingResult({'name': ' '}, 'form');
/// ValidationUtils.rejectIfEmptyOrWhitespace(errors, 'name', 'required');
/// errors.fieldError('name')!.codes.first; // 'required.form.name'
/// ```
///
/// Spring (Java):
/// ```java
/// Errors errors = new MapBindingResult(Map.of("name", " "), "form");
/// ValidationUtils.rejectIfEmptyOrWhitespace(errors, "name", "required");
/// errors.getFieldError("name").getCode(); // "required"
/// ```
abstract final class ValidationUtils {
  /// Runs [validator] on [target], recording problems in [errors].
  ///
  /// Throws an [ArgumentError] when [Validator.supports] returns `false`
  /// for [target]. Non-empty [groups] are passed on when [validator] is a
  /// [SmartValidator] and ignored otherwise.
  ///
  /// ```dart
  /// // Only the update rules of the form.
  /// ValidationUtils.invokeValidator(
  ///   BeanValidator(),
  ///   form,
  ///   errors,
  ///   groups: [OnUpdate],
  /// );
  /// ```
  static void invokeValidator(
    Validator validator,
    Object target,
    Errors errors, {
    List<Type> groups = const [],
  }) {
    if (!validator.supports(target)) {
      throw ArgumentError.value(
        target,
        'target',
        'Validator ${validator.runtimeType} does not support '
            '${target.runtimeType}',
      );
    }
    if (groups.isNotEmpty && validator is SmartValidator) {
      validator.validateWithGroups(target, errors, groups);
    } else {
      validator.validate(target, errors);
    }
  }

  /// Records an [errorCode] error on [field] when its value is `null`, an
  /// empty string, or an empty list, set or map.
  ///
  /// The value is read with [Errors.getFieldValue]. Numbers and other
  /// objects never count as empty. [args] and [defaultMessage] are stored
  /// on the field error, for its message.
  static void rejectIfEmpty(
    Errors errors,
    String field,
    String errorCode, {
    List<Object?> args = const [],
    String? defaultMessage,
  }) {
    final value = errors.getFieldValue(field);
    if (_isEmpty(value, trim: false)) {
      errors.rejectValue(
        field,
        errorCode,
        args: args,
        defaultMessage: defaultMessage,
      );
    }
  }

  /// Like [rejectIfEmpty], but a string of only whitespace is rejected
  /// too.
  ///
  /// [args] and [defaultMessage] are stored on the field error, for its
  /// message.
  static void rejectIfEmptyOrWhitespace(
    Errors errors,
    String field,
    String errorCode, {
    List<Object?> args = const [],
    String? defaultMessage,
  }) {
    final value = errors.getFieldValue(field);
    if (_isEmpty(value, trim: true)) {
      errors.rejectValue(
        field,
        errorCode,
        args: args,
        defaultMessage: defaultMessage,
      );
    }
  }

  // Values of other types (numbers, objects) are never "empty".
  static bool _isEmpty(Object? value, {required bool trim}) => switch (value) {
    null => true,
    String() => (trim ? value.trim() : value).isEmpty,
    Iterable<Object?>() => value.isEmpty,
    Map<Object?, Object?>() => value.isEmpty,
    _ => false,
  };
}
