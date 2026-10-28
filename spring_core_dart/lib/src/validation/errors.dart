import 'package:spring_core_dart/src/beans/bean_wrapper.dart';
import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';

/// A validation error about a whole object rather than one of its fields,
/// such as "the passwords differ" or a failed class-level constraint.
///
/// Its text is not fixed. It carries message [codes], from the most
/// specific (`passwordsMismatch.signup`) to the plain one
/// (`passwordsMismatch`), with [arguments] and a [defaultMessage] for when
/// no code is defined. A `MessageSource` turns it into text in the user's
/// language, using the first code `messages.properties` defines; this is
/// how the web starter writes the messages of a 400.
///
/// Applications receive it in [Errors.globalErrors] (for example from a
/// `MethodArgumentNotValidException` in an exception handler) and rarely
/// create one: [Errors.reject] builds it with the right codes. A
/// [FieldError] is the variant for one field.
///
/// ```dart
/// // A validator rejects the whole form; the message comes from
/// // `passwordsMismatch=...` in messages.properties, if defined.
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
  /// An error of the object named [objectName], with message [codes] (most
  /// specific first), message [arguments] and a [defaultMessage] for when
  /// no code has a message.
  ///
  /// [Errors.reject] is the usual way to make one; call this to build an
  /// error for [BindingResult.addError].
  ObjectError(
    this.objectName,
    List<String> codes, {
    List<Object?> arguments = const [],
    this.defaultMessage,
    this.shouldRenderDefaultMessage = true,
  }) : codes = List.unmodifiable(codes),
       arguments = List.unmodifiable(arguments);

  /// Whether a message source formats [defaultMessage] with [arguments]
  /// (`{0}`, `{1}`) before showing it; `true` by default.
  ///
  /// The validator sets it to `false` for constraint messages that contain
  /// no `{0}`-style placeholder, so a regular expression such as `\d{2,3}`
  /// in the text is shown as written, like Spring's `ViolationFieldError`.
  @override
  final bool shouldRenderDefaultMessage;

  /// Name of the validated object, such as `signup`; part of the message
  /// codes. The web starter uses the name of the validated parameter.
  final String objectName;

  @override
  final List<String> codes;

  @override
  final List<Object?> arguments;

  @override
  final String? defaultMessage;

  /// The plain error code, the last and least specific of [codes]:
  /// `NotBlank` for `[NotBlank.signup.name, NotBlank.name, NotBlank.String,
  /// NotBlank]`. For a failed constraint it is the constraint's name.
  ///
  /// Use it to react to a kind of error in code; use `codes.first` for the
  /// most specific code. Spring's `getCode()`.
  String get code => codes.last;

  @override
  String toString() =>
      "Error in object '$objectName': codes $codes; arguments $arguments; "
      'default message [$defaultMessage]';
}

/// A validation or binding error about one field of an object: which field,
/// the value that was rejected, and the message codes.
///
/// There are two kinds. A binding failure ([bindingFailure] is `true`)
/// means the input could not be stored at all, such as `'old'` for an
/// `int`; its code is `typeMismatch` and [rejectedValue] is the raw input.
/// A validation error means the value was stored but breaks a rule, such
/// as `@Min(18)`; its code is the constraint's name.
///
/// Applications read field errors to show them next to form fields or to
/// shape an error response; they get them from
/// [BindingResult.fieldErrors]. The web starter already writes each one
/// into a 400 as `field`, `message` and `rejectedValue`.
///
/// ```dart
/// // After binding `{'age': 'old'}` onto a form with an int age.
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
  /// An error of [field] of the object [objectName] that rejected
  /// [rejectedValue]; [bindingFailure] marks a value that could not be
  /// converted.
  ///
  /// [Errors.rejectValue] is the usual way to make one.
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

  /// Full property path of the field, such as `name`, `address.city` or
  /// `items[0].sku`.
  final String field;

  /// The value that was rejected: the raw input for a binding failure, the
  /// invalid value for a validation error. Show it to let the user fix
  /// what they typed.
  final Object? rejectedValue;

  /// Whether the input could not be stored in the field (for example text
  /// for a number) rather than breaking a constraint. A field with a
  /// binding failure gets no constraint errors on top.
  final bool bindingFailure;

  @override
  String toString() =>
      "Field error in object '$objectName' on field '$field': rejected value "
      '[$rejectedValue]; codes $codes; arguments $arguments; default message '
      '[$defaultMessage]';
}

