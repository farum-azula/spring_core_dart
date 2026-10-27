import 'package:spring_core_dart/src/validation/errors.dart';

/// Validates objects, like Spring's `Validator`.
///
/// `supports` receives the target itself (Dart cannot test subtypes on a
/// `Type`).
///
/// ```dart
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
  /// Whether this validator can validate [target] (Spring's
  /// `supports(Class)` takes the class instead).
  bool supports(Object target);

  /// Validates [target], recording problems in [errors].
  void validate(Object target, Errors errors);
}

/// A [Validator] that understands validation groups, like Spring's
/// `SmartValidator`.
///
/// ```dart
/// final validator = BeanValidator();
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
  /// Validates [target] against the constraints of [groups] only (like
  /// Spring's `validate(target, errors, validationHints...)`).
  void validateWithGroups(Object target, Errors errors, List<Type> groups);
}

/// Helpers for validators, like Spring's `ValidationUtils`.
///
/// ```dart
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
  /// Runs [validator] on [target]; throws [ArgumentError] when it does not
  /// support it.
  ///
  /// Non-empty [groups] are passed on when [validator] is a
  /// [SmartValidator] and ignored otherwise.
  ///
  /// ```dart
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

  /// Rejects [field] when it is `null` or an empty string/collection.
  ///
  /// [args] and [defaultMessage] are stored on the resulting field error.
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

  /// Rejects [field] when it is `null`, empty or only whitespace.
  ///
  /// [args] and [defaultMessage] are stored on the resulting field error.
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
