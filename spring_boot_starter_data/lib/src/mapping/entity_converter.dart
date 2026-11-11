import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_introspection.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';

/// Turns an entity into a row and a row into an entity, for the entity's
/// own table (its [MappedCollection] children are the store's business).
///
/// A row is a `Map<String, Object?>` keyed by column name. The values are
/// those of Dart: `int`, `double`, `num`, `String`, `bool`, `DateTime`,
/// `Uint8List`, `BigInt` and null. What a database needs besides (a
/// `DateTime` as text, a `bool` as 0/1) is the store's conversion, done
/// after [write] and before [read].
///
/// [write] stores an `AggregateReference` as its id and an enum as its
/// `name`. [read] does the reverse and the conversions databases make
/// necessary: an enum's name to the constant, an `int` to a `double`
/// property, an `int` 0/1 (SQLite) to a `bool`, an ISO-8601 `String` (or
/// epoch milliseconds) to a `DateTime`, a `List<int>` to `Uint8List`. The
/// elements of a `List` or a `Set` that is a column (an array of
/// PostgreSQL, anything in the in-memory store) are written and read as
/// single values of their type are.
///
/// A [Json] property is the exception to the plain values: [write] gives
/// its decoded JSON (what `jsonDecode` returns: maps, lists, numbers,
/// strings, booleans), made by the [mapper], and [read] takes that tree
/// back, or the JSON text of a store that gave text; a SQL store asks its
/// dialect how the tree is bound and read (`SqlDialect.jsonStorage`), a
/// store that keeps or sends JSON uses it as it is.
///
/// ```dart
/// final row = converter.write(profiles, Profile(settings: Settings('dark')));
/// row['settings']; // {'theme': 'dark'}
/// converter.read(profiles, row).settings.theme; // 'dark'
/// ```
///
/// An instance is created through the class's constructor, with the values
/// of all the properties given to its `EntityIntrospection.create`: a
/// property takes the column of its name, else its default value (a
/// constant initializer or a constant default of its constructor
/// parameter), else null, which a parameter that cannot be null refuses
/// with a [MappingException]. The other writable properties are set after.
///
/// An entity with `final` properties cannot be changed in place: [withId],
/// [withVersion] and [withValues] return a copy made through the
/// constructor when a property is not writable (and the same instance
/// otherwise), so `save` must return what they return, never rely on the
/// instance it was given.
///
/// An `AggregateReference<X, ID>` is created with no reflection: the
/// generator describes the property as a `GenericType` whose arguments
/// describe `X` and `ID`, and capturing both gives the reified type.
///
/// Spring (Java):
/// `org.springframework.data.jdbc.core.convert.MappingJdbcConverter`
/// (with `org.springframework.data.mapping.PersistentPropertyAccessor` for
/// the id and version).
class EntityConverter {
  /// A converter looking enums up in [introspector] (by default
  /// `BeanIntrospector.shared`) when the type given does not carry them (a
  /// `ClassType` of the JDBC-level mappers; an entity's enum property is an
  /// `EnumType`), and writing and reading the [Json] properties with
  /// [mapper] (the application's `ObjectMapper` bean in an application; by
  /// default one over [introspector]).
  EntityConverter({BeanIntrospector? introspector, ObjectMapper? mapper})
    : introspector = introspector ?? BeanIntrospector.shared,
      // The field is private; the parameter is public.
      // ignore: prefer_initializing_formals
      _mapper = mapper;

  /// Where enums not described by their type are looked up.
  final BeanIntrospector introspector;

  ObjectMapper? _mapper;

  /// Writes and reads the [Json] properties: the mapper given, else one
  /// with the default settings over [introspector], made on first use.
  ///
  /// Spring (Java): the `ObjectMapper` a `@WritingConverter` to JSON is
  /// given.
  ObjectMapper get mapper =>
      _mapper ??= ObjectMapper(introspector: introspector);

  // ---------------------------------------------------------------- write

  /// The row of [instance]: every column of [entity] (so the id and
  /// version too, and nulls included) with its value as [toColumnValue]
  /// gives it; a [Json] property as [toJsonTree] gives it.
  Map<String, Object?> write(PersistentEntity<Object> entity, Object instance) {
    return {
      for (final p in entity.columns)
        p.columnName: p.isJson
            ? toJsonTree(p.getValue(instance), p.type, where: _where(entity, p))
            : toColumnValue(p.getValue(instance)),
    };
  }