/// The rule that turns an error code and a field into the list of message
/// codes an error carries.
///
/// The codes decide which keys of `messages.properties` can give the
/// message of an error. [DefaultMessageCodesResolver] is Spring's scheme
/// (`NotBlank.signup.name`, `NotBlank.name`, ..., `NotBlank`) and almost
/// every application keeps it. Implement this interface only to use other
/// keys, for example to match an existing translation file, and pass it to
/// `DataBinder` or a binding result.
///
/// ```dart
/// // Upper-case codes: `NOTBLANK.name` in the message file.
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
  /// The codes of an error of the whole object [objectName] with
  /// [errorCode], most specific first.
  List<String> resolveMessageCodes(String errorCode, String objectName);

  /// The codes of an error of [field] of [objectName] with [errorCode],
  /// most specific first. [fieldType] is the declared type of the field,
  /// `null` when unknown.
  List<String> resolveFieldMessageCodes(
    String errorCode,
    String objectName,
    String field,
    Type? fieldType,
  );
}

/// The standard message codes of errors, the ones every binding result and
/// validator uses unless told otherwise.
///
/// You do not call it; you need its scheme to name the keys of
/// `messages.properties`. An error carries several codes, from specific to
/// general, and the first key the message file defines wins. So
/// `NotBlank=must not be empty` covers every `@NotBlank()`, while
/// `NotBlank.signup.name=Please enter your name` covers one field of one
/// object.
///
/// For code `NotBlank`, object `user` and field `orders[0].sku` of type
/// `String`, the codes are: `NotBlank.user.orders[0].sku`,
/// `NotBlank.user.orders.sku`, `NotBlank.orders[0].sku`,
/// `NotBlank.orders.sku`, `NotBlank.sku`, `NotBlank.String`, `NotBlank`.
/// Indexes and keys are removed one at a time from the last (`a[0][1].b`
/// also gives `a[0].b` and `a.b`), and the last path segment gets a code
/// of its own (`NotBlank.city` for `address.city`), exactly as in Spring.
/// The type is the Dart type name (`String`, not `java.lang.String`). An
/// error of the whole object gets `NotBlank.user` and `NotBlank`.
///
/// Create one with a [prefix] or [postfixFormat] to change the keys, and
/// pass it to `DataBinder(messageCodesResolver: ...)`.
///
/// ```dart
/// // All validation keys under `validation.` in the message file.
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
  /// A resolver that puts [prefix] before every code, and the error code
  /// last when [postfixFormat] is `true`. The defaults give Spring's codes.
  const DefaultMessageCodesResolver({
    this.prefix = '',
    this.postfixFormat = false,
  });

  /// Text put before every code, such as `validation.`; empty by default.
  final String prefix;

  /// Whether the error code comes last (`user.name.NotBlank`) instead of
  /// first (`NotBlank.user.name`); `false` by default. Spring's
  /// `POSTFIX_ERROR_CODE` format.
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

