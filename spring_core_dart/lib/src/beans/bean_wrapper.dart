import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/type_info.dart';
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';

/// A property path that cannot be read, like Spring's
/// `NotReadablePropertyException`.
///
/// Thrown for unknown properties, classes that are not `@Introspected`
/// and out-of-range indexes.
///
/// ```dart
/// try {
///   BeanWrapper(person).getPropertyValue('nickname');
/// } on NotReadablePropertyException catch (e) {
///   print(e.propertyName); // nickname
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   new BeanWrapperImpl(person).getPropertyValue("nickname");
/// } catch (NotReadablePropertyException e) {
///   System.out.println(e.getPropertyName());
/// }
/// ```
class NotReadablePropertyException extends BeansException {
  /// [propertyName] of [beanType] cannot be read, for an optional reason.
  NotReadablePropertyException(
    this.beanType,
    this.propertyName, [
    String? reason,
  ]) : super(
         "Invalid property '$propertyName' of $beanType: ${reason ?? 'not readable'}",
       );

  /// Type of the wrapped (root) object.
  final Type beanType;

  /// The full property path that failed.
  final String propertyName;
}

/// A property path that cannot be written, like Spring's
/// `NotWritablePropertyException`.
///
/// Thrown for unknown or read-only properties and invalid indexes.
/// `BeanWrapper.setPropertyValues` can skip these with `ignoreUnknown`.
///
/// ```dart
/// try {
///   BeanWrapper(person).setPropertyValue('id', 'p2'); // final field
/// } on NotWritablePropertyException catch (e) {
///   print(e.message); // ... 'id' of Person: read-only
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   new BeanWrapperImpl(person).setPropertyValue("id", "p2");
/// } catch (NotWritablePropertyException e) {
///   System.out.println(e.getMessage());
/// }
/// ```
class NotWritablePropertyException extends BeansException {
  /// [propertyName] of [beanType] cannot be written, for an optional
  /// reason.
  NotWritablePropertyException(
    this.beanType,
    this.propertyName, [
    String? reason,
  ]) : super(
         "Invalid property '$propertyName' of $beanType: ${reason ?? 'not writable'}",
       );

  /// Type of the wrapped (root) object.
  final Type beanType;

  /// The full property path that failed.
  final String propertyName;
}

/// A property path is malformed (`items[`, `address..city`), like Spring's
/// `InvalidPropertyException`.
///
/// `DataBinder` treats it like an unknown field: skipped while
/// `ignoreUnknownFields` is on, so hostile request keys cannot break
/// binding.
///
/// ```dart
/// try {
///   BeanWrapper(person).setPropertyValue('items[', 'x');
/// } on InvalidPropertyException catch (e) {
///   print(e.propertyName); // items[
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// } catch (InvalidPropertyException e) { ... }
/// ```
class InvalidPropertyException extends BeansException {
  /// The path [propertyName] is malformed for [reason].
  InvalidPropertyException(this.propertyName, String reason)
    : super("Invalid property path '$propertyName': $reason");

  /// The malformed path.
  final String propertyName;
}

/// A property setter threw, like Spring's `MethodInvocationException`.
///
/// `DataBinder` records it as a `methodInvocation` field error.
///
/// ```dart
/// try {
///   BeanWrapper(account).setPropertyValue('iban', 'nope');
/// } on MethodInvocationException catch (e) {
///   print(e.cause); // what the setter threw
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// } catch (MethodInvocationException e) { ... }
/// ```
class MethodInvocationException extends BeansException {
  /// The setter of [propertyName] threw [cause].
  MethodInvocationException(this.propertyName, Object cause)
    : super("Property '$propertyName' threw exception: $cause", cause: cause);

  /// The property whose setter threw.
  final String propertyName;
}