  /// [value] (of a [Json] property of [type]) as decoded JSON, written by
  /// the [mapper]: new maps and lists that share nothing with [value]; null
  /// for null. Throws a [MappingException] (naming [where], never the
  /// value) for a value the mapper cannot write, such as a class that is
  /// not described.
  ///
  /// ```dart
  /// converter.toJsonTree([Address('Oak St')], addresses.type);
  /// // [{'street': 'Oak St'}]
  /// ```
  Object? toJsonTree(
    Object? value,
    TypeInfo<Object?> type, {
    String where = 'value',
  }) {
    if (value == null) {
      return null;
    }
    try {
      return copyJsonTree(mapper.valueToTree(value, type));
    } on JsonMappingException catch (error) {
      throw MappingException(
        '$where: its value cannot be written as JSON'
        '${error.path.isEmpty ? '' : ' (at ${error.path})'}: is every '
        'class in it described (the build describes the classes of a '
        '@Json property of the application; a class of another package '
        'needs @Introspected there)?',
      );
    }
  }

  /// [tree] (decoded JSON, a `JsonNode`, or JSON text) read by the
  /// [mapper] as a [Json] property of [type] holds it; the result shares
  /// nothing with [tree]. Throws a [MappingException] naming [where] and
  /// the place in the JSON, never the value, when the JSON does not fit
  /// [type].
  ///
  /// A `String` is JSON text when [type] takes no `String` (a class, a
  /// list, a map, a number: what a store that keeps text gave) and is
  /// decoded; for a type that takes one (`String`, `Object`) it is the
  /// value.
  ///
  /// ```dart
  /// converter.fromJsonTree({'theme': 'dark'}, settings.type); // Settings
  /// converter.fromJsonTree('{"theme":"dark"}', settings.type); // the same
  /// ```
  Object? fromJsonTree(
    Object? tree,
    TypeInfo<Object?> type, {
    String where = 'value',
  }) {
    if (tree == null) {
      if (!type.nullable) {
        throw MappingException('$where is null but its type $type is not');
      }
      return null;
    }
    Object? json = tree;
    if (tree is String && !type.isInstance(tree)) {
      // The text of a JSON document, from a store that gave the column as
      // it is. Only a document: a JSON string that happens to parse (a
      // BigInt written as "123...", the text "null") is the value itself,
      // and reading it as a number would lose digits without an error.
      try {
        if (jsonDecode(tree) case final Object decoded
            when decoded is Map || decoded is List) {
          json = decoded;
        }
      } on FormatException {
        // No JSON text: a JSON string (an enum's name); the mapper judges.
      }
    }
    final Object? read;
    try {
      read = mapper.treeToValue<Object?>(copyJsonTree(json), type);
    } on JsonMappingException catch (error) {
      throw MappingException(
        '$where: the stored JSON cannot be read as $type'
        '${error.path.isEmpty ? '' : ' (at ${error.path})'}',
      );
    } on TypeError {
      throw MappingException(
        '$where: the stored JSON cannot be read as $type',
      );
    }
    if (!type.isInstance(read)) {
      throw MappingException(
        '$where: the stored JSON cannot be read as $type',
      );
    }
    return read;
  }

  /// A copy of the decoded JSON [tree] with maps and lists of its own (a
  /// `JsonNode` is left as it is: the mapper copies it).
  static Object? copyJsonTree(Object? tree) => switch (tree) {
    final Map<Object?, Object?> map => <String, Object?>{
      for (final MapEntry(:key, :value) in map.entries)
        '$key': copyJsonTree(value),
    },
    final List<Object?> list => <Object?>[
      for (final item in list) copyJsonTree(item),
    ],
    _ => tree,
  };