/// The list of errors found for one object, and the way a validator
/// records them.
///
/// A `Validator` receives it in `validate` and calls [rejectValue] for a
/// bad field or [reject] for a problem of the whole object; the error codes
/// it passes are turned into full message codes. Code that shows the
/// errors reads them through [fieldErrors], [globalErrors] and
/// [hasErrors]; it usually holds a [BindingResult], which adds the target
/// object.
///
/// A nested path lets a validator for a nested object name fields relative
/// to that object, so one address validator serves `billing.city` and
/// `shipping.city`.
///
/// ```dart
/// // Reuse an address check inside a larger object.
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
  /// Name of the validated object, such as `signup`; part of every message
  /// code.
  String get objectName;

  /// The path put before the field names given to [rejectValue] and the
  /// field queries, such as `address.`; empty at the top level.
  String get nestedPath;

  /// Replaces the nested path, adding the trailing `.` when missing, and
  /// forgets the paths saved by [pushNestedPath].
  set nestedPath(String path);

  /// Goes one level down: appends [subPath] (`address`, `items[0]`) to the
  /// nested path and saves the current one for [popNestedPath].
  void pushNestedPath(String subPath);

  /// Goes back to the nested path saved by the last [pushNestedPath];
  /// throws a [StateError] when none is saved.
  void popNestedPath();

  /// Records an error of the whole object with [errorCode], such as
  /// `passwordsMismatch`.
  ///
  /// [args] fill the `{0}`, `{1}` placeholders of the message, and
  /// [defaultMessage] is used when no message code is defined. With
  /// [renderDefaultMessage] `false` the default message is shown as
  /// written instead of being formatted with [args].
  void reject(
    String errorCode, {
    List<Object?> args,
    String? defaultMessage,
    bool renderDefaultMessage,
  });

  /// Records an error of [field] (relative to [nestedPath]) with
  /// [errorCode], such as `required`; the field's current value becomes the
  /// rejected value.
  ///
  /// [args], [defaultMessage] and [renderDefaultMessage] are as in
  /// [reject]. An empty [field] names the nested object itself; at the top
  /// level it records an error of the whole object instead.
  void rejectValue(
    String field,
    String errorCode, {
    List<Object?> args,
    String? defaultMessage,
    bool renderDefaultMessage,
  });

  /// Copies every error of [errors], for example from a validator run on a
  /// separate result. Throws an [ArgumentError] when its [objectName]
  /// differs.
  void addAllErrors(Errors errors);

  /// Whether any error, of a field or of the object, was recorded.
  bool get hasErrors;

  /// The number of errors, of fields and of the object.
  int get errorCount;

  /// Every error, of fields and of the object, in the order they were
  /// recorded.
  List<ObjectError> get allErrors;

  /// Whether an error of the whole object (not of a field) was recorded.
  bool get hasGlobalErrors;

  /// The errors of the whole object, the ones that are not [FieldError]s,
  /// in the order they were recorded.
  List<ObjectError> get globalErrors;

  /// The first error of the whole object; `null` when there is none.
  ObjectError? get globalError;

  /// Whether a field has errors: any field when [field] is omitted, else
  /// that field (relative to [nestedPath]), or every field under a path
  /// that ends with `*` (`address.*`).
  bool hasFieldErrors([String? field]);

  /// The field errors in the order they were recorded: all when [field] is
  /// omitted, else those of [field] (relative to [nestedPath]); a trailing
  /// `*` matches every field under a path (`address.*`).
  List<FieldError> fieldErrors([String? field]);

  /// The first error of [field] (or of any field when omitted); `null` when
  /// there is none.
  FieldError? fieldError([String? field]);

  /// The value to show for [field] in a form: the rejected value of its
  /// first error when it has one, else its current value.
  ///
  /// After a binding failure the field still holds its old value, so this
  /// returns what the user typed instead, as Spring does.
  Object? getFieldValue(String field);
}

/// The outcome of binding input onto an object and validating it: the
/// [Errors] together with the object they are about.
///
/// This is the object applications read after validation: from
/// `DataBinder.bindingResult`, from a `MethodArgumentNotValidException`
/// in a web exception handler, or from a [BeanPropertyBindingResult] they
/// passed to a validator. Besides the errors it gives the [target], reads
/// field values, and lets framework code add prepared errors.
///
/// ```dart
/// // Print each field error after binding a form.
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
  /// The start of the key under which [model] holds a binding result:
  /// `BindingResult.signup` for the object `signup`. Spring's key starts
  /// with the full class name, `org.springframework.validation.`.
  static const modelKeyPrefix = 'BindingResult.';

  /// The object being bound or validated; `null` when constructor binding
  /// could not create it.
  Object? get target;

  /// The rule that builds the message codes of new errors;
  /// [DefaultMessageCodesResolver] unless one was given.
  MessageCodesResolver get messageCodesResolver;

  /// Records an [error] built elsewhere, codes included; the validator uses
  /// it to keep a rejected value it chose. Throws an [ArgumentError] when
  /// the error's object name differs from [objectName].
  void addError(ObjectError error);

  /// The current value of [field] on the target, ignoring errors (unlike
  /// [getFieldValue], which prefers the rejected value).
  Object? getRawFieldValue(String field);

  /// The message codes an error with [errorCode] would get: of [field]
  /// (relative to the nested path) when given, else of the whole object.
  ///
  /// Use it to build an error for [addError], or to see which keys a
  /// message file can define.
  ///
  /// ```dart
  /// result.resolveMessageCodes('NotBlank', 'name');
  /// // [NotBlank.signup.name, NotBlank.name, NotBlank.String, NotBlank]
  /// ```
  List<String> resolveMessageCodes(String errorCode, [String? field]);

  /// Records a binding failure of [field]: the input [rejectedValue] could
  /// not be stored, for example text for a number.
  ///
  /// `DataBinder` calls it; the error is marked as a binding failure, so
  /// validation adds no constraint error on top. [fieldType] is the
  /// declared type, for the codes, when the target cannot tell it.
  void recordFieldError(
    String field,
    String errorCode,
    Object? rejectedValue, {
    List<Object?> args,
    String? defaultMessage,
    Type? fieldType,
  });

  /// A map for a view model: the target under [objectName] and this result
  /// under `BindingResult.<objectName>`.
  Map<String, Object?> get model;
}