/// A nested path is `null` (e.g. `address` in `address.city`), like
/// Spring's `NullValueInNestedPathException`.
///
/// Enable `BeanWrapper.autoGrowNestedPaths` to create the missing objects
/// instead.
///
/// ```dart
/// try {
///   BeanWrapper(Person()).setPropertyValue('address.city', 'Lyon');
/// } on NullValueInNestedPathException catch (e) {
///   print(e.propertyName); // address
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   new BeanWrapperImpl(new Person()).setPropertyValue("address.city", "x");
/// } catch (NullValueInNestedPathException e) {
///   System.out.println(e.getPropertyName());
/// }
/// ```
class NullValueInNestedPathException extends BeansException {
  /// The path [propertyName] of [beanType] evaluated to `null`.
  NullValueInNestedPathException(this.beanType, this.propertyName)
    : super("Value of nested property '$propertyName' of $beanType is null");

  /// Type of the wrapped (root) object.
  final Type beanType;

  /// The path prefix that is `null`.
  final String propertyName;
}

/// A value cannot be converted to the property type, like Spring's
/// `TypeMismatchException`.
///
/// Data binding turns it into a field error with code [errorCode].
///
/// ```dart
/// try {
///   BeanWrapper(person).setPropertyValue('age', 'old');
/// } on TypeMismatchException catch (e) {
///   print('${e.propertyName}: ${e.requiredType}'); // age: int
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   new BeanWrapperImpl(person).setPropertyValue("age", "old");
/// } catch (TypeMismatchException e) {
///   System.out.println(e.getPropertyName() + ": " + e.getRequiredType());
/// }
/// ```
class TypeMismatchException extends BeansException {
  /// [value] for [propertyName] is not convertible to [requiredType].
  TypeMismatchException(
    this.propertyName,
    this.value,
    this.requiredType, [
    Object? cause,
  ]) : super(
         "Failed to convert value '$value' of type ${value.runtimeType} to "
         "required type $requiredType for property '$propertyName'",
         cause: cause,
       );

  /// Error code used by data binding.
  static const errorCode = 'typeMismatch';

  /// The property path being written.
  final String propertyName;

  /// The rejected value.
  final Object? value;

  /// The type the value had to be converted to.
  final Type requiredType;
}

/// Several property updates failed, like Spring's
/// `PropertyBatchUpdateException`.
///
/// ```dart
/// try {
///   wrapper.setPropertyValues({'age': 'old', 'nickname': 'x'});
/// } on PropertyBatchUpdateException catch (e) {
///   e.exceptions.forEach(print); // one entry per failed property
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   wrapper.setPropertyValues(new MutablePropertyValues(values));
/// } catch (PropertyBatchUpdateException e) {
///   for (PropertyAccessException ex : e.getPropertyAccessExceptions()) {
///     System.out.println(ex);
///   }
/// }
/// ```
class PropertyBatchUpdateException extends BeansException {
  /// Collects the individual failures.
  PropertyBatchUpdateException(this.exceptions)
    : super(
        '${exceptions.length} property update(s) failed: ${exceptions.join('; ')}',
      );

  /// The failures, in the order of the values.
  final List<BeansException> exceptions;
}

