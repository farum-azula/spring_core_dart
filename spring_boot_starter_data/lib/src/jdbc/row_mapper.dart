import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';

/// Turns one row of a result into an object.
///
/// Spring (Java): `org.springframework.jdbc.core.RowMapper`.
typedef RowMapper<T> = T Function(JdbcRow row);

/// Turns a whole result into one object: for what a row mapper cannot
/// do, such as joining the rows of a one-to-many query into one parent
/// with its children.
///
/// Spring (Java): `org.springframework.jdbc.core.ResultSetExtractor`.
typedef ResultSetExtractor<T> = T Function(JdbcResult result);

/// A query of one column was given a result of another number of columns.
///
/// Spring (Java): `org.springframework.jdbc.IncorrectResultSetColumnCount
/// Exception`.
class IncorrectResultSetColumnCountException
    extends NonTransientDataAccessException {
  /// A result of [actual] columns where [expected] were needed.
  IncorrectResultSetColumnCountException(
    this.expected,
    this.actual, {
    super.sql,
  }) : super('Incorrect column count: expected $expected, actual $actual');

  /// The columns needed.
  final int expected;

  /// The columns the result has.
  final int actual;
}

/// The key a database gave an inserted row, as the `update` methods fill
/// it.
///
/// Spring (Java): `org.springframework.jdbc.support.KeyHolder`.
final class KeyHolder {
  /// The generated key, or null before an update that gave one.
  Object? key;

  /// The key as a [T]; throws an [InvalidDataAccessApiUsageException] when
  /// there is none or it is not a [T].
  T keyAs<T>() {
    final value = key;
    if (value is T) {
      return value;
    }
    throw InvalidDataAccessApiUsageException(
      value == null
          ? 'The statement generated no key'
          : 'The generated key ${value.runtimeType} is not a $T',
    );
  }

  @override
  String toString() => 'KeyHolder($key)';
}

/// Typed reads of a row's columns, for hand-written [RowMapper]s.
///
/// The values are read as the database gave them with the usual widening
/// (`int` to `double`, 0/1 to `bool`, an ISO-8601 text to `DateTime`); a
/// null where a non-null type is asked fails with an
/// [InvalidDataAccessApiUsageException]: use the `OrNull` form. A mapper
/// that wants the dialect's full conversions uses [DataClassRowMapper].
extension JdbcRowReaders on JdbcRow {
  /// The column [column] as a `String`.
  String string(String column) => _need(column, stringOrNull(column));

  /// The column [column] as a `String`, or null.
  String? stringOrNull(String column) => this[column]?.toString();

  /// The column [column] as an `int`.
  int int_(String column) => _need(column, intOrNull(column));

  /// The column [column] as an `int`, or null.
  int? intOrNull(String column) => switch (this[column]) {
    null => null,
    final int v => v,
    final double v when v == v.truncateToDouble() => v.toInt(),
    final BigInt v => v.toInt(),
    final bool v => v ? 1 : 0,
    final String v => int.tryParse(v) ?? _bad(column, 'int'),
    _ => _bad(column, 'int'),
  };

  /// The column [column] as a `double`.
  double double_(String column) => _need(column, doubleOrNull(column));

  /// The column [column] as a `double`, or null.
  double? doubleOrNull(String column) => switch (this[column]) {
    null => null,
    final num v => v.toDouble(),
    final String v => double.tryParse(v) ?? _bad(column, 'double'),
    _ => _bad(column, 'double'),
  };

  /// The column [column] as a `bool` (0 is false).
  bool bool_(String column) => _need(column, boolOrNull(column));

  /// The column [column] as a `bool`, or null.
  bool? boolOrNull(String column) => switch (this[column]) {
    null => null,
    final bool v => v,
    final num v => v != 0,
    _ => _bad(column, 'bool'),
  };

  /// The column [column] as a `DateTime`.
  DateTime dateTime(String column) => _need(column, dateTimeOrNull(column));

