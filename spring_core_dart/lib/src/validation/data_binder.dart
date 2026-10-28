import 'package:spring_core_dart/src/beans/bean_wrapper.dart';
import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/type_info.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';
import 'package:spring_core_dart/src/core/convert/lenient_enum.dart';
import 'package:spring_core_dart/src/validation/errors.dart';
import 'package:spring_core_dart/src/validation/validator.dart';

/// The source of the input values when [DataBinder.construct] creates an
/// object through its constructor.
///
/// The binder asks it for one value per constructor parameter, by name
/// (`isbn`, `author.name`, `tags[0]`), and for the names it has, to build
/// nested objects, lists and maps. [MapValueResolver] covers input that is
/// already a map, which is the usual case. Implement it only to read values
/// from somewhere else without copying them into a map first.
///
/// ```dart
/// // Constructor values straight from a query string.
/// final class RequestValues implements ValueResolver {
///   RequestValues(this.query);
///   final Map<String, String> query;
///
///   @override
///   Object? resolveValue(String name, Type type) => query[name];
///
///   @override
///   Set<String> get names => query.keys.toSet();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class RequestValues implements DataBinder.ValueResolver {
///   public Object resolveValue(String name, Class<?> type) { ... }
///   public Set<String> getNames() { ... }
/// }
/// ```
abstract interface class ValueResolver {
  /// The input for the parameter path [name] (`isbn`, `author.name`,
  /// `tags[0]`), whose declared type is [type]; `null` when there is none.
  ///
  /// The value may be a string or any other object; the binder converts it
  /// to [type].
  Object? resolveValue(String name, Type type);

  /// Every name a value exists for. The binder searches it for prefixes
  /// (`author.`, `tags[`) to decide whether to build a nested object, list
  /// or map.
  Set<String> get names;
}

/// A [ValueResolver] that reads the values from a map keyed by parameter
/// path, the one to use with [DataBinder.construct] in most cases.
///
/// ```dart
/// // A book with two tags, created from form input.
/// binder.construct(MapValueResolver({'isbn': '978-0', 'tags[0]': 'sf'}));
/// ```
final class MapValueResolver implements ValueResolver {
  /// A resolver over [values].
  const MapValueResolver(this.values);

  /// The input values, keyed by parameter path (`isbn`, `tags[0]`).
  final Map<String, Object?> values;

  @override
  Object? resolveValue(String name, Type type) => values[name];

  @override
  Set<String> get names => values.keys.toSet();
}

/// Copies input values, usually strings from a form or a query, onto the
/// properties of an `@Introspected` object, then validates it, collecting
/// every problem in one [bindingResult].
///
/// Use it when the input is a flat map of strings rather than JSON: form
/// fields, query parameters, a CSV row. Each value is converted to the
/// property's type; text that cannot be converted becomes a `typeMismatch`
/// field error that keeps what was typed, instead of an exception. Rules
/// such as [requiredFields] and [disallowedFields] protect the object from
/// missing or unexpected input (a client must not set `id` or `admin`).
///
/// The web starter does not use it: JSON bodies are read by the
/// `ObjectMapper` and checked with `@Valid()`. Spring Boot uses it to
/// validate `@ConfigurationProperties` classes.
///
/// ```dart
/// // A signup form: only known fields, `email` required, `id` never set
/// // by the client.
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
/// // {signup: form, BindingResult.signup: ...}; throws on errors.
/// final model = binder.close();
/// ```
///
/// An immutable class (final fields, no setters) cannot be bound onto.
/// Create it from the values with [construct] instead: constructor
/// binding, Spring 6.1. It goes through the constructor the generator
/// describes for `@Introspected` classes, the one `ObjectMapper` uses:
///
/// ```dart
/// // Start without a target; construct creates it.
/// final binder =
///     DataBinder(null, objectName: 'book', introspector: introspector)
///   ..targetType = Book
///   ..construct(MapValueResolver({'isbn': '978-0', 'title': 'Dune'}));
/// final book = binder.target as Book?; // null when a value was invalid
/// ```
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
///
/// DataBinder books = new DataBinder(null, "book");
/// books.setTargetType(ResolvableType.forClass(Book.class));
/// books.construct(valueResolver);
/// ```
class DataBinder {
  /// A binder for [target], or for an object [construct] creates when
  /// [target] is `null`; [objectName] names it in error codes and the
  /// model.
  ///
  /// [introspector] (default `BeanIntrospector.shared`; inside an
  /// application pass the context's), [conversionService] (default: the
  /// shared `DefaultConversionService`) and [messageCodesResolver] change
  /// property access, value conversion and error codes.
  DataBinder(
    Object? target, {
    this.objectName = defaultObjectName,
    BeanIntrospector? introspector,
    ConversionService? conversionService,
    this.messageCodesResolver = const DefaultMessageCodesResolver(),
  }) : _target = target,
       introspector = introspector ?? BeanIntrospector.shared,
       conversionService =
           conversionService ?? DefaultConversionService.sharedInstance;

