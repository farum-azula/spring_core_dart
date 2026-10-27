import 'package:spring_core_dart/src/beans/bean_wrapper.dart';
import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';

/// An error of the whole object, like Spring's `ObjectError`.
///
/// It is a [MessageSourceResolvable], so a `MessageSource` can turn it
/// into a localized message.
///
/// ```dart
/// final result = BeanPropertyBindingResult(form, 'signup')
///   ..reject('passwordsMismatch', defaultMessage: 'passwords differ');
/// final error = result.globalError!;
/// print(error.codes); // [passwordsMismatch.signup, passwordsMismatch]
/// print(messageSource.getMessageFromResolvable(error));
/// ```
///
/// Spring (Java):
/// ```java
/// BindingResult result = new BeanPropertyBindingResult(form, "signup");
/// result.reject("passwordsMismatch", "passwords differ");
/// ObjectError error = result.getGlobalError();
/// messageSource.getMessage(error, Locale.getDefault());
/// ```
class ObjectError implements MessageSourceResolvable, DefaultMessageRendering {
  /// Creates an error of [objectName] with message [codes] (most specific
  /// first), optional message [arguments] and a [defaultMessage].
  ObjectError(
    this.objectName,
    List<String> codes, {
    List<Object?> arguments = const [],
    this.defaultMessage,
    this.shouldRenderDefaultMessage = true,
  }) : codes = List.unmodifiable(codes),
       arguments = List.unmodifiable(arguments);

  /// Whether [defaultMessage] is formatted with [arguments]; `false` for
  /// Bean Validation messages without `{0}`-style placeholders (Spring's
  /// `ViolationFieldError`).
  @override
  final bool shouldRenderDefaultMessage;

  /// Name of the validated object, e.g. `signup`.
  final String objectName;

  @override
  final List<String> codes;

  @override
  final List<Object?> arguments;

  @override
  final String? defaultMessage;

  /// The plain error code, i.e. the last (least specific) code, like
  /// Spring's `getCode()`: `NotBlank` for the codes
  /// `[NotBlank.signup.name, NotBlank.name, NotBlank.String, NotBlank]`.
  ///
  /// Use `codes.first` for the most specific code.
  String get code => codes.last;

  @override
  String toString() =>
      "Error in object '$objectName': codes $codes; arguments $arguments; "
      'default message [$defaultMessage]';
}

/// An error of one field, like Spring's `FieldError`.
///
/// ```dart
/// final error = binder.bindingResult.fieldError('age')!;
/// error.field; // 'age'
/// error.rejectedValue; // 'old'
/// error.bindingFailure; // true: 'old' is not an int
/// ```
///
/// Spring (Java):
/// ```java
/// FieldError error = binder.getBindingResult().getFieldError("age");
/// error.getField();
/// error.getRejectedValue();
/// error.isBindingFailure();
/// ```
class FieldError extends ObjectError {
  /// Creates an error of [field] of [objectName] that rejected
  /// [rejectedValue].
  FieldError(
    super.objectName,
    this.field,
    this.rejectedValue,
    super.codes, {
    super.arguments,
    super.defaultMessage,
    super.shouldRenderDefaultMessage,
    this.bindingFailure = false,
  });

  /// Full property path of the field, e.g. `address.city`.
  final String field;

  /// The value that was rejected (the raw input for binding failures).
  final Object? rejectedValue;

  /// Whether the error comes from binding (type mismatch) rather than
  /// validation.
  final bool bindingFailure;

  @override
  String toString() =>
      "Field error in object '$objectName' on field '$field': rejected value "
      '[$rejectedValue]; codes $codes; arguments $arguments; default message '
      '[$defaultMessage]';
}

