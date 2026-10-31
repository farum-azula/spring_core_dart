import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/annotations.dart';
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
/// epoch milliseconds) to a `DateTime`, a `List<int>` to `Uint8List`.
///
/// An instance is created through the class's constructor: each parameter
/// takes the column of the property of the same name (a missing optional
/// parameter is left out, so its default applies; a missing required one is
/// a [MappingException]); the other writable properties are set after.
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
  /// `BeanIntrospector.shared`) when a property's description does not
  /// carry them.
  EntityConverter({BeanIntrospector? introspector})
    : introspector = introspector ?? BeanIntrospector.shared;

  /// Where enums not described by their property are looked up.
  final BeanIntrospector introspector;

  // ---------------------------------------------------------------- write

  /// The row of [instance]: every column of [entity] (so the id and
  /// version too, and nulls included) with its value as [toColumnValue]
  /// gives it.
  Map<String, Object?> write(
    PersistentEntity<Object> entity,
    Object instance,
  ) => {
    for (final p in entity.columns)
      p.columnName: toColumnValue(p.getValue(instance)),
  };

  /// [value] as a column holds it: an `AggregateReference` as its id, an
  /// enum as its `name`, anything else unchanged.
  Object? toColumnValue(Object? value) => switch (value) {
    final AggregateReference<Object?, Object?> ref => toColumnValue(ref.id),
    final Enum e => e.name,
    _ => value,
  };

  // ----------------------------------------------------------------- read

  /// Creates the entity of [entity]'s class from [row] (keyed by column
  /// name); [children] holds the ready-made values of the
  /// [MappedCollection] properties, by property name (a `List`, `Set` or
  /// `Map`, of the right element types or not: it is converted). A
  /// non-null mapped collection absent from [children] is empty.
  ///
  /// A column missing from [row], or null for a property that cannot be
  /// null, leaves the property to the constructor's default (a null a
  /// required parameter cannot take is refused). An unconvertible value, or
  /// a required constructor parameter without a column, is a
  /// [MappingException].
  T read<T extends Object>(
    PersistentEntity<T> entity,
    Map<String, Object?> row, {
    Map<String, Object?> children = const {},
  }) {
    final values = <String, Object?>{};
    final settable = <String>{};
    for (final p in entity.properties) {
      settable.add(p.name);
      if (p.isMappedCollection) {
        if (children.containsKey(p.name)) {
          values[p.name] = _collection(entity, p, children[p.name]);
        } else if (!p.isNullable) {
          values[p.name] = _collection(
            entity,
            p,
            p.type is MapType<Object?, Object?>
                ? const <Object?, Object?>{}
                : const <Object?>[],
          );
        }
      } else if (row.containsKey(p.columnName)) {
        final value = row[p.columnName];
        // A null for a property that cannot be null is left to the
        // constructor: its default applies, or (required) it is refused.
        values[p.name] = value == null
            ? null
            : fromColumnValue(value, p.type, where: _where(entity, p));
      }
    }
    return _create(entity, values, settable);
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
    switch (type) {
      case final ListType<Object?> list when value is Iterable<Object?>:
        return list.create(value);
      case final SetType<Object?> set when value is Iterable<Object?>:
        return set.create(value);
      case final MapType<Object?, Object?> map
          when value is Map<Object?, Object?>:
        return map.create(value.entries);
      case _:
        throw MappingException(
          '$where: cannot use a ${value.runtimeType} as $type',
        );
    }
  }

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
  /// one too) carried over.
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
    if (changes.keys.every((n) => properties[n]!.accessor.isWritable)) {
      for (final MapEntry(:key, :value) in converted.entries) {
        properties[key]!.setValue(instance, value);
      }
      return instance;
    }
    final values = <String, Object?>{};
    final settable = <String>{};
    for (final bean in entity.introspection.properties) {
      values[bean.name] = bean.getValue(instance);
      if (bean.isWritable) {
        settable.add(bean.name);
      }
    }
    values.addAll(converted);
    return _create(entity, values, settable);
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
    if (!property.accessor.isWritable) {
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

  static const _missing = Object();

  /// Creates the instance: the constructor's parameters from [values] (by
  /// property name), then the properties of [settable] still unused.
  T _create<T extends Object>(
    PersistentEntity<T> entity,
    Map<String, Object?> values,
    Set<String> settable,
  ) {
    final introspection = entity.introspection;
    final className = introspection.className;
    final used = <String>{};
    final T instance;
    final constructor = introspection.constructor;
    if (constructor != null) {
      final positional = <Object?>[];
      final named = <Symbol, Object?>{};
      for (final parameter in constructor.parameters) {
        final has = values.containsKey(parameter.name);
        final value = values[parameter.name];
        final usable = has && (value != null || parameter.type.nullable);
        if (!usable && parameter.isRequired) {
          throw MappingException(
            has
                ? '$className.${parameter.name} is null but the '
                      'constructor requires a ${parameter.type}'
                : '$className: the constructor requires '
                      '${parameter.name} but there is no column for it '
                      '(a @Transient property, or a missing column)',
          );
        }
        if (usable) {
          used.add(parameter.name);
        }
        if (parameter.symbol case final symbol?) {
          if (usable) {
            named[symbol] = value;
          }
        } else {
          positional.add(usable ? value : _missing);
        }
      }
      while (positional.isNotEmpty && identical(positional.last, _missing)) {
        positional.removeLast();
      }
      instance = constructor.newInstance([
        for (final v in positional)
          if (identical(v, _missing)) null else v,
      ], named);
    } else if (introspection.isInstantiable) {
      instance = introspection.instantiate();
    } else {
      throw MappingException(
        '$className has neither a constructor nor a no-argument '
        'constructor in its description',
      );
    }
    for (final bean in introspection.properties) {
      if (used.contains(bean.name) ||
          !settable.contains(bean.name) ||
          !values.containsKey(bean.name) ||
          !bean.isWritable ||
          (values[bean.name] == null && !bean.nullable)) {
        continue;
      }
      bean.setValue(instance, values[bean.name]);
    }
    return instance;
  }
}