  /// [value] as a column holds it: an `AggregateReference` as its id, an
  /// enum as its `name`, anything else unchanged.
  ///
  /// The elements of a `List` or a `Set` are converted as single values
  /// are (an array column and the list of an `in` hold what a column of
  /// one value holds): a new collection when an element changed, else
  /// [value] itself. Bytes (`List<int>`, `Uint8List`) are one value, not
  /// a collection.
  ///
  /// ```dart
  /// converter.toColumnValue(Color.red); // 'red'
  /// converter.toColumnValue([Color.red, null]); // ['red', null]
  /// ```
  Object? toColumnValue(Object? value) => switch (value) {
    final AggregateReference<Object?, Object?> ref => toColumnValue(ref.id),
    final Enum e => e.name,
    List<int>() => value,
    final List<Object?> list =>
      _changes(list) ? [for (final item in list) toColumnValue(item)] : list,
    final Set<Object?> set =>
      _changes(set) ? {for (final item in set) toColumnValue(item)} : set,
    _ => value,
  };

  // Whether an element of [items] is written as something else.
  bool _changes(Iterable<Object?> items) =>
      items.any((item) => !identical(toColumnValue(item), item));

  // ----------------------------------------------------------------- read

  /// Creates the entity of [entity]'s class from [row] (keyed by column
  /// name; the column of a [Json] property holds decoded JSON, see
  /// [fromJsonTree]); [children] holds the ready-made values of the
  /// [MappedCollection] properties, by property name (a `List`, `Set` or
  /// `Map`, of the right element types or not: it is converted). A
  /// non-null mapped collection absent from [children] is empty.
  ///
  /// A column missing from [row], or null for a property that cannot be
  /// null, leaves the property its default value (when it has one; else a
  /// parameter that cannot be null is refused, and any other property is
  /// left as the constructor makes it). An unconvertible value, or a
  /// non-null parameter without a column or a default, is a
  /// [MappingException].
  T read<T extends Object>(
    PersistentEntity<T> entity,
    Map<String, Object?> row, {
    Map<String, Object?> children = const {},
  }) {
    final introspection = entity.introspection;
    final properties = introspection.properties;
    final values = List<Object?>.filled(properties.length, null);
    final usable = List<bool>.filled(properties.length, false);
    for (final (i, described) in properties.indexed) {
      final p = entity.propertyAt(i);
      var inRow = false;
      if (p != null && p.isMappedCollection) {
        if (children.containsKey(p.name)) {
          values[i] = _collection(entity, p, children[p.name]);
          usable[i] = true;
        } else if (!p.isNullable) {
          values[i] = _collection(
            entity,
            p,
            p.type is MapType<Object?, Object?>
                ? const <Object?, Object?>{}
                : const <Object?>[],
          );
          usable[i] = true;
        }
      } else if (p != null && row.containsKey(p.columnName)) {
        inRow = true;
        final value = row[p.columnName];
        if (value != null) {
          values[i] = p.isJson
              ? fromJsonTree(value, p.type, where: _where(entity, p))
              : fromColumnValue(value, p.type, where: _where(entity, p));
          usable[i] = true;
        } else if (described.type.nullable) {
          usable[i] = true;
        }
      }
      if (!usable[i] && described.hasDefaultValue) {
        values[i] = _defaultOf(introspection.className, described);
        usable[i] = true;
      }
      if (!usable[i] && described.parameter && !described.type.nullable) {
        throw MappingException(
          inRow
              ? '${introspection.className}.${described.name} is null but '
                    'the constructor requires a ${described.type}'
              : '${introspection.className}: the constructor requires '
                    '${described.name} but there is no column for it '
                    '(a @Transient property, or a missing column)',
        );
      }
    }
    return _create(introspection, values, usable);
  }

  // The default of [described] as the property holds it (a constant of the
  // description, such as the `0` of a `double`, widened).
  Object? _defaultOf(String className, EntityProperty described) {
    final value = described.defaultValue;
    return value == null
        ? null
        : fromColumnValue(
            value,
            described.type,
            where: '$className.${described.name} (default)',
          );
  }

  /// [value], as read from a column, converted to what a property of type
  /// [type] holds; throws a [MappingException] (naming [where]) when it
  /// cannot be.
  Object? fromColumnValue(
    Object? value,
    TypeInfo<Object?> type, {
    String where = 'value',
  }) {
    if (value == null) {
      if (!type.nullable) {
        throw MappingException('$where is null but its type $type is not');
      }
      return null;
    }
    final converted = _convert(value, type, where);
    if (!type.isInstance(converted)) {
      throw MappingException(
        '$where: cannot use a ${converted.runtimeType} as $type',
      );
    }
    return converted;
  }