/// Builds message codes for errors, like Spring's `MessageCodesResolver`.
///
/// ```dart
/// class UpperCodes implements MessageCodesResolver {
///   @override
///   List<String> resolveMessageCodes(String errorCode, String objectName) =>
///       [errorCode.toUpperCase()];
///
///   @override
///   List<String> resolveFieldMessageCodes(
///     String errorCode,
///     String objectName,
///     String field,
///     Type? fieldType,
///   ) => ['${errorCode.toUpperCase()}.$field'];
/// }
///
/// DataBinder(form, messageCodesResolver: UpperCodes());
/// ```
///
/// Spring (Java):
/// ```java
/// class UpperCodes implements MessageCodesResolver {
///   public String[] resolveMessageCodes(String code, String objectName) {
///     return new String[] {code.toUpperCase()};
///   }
///
///   public String[] resolveMessageCodes(
///       String code, String objectName, String field, Class<?> type) {
///     return new String[] {code.toUpperCase() + "." + field};
///   }
/// }
///
/// binder.setMessageCodesResolver(new UpperCodes());
/// ```
abstract interface class MessageCodesResolver {
  /// Codes for a global error, most specific first.
  List<String> resolveMessageCodes(String errorCode, String objectName);

  /// Codes for an error of [field] (of [fieldType], when known), most
  /// specific first.
  List<String> resolveFieldMessageCodes(
    String errorCode,
    String objectName,
    String field,
    Type? fieldType,
  );
}

/// Spring's `DefaultMessageCodesResolver`: for code `NotBlank`, object
/// `user`, field `orders[0].sku` of type `String`:
/// `NotBlank.user.orders[0].sku`, `NotBlank.user.orders.sku`,
/// `NotBlank.orders[0].sku`, `NotBlank.orders.sku`, `NotBlank.sku`,
/// `NotBlank.String`, `NotBlank`.
///
/// Keys are removed one at a time from the last (`a[0][1].b` also gives
/// `a[0].b` and `a.b`), and the last path segment is a code of its own
/// (`NotBlank.city` for `address.city`), exactly as in Spring. The field
/// type is the Dart type name (`String`, not `java.lang.String`).
///
/// Global errors get `NotBlank.user` and `NotBlank`.
///
/// ```dart
/// const resolver = DefaultMessageCodesResolver(prefix: 'validation.');
/// resolver.resolveFieldMessageCodes('NotBlank', 'user', 'name', String);
/// // [validation.NotBlank.user.name, validation.NotBlank.name,
/// //  validation.NotBlank.String, validation.NotBlank]
/// ```
///
/// Spring (Java):
/// ```java
/// DefaultMessageCodesResolver resolver = new DefaultMessageCodesResolver();
/// resolver.setPrefix("validation.");
/// resolver.resolveMessageCodes("NotBlank", "user", "name", String.class);
/// ```
final class DefaultMessageCodesResolver implements MessageCodesResolver {
  /// Creates a resolver with an optional code [prefix]; [postfixFormat]
  /// puts the error code last.
  const DefaultMessageCodesResolver({
    this.prefix = '',
    this.postfixFormat = false,
  });

  /// Prepended to every code.
  final String prefix;

  /// Spring's `POSTFIX_ERROR_CODE` format (`user.name.NotBlank`).
  final bool postfixFormat;

  @override
  List<String> resolveMessageCodes(String errorCode, String objectName) => [
    _code(errorCode, objectName),
    _code(errorCode, null),
  ];

  @override
  List<String> resolveFieldMessageCodes(
    String errorCode,
    String objectName,
    String field,
    Type? fieldType,
  ) {
    // Spring's algorithm: the field and its key-free forms qualified by
    // the object name, then unqualified plus the last path segment (and
    // its key-free forms), the field type and the bare code. A set drops
    // duplicates while keeping that order.
    final fields = _fieldList(field);
    final codes = <String>{
      for (final f in fields) _code(errorCode, '$objectName.$f'),
    };
    final dot = field.lastIndexOf('.');
    if (dot >= 0) {
      fields.addAll(_fieldList(field.substring(dot + 1)));
    }
    codes
      ..addAll([for (final f in fields) _code(errorCode, f)])
      ..addAll([
        if (fieldType != null) _code(errorCode, '$fieldType'),
        _code(errorCode, null),
      ]);
    return codes.toList();
  }