  /// The object name when none is given, `target` (Spring's
  /// `DataBinder.DEFAULT_OBJECT_NAME`).
  static const defaultObjectName = 'target';

  /// The object values are bound onto; `null` until [construct] creates
  /// it, and still `null` when that failed.
  Object? get target => _target;
  Object? _target;

  /// The class [construct] creates; it must be `@Introspected`. Set it
  /// before calling [construct]. Spring's `setTargetType`.
  Type? targetType;

  /// The name of the target in error codes (`NotBlank.signup.name`) and in
  /// the model.
  final String objectName;

  /// Describes the properties and constructors of the target's class and
  /// of nested classes.
  final BeanIntrospector introspector;

  /// Converts input values, usually strings, to the property types.
  final ConversionService conversionService;

  /// Builds the message codes of binding and validation errors.
  final MessageCodesResolver messageCodesResolver;

  /// The errors of binding and validation, with the target; created on
  /// first use for the current [target]. Read it after [bind] and
  /// [validate], or let [close] throw when it has errors.
  BeanPropertyBindingResult get bindingResult =>
      _bindingResult ??= BeanPropertyBindingResult(
        _target,
        objectName,
        introspector: introspector,
        conversionService: conversionService,
        messageCodesResolver: messageCodesResolver,
      );
  BeanPropertyBindingResult? _bindingResult;

  /// The fields that may be bound, as patterns with `*` wildcards
  /// (`address.*`); input for other fields is skipped. `null` or empty
  /// allows every field, like Spring's `setAllowedFields()` with no
  /// patterns.
  List<String>? allowedFields;

  /// Fields that are never bound, as patterns with `*` wildcards, such as
  /// `id` or `*.admin`; they win over [allowedFields]. Matching ignores case
  /// and also catches the bracket form of a dotted path (`roles[admin]`
  /// for `roles.admin`), as Spring does since CVE-2022-22968. Empty by
  /// default.
  List<String> disallowedFields = const [];

  /// Fields the input must contain with a non-blank value; a missing one
  /// gets a `required` field error. Empty by default. A field that is also
  /// disallowed counts as missing.
  List<String> requiredFields = const [];

  /// Whether input for a field the target does not have (or a malformed
  /// path such as `items[`) is skipped; `true` by default. When `false`,
  /// [bind] throws for it.
  bool ignoreUnknownFields = true;

  /// Whether input for a path that cannot be reached, such as
  /// `address.city` while `address` is `null` and cannot be created, is
  /// skipped; `false` by default, and [bind] throws for it.
  bool ignoreInvalidFields = false;

  /// Whether binding `address.city` or `items[2].sku` creates a `null`
  /// nested object, list or map, and missing list elements, on the way;
  /// `true` by default.
  bool autoGrowNestedPaths = true;

  /// The highest list index plus one that binding may create, 256 by
  /// default (Spring's `DEFAULT_AUTO_GROW_COLLECTION_LIMIT`), so input such
  /// as `items[999999]` cannot make the binder allocate a huge list.
  int autoGrowCollectionLimit = 256;

