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

/// Values for constructor binding ([DataBinder.construct]), like Spring's
/// `DataBinder.ValueResolver`.
///
/// ```dart
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
  /// The value for the parameter path [name] (`isbn`, `author.name`,
  /// `tags[0]`) of [type], or `null` when there is none.
  Object? resolveValue(String name, Type type);

  /// Every name a value exists for (used for nested objects, lists and
  /// maps).
  Set<String> get names;
}

/// A [ValueResolver] over a map of values keyed by parameter path.
///
/// ```dart
/// binder.construct(MapValueResolver({'isbn': '978-0', 'tags[0]': 'sf'}));
/// ```
final class MapValueResolver implements ValueResolver {
  /// Resolves names from [values].
  const MapValueResolver(this.values);

  /// The values, keyed by parameter path.
  final Map<String, Object?> values;

  @override
  Object? resolveValue(String name, Type type) => values[name];

  @override
  Set<String> get names => values.keys.toSet();
}

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
/// Immutable classes are created from the values with [construct]
/// (constructor binding, Spring 6.1), through the constructor the
/// generator describes for `@Introspected` classes (the one `ObjectMapper`
/// uses):
///
/// ```dart
/// final binder = DataBinder(null, objectName: 'book', introspector: introspector)
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
  /// Creates a binder for [target] (`null` to create it with [construct]),
  /// exposed as [objectName] in messages and the model.
  ///
  /// [introspector], [conversionService] and [messageCodesResolver]
  /// customize property access, value conversion and error codes.
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

  /// Object name used when none is given, like Spring's
  /// `DataBinder.DEFAULT_OBJECT_NAME`.
  static const defaultObjectName = 'target';

  /// The object values are bound onto; `null` until [construct] created
  /// it (and when it failed).
  Object? get target => _target;
  Object? _target;

  /// The class [construct] creates (must be `@Introspected`), like
  /// Spring's `setTargetType`.
  Type? targetType;

  /// Name of the target in error codes and the model.
  final String objectName;

  /// Metadata of the target's class (and nested classes).
  final BeanIntrospector introspector;

  /// Converts input values (usually strings) to property types.
  final ConversionService conversionService;

  /// Builds the codes of binding and validation errors.
  final MessageCodesResolver messageCodesResolver;

  /// Errors from binding and validation (created on first use, for the
  /// current [target]).
  BeanPropertyBindingResult get bindingResult =>
      _bindingResult ??= BeanPropertyBindingResult(
        _target,
        objectName,
        introspector: introspector,
        conversionService: conversionService,
        messageCodesResolver: messageCodesResolver,
      );
  BeanPropertyBindingResult? _bindingResult;

  /// Only these fields may be bound (`*` wildcards); `null` or empty
  /// allows all (Spring's `setAllowedFields()` with no patterns).
  List<String>? allowedFields;

  /// These fields are never bound (`*` wildcards).
  List<String> disallowedFields = const [];

  /// Fields that must be present and non-empty.
  List<String> requiredFields = const [];

  /// Silently skip fields the target does not have.
  bool ignoreUnknownFields = true;

  /// Silently skip fields with a `null` nested path.
  bool ignoreInvalidFields = false;

  /// Create `null` nested objects, lists, maps and missing list elements
  /// while binding nested paths.
  bool autoGrowNestedPaths = true;

  /// Lists grow up to (not including) this index, like Spring's
  /// `DataBinder.DEFAULT_AUTO_GROW_COLLECTION_LIMIT` (256).
  int autoGrowCollectionLimit = 256;

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

  /// Binds [values] onto the target.
  ///
  /// Keys are property paths (`name`, `address.city`, `items[0].sku`).
  /// Disallowed keys are skipped (see [suppressedFields]); missing
  /// [requiredFields] get `required` errors; conversion failures get
  /// `typeMismatch` errors; setters that throw get `methodInvocation`
  /// errors; unknown fields and malformed keys (`items[`) are skipped
  /// while [ignoreUnknownFields] is on (the default), unreachable nested
  /// paths throw unless [ignoreInvalidFields] is on. Binding errors carry
  /// Spring's arguments (a resolvable of the field name) and `required`
  /// errors reject `""`.
  ///
  /// ```dart
  /// binder.bind({'age': 'old'});
  /// binder.bindingResult.fieldError('age')!.codes.first; // typeMismatch.signup.age
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

  /// Creates the target of [targetType] from [valueResolver] through its
  /// constructor, like Spring's `DataBinder.construct` (constructor
  /// binding).
  ///
  /// Each constructor parameter is looked up by name (`isbn`); nested
  /// introspected objects by prefix (`author.name`), lists and sets by
  /// index (`tags[0]`, `authors[1].name`) and maps by key (`prices[eur]`).
  /// Values are converted to the parameter types. Optional parameters
  /// without a value keep their defaults; a conversion failure, or no value
  /// for a required non-nullable parameter (Java's primitive), records a
  /// `typeMismatch` error, and then the target stays `null` when it cannot
  /// be created. Without errors the binding result is reset for the new
  /// target, so [bind] and [validate] can follow. A list index at or above
  /// [autoGrowCollectionLimit] throws an [InvalidPropertyException] before
  /// the list is allocated, like Spring's `createList`.
  ///
  /// ```dart
  /// final binder = DataBinder(null, objectName: 'book', introspector: introspector)
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

  /// Runs every validator that supports the target.
  ///
  /// Non-empty [groups] restrict [SmartValidator]s to those groups.
  ///
  /// ```dart
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