  /// The column [column] as a `DateTime`, or null.
  DateTime? dateTimeOrNull(String column) => switch (this[column]) {
    null => null,
    final DateTime v => v,
    final String v => DateTime.tryParse(v) ?? _bad(column, 'DateTime'),
    final int v => DateTime.fromMillisecondsSinceEpoch(v, isUtc: true),
    _ => _bad(column, 'DateTime'),
  };

  /// The column [column] as bytes, or null.
  Uint8List? bytesOrNull(String column) => switch (this[column]) {
    null => null,
    final Uint8List v => v,
    final List<int> v => Uint8List.fromList(v),
    _ => _bad(column, 'Uint8List'),
  };

  T _need<T>(String column, T? value) =>
      value ??
      (throw InvalidDataAccessApiUsageException(
        'Column $column is null; read it with its OrNull form',
      ));

  Never _bad(String column, String type) =>
      throw InvalidDataAccessApiUsageException(
        'Column $column holds a ${this[column].runtimeType}, not a $type',
      );
}

/// Whether the values of type [T] are read from one column (numbers,
/// text, dates, bytes, enums) rather than built from several.
bool isSimpleType<T>() =>
    <T>[] is List<num?> ||
    <T>[] is List<String?> ||
    <T>[] is List<bool?> ||
    <T>[] is List<DateTime?> ||
    <T>[] is List<BigInt?> ||
    <T>[] is List<Uint8List?> ||
    <T>[] is List<Enum?>;

/// Reads the only column of each row as a [T]: the dialect's
/// `fromDatabase` and the converter's widening and enum conversions apply.
///
/// A result of another number of columns is an
/// [IncorrectResultSetColumnCountException]; a null where [T] is not
/// nullable, an [InvalidDataAccessApiUsageException] (ask for `int?`).
///
/// Spring (Java): `org.springframework.jdbc.core.SingleColumnRowMapper`.
class SingleColumnRowMapper<T> {
  /// A mapper reading [T]; [dialect] (when given) converts the values
  /// first.
  SingleColumnRowMapper({this.dialect, EntityConverter? converter})
    : converter = converter ?? EntityConverter();

  /// The dialect converting the values read, or null for none.
  final SqlDialect? dialect;

  /// The converter doing the widening and the enums.
  final EntityConverter converter;

  /// The mapper as a function.
  T call(JdbcRow row) {
    if (row.columns.length != 1) {
      throw IncorrectResultSetColumnCountException(1, row.columns.length);
    }
    final value = row.values.single;
    final type = ClassType<T>(nullable: null is T);
    if (value == null) {
      if (null is T) {
        return null as T;
      }
      throw InvalidDataAccessApiUsageException(
        'Column ${row.columns.single} is null; ask for a nullable type '
        '($T?)',
      );
    }
    final read = dialect?.fromDatabase(value, type) ?? value;
    final converted = converter.fromColumnValue(
      read,
      type,
      where: 'column ${row.columns.single}',
    );
    return converted as T;
  }
}

/// Reads each row as a map from column label to value.
///
/// Spring (Java): `org.springframework.jdbc.core.ColumnMapRowMapper`.
class ColumnMapRowMapper {
  /// A mapper of rows to maps.
  const ColumnMapRowMapper();

  /// The mapper as a function.
  Map<String, Object?> call(JdbcRow row) => row.toMap();
}

/// Builds an object of an introspected class from each row, as Spring's
/// `DataClassRowMapper` does: through its constructor's parameters, the
/// columns matched by name without case and without underscores
/// (`author_name` fills `authorName`), then the settable properties not
/// set by the constructor.
///
/// - A required constructor parameter without a column, or with a null a
///   non-nullable type cannot take, is a [MappingException] naming the
///   class and the columns the row has; an optional parameter is left to
///   its default.
/// - A column no property wants is ignored.
/// - A value goes through the dialect's `fromDatabase` (when a [dialect] is
///   given) with the parameter's `TypeInfo`, then the converter's enum,
///   widening and reference conversions.
///
/// The class must be introspected (`@Introspected`). An entity, or a class
/// a `@Query` returns, is described by the build as an `EntityIntrospection`
/// instead, which `EntityRowMapper` maps.
///
/// Spring (Java): `org.springframework.jdbc.core.DataClassRowMapper`.
class DataClassRowMapper<T extends Object> {
  /// A mapper of [T]. [introspection] describes it; without it, the
  /// [introspector] (default `BeanIntrospector.shared`) is asked on first
  /// use.
  DataClassRowMapper({
    this.dialect,
    EntityConverter? converter,
    BeanIntrospector? introspector,
    BeanIntrospection<T>? introspection,
  }) : _introspector = introspector ?? BeanIntrospector.shared,
       converter = converter ?? EntityConverter(introspector: introspector),
       // The field is private; the parameter is public.
       // ignore: prefer_initializing_formals
       _introspection = introspection;