  // `a[0][1].b` → [a[0][1].b, a[0].b, a.b]: keys removed from the last
  // (Spring's buildFieldList).
  static List<String> _fieldList(String field) {
    final fields = [field];
    var plain = field;
    var open = plain.lastIndexOf('[');
    while (open >= 0) {
      final close = plain.indexOf(']', open);
      if (close < 0) {
        break;
      }
      plain = plain.substring(0, open) + plain.substring(close + 1);
      fields.add(plain);
      open = plain.lastIndexOf('[');
    }
    return fields;
  }

  String _code(String errorCode, String? suffix) {
    if (suffix == null) {
      return '$prefix$errorCode';
    }
    return postfixFormat
        ? '$prefix$suffix.$errorCode'
        : '$prefix$errorCode.$suffix';
  }
}

/// Collects errors for an object, like Spring's `Errors`.
///
/// Validators receive it to record global errors ([reject]) and field
/// errors ([rejectValue]). Nested paths let a validator for a nested
/// object report fields relative to it.
///
/// ```dart
/// void validateAddress(Address address, Errors errors) {
///   errors.pushNestedPath('address');
///   ValidationUtils.rejectIfEmpty(errors, 'city', 'required');
///   errors.popNestedPath(); // the error is on 'address.city'
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// errors.pushNestedPath("address");
/// ValidationUtils.rejectIfEmpty(errors, "city", "required");
/// errors.popNestedPath();
/// ```
abstract interface class Errors {
  /// Name of the validated object, used in message codes.
  String get objectName;

  /// Prefix applied to field names (e.g. `address.`).
  String get nestedPath;

  /// Replaces the nested path (a trailing `.` is added) and clears the
  /// nested path stack.
  set nestedPath(String path);

  /// Appends [subPath] to the nested path, remembering the current one
  /// for [popNestedPath].
  void pushNestedPath(String subPath);

  /// Restores the nested path saved by the last [pushNestedPath]; throws a
  /// [StateError] when there is none.
  void popNestedPath();

  /// Adds a global error.
  ///
  /// With [renderDefaultMessage] `false` the default message is shown
  /// as-is instead of being formatted with [args].
  void reject(
    String errorCode, {
    List<Object?> args,
    String? defaultMessage,
    bool renderDefaultMessage,
  });

  /// Adds an error for [field] (relative to [nestedPath]).
  ///
  /// An empty [field] without a nested path adds a global error instead.
  void rejectValue(
    String field,
    String errorCode, {
    List<Object?> args,
    String? defaultMessage,
    bool renderDefaultMessage,
  });

  /// Adds every error of [errors], which must have the same [objectName].
  void addAllErrors(Errors errors);

  /// Whether any error was recorded.
  bool get hasErrors;

  /// Number of global and field errors.
  int get errorCount;

  /// Global and field errors in the order they were added.
  List<ObjectError> get allErrors;

  /// Whether any global error was recorded.
  bool get hasGlobalErrors;

  /// Errors that are not [FieldError]s.
  List<ObjectError> get globalErrors;

  /// The first global error, if any.
  ObjectError? get globalError;

  /// Whether there are field errors (for [field], which may end with `*`).
  bool hasFieldErrors([String? field]);

  /// Field errors, all or those of [field] (relative to [nestedPath];
  /// `address.*` matches every field under `address`).
  List<FieldError> fieldErrors([String? field]);

  /// The first error of [field] (or of any field when omitted).
  FieldError? fieldError([String? field]);

  /// The current value of [field], or the rejected value of its first
  /// error (binding failure or validation error), like Spring.
  Object? getFieldValue(String field);
}

/// [Errors] plus the target object, like Spring's `BindingResult`.
///
/// ```dart
/// final result = binder.bindingResult;
/// if (result.hasErrors) {
///   for (final error in result.fieldErrors()) {
///     print('${error.field}: ${error.defaultMessage}');
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// BindingResult result = binder.getBindingResult();
/// if (result.hasErrors()) {
///   for (FieldError error : result.getFieldErrors()) {
///     System.out.println(error.getField() + ": "
///         + error.getDefaultMessage());
///   }
/// }
/// ```
abstract interface class BindingResult implements Errors {
  /// Key under which a binding result is exposed in a model.
  static const modelKeyPrefix = 'BindingResult.';

