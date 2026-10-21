import 'package:spring_core_dart/src/beans/bean_wrapper.dart';
import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';
import 'package:spring_core_dart/src/validation/errors.dart';
import 'package:spring_core_dart/src/validation/validator.dart';

/// Binds values (e.g. form input) onto an `@Introspected` object and
/// validates it, like Spring's `DataBinder`.
///
/// ```dart
/// final form = SignupForm();
/// final binder = DataBinder(form, objectName: 'signup')
///   ..requiredFields = ['email']
///   ..disallowedFields = ['id']
///   ..validators.add(BeanValidator())
///   ..bind({'name': 'Ada', 'age': '36', 'address.city': 'Oslo'})
///   ..validate();
/// if (binder.bindingResult.hasErrors) {
///   print(binder.bindingResult.fieldErrors());
/// }
/// final model = binder.close(); // {signup: form, BindingResult.signup: ...}
/// ```
///
/// Values are converted to the property types; conversion failures become
/// `typeMismatch` field errors that keep the rejected input.
///
/// Spring (Java):
/// ```java
/// DataBinder binder = new DataBinder(form, "signup");
/// binder.setRequiredFields("email");
/// binder.setDisallowedFields("id");
/// binder.addValidators(validator);
/// MutablePropertyValues values = new MutablePropertyValues();
/// values.add("name", "Ada");
/// values.add("age", "36");
/// values.add("address.city", "Oslo");
/// binder.bind(values);
/// binder.validate();
/// BindingResult result = binder.getBindingResult();
/// Map<?, ?> model = binder.close(); // throws BindException on errors
/// ```
class DataBinder {
  /// Creates a binder for [target], exposed as [objectName] in messages
  /// and the model.
  ///
  /// [introspector], [conversionService] and [messageCodesResolver]
  /// customize property access, value conversion and error codes.
  DataBinder(
    Object target, {
    String objectName = defaultObjectName,
    BeanIntrospector? introspector,
    ConversionService? conversionService,
    MessageCodesResolver messageCodesResolver =
        const DefaultMessageCodesResolver(),
  }) : this._(
         target,
         objectName,
         introspector,
         conversionService ?? DefaultConversionService.sharedInstance,
         messageCodesResolver,
       );

  // Resolves the conversion service once, so the binder and its binding
  // result (which formats rejected values) use the same one.
  DataBinder._(
    this.target,
    this.objectName,
    BeanIntrospector? introspector,
    this.conversionService,
    MessageCodesResolver messageCodesResolver,
  ) : bindingResult = BeanPropertyBindingResult(
        target,
        objectName,
        introspector: introspector,
        conversionService: conversionService,
        messageCodesResolver: messageCodesResolver,
      );

  /// Object name used when none is given, like Spring's
  /// `DataBinder.DEFAULT_OBJECT_NAME`.
  static const defaultObjectName = 'target';

  /// The object values are bound onto.
  final Object target;

  /// Name of the target in error codes and the model.
  final String objectName;

  /// Converts input values (usually strings) to property types.
  final ConversionService conversionService;

  /// Errors from binding and validation.
  final BeanPropertyBindingResult bindingResult;

  /// Only these fields may be bound (`*` wildcards); `null` allows all.
  List<String>? allowedFields;

  /// These fields are never bound (`*` wildcards).
  List<String> disallowedFields = const [];

  /// Fields that must be present and non-empty.
  List<String> requiredFields = const [];

  /// Silently skip fields the target does not have.
  bool ignoreUnknownFields = true;

  /// Silently skip fields with a `null` nested path.
  bool ignoreInvalidFields = false;

  /// Create `null` nested objects while binding nested paths.
  bool autoGrowNestedPaths = true;

  /// Validators run by [validate].
  final validators = <Validator>[];

  /// Fields skipped because they were not allowed.
  ///
  /// Accumulates over all [bind] calls, like Spring's
  /// `BindingResult.getSuppressedFields()`.
  List<String> get suppressedFields => List.unmodifiable(_suppressed);

  final _suppressed = <String>[];

  // A fresh wrapper per bind so the current [autoGrowNestedPaths] and
  // [conversionService] apply.
  BeanWrapper get _wrapper => BeanWrapper(
    target,
    introspector: bindingResult.wrapper.introspector,
    conversionService: conversionService,
    autoGrowNestedPaths: autoGrowNestedPaths,
  );