  /// The validators [validate] runs, in order; usually the application's
  /// `BeanValidator` and, for rules in code, your own [Validator]s. Empty
  /// by default, so nothing is checked until you add one.
  final validators = <Validator>[];

  /// The input fields [bind] skipped because [allowedFields] or
  /// [disallowedFields] rejected them, over all [bind] calls; useful to log
  /// tampering attempts. Spring's `BindingResult.getSuppressedFields()`.
  List<String> get suppressedFields => List.unmodifiable(_suppressed);

  final _suppressed = <String>[];

  // A fresh wrapper per bind so the current [autoGrowNestedPaths] and
  // [conversionService] apply.
  BeanWrapper _wrapper(Object target) => BeanWrapper(
    target,
    introspector: introspector,
    conversionService: conversionService,
    autoGrowNestedPaths: autoGrowNestedPaths,
    autoGrowCollectionLimit: autoGrowCollectionLimit,
  );

  // Spring's getArgumentsForBindError: one resolvable for the field name.
  List<Object?> _bindErrorArguments(String field) => [
    DefaultMessageSourceResolvable([
      '$objectName.$field',
      field,
    ], defaultMessage: field),
  ];

  /// Sets the target's properties from [values], whose keys are property
  /// paths (`name`, `address.city`, `items[0].sku`); problems become field
  /// errors in [bindingResult] instead of exceptions.
  ///
  /// - Keys not allowed by [allowedFields] and [disallowedFields] are
  ///   skipped and listed in [suppressedFields]. Keys are compared in a
  ///   canonical form (see [canonicalPropertyName]).
  /// - A missing or blank entry of [requiredFields] gets a `required` error
  ///   with the rejected value `""`.
  /// - A value that cannot be converted gets a `typeMismatch` error, and a
  ///   setter that throws a `methodInvocation` error.
  /// - Unknown fields and malformed keys are skipped while
  ///   [ignoreUnknownFields] is on; unreachable nested paths throw unless
  ///   [ignoreInvalidFields] is on.
  ///
  /// Binding errors get Spring's arguments: `{0}` is the field name, which
  /// a message source may translate too. Throws a [StateError] when there
  /// is no target yet.
  ///
  /// ```dart
  /// // `age` is an int: the text is kept as a typeMismatch error.
  /// binder.bind({'age': 'old'});
  /// binder.bindingResult.fieldError('age')!.codes.first;
  /// // typeMismatch.signup.age
  /// ```
  void bind(Map<String, Object?> values) {
    final target =
        _target ?? (throw StateError('No target to bind to: call construct'));
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
        // Spring's processMissingFieldError: rejected value "".
        final fixed = '${bindingResult.nestedPath}$field';
        bindingResult.recordFieldError(
          field,
          'required',
          '',
          args: _bindErrorArguments(fixed),
          defaultMessage: "Field '$fixed' is required",
        );
        accepted.remove(field);
      }
    }
    final wrapper = _wrapper(target);
    for (final MapEntry(:key, :value) in accepted.entries) {
      try {
        wrapper.setPropertyValue(key, value);
      } on TypeMismatchException catch (error) {
        _recordTypeMismatch(key, value, error);
      } on NotWritablePropertyException {
        if (!ignoreUnknownFields) {
          rethrow;
        }
      } on InvalidPropertyException {
        // A malformed key (`items[`) is an unknown field, not a crash.
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
          args: _bindErrorArguments('${bindingResult.nestedPath}$key'),
          defaultMessage: error.message,
        );
      }
    }
  }

  void _recordTypeMismatch(
    String field,
    Object? value,
    TypeMismatchException error,
  ) => bindingResult.recordFieldError(
    field,
    TypeMismatchException.errorCode,
    value,
    args: _bindErrorArguments('${bindingResult.nestedPath}$field'),
    defaultMessage: error.message,
    fieldType: error.requiredType,
  );

  /// Creates the target, an instance of [targetType], by calling its
  /// constructor with values from [valueResolver]: constructor binding,
  /// for classes with final fields. Spring's `DataBinder.construct`.
  ///
  /// Each constructor parameter is looked up by name (`isbn`), a nested
  /// `@Introspected` object by prefix (`author.name`), lists and sets by
  /// index (`tags[0]`, `authors[1].name`) and maps by key (`prices[eur]`).
  /// Values are converted to the parameter types, and optional parameters
  /// without a value keep their defaults.
  ///
  /// A value that cannot be converted, or no value for a required
  /// non-nullable parameter (Java's missing primitive), records a
  /// `typeMismatch` error; [target] then stays `null` when the object
  /// cannot be created. Without errors the binding result starts afresh for
  /// the new target, so [bind] and [validate] can follow.
  ///
  /// Throws a [StateError] when there is already a target or [targetType]
  /// is not set, an [ArgumentError] when [targetType] is not
  /// `@Introspected`, and an [InvalidPropertyException] for a list index at
  /// or above [autoGrowCollectionLimit], before the list is allocated
  /// (Spring's `createList`).
  ///
  /// ```dart
  /// // A Book with final fields, created from form input.
  /// final binder =
  ///     DataBinder(null, objectName: 'book', introspector: introspector)
  ///   ..targetType = Book
  ///   ..construct(MapValueResolver({'isbn': '978-0', 'title': 'Dune'}));
  /// binder.bindingResult.hasErrors; // false
  /// ```
  void construct(ValueResolver valueResolver) {
    if (_target != null) {
      throw StateError('Target instance already available');
    }
    final type = targetType ?? (throw StateError('Target type not set'));
    final introspection =
        introspector.forType(type) ??
        (throw ArgumentError.value(
          type,
          'targetType',
          '$type is not @Introspected (or its module is not registered)',
        ));
    _target = _createObject(introspection, '', valueResolver);
    if (_target != null && !bindingResult.hasErrors) {
      _bindingResult = null;
    }
  }

  Object? _createObject(
    BeanIntrospection<Object> introspection,
    String nestedPath,
    ValueResolver resolver,
  ) {
    final constructor = introspection.constructor;
    if (constructor == null || constructor.parameters.isEmpty) {
      if (introspection.isInstantiable) {
        return introspection.instantiate();
      }
      if (constructor != null) {
        return constructor.newInstance(const []);
      }
      throw StateError(
        '${introspection.beanType} has no public constructor to bind',
      );
    }
    final positional = <(BeanParameter, Object?, bool)>[];
    final named = <Symbol, Object?>{};
    final resolved = <String, (Type, Object?)>{};
    final failed = <String>{};
    var creatable = true;
    for (final parameter in constructor.parameters) {
      final path = '$nestedPath${parameter.name}';
      final type = parameter.type;
      final value =
          resolver.resolveValue(path, type.type) ??
          type.accept(_Composite(this, path, resolver));
      Object? argument;
      var given = false;
      if (value == null) {
        if (parameter.isRequired) {
          if (type.nullable) {
            given = true;
          } else {
            // Dart cannot pass null here; Spring reports a type mismatch
            // for a missing primitive argument the same way.
            failed.add(path);
            creatable = false;
            bindingResult.recordFieldError(
              path,
              TypeMismatchException.errorCode,
              null,
              args: _bindErrorArguments(path),
              defaultMessage: TypeMismatchException(
                path,
                null,
                type.type,
              ).message,
              fieldType: type.type,
            );
          }
        }
      } else {
        try {
          argument = _convertArgument(value, type, path);
          given = true;
        } on TypeMismatchException catch (error) {
          failed.add(path);
          bindingResult.recordFieldValue(path, type.type, value);
          _recordTypeMismatch(path, value, error);
          if (type.nullable) {
            given = true;
          } else if (parameter.isRequired) {
            creatable = false;
          }
        }
      }
      if (given) {
        resolved[path] = (type.type, argument);
      }
      if (parameter.isNamed) {
        if (given) {
          named[parameter.symbol!] = argument;
        }
      } else {
        positional.add((parameter, argument, given));
      }
    }
    // Trailing optional positional parameters that are absent keep their
    // defaults; an absent one before a given one can only be null.
    while (positional.isNotEmpty && !positional.last.$3) {
      positional.removeLast();
    }
    for (final (parameter, _, given) in positional) {
      if (!given && !parameter.type.nullable) {
        creatable = false;
      }
    }
    Object create() => constructor.newInstance([
      for (final (_, argument, _) in positional) argument,
    ], named);
    if (bindingResult.hasErrors) {
      // Like Spring: remember the values for re-rendering, and create the
      // object only if possible (failures are already reported).
      for (final MapEntry(key: path, value: (type, value))
          in resolved.entries) {
        if (!failed.contains(path)) {
          bindingResult.recordFieldValue(path, type, value);
        }
      }
      if (!creatable) {
        return null;
      }
      try {
        return create();
      } on Object {
        return null;
      }
    }
    return create();
  }

  // [value] as a [type] for a constructor argument.
  Object? _convertArgument(Object? value, TypeInfo<Object?> type, String path) {
    if (type.isInstance(value)) {
      return value;
    }
    if (type is EnumType<Enum>) {
      return findLenientEnum(
            type.values,
            '$value'.trim(),
            alias: type.toJsonValue,
          ) ??
          (throw TypeMismatchException(path, value, type.type));
    }
    try {
      final converted = conversionService.convertTo(value, type.type);
      if (converted == null && !type.nullable) {
        throw TypeMismatchException(path, value, type.type);
      }
      return converted;
    } on BeansException {
      rethrow;
    } catch (error) {
      throw TypeMismatchException(path, value, type.type, error);
    }
  }

  /// Runs each of [validators] that supports the target, adding the errors
  /// to [bindingResult]; does nothing when there is no target.
  ///
  /// Non-empty [groups] restrict [SmartValidator]s such as `BeanValidator`
  /// to the constraints of those groups. A field that already has a
  /// `typeMismatch` error gets no constraint error on top.
  ///
  /// ```dart
  /// // An edit form: check the update rules.
  /// binder.validate(groups: [OnUpdate]);
  /// ```
  void validate({List<Type> groups = const []}) {
    final target = _target;
    if (target == null) {
      return;
    }
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

  /// Ends binding: throws a [BindException] when [bindingResult] has
  /// errors, else returns the model map.
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
    if (allowed != null &&
        allowed.isNotEmpty &&
        !allowed.any((p) => simpleMatch(p, field))) {
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
  /// `map[key]`.
  ///
  /// [bind] compares keys with the field rules in this form, so quoting a
  /// key cannot slip past a `roles[admin]` rule. Spring's
  /// `PropertyAccessorUtils.canonicalPropertyName`.
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

  /// Whether [text] matches [pattern], where `*` stands for any text
  /// (dots included) and everything else matches itself; the matching of
  /// [allowedFields] and [disallowedFields]. Case-sensitive. Spring's
  /// `PatternMatchUtils.simpleMatch`.
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

/// Builds a constructor argument that has no value of its own: a nested
/// introspected object from `path.*` values, a list or set from
/// `path[index]` values, a map from `path[key]` values (Spring's
/// `createObject`, `createList`, `createMap`); `null` when there are none.
final class _Composite implements TypeInfoVisitor<Object?> {
  _Composite(this.binder, this.path, this.resolver);

  final DataBinder binder;
  final String path;
  final ValueResolver resolver;

  @override
  Object? visitClass<T>(ClassType<T> type) {
    final introspection = binder.introspector.forTypeArgument<T>();
    if (introspection == null ||
        !resolver.names.any((name) => name.startsWith('$path.'))) {
      return null;
    }
    return binder._createObject(introspection, '$path.', resolver);
  }

  @override
  Object? visitList<E>(ListType<E> type) {
    final elements = _elements(type.element, indexed: true);
    return elements == null ? null : type.create(elements);
  }

  @override
  Object? visitSet<E>(SetType<E> type) {
    final elements = _elements(type.element);
    return elements == null ? null : type.create(elements);
  }

  // Elements at the indexes the names mention, in index order; elements
  // that fail are reported and left out. [indexed] (a list, Spring's
  // createList): each element stays at its index, gaps and failed
  // elements are `null` (`tags[1]=t` gives `[null, t]`); when the element
  // type is not nullable, a gap is reported like a missing primitive and
  // left out.
  List<Object?>? _elements(TypeInfo<Object?> element, {bool indexed = false}) {
    final pattern = RegExp('^${RegExp.escape(path)}\\[(\\d+)\\]');
    final indexes = {
      for (final name in resolver.names)
        if (pattern.firstMatch(name) case final match?) int.parse(match[1]!),
    }.toList()..sort();
    if (indexes.isEmpty) {
      return null;
    }
    if (!indexed) {
      return [
        for (final index in indexes)
          if (_element(element, '$path[$index]') case (final value,)) value,
      ];
    }
    // Like Spring's createList, the list is only padded below
    // autoGrowCollectionLimit: a higher index fails before anything is
    // allocated (Spring's list.set throws IndexOutOfBoundsException).
    final last = indexes.last;
    if (last >= binder.autoGrowCollectionLimit) {
      throw InvalidPropertyException(
        '$path[$last]',
        'index $last is out of bounds: lists grow up to '
            'autoGrowCollectionLimit (${binder.autoGrowCollectionLimit})',
      );
    }
    final present = indexes.toSet();
    final elements = <Object?>[];
    for (var index = 0; index <= indexes.last; index++) {
      final elementPath = '$path[$index]';
      if (present.contains(index)) {
        switch (_element(element, elementPath)) {
          case (final value,):
            elements.add(value);
          case null when element.nullable:
            elements.add(null);
          case null:
            break;
        }
      } else if (element.nullable) {
        elements.add(null);
      } else {
        // Dart cannot hold null here; Spring reports a type mismatch for a
        // missing primitive the same way.
        binder.bindingResult.recordFieldError(
          elementPath,
          TypeMismatchException.errorCode,
          null,
          args: binder._bindErrorArguments(elementPath),
          defaultMessage: TypeMismatchException(
            elementPath,
            null,
            element.type,
          ).message,
          fieldType: element.type,
        );
      }
    }
    return elements;
  }

  @override
  Object? visitMap<K, V>(MapType<K, V> type) {
    final pattern = RegExp('^${RegExp.escape(path)}\\[([^\\]]+)\\]');
    final keys = {
      for (final name in resolver.names)
        if (pattern.firstMatch(name) case final match?) match[1]!,
    };
    if (keys.isEmpty) {
      return null;
    }
    final entries = <MapEntry<Object?, Object?>>[];
    for (final key in keys) {
      final elementPath = '$path[$key]';
      final Object? mapKey;
      try {
        mapKey = binder._convertArgument(key, type.key, elementPath);
      } on TypeMismatchException catch (error) {
        binder._recordTypeMismatch(elementPath, key, error);
        continue;
      }
      if (_element(type.value, elementPath) case (final value,)) {
        entries.add(MapEntry(mapKey, value));
      }
    }
    return type.create(entries);
  }

  // The element at [elementPath] in a one-element record, or `null` when
  // it is missing or failed (reported).
  (Object?,)? _element(TypeInfo<Object?> type, String elementPath) {
    final value =
        resolver.resolveValue(elementPath, type.type) ??
        type.accept(_Composite(binder, elementPath, resolver));
    if (value == null) {
      return type.nullable ? (null,) : null;
    }
    try {
      return (binder._convertArgument(value, type, elementPath),);
    } on TypeMismatchException catch (error) {
      binder._recordTypeMismatch(elementPath, value, error);
      return null;
    }
  }

  @override
  Object? visitEnum<E extends Enum>(EnumType<E> type) => null;

  @override
  Object? visitGeneric<T>(GenericType<T> type) => null;

  @override
  Object? visitDynamic(DynamicType type) => null;
}