  /// The object being bound or validated.
  Object? get target;

  /// Builds the message codes of new errors.
  MessageCodesResolver get messageCodesResolver;

  /// Adds a prepared [error]; its object name must match [objectName].
  void addError(ObjectError error);

  /// The field value without the rejected-value fallback.
  Object? getRawFieldValue(String field);

  /// Message codes for [errorCode], of [field] (relative to the nested
  /// path) when given, like Spring's `BindingResult.resolveMessageCodes`.
  ///
  /// ```dart
  /// result.resolveMessageCodes('NotBlank', 'name');
  /// // [NotBlank.signup.name, NotBlank.name, NotBlank.String, NotBlank]
  /// ```
  List<String> resolveMessageCodes(String errorCode, [String? field]);

  /// Records a binding failure (e.g. type mismatch) for [field].
  void recordFieldError(
    String field,
    String errorCode,
    Object? rejectedValue, {
    List<Object?> args,
    String? defaultMessage,
    Type? fieldType,
  });

  /// `{objectName: target, 'BindingResult.objectName': this}`.
  Map<String, Object?> get model;
}

/// Shared [BindingResult] logic, like Spring's `AbstractBindingResult`.
///
/// Subclasses provide [target], [getRawFieldValue] and [getFieldType].
///
/// ```dart
/// class RecordBindingResult extends AbstractBindingResult {
///   RecordBindingResult(this.target) : super('point');
///
///   @override
///   final ({int x, int y}) target;
///
///   @override
///   Object? getRawFieldValue(String field) =>
///       field == 'x' ? target.x : target.y;
///
///   @override
///   Type? getFieldType(String field) => int;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class PointBindingResult extends AbstractBindingResult {
///   PointBindingResult(Point target) { super("point"); ... }
///   public Object getTarget() { return target; }
///   protected Object getActualFieldValue(String field) { ... }
/// }
/// ```
abstract class AbstractBindingResult implements BindingResult {
  /// Creates an empty result for [objectName].
  AbstractBindingResult(
    this.objectName, {
    this.messageCodesResolver = const DefaultMessageCodesResolver(),
  });

  @override
  final String objectName;

  @override
  final MessageCodesResolver messageCodesResolver;

  final _errors = <ObjectError>[];
  String _nestedPath = '';
  final _nestedPathStack = <String>[];

  @override
  String get nestedPath => _nestedPath;

  @override
  set nestedPath(String path) {
    _nestedPath = _canonicalPath(path);
    _nestedPathStack.clear();
  }

  @override
  void pushNestedPath(String subPath) {
    _nestedPathStack.add(_nestedPath);
    _nestedPath = _canonicalPath('$_nestedPath$subPath');
  }

  @override
  void popNestedPath() {
    if (_nestedPathStack.isEmpty) {
      throw StateError('Cannot pop nested path: no nested path on stack');
    }
    _nestedPath = _nestedPathStack.removeLast();
  }

  // Nested paths always end with '.' so fields can simply be appended.
  static String _canonicalPath(String path) =>
      path.isEmpty || path.endsWith('.') ? path : '$path.';

  // The full path of [field]; an empty field means the nested object
  // itself (the nested path without its trailing dot).
  String _fixedField(String field) => field.isEmpty
      ? _nestedPath.replaceFirst(RegExp(r'\.$'), '')
      : '$_nestedPath$field';

  /// Declared type of [field], for message codes.
  Type? getFieldType(String field);

  @override
  List<String> resolveMessageCodes(String errorCode, [String? field]) {
    if (field == null) {
      return messageCodesResolver.resolveMessageCodes(errorCode, objectName);
    }
    final fixed = _fixedField(field);
    return messageCodesResolver.resolveFieldMessageCodes(
      errorCode,
      objectName,
      fixed,
      getFieldType(fixed),
    );
  }