  Object _convert(Object value, TypeInfo<Object?> type, String where) {
    if (value is AggregateReference<Object?, Object?>) {
      return value;
    }
    switch (type) {
      case final EnumType<Enum> enumType:
        return _enumValue(value, enumType, where);
      case final GenericType<Object?> generic
          when generic.arguments.length == 2 &&
              generic.isSubtypeOf<AggregateReference<Object?, Object?>>():
        return _reference(value, generic, where);
      case ListType<Object?>() ||
          SetType<Object?>() ||
          MapType<Object?, Object?>():
        return _collectionOf(type, value, where);
      default:
        break;
    }
    final target = type.type;
    if (target == double && value is int) {
      return value.toDouble();
    }
    if (target == int && value is double && value == value.truncateToDouble()) {
      return value.toInt();
    }
    if (target == bool && value is int) {
      return value != 0;
    }
    if (target == DateTime) {
      if (value is String) {
        return DateTime.tryParse(value) ??
            (throw MappingException('$where: "$value" is not a date'));
      }
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
    }
    if (target == BigInt) {
      if (value is int) {
        return BigInt.from(value);
      }
      if (value is String) {
        return BigInt.tryParse(value) ??
            (throw MappingException('$where: "$value" is not a number'));
      }
    }
    if (target == Uint8List && value is List<int> && value is! Uint8List) {
      return Uint8List.fromList(value);
    }
    if (value is String && target != String && target != Object) {
      // An enum the property's description does not carry.
      final enumType = introspector.enumTypeFor(target);
      if (enumType != null) {
        return _enumValue(value, enumType, where);
      }
    }
    return value;
  }

  Enum _enumValue(Object value, EnumType<Enum> type, String where) {
    if (value is Enum && type.isInstance(value)) {
      return value;
    }
    for (final constant in type.values) {
      if (constant.name == value) {
        return constant;
      }
    }
    throw MappingException(
      '$where: "$value" is not a constant of ${type.type}',
    );
  }

  Object _reference(Object id, GenericType<Object?> type, String where) {
    final idType = type.arguments[1];
    final idValue = fromColumnValue(id, idType, where: '$where (id)');
    return type.arguments[0].capture<Object>(
      <A>() => idType.capture<Object>(
        <I>() => AggregateReference<A, I>(idValue as I),
      ),
    );
  }

  Object _collection(
    PersistentEntity<Object> entity,
    PersistentProperty property,
    Object? value,
  ) {
    if (value == null) {
      return const <Object?>[];
    }
    return _collectionOf(property.type, value, _where(entity, property));
  }

  Object _collectionOf(TypeInfo<Object?> type, Object value, String where) {
    if (value is TypedData && !type.isInstance(value)) {
      // Bytes are one value (what a driver gives for a column it does not
      // decode), never the elements of a collection of something else.
      throw MappingException(
        '$where: cannot use a ${value.runtimeType} as $type',
      );
    }
    switch (type) {
      case final ListType<Object?> list when value is Iterable<Object?>:
        return list.create(_elements(type, list.element, value, where));
      case final SetType<Object?> set when value is Iterable<Object?>:
        return set.create(_elements(type, set.element, value, where));
      case final MapType<Object?, Object?> map
          when value is Map<Object?, Object?>:
        return map.create(value.entries);
      case _:
        throw MappingException(
          '$where: cannot use a ${value.runtimeType} as $type',
        );
    }
  }

  // The elements of [value] as a collection of [type] holds them: each
  // converted as a single value of the [element] type is (an enum's name
  // of a `text[]` to the constant, a number to a `BigInt`), unless
  // [value] is such a collection already (bytes, the entities of a mapped
  // collection, a list read by the property's own type).
  Iterable<Object?> _elements(
    TypeInfo<Object?> type,
    TypeInfo<Object?> element,
    Iterable<Object?> value,
    String where,
  ) => type.isInstance(value)
      ? value
      : [
          for (final (index, item) in value.indexed)
            fromColumnValue(item, element, where: '$where[$index]'),
        ];

  // ------------------------------------------------------ id and version

  /// The id of [instance]; throws a [MappingException] when the class has
  /// no `@Id`.
  Object? idOf(PersistentEntity<Object> entity, Object instance) =>
      _requireId(entity).getValue(instance);

