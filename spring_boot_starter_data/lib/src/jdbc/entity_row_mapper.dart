import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_introspection.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';

/// Builds an object of a class the build described as an
/// [EntityIntrospection] from each row, with the rules of
/// `DataClassRowMapper`: the columns are matched with the properties by
/// name without case and without underscores (`author_name` fills
/// `authorName`), the constructor takes its parameters from them, and the
/// writable properties it does not take are set after.
///
/// - A parameter that cannot be null, without a column (or with a null) and
///   without a default value, is a [MappingException] naming the class and
///   the columns the row has; any other parameter without a column gets its
///   default value, else null.
/// - A column no property wants is ignored.
/// - A value goes through the dialect's `fromDatabase` (when a [dialect] is
///   given) with the property's `TypeInfo`, then the converter's enum,
///   widening and reference conversions.
///
/// It maps the classes a `@Query` method returns that are not entities (the
/// build describes them as projections), and any described class.
///
/// Spring (Java): `org.springframework.jdbc.core.DataClassRowMapper`.
class EntityRowMapper<T extends Object> {
  /// A mapper of the class [introspection] describes.
  EntityRowMapper(
    this.introspection, {
    this.dialect,
    EntityConverter? converter,
  }) : converter = converter ?? EntityConverter();

  /// The class mapped.
  final EntityIntrospection<T> introspection;

  /// The dialect converting the values read, or null for none.
  final SqlDialect? dialect;

  /// The converter doing the enums and the widening.
  final EntityConverter converter;

  List<String>? _columns;
  List<int?> _propertyColumns = const [];

  static String _normalize(String name) =>
      name.replaceAll('_', '').toLowerCase();

  // Matches the columns of a result with the properties, once per result.
  void _plan(JdbcRow row) {
    if (identical(_columns, row.columns)) {
      return;
    }
    final byName = <String, int>{};
    for (var i = 0; i < row.columns.length; i++) {
      byName.putIfAbsent(_normalize(row.columns[i]), () => i);
    }
    _propertyColumns = [
      for (final property in introspection.properties)
        byName[_normalize(property.name)],
    ];
    _columns = row.columns;
  }

  Object? _read(JdbcRow row, int index, TypeInfo<Object?> type, String where) {
    final raw = row.values[index];
    if (raw == null) {
      return null;
    }
    final read = dialect?.fromDatabase(raw, type) ?? raw;
    return converter.fromColumnValue(read, type, where: where);
  }

  /// The mapper as a function.
  T call(JdbcRow row) {
    _plan(row);
    final className = introspection.className;
    final properties = introspection.properties;
    final values = List<Object?>.filled(properties.length, null);
    final usable = List<bool>.filled(properties.length, false);
    for (final (i, property) in properties.indexed) {
      final index = _propertyColumns[i];
      final where = '$className.${property.name}';
      if (index != null) {
        values[i] = _read(row, index, property.type, where);
        usable[i] = values[i] != null || property.type.nullable;
      }
      if (!usable[i] && property.parameter) {
        if (property.hasDefaultValue) {
          values[i] = _default(property, where);
          usable[i] = true;
        } else if (property.type.nullable) {
          usable[i] = true;
        } else {
          throw MappingException(
            index == null
                ? '$className: the constructor requires ${property.name} '
                      'but the row has no column for it '
                      '(columns: ${row.columns.join(', ')})'
                : '$where is null but the constructor requires a '
                      '${property.type}',
          );
        }
      }
    }
    final instance = introspection.create(values);
    for (final (i, property) in properties.indexed) {
      if (property.writable &&
          !property.parameter &&
          _propertyColumns[i] != null &&
          usable[i]) {
        introspection.write(instance, i, values[i]);
      }
    }
    return instance;
  }

  // A default of the description as the property holds it (the `0` of a
  // `double` widened).
  Object? _default(EntityProperty property, String where) {
    final value = property.defaultValue;
    return value == null
        ? null
        : converter.fromColumnValue(
            value,
            property.type,
            where: '$where (default)',
          );
  }
}