  @override
  void reject(
    String errorCode, {
    List<Object?> args = const [],
    String? defaultMessage,
    bool renderDefaultMessage = true,
  }) => addError(
    ObjectError(
      objectName,
      messageCodesResolver.resolveMessageCodes(errorCode, objectName),
      arguments: args,
      defaultMessage: defaultMessage,
      shouldRenderDefaultMessage: renderDefaultMessage,
    ),
  );

  @override
  void rejectValue(
    String field,
    String errorCode, {
    List<Object?> args = const [],
    String? defaultMessage,
    bool renderDefaultMessage = true,
  }) {
    if (field.isEmpty && _nestedPath.isEmpty) {
      reject(
        errorCode,
        args: args,
        defaultMessage: defaultMessage,
        renderDefaultMessage: renderDefaultMessage,
      );
      return;
    }
    final fixed = _fixedField(field);
    addError(
      FieldError(
        objectName,
        fixed,
        getRawFieldValue(fixed),
        messageCodesResolver.resolveFieldMessageCodes(
          errorCode,
          objectName,
          fixed,
          getFieldType(fixed),
        ),
        arguments: args,
        defaultMessage: defaultMessage,
        shouldRenderDefaultMessage: renderDefaultMessage,
      ),
    );
  }

  @override
  void recordFieldError(
    String field,
    String errorCode,
    Object? rejectedValue, {
    List<Object?> args = const [],
    String? defaultMessage,
    Type? fieldType,
  }) {
    final fixed = _fixedField(field);
    addError(
      FieldError(
        objectName,
        fixed,
        rejectedValue,
        messageCodesResolver.resolveFieldMessageCodes(
          errorCode,
          objectName,
          fixed,
          fieldType ?? getFieldType(fixed),
        ),
        arguments: args,
        defaultMessage: defaultMessage,
        bindingFailure: true,
      ),
    );
  }

  @override
  void addError(ObjectError error) {
    if (error.objectName != objectName) {
      throw ArgumentError.value(
        error,
        'error',
        "Error belongs to object '${error.objectName}', not '$objectName'",
      );
    }
    _errors.add(error);
  }

  @override
  void addAllErrors(Errors errors) {
    if (errors.objectName != objectName) {
      throw ArgumentError.value(errors, 'errors', 'Different object name');
    }
    _errors.addAll(errors.allErrors);
  }

  @override
  bool get hasErrors => _errors.isNotEmpty;

  @override
  int get errorCount => _errors.length;

  @override
  List<ObjectError> get allErrors => List.unmodifiable(_errors);

  @override
  bool get hasGlobalErrors => globalErrors.isNotEmpty;

  @override
  List<ObjectError> get globalErrors =>
      List.unmodifiable(_errors.where((e) => e is! FieldError));

  @override
  ObjectError? get globalError => globalErrors.firstOrNull;

  @override
  bool hasFieldErrors([String? field]) => fieldErrors(field).isNotEmpty;

  @override
  List<FieldError> fieldErrors([String? field]) {
    final all = _errors.whereType<FieldError>();
    if (field == null) {
      return List.unmodifiable(all);
    }
    final fixed = _fixedField(field);
    // A trailing '*' is a prefix match (`address.*`); otherwise exact.
    return List.unmodifiable(
      all.where(
        (e) => fixed.endsWith('*')
            ? e.field.startsWith(fixed.substring(0, fixed.length - 1))
            : e.field == fixed,
      ),
    );
  }

  @override
  FieldError? fieldError([String? field]) => fieldErrors(field).firstOrNull;

  @override
  Object? getFieldValue(String field) {
    // Like Spring: a field with an error shows the rejected value (the
    // user's input after a binding failure, the invalid value after a
    // validation error), so a form is re-rendered with what was entered.
    final error = fieldError(field);
    if (error != null) {
      return error.rejectedValue;
    }
    return getRawFieldValue(_fixedField(field));
  }

  @override
  Map<String, Object?> get model => {
    objectName: target,
    '${BindingResult.modelKeyPrefix}$objectName': this,
  };

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $errorCount errors');
    for (final error in _errors) {
      buffer.write('\n$error');
    }
    return buffer.toString();
  }
}

