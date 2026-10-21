import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
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
/// type with the conversion service. Plain `Map`s can be wrapped too
/// (keys act as properties).
///
/// ```dart
/// final wrapper = BeanWrapper(person, autoGrowNestedPaths: true)
///   ..setPropertyValue('age', '42') // converted to int
///   ..setPropertyValue('address.city', 'Lyon') // creates the Address
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
/// wrapper.setPropertyValue("tags[0]", "admin");
/// wrapper.getPropertyValue("address.city");
/// ```
///
/// Unlike Spring, the classes involved must be `@Introspected` (no
/// reflection), and element types of lists and maps are not known, so
/// indexed values are stored without conversion.
class BeanWrapper {
  /// Wraps [wrappedInstance]; [introspector] defaults to
  /// [BeanIntrospector.shared] and [conversionService] to the shared
  /// `DefaultConversionService`.
  BeanWrapper(
    this.wrappedInstance, {
    BeanIntrospector? introspector,
    ConversionService? conversionService,
    this.autoGrowNestedPaths = false,
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
  /// constructor) instead of failing.
  final bool autoGrowNestedPaths;

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
      final (target, last) = _resolveParent(path, grow: false);
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

  /// The declared type of the property at [path] (the runtime type for map
  /// and list elements), or `null` if unknown.
  Type? getPropertyType(String path) {
    try {
      final (target, last) = _resolveParent(path, grow: false);
      if (last.keys.isEmpty) {
        return _property(target, last.name)?.type;
      }
      return getPropertyValue(path)?.runtimeType;
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
    final segments = _parse(path);
    for (var i = 0; i < segments.length; i++) {
      if (current == null) {
        throw NullValueInNestedPathException(
          wrappedInstance.runtimeType,
          _join(segments.take(i)),
        );
      }
      current = _readSegment(current, segments[i], path);
    }
    return current;
  }

  /// Writes [value] at [path], converting it to the property type.
  ///
  /// ```dart
  /// wrapper.setPropertyValue('score', '9.5'); // double 9.5
  /// wrapper.setPropertyValue("counts['math']", 3);
  /// wrapper.setPropertyValue('tags[2]', 'x'); // index == length appends
  /// ```
  ///
  /// Throws [NotWritablePropertyException], [TypeMismatchException] or
  /// [NullValueInNestedPathException].
  void setPropertyValue(String path, Object? value) {
    final (target, last) = _resolveParent(path, grow: autoGrowNestedPaths);
    if (last.keys.isEmpty) {
      _writeProperty(target, last.name, value, path);
      return;
    }
    // Indexed write such as `a.b[0]['k']`: read `b`, follow all keys but
    // the last, then write the element.
    var container = last.name.isEmpty
        ? target
        : _readProperty(target, last.name, path);
    for (var i = 0; i < last.keys.length - 1; i++) {
      container = _index(container, last.keys[i], path);
    }
    _writeIndex(container, last.keys.last, value, path);
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

  /// The object holding the last segment of [path], and that segment.
  /// With [grow], `null` intermediate properties are instantiated.
  (Object, _Segment) _resolveParent(String path, {required bool grow}) {
    final segments = _parse(path);
    Object current = wrappedInstance;
    for (var i = 0; i < segments.length - 1; i++) {
      final segment = segments[i];
      var next = _readSegment(current, segment, path);
      if (next == null && grow && segment.keys.isEmpty) {
        next = _grow(current, segment.name, path);
      }
      if (next == null) {
        throw NullValueInNestedPathException(
          wrappedInstance.runtimeType,
          _join(segments.take(i + 1)),
        );
      }
      current = next;
    }
    return (current, segments.last);
  }

  /// Creates and assigns a new instance for the `null` property [name],
  /// using its type's introspection (no-argument constructor required).
  Object _grow(Object target, String name, String path) {
    final property = _property(target, name);
    final introspection = property == null
        ? null
        : introspector.forType(property.type);
    if (property == null ||
        introspection == null ||
        !introspection.isInstantiable) {
      throw NullValueInNestedPathException(wrappedInstance.runtimeType, name);
    }
    final created = introspection.instantiate();
    property.setValue(target, created);
    return created;
  }

  /// Reads one segment: the named property (if any) and then its keys.
  Object? _readSegment(Object target, _Segment segment, String path) {
    Object? value = segment.name.isEmpty
        ? target
        : _readProperty(target, segment.name, path);
    for (final key in segment.keys) {
      if (value == null) {
        throw NullValueInNestedPathException(wrappedInstance.runtimeType, path);
      }
      value = _index(value, key, path);
    }
    return value;
  }

  BeanProperty<Object>? _property(Object target, String name) =>
      introspector.findIntrospection(target)?.getProperty(name);

  Object? _readProperty(Object target, String name, String path) {
    // Maps expose their keys as properties (like Spring's map access).
    if (target is Map) {
      return target[name];
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
    return property.getValue(target);
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

  /// Reads element [key] of a map, list or other iterable.
  Object? _index(Object? container, String key, String path) {
    switch (container) {
      case Map<Object?, Object?>():
        return container[_mapKey(container, key)];
      case List<Object?>():
        final index = int.tryParse(key);
        if (index == null || index < 0 || index >= container.length) {
          throw NotReadablePropertyException(
            wrappedInstance.runtimeType,
            path,
            'index $key out of bounds for length ${container.length}',
          );
        }
        return container[index];
      case Iterable<Object?>():
        final index = int.tryParse(key);
        if (index == null || index < 0 || index >= container.length) {
          throw NotReadablePropertyException(
            wrappedInstance.runtimeType,
            path,
            'index $key out of bounds',
          );
        }
        return container.elementAt(index);
      default:
        throw NotReadablePropertyException(
          wrappedInstance.runtimeType,
          path,
          'cannot index into ${container.runtimeType}',
        );
    }
  }

  /// Writes element [key] of a map or list; writing at `length` appends.
  void _writeIndex(Object? container, String key, Object? value, String path) {
    try {
      switch (container) {
        case Map<Object?, Object?>():
          container[_mapKey(container, key)] = value;
        case List<Object?>():
          final index = int.tryParse(key);
          if (index == null || index < 0 || index > container.length) {
            throw NotWritablePropertyException(
              wrappedInstance.runtimeType,
              path,
              'index $key out of bounds',
            );
          }
          if (index == container.length) {
            container.add(value);
          } else {
            container[index] = value;
          }
        default:
          throw NotWritablePropertyException(
            wrappedInstance.runtimeType,
            path,
            'cannot index into ${container.runtimeType}',
          );
      }
    } on TypeError catch (error) {
      // Element types are not known at runtime; the collection rejected it.
      throw TypeMismatchException(path, value, container.runtimeType, error);
    }
  }

  /// Map keys are strings unless the map has non-string keys parseable as
  /// integers.
  Object? _mapKey(Map<Object?, Object?> map, String key) {
    if (map.containsKey(key)) {
      return key;
    }
    final asInt = int.tryParse(key);
    return asInt != null && map.containsKey(asInt) ? asInt : key;
  }

  static String _join(Iterable<_Segment> segments) => segments.join('.');

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

/// One `.`-separated part of a property path: `name[key1][key2]`.
final class _Segment {
  _Segment(this.name, this.keys);

  final String name;
  final List<String> keys;

  @override
  String toString() => '$name${keys.map((k) => '[$k]').join()}';
}