/// The common part of every [BindingResult]: the error list, nested
/// paths, message codes and the field queries.
///
/// Extend it only for a kind of target that neither
/// [BeanPropertyBindingResult] (an `@Introspected` object) nor
/// [MapBindingResult] (a map) covers; applications almost never do. A
/// subclass provides [target], [getRawFieldValue] and [getFieldType].
///
/// ```dart
/// // Errors for a record, which has no introspection.
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
  /// An empty result for the object [objectName], building codes with
  /// [messageCodesResolver] (Spring's codes by default).
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

  /// The declared type of [field], for the type code (`NotBlank.String`);
  /// `null` when unknown, and that code is left out.
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

/// The [BindingResult] for an `@Introspected` object, the one used almost
/// everywhere.
///
/// `DataBinder` and the web starter create it. Create one yourself to call
/// a validator directly and collect its errors. Field values and types are
/// read through a [BeanWrapper], so nested paths such as `address.city`
/// and `items[0].sku` work.
///
/// ```dart
/// // Check a form outside of data binding.
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
  /// An empty result for [target], named [objectName] in message codes.
  ///
  /// `introspector` (default `BeanIntrospector.shared`) and
  /// `conversionService` configure the [wrapper]. [target] is `null` when
  /// `DataBinder.construct` could not create the object; field values and
  /// types then come from [recordFieldValue].
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

  /// Reads and writes the target's properties by path; created on first
  /// use. Throws a [StateError] when there is no target.
  late final BeanWrapper wrapper = BeanWrapper(
    target ?? (throw StateError('No target object for $objectName')),
    introspector: _introspector,
    conversionService: _conversionService,
  );

  /// Remembers [value] (of [type]) for [field] when there is no target, so
  /// a form can show what was entered after constructor binding failed.
  /// `DataBinder.construct` calls it; Spring's `recordFieldValue`.
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

/// A [BindingResult] for values held in a map instead of an object.
///
/// Use it to check loose input with a hand-written `Validator` or the
/// `ValidationUtils` helpers, for example request parameters that were
/// never bound onto a class. Field names are the map keys; a field's type
/// is the runtime type of its current value.
///
/// ```dart
/// // A required parameter, checked without a form class.
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
  /// An empty result for the map [target], named [objectName] in message
  /// codes.
  MapBindingResult(this.target, super.objectName, {super.messageCodesResolver});

  @override
  final Map<String, Object?> target;

  @override
  Object? getRawFieldValue(String field) => target[field];

  @override
  Type? getFieldType(String field) => target[field]?.runtimeType;
}

/// The exception `DataBinder.close` throws when binding or validation
/// found errors; it carries them in [bindingResult].
///
/// Throw or catch it where a whole bind-and-check step must succeed. The
/// web starter reports invalid `@Valid()` arguments with its own
/// `MethodArgumentNotValidException`, which also holds a binding result.
///
/// ```dart
/// // Bind, check, and stop on the first invalid input.
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
  /// An exception for the errors in [bindingResult].
  BindException(this.bindingResult);

  /// The errors, with the target they are about.
  final BindingResult bindingResult;

  @override
  String toString() => 'BindException: $bindingResult';
}