/// Binding result for an introspected object, like Spring's
/// `BeanPropertyBindingResult`.
///
/// Field values and types are read through a [BeanWrapper], so nested
/// paths such as `address.city` and `items[0].sku` work.
///
/// ```dart
/// final errors = BeanPropertyBindingResult(form, 'signup');
/// BeanValidator().validate(form, errors);
/// errors.fieldError('name')?.codes;
/// // [NotBlank.signup.name, NotBlank.name, NotBlank.String, NotBlank]
/// ```
///
/// Spring (Java):
/// ```java
/// Errors errors = new BeanPropertyBindingResult(form, "signup");
/// validator.validate(form, errors);
/// errors.getFieldError("name").getCodes();
/// ```
class BeanPropertyBindingResult extends AbstractBindingResult {
  /// Creates an empty result for [target] named [objectName].
  ///
  /// `introspector` and `conversionService` configure the [wrapper]. The
  /// target is `null` while `DataBinder.construct` failed to create it;
  /// field values and types then come from [recordFieldValue].
  BeanPropertyBindingResult(
    this.target,
    super.objectName, {
    this._introspector,
    this._conversionService,
    super.messageCodesResolver,
  });

  @override
  final Object? target;

  final BeanIntrospector? _introspector;
  final ConversionService? _conversionService;
  final _fieldValues = <String, Object?>{};
  final _fieldTypes = <String, Type?>{};

  /// Access to the target's properties; throws a [StateError] when there
  /// is no target.
  late final BeanWrapper wrapper = BeanWrapper(
    target ?? (throw StateError('No target object for $objectName')),
    introspector: _introspector,
    conversionService: _conversionService,
  );

  /// Remembers [value] (of [type]) for [field] when there is no target,
  /// like Spring's `recordFieldValue` (constructor binding).
  void recordFieldValue(String field, Type? type, Object? value) {
    _fieldValues[field] = value;
    _fieldTypes[field] = type;
  }

  // Unknown or unreadable paths have no value rather than failing the
  // error recording.
  @override
  Object? getRawFieldValue(String field) {
    if (target == null) {
      return _fieldValues[field];
    }
    try {
      return wrapper.getPropertyValue(field);
    } on BeansException {
      return null;
    }
  }

  @override
  Type? getFieldType(String field) =>
      target == null ? _fieldTypes[field] : wrapper.getPropertyType(field);
}

/// Binding result for a map target, like Spring's `MapBindingResult`.
///
/// Field types are the runtime types of the current values.
///
/// ```dart
/// final errors = MapBindingResult({'email': ''}, 'request');
/// ValidationUtils.rejectIfEmpty(errors, 'email', 'required');
/// errors.hasFieldErrors('email'); // true
/// ```
///
/// Spring (Java):
/// ```java
/// Map<String, Object> values = new HashMap<>(Map.of("email", ""));
/// Errors errors = new MapBindingResult(values, "request");
/// ValidationUtils.rejectIfEmpty(errors, "email", "required");
/// errors.hasFieldErrors("email");
/// ```
class MapBindingResult extends AbstractBindingResult {
  /// Creates an empty result for the map [target] named [objectName].
  MapBindingResult(this.target, super.objectName, {super.messageCodesResolver});

  @override
  final Map<String, Object?> target;

  @override
  Object? getRawFieldValue(String field) => target[field];

  @override
  Type? getFieldType(String field) => target[field]?.runtimeType;
}

/// Thrown when binding or validation produced errors, like Spring's
/// `BindException`.
///
/// ```dart
/// try {
///   final model = binder.close();
/// } on BindException catch (e) {
///   print(e.bindingResult.errorCount);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   Map<?, ?> model = binder.close();
/// } catch (BindException e) {
///   System.out.println(e.getBindingResult().getErrorCount());
/// }
/// ```
class BindException implements Exception {
  /// Creates an exception reporting the errors of [bindingResult].
  BindException(this.bindingResult);

  /// The result holding the errors.
  final BindingResult bindingResult;

  @override
  String toString() => 'BindException: $bindingResult';
}