  /// Binds [values] onto the target.
  ///
  /// Keys are property paths (`name`, `address.city`, `items[0].sku`).
  /// Disallowed keys are skipped (see [suppressedFields]); missing
  /// [requiredFields] get `required` errors; conversion failures get
  /// `typeMismatch` errors; unknown or unreachable fields throw unless
  /// [ignoreUnknownFields] / [ignoreInvalidFields] allow skipping them.
  ///
  /// ```dart
  /// binder.bind({'age': 'old'});
  /// binder.bindingResult.fieldError('age')!.codes.first; // typeMismatch.signup.age
  /// ```
  void bind(Map<String, Object?> values) {
    final accepted = <String, Object?>{};
    for (final MapEntry(key: raw, :value) in values.entries) {
      // Matched and bound under one canonical name, so `roles['admin']`,
      // `roles["admin"]` or `roles[ admin ]` cannot slip past a
      // `roles[admin]` rule (Spring's canonicalPropertyName).
      final key = canonicalPropertyName(raw);
      if (_isAllowed(key)) {
        accepted[key] = value;
      } else {
        _suppressed.add(key);
      }
    }
    // Required fields are checked on the accepted input only, so a
    // disallowed field also counts as missing.
    for (final field in requiredFields) {
      final value = accepted[field];
      if (value == null || (value is String && value.trim().isEmpty)) {
        bindingResult.recordFieldError(
          field,
          'required',
          value,
          defaultMessage: "Field '$field' is required",
        );
        accepted.remove(field);
      }
    }
    final wrapper = _wrapper;
    for (final MapEntry(:key, :value) in accepted.entries) {
      try {
        wrapper.setPropertyValue(key, value);
      } on TypeMismatchException catch (error) {
        bindingResult.recordFieldError(
          key,
          TypeMismatchException.errorCode,
          value,
          args: [error.requiredType],
          defaultMessage: error.message,
          fieldType: error.requiredType,
        );
      } on NotWritablePropertyException {
        if (!ignoreUnknownFields) {
          rethrow;
        }
      } on NullValueInNestedPathException {
        if (!ignoreInvalidFields) {
          rethrow;
        }
      } on NotReadablePropertyException {
        if (!ignoreInvalidFields) {
          rethrow;
        }
      } on BeansException catch (error) {
        // Any other property access failure (e.g. a throwing setter).
        bindingResult.recordFieldError(
          key,
          'methodInvocation',
          value,
          defaultMessage: error.message,
        );
      }
    }
  }

  /// Runs every validator that supports the target.
  ///
  /// Non-empty [groups] restrict [SmartValidator]s to those groups.
  ///
  /// ```dart
  /// binder.validate(groups: [OnUpdate]);
  /// ```
  void validate({List<Type> groups = const []}) {
    for (final validator in validators) {
      if (validator.supports(target)) {
        ValidationUtils.invokeValidator(
          validator,
          target,
          bindingResult,
          groups: groups,
        );
      }
    }
  }

  /// The model map; throws [BindException] when there are errors.
  ///
  /// The map holds the target under [objectName] and the
  /// [bindingResult] under `BindingResult.<objectName>`.
  Map<String, Object?> close() {
    if (bindingResult.hasErrors) {
      throw BindException(bindingResult);
    }
    return bindingResult.model;
  }

  // Allowed when it matches an allowed pattern (or none are set) and no
  // disallowed pattern; disallowed wins.
  //
  // Disallowed patterns are matched case-insensitively (Spring's fix for
  // CVE-2022-22968) and also against the bracket form of dotted paths, so
  // `roles.admin` (a map value reached as a property) is caught by
  // `roles[admin]`.
  bool _isAllowed(String field) {
    final allowed = allowedFields;
    if (allowed != null && !allowed.any((p) => simpleMatch(p, field))) {
      return false;
    }
    final candidates = {field.toLowerCase(), _bracketForm(field).toLowerCase()};
    return !disallowedFields.any((pattern) {
      final lower = pattern.toLowerCase();
      return candidates.any((c) => simpleMatch(lower, c));
    });
  }

  // `a.b.c` → `a[b][c]` (keys inside brackets are kept).
  static String _bracketForm(String path) {
    final first = path.indexOf('.');
    if (first < 0) {
      return path;
    }
    final head = path.substring(0, first);
    final rest = path.substring(first + 1).split('.');
    return '$head${rest.map((segment) => '[$segment]').join()}';
  }

  /// [name] with quotes and surrounding blanks removed from map keys and
  /// indexes: `map['key']`, `map["key"]` and `map[ key ]` all become
  /// `map[key]`, like Spring's `PropertyAccessorUtils.canonicalPropertyName`.
  ///
  /// ```dart
  /// DataBinder.canonicalPropertyName("roles['admin']"); // roles[admin]
  /// ```
  static String canonicalPropertyName(String name) =>
      name.replaceAllMapped(RegExp(r'\[([^\]]*)\]'), (match) {
        var key = match.group(1)!.trim();
        if (key.length >= 2 &&
            (key.startsWith("'") && key.endsWith("'") ||
                key.startsWith('"') && key.endsWith('"'))) {
          key = key.substring(1, key.length - 1);
        }
        return '[$key]';
      });

  /// `*` wildcard matching, like Spring's `PatternMatchUtils.simpleMatch`.
  ///
  /// ```dart
  /// DataBinder.simpleMatch('address.*', 'address.city'); // true
  /// ```
  static bool simpleMatch(String pattern, String text) {
    final regex = RegExp(
      '^${pattern.split('*').map(RegExp.escape).join('.*')}\$',
      dotAll: true,
    );
    return regex.hasMatch(text);
  }
}