/// Reads and writes nested properties of an introspected object, like
/// Spring's `BeanWrapperImpl`.
///
/// Paths: `name`, `address.city`, `tags[0]`, `scores['math']`,
/// `orders[1].items[0].sku`. Written values are converted to the property
/// type with the conversion service — also list elements and map keys and
/// values, whose types come from the generated `TypeInfo` of the property
/// (`scores[3]` of a `Map<int, double>` puts the key `3`). Plain `Map`s can
/// be wrapped too (keys act as properties).
///
/// With [autoGrowNestedPaths], writes create what the path needs: `null`
/// nested objects, lists and maps, and list elements up to the index
/// (`items[2].sku` on an empty list adds three items, below
/// [autoGrowCollectionLimit]).
///
/// ```dart
/// final wrapper = BeanWrapper(person, autoGrowNestedPaths: true)
///   ..setPropertyValue('age', '42') // converted to int
///   ..setPropertyValue('address.city', 'Lyon') // creates the Address
///   ..setPropertyValue('previous[1].city', 'Oslo') // grows the list
///   ..setPropertyValue('tags[0]', 'admin');
/// wrapper.getPropertyValue('address.city'); // 'Lyon'
/// wrapper.getPropertyType('age'); // int
/// ```
///
/// Spring (Java):
/// ```java
/// BeanWrapper wrapper = new BeanWrapperImpl(person);
/// wrapper.setAutoGrowNestedPaths(true);
/// wrapper.setPropertyValue("age", "42");
/// wrapper.setPropertyValue("address.city", "Lyon");
/// wrapper.setPropertyValue("previous[1].city", "Oslo");
/// wrapper.setPropertyValue("tags[0]", "admin");
/// wrapper.getPropertyValue("address.city");
/// ```
///
/// Unlike Spring, the classes involved must be `@Introspected` (no
/// reflection); without generated `TypeInfo` (hand-written
/// introspections) element types are unknown and indexed values are stored
/// as they are. Reads never grow anything.
class BeanWrapper {
  /// Wraps [wrappedInstance]; [introspector] defaults to
  /// [BeanIntrospector.shared] and [conversionService] to the shared
  /// `DefaultConversionService`.
  BeanWrapper(
    this.wrappedInstance, {
    BeanIntrospector? introspector,
    ConversionService? conversionService,
    this.autoGrowNestedPaths = false,
    this.autoGrowCollectionLimit = 0x7FFFFFFF,
  }) : introspector = introspector ?? BeanIntrospector.shared,
       conversionService =
           conversionService ?? DefaultConversionService.sharedInstance;

  /// The object whose properties are accessed.
  final Object wrappedInstance;

  /// Source of the property metadata.
  final BeanIntrospector introspector;

  /// Converts written values to the property types.
  final ConversionService conversionService;

  /// Instantiate `null` nested introspected objects (with a no-argument
  /// constructor), lists and maps, and missing list elements, instead of
  /// failing.
  final bool autoGrowNestedPaths;

  /// Lists are grown up to (not including) this index, like Spring's
  /// `autoGrowCollectionLimit`.
  final int autoGrowCollectionLimit;

  /// Whether [path] can be read (all its segments exist and are not
  /// `null`).
  bool isReadableProperty(String path) {
    try {
      getPropertyValue(path);
      return true;
    } on BeansException {
      return false;
    }
  }

  /// Whether [path] can be written: a writable property, a map key, or an
  /// index into an existing collection.
  bool isWritableProperty(String path) {
    try {
      final segments = _parse(path);
      final last = segments.last;
      var target = wrappedInstance;
      for (final segment in segments.take(segments.length - 1)) {
        final (value, _) = _readSegment(target, segment, path, null);
        if (value == null) {
          return false;
        }
        target = value;
      }
      // Indexed writes are only checked when performed.
      if (last.keys.isNotEmpty) {
        return true;
      }
      final property = _property(target, last.name);
      return property?.isWritable ?? (target is Map);
    } on BeansException {
      return false;
    }
  }