  /// The dialect converting the values read, or null for none.
  final SqlDialect? dialect;

  /// The converter doing the enums and the widening.
  final EntityConverter converter;

  final BeanIntrospector _introspector;
  BeanIntrospection<T>? _introspection;

  List<String>? _columns;
  List<int?> _parameterColumns = const [];
  List<(BeanProperty<T>, int)> _propertyColumns = [];

  static String _normalize(String name) =>
      name.replaceAll('_', '').toLowerCase();

  BeanIntrospection<T> get _description => _introspection ??=
      ((_introspector.forTypeArgument<T>() as BeanIntrospection<T>?) ??
            (throw InvalidDataAccessApiUsageException(
              '$T is not introspected: mark it @Introspected and '
              'register its module, or use a RowMapper function',
            )))
        ..requirePart(IntrospectionPart.write, 'rows are mapped to it');

  // Matches the columns of a result with the parameters and properties,
  // once per result.
  void _plan(JdbcRow row) {
    if (identical(_columns, row.columns)) {
      return;
    }
    final description = _description;
    final byName = <String, int>{};
    for (var i = 0; i < row.columns.length; i++) {
      byName.putIfAbsent(_normalize(row.columns[i]), () => i);
    }
    final parameters =
        description.constructor?.parameters ?? const <BeanParameter>[];
    _parameterColumns = [
      for (final parameter in parameters) byName[_normalize(parameter.name)],
    ];
    final constructed = {for (final parameter in parameters) parameter.name};
    _propertyColumns = [];
    for (final property in description.properties) {
      final index = byName[_normalize(property.name)];
      if (index != null &&
          property.isWritable &&
          !constructed.contains(property.name)) {
        _propertyColumns.add((property, index));
      }
    }
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
    final description = _description;
    final className = description.className;
    final constructor = description.constructor;
    final T instance;
    final used = <String>{};
    if (constructor != null) {
      final positional = <Object?>[];
      final named = <Symbol, Object?>{};
      const missing = Object();
      for (final (i, parameter) in constructor.parameters.indexed) {
        final index = _parameterColumns[i];
        final where = '$className.${parameter.name}';
        Object? value;
        var usable = false;
        if (index != null) {
          value = _read(row, index, parameter.type, where);
          usable = value != null || parameter.type.nullable;
        }
        if (!usable && parameter.isRequired) {
          throw MappingException(
            index == null
                ? '$className: the constructor requires ${parameter.name} '
                      'but the row has no column for it '
                      '(columns: ${row.columns.join(', ')})'
                : '$where is null but the constructor requires a '
                      '${parameter.type}',
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
          positional.add(usable ? value : missing);
        }
      }
      while (positional.isNotEmpty && identical(positional.last, missing)) {
        positional.removeLast();
      }
      instance = constructor.newInstance([
        for (final v in positional)
          if (identical(v, missing)) null else v,
      ], named);
    } else if (description.isInstantiable) {
      instance = description.instantiate();
    } else {
      throw MappingException(
        '$className has neither a constructor nor a no-argument '
        'constructor in its description',
      );
    }
    for (final (property, index) in _propertyColumns) {
      if (used.contains(property.name)) {
        continue;
      }
      final type =
          property.typeInfo ?? const ClassType<Object?>(nullable: true);
      final value = _read(row, index, type, '$className.${property.name}');
      if (value == null && !property.nullable) {
        continue;
      }
      property.setValue(instance, value);
    }
    return instance;
  }
}