  /// The version of [instance]; throws a [MappingException] when the
  /// class has no `@Version`.
  Object? versionOf(PersistentEntity<Object> entity, Object instance) =>
      _requireVersion(entity).getValue(instance);

  /// Sets the id of [instance] in place; throws a [MappingException] when
  /// the id is `final` (use [withId], which copies).
  void setId(PersistentEntity<Object> entity, Object instance, Object? id) =>
      _set(entity, instance, _requireId(entity), id);

  /// Sets the version of [instance] in place; throws a [MappingException]
  /// when it is `final` (use [withVersion], which copies).
  void setVersion(
    PersistentEntity<Object> entity,
    Object instance,
    Object? version,
  ) => _set(entity, instance, _requireVersion(entity), version);

  /// [instance] with its id set to [id]: the same instance when the id is
  /// writable, else a copy made through the constructor.
  T withId<T extends Object>(
    PersistentEntity<T> entity,
    T instance,
    Object? id,
  ) => withValues(entity, instance, {_requireId(entity).name: id});

  /// [instance] with its version set to [version]: the same instance when
  /// the version is writable, else a copy made through the constructor.
  T withVersion<T extends Object>(
    PersistentEntity<T> entity,
    T instance,
    Object? version,
  ) => withValues(entity, instance, {_requireVersion(entity).name: version});

  /// [instance] with the properties named by [changes] (property name to
  /// value, as a property holds it, not as a column does) set: the same
  /// instance when every one is writable, else a copy made through the
  /// constructor, with every property of the original (a `@Transient`
  /// one too) carried over: the writable ones the constructor does not take
  /// are set on the copy.
  T withValues<T extends Object>(
    PersistentEntity<T> entity,
    T instance,
    Map<String, Object?> changes,
  ) {
    final properties = {for (final p in entity.properties) p.name: p};
    for (final name in changes.keys) {
      if (properties[name] == null) {
        throw MappingException(
          '${entity.introspection.className} has no stored property $name',
        );
      }
    }
    final converted = {
      for (final MapEntry(:key, :value) in changes.entries)
        key: fromColumnValue(
          value,
          properties[key]!.type,
          where: _where(entity, properties[key]!),
        ),
    };
    final introspection = entity.introspection;
    if (changes.keys.every((n) => properties[n]!.isWritable)) {
      for (final MapEntry(:key, :value) in converted.entries) {
        introspection.write(instance, properties[key]!.index, value);
      }
      return instance;
    }
    final values = introspection.values(instance);
    for (final MapEntry(:key, :value) in converted.entries) {
      values[properties[key]!.index] = value;
    }
    return _create(introspection, values);
  }

  // ------------------------------------------------------------- internals

  PersistentProperty _requireId(PersistentEntity<Object> entity) =>
      entity.idProperty ??
      (throw MappingException(
        '${entity.introspection.className} has no @Id property',
      ));

  PersistentProperty _requireVersion(PersistentEntity<Object> entity) =>
      entity.versionProperty ??
      (throw MappingException(
        '${entity.introspection.className} has no @Version property',
      ));

  void _set(
    PersistentEntity<Object> entity,
    Object instance,
    PersistentProperty property,
    Object? value,
  ) {
    if (!property.isWritable) {
      throw MappingException(
        '${_where(entity, property)} is final: create a copy with '
        'withValues (withId, withVersion) instead of setting it',
      );
    }
    property.setValue(
      instance,
      fromColumnValue(value, property.type, where: _where(entity, property)),
    );
  }

  String _where(PersistentEntity<Object> entity, PersistentProperty p) =>
      '${entity.introspection.className}.${p.name}';

  /// Creates the instance from [values] (one for each property of the
  /// description, in its order), then sets the writable properties the
  /// constructor does not take: those [usable] says have a value (all, when
  /// it is null) except a null a non-nullable property refuses.
  T _create<T extends Object>(
    EntityIntrospection<T> introspection,
    List<Object?> values, [
    List<bool>? usable,
  ]) {
    final instance = introspection.create(values);
    for (final (i, described) in introspection.properties.indexed) {
      if (described.parameter ||
          !described.writable ||
          !(usable?[i] ?? true) ||
          (values[i] == null && !described.type.nullable)) {
        continue;
      }
      introspection.write(instance, i, values[i]);
    }
    return instance;
  }
}