  /// The declared type of the property at [path] (for list elements and
  /// map values: the generated element type, else the runtime type of the
  /// value), or `null` if unknown.
  Type? getPropertyType(String path) {
    try {
      final segments = _parse(path);
      Object? current = wrappedInstance;
      TypeInfo<Object?>? type;
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        if (current == null) {
          return null;
        }
        if (i == segments.length - 1 && segment.keys.isEmpty) {
          return _property(current, segment.name)?.type;
        }
        (current, type) = _readSegment(current, segment, path, type);
      }
      return type?.type ?? current?.runtimeType;
    } on BeansException {
      return null;
    }
  }

  /// The value at [path].
  ///
  /// ```dart
  /// wrapper.getPropertyValue('previous[0].city');
  /// wrapper.getPropertyValue("counts['math']");
  /// ```
  ///
  /// Throws [NotReadablePropertyException] for unknown properties or bad
  /// indexes and [NullValueInNestedPathException] when an intermediate
  /// value is `null`.
  Object? getPropertyValue(String path) {
    Object? current = wrappedInstance;
    TypeInfo<Object?>? type;
    final segments = _parse(path);
    for (var i = 0; i < segments.length; i++) {
      if (current == null) {
        throw NullValueInNestedPathException(
          wrappedInstance.runtimeType,
          _join(segments.take(i)),
        );
      }
      (current, type) = _readSegment(current, segments[i], path, type);
    }
    return current;
  }

  /// Writes [value] at [path], converting it to the property type (or the
  /// element / map value type).
  ///
  /// ```dart
  /// wrapper.setPropertyValue('score', '9.5'); // double 9.5
  /// wrapper.setPropertyValue("counts['math']", '3'); // int 3
  /// wrapper.setPropertyValue('tags[2]', 'x'); // index == length appends
  /// ```
  ///
  /// Throws [NotWritablePropertyException], [TypeMismatchException] or
  /// [NullValueInNestedPathException].
  void setPropertyValue(String path, Object? value) {
    final segments = _parse(path);
    Object current = wrappedInstance;
    TypeInfo<Object?>? currentType;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;
      if (isLast && segment.keys.isEmpty) {
        _writeProperty(current, segment.name, value, path);
        return;
      }
      // The named property (if any), grown when `null`.
      Object? container;
      TypeInfo<Object?>? type;
      if (segment.name.isEmpty) {
        (container, type) = (current, currentType);
      } else {
        (container, type) = _readProperty(current, segment.name, path);
        if (container == null && autoGrowNestedPaths) {
          container = _growProperty(current, segment.name, path);
        }
      }
      // Then its keys; the last key of the path is written.
      for (var k = 0; k < segment.keys.length; k++) {
        if (container == null) {
          throw NullValueInNestedPathException(
            wrappedInstance.runtimeType,
            _prefix(segments, i, k),
          );
        }
        if (isLast && k == segment.keys.length - 1) {
          _writeIndex(container, type, segment.keys[k], value, path);
          return;
        }
        (container, type) = _index(
          container,
          type,
          segment.keys[k],
          path,
          grow: autoGrowNestedPaths,
        );
      }
      if (container == null) {
        throw NullValueInNestedPathException(
          wrappedInstance.runtimeType,
          _join(segments.take(i + 1)),
        );
      }
      current = container;
      currentType = type;
    }
  }

  /// Sets every entry; failures are collected into a
  /// [PropertyBatchUpdateException].
  ///
  /// [ignoreUnknown] skips unknown or read-only properties;
  /// [ignoreInvalid] skips paths through `null` values (Spring's
  /// `setPropertyValues(pvs, ignoreUnknown, ignoreInvalid)`).
  ///
  /// ```dart
  /// wrapper.setPropertyValues(
  ///   {'name': 'Ann', 'age': '30', 'unknown': 1},
  ///   ignoreUnknown: true,
  /// );
  /// ```
  void setPropertyValues(
    Map<String, Object?> values, {
    bool ignoreUnknown = false,
    bool ignoreInvalid = false,
  }) {
    final failures = <BeansException>[];
    for (final MapEntry(:key, :value) in values.entries) {
      try {
        setPropertyValue(key, value);
      } on NotWritablePropertyException catch (error) {
        if (!ignoreUnknown) {
          failures.add(error);
        }
      } on NullValueInNestedPathException catch (error) {
        if (!ignoreInvalid) {
          failures.add(error);
        }
      } on BeansException catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) {
      throw PropertyBatchUpdateException(failures);
    }
  }

  // ---------------------------------------------------------------------

  /// Creates and assigns a new value for the `null` property [name]: an
  /// introspected object (no-argument constructor required), a list, a set
  /// or a map.
  Object _growProperty(Object target, String name, String path) {
    final property = _property(target, name);
    final created = property == null
        ? null
        : (property.typeInfo == null
              ? _instantiate(property.type)
              : _newValue(property.typeInfo!));
    if (property == null || created == null || !property.isWritable) {
      throw NullValueInNestedPathException(wrappedInstance.runtimeType, name);
    }
    property.setValue(target, created);
    return created;
  }

  /// A new instance of the introspected [type], or `null`.
  Object? _instantiate(Type type) {
    final introspection = introspector.forType(type);
    return introspection != null && introspection.isInstantiable
        ? introspection.instantiate()
        : null;
  }

  /// A new empty value of [type] (introspected object, list, set, map), or
  /// `null` when it cannot be created.
  Object? _newValue(TypeInfo<Object?> type) => type.accept(_NewValue(this));

  /// Reads one segment: the named property (if any) and then its keys,
  /// with the declared type of the result when known.
  (Object?, TypeInfo<Object?>?) _readSegment(
    Object target,
    _Segment segment,
    String path,
    TypeInfo<Object?>? targetType,
  ) {
    var (value, type) = segment.name.isEmpty
        ? (target, targetType)
        : _readProperty(target, segment.name, path);
    for (final key in segment.keys) {
      if (value == null) {
        throw NullValueInNestedPathException(wrappedInstance.runtimeType, path);
      }
      (value, type) = _index(value, type, key, path, grow: false);
    }
    return (value, type);
  }

  BeanProperty<Object>? _property(Object target, String name) =>
      introspector.findIntrospection(target)?.getProperty(name);

  (Object?, TypeInfo<Object?>?) _readProperty(
    Object target,
    String name,
    String path,
  ) {
    // Maps expose their keys as properties (like Spring's map access).
    if (target is Map) {
      return (target[name], null);
    }
    final introspection = introspector.findIntrospection(target);
    if (introspection == null) {
      throw NotReadablePropertyException(
        target.runtimeType,
        path,
        'not @Introspected',
      );
    }
    final property = introspection.getProperty(name);
    if (property == null) {
      throw NotReadablePropertyException(
        target.runtimeType,
        path,
        "no property '$name'",
      );
    }
    return (property.getValue(target), property.typeInfo);
  }

  void _writeProperty(Object target, String name, Object? value, String path) {
    if (target is Map) {
      target[name] = value;
      return;
    }
    final introspection = introspector.findIntrospection(target);
    final property = introspection?.getProperty(name);
    if (property == null || !property.isWritable) {
      throw NotWritablePropertyException(
        target.runtimeType,
        path,
        introspection == null
            ? 'not @Introspected'
            : property == null
            ? "no property '$name'"
            : 'read-only',
      );
    }
    final converted = _convert(value, property.type, property.nullable, path);
    try {
      property.setValue(target, converted);
    } on BeansException {
      rethrow;
    } catch (error) {
      // Whatever the setter throws (validation in a setter, ...).
      throw MethodInvocationException(path, error);
    }
  }

  /// Converts [value] for a property of [type]; non-[BeansException]
  /// conversion errors become [TypeMismatchException]s.
  Object? _convert(Object? value, Type type, bool nullable, String path) {
    if (value == null) {
      if (nullable) {
        return null;
      }
      throw TypeMismatchException(path, value, type);
    }
    try {
      final converted = conversionService.convertTo(value, type);
      if (converted == null && !nullable) {
        throw TypeMismatchException(path, value, type);
      }
      return converted;
    } on BeansException {
      rethrow;
    } catch (error) {
      throw TypeMismatchException(path, value, type, error);
    }
  }

  /// [value] converted to the element type [type] (as it is when unknown
  /// or `dynamic`).
  Object? _convertElement(Object? value, TypeInfo<Object?>? type, String path) {
    if (type == null || type is DynamicType || type.isInstance(value)) {
      return value;
    }
    return _convert(value, type.type, type.nullable, path);
  }

  /// Element [key] of a map, list or other iterable, with its declared
  /// type; with [grow], missing map values and list elements are created.
  (Object?, TypeInfo<Object?>?) _index(
    Object container,
    TypeInfo<Object?>? type,
    String key,
    String path, {
    required bool grow,
  }) {
    switch (container) {
      case Map<Object?, Object?>():
        final mapType = type is MapType ? type : null;
        final mapKey = _mapKey(container, key, mapType?.key, path);
        var value = container[mapKey];
        if (value == null && grow && mapType != null) {
          value = _newValue(mapType.value);
          if (value != null) {
            _put(container, mapKey, value, path);
          }
        }
        return (value, mapType?.value);
      case List<Object?>():
        final elementType = type is ListType ? type.element : null;
        final index = int.tryParse(key);
        if (index != null &&
            index >= container.length &&
            grow &&
            elementType != null &&
            index < autoGrowCollectionLimit) {
          _growList(container, elementType, index + 1, path);
        }
        if (index == null || index < 0 || index >= container.length) {
          throw NotReadablePropertyException(
            wrappedInstance.runtimeType,
            path,
            'index $key out of bounds for length ${container.length}',
          );
        }
        return (container[index], elementType);
      case Iterable<Object?>():
        final index = int.tryParse(key);
        if (index == null || index < 0 || index >= container.length) {
          throw NotReadablePropertyException(
            wrappedInstance.runtimeType,
            path,
            'index $key out of bounds',
          );
        }
        return (
          container.elementAt(index),
          type is SetType ? type.element : null,
        );
      default:
        throw NotReadablePropertyException(
          wrappedInstance.runtimeType,
          path,
          'cannot index into ${container.runtimeType}',
        );
    }
  }

  /// Adds new elements of [elementType] to [list] until it has [length].
  void _growList(
    List<Object?> list,
    TypeInfo<Object?> elementType,
    int length,
    String path,
  ) {
    while (list.length < length) {
      final element = _newValue(elementType);
      if (element == null) {
        throw NotReadablePropertyException(
          wrappedInstance.runtimeType,
          path,
          'cannot create a $elementType to grow the list',
        );
      }
      _add(list, element, path);
    }
  }

  /// Writes element [key] of a map or list, converting the key and the
  /// value to the declared types; writing at `length` appends, and with
  /// [autoGrowNestedPaths] an index beyond it pads the list (with `null`
  /// for nullable elements, else new elements).
  void _writeIndex(
    Object container,
    TypeInfo<Object?>? type,
    String key,
    Object? value,
    String path,
  ) {
    switch (container) {
      case Map<Object?, Object?>():
        final mapType = type is MapType ? type : null;
        _put(
          container,
          _mapKey(container, key, mapType?.key, path),
          _convertElement(value, mapType?.value, path),
          path,
        );
      case List<Object?>():
        final elementType = type is ListType ? type.element : null;
        final index = int.tryParse(key);
        if (index == null ||
            index < 0 ||
            (index > container.length &&
                !(autoGrowNestedPaths && index < autoGrowCollectionLimit))) {
          throw NotWritablePropertyException(
            wrappedInstance.runtimeType,
            path,
            'index $key out of bounds',
          );
        }
        final converted = _convertElement(value, elementType, path);
        while (container.length < index) {
          final padding = elementType == null || elementType.nullable
              ? null
              : _newValue(elementType);
          _add(container, padding, path);
        }
        if (index == container.length) {
          _add(container, converted, path);
        } else {
          try {
            container[index] = converted;
          } on TypeError catch (error) {
            throw TypeMismatchException(
              path,
              converted,
              container.runtimeType,
              error,
            );
          }
        }
      default:
        throw NotWritablePropertyException(
          wrappedInstance.runtimeType,
          path,
          'cannot index into ${container.runtimeType}',
        );
    }
  }

  // Element types are not always known; the collection rejects a value of
  // the wrong type with a TypeError.
  void _add(List<Object?> list, Object? value, String path) {
    try {
      list.add(value);
    } on TypeError catch (error) {
      throw TypeMismatchException(path, value, list.runtimeType, error);
    }
  }

  void _put(
    Map<Object?, Object?> map,
    Object? key,
    Object? value,
    String path,
  ) {
    try {
      map[key] = value;
    } on TypeError catch (error) {
      throw TypeMismatchException(path, value, map.runtimeType, error);
    }
  }

  /// The map key for [key]: converted to the declared [keyType] when
  /// known; otherwise a string unless the map has an integer key like it.
  Object? _mapKey(
    Map<Object?, Object?> map,
    String key,
    TypeInfo<Object?>? keyType,
    String path,
  ) {
    if (keyType != null && keyType is! DynamicType) {
      return _convertElement(key, keyType, path);
    }
    if (map.containsKey(key)) {
      return key;
    }
    final asInt = int.tryParse(key);
    return asInt != null && map.containsKey(asInt) ? asInt : key;
  }

  static String _join(Iterable<_Segment> segments) => segments.join('.');

  // The path up to key [key] of segment [segment] (exclusive).
  static String _prefix(List<_Segment> segments, int segment, int key) {
    final current = segments[segment];
    return [
      ...segments.take(segment),
      _Segment(current.name, current.keys.take(key).toList()),
    ].join('.');
  }

  /// Splits `a.b[0]['k'].c` into segments with index keys.
  ///
  /// Each segment is a (possibly empty) name followed by `[key]`s; quotes
  /// around keys are optional and removed. A segment with neither name
  /// nor keys (e.g. `a..b`) is invalid.
  static List<_Segment> _parse(String path) {
    final segments = <_Segment>[];
    var name = StringBuffer();
    var keys = <String>[];
    var i = 0;
    while (i < path.length) {
      final c = path[i];
      if (c == '.') {
        segments.add(_Segment(name.toString(), keys));
        name = StringBuffer();
        keys = [];
        i++;
      } else if (c == '[') {
        final end = path.indexOf(']', i);
        if (end < 0) {
          throw InvalidPropertyException(path, "missing ']'");
        }
        var key = path.substring(i + 1, end).trim();
        if (key.length >= 2 &&
            ((key.startsWith("'") && key.endsWith("'")) ||
                (key.startsWith('"') && key.endsWith('"')))) {
          key = key.substring(1, key.length - 1);
        }
        keys.add(key);
        i = end + 1;
      } else {
        name.write(c);
        i++;
      }
    }
    segments.add(_Segment(name.toString(), keys));
    if (segments.any((s) => s.name.isEmpty && s.keys.isEmpty)) {
      throw InvalidPropertyException(path, 'empty property name');
    }
    return segments;
  }
}

/// Creates empty values for auto-growing: introspected objects with a
/// no-argument constructor, lists, sets and maps of the right static type.
final class _NewValue implements TypeInfoVisitor<Object?> {
  _NewValue(this.wrapper);

  final BeanWrapper wrapper;

  @override
  Object? visitClass<T>(ClassType<T> type) {
    final introspection = wrapper.introspector.forTypeArgument<T>();
    return introspection != null && introspection.isInstantiable
        ? introspection.instantiate()
        : null;
  }

  @override
  Object? visitList<E>(ListType<E> type) => type.create(const []);

  @override
  Object? visitSet<E>(SetType<E> type) => type.create(const []);

  @override
  Object? visitMap<K, V>(MapType<K, V> type) => type.create(const []);

  @override
  Object? visitEnum<E extends Enum>(EnumType<E> type) => null;

  @override
  Object? visitGeneric<T>(GenericType<T> type) => null;

  @override
  Object? visitDynamic(DynamicType type) => null;
}

/// One `.`-separated part of a property path: `name[key1][key2]`.
final class _Segment {
  _Segment(this.name, this.keys);

  final String name;
  final List<String> keys;

  @override
  String toString() => '$name${keys.map((k) => '[$k]').join()}';
}
