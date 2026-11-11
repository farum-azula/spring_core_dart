import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/entity_row_mapper.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/row_mapper.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_introspection.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/repository/query/query_method.dart';
import 'package:spring_boot_starter_data/src/repository/query/result_shaper.dart';

/// What one row of a query method's result becomes.
enum QueryResultKind {
  /// The repository's entity: read by the store, with its children.
  entity,

  /// A class of the application, from the columns by name.
  dto,

  /// A simple type or an enum, from the only column.
  scalar,

  /// A `Map` of the columns.
  map,

  /// What the method's own row mapper or extractor returns.
  custom,
}

/// Turns the rows of a repository method that is not derived from its
/// name (a `@Query`, a `@Procedure`) into what the method returns: the same
/// rules for both, so a function's rows are read as a query's are.
///
/// - The **kind** of a row is decided once from the element type of the
///   method ([QueryResultMapper.of]): the repository's entity, a `Map`,
///   a simple type or an enum (one column), else a class of the
///   application, which must be
///   described (a projection the build wrote, or `@Introspected`): a class
///   that is neither is a problem of the repository.
/// - A value goes through the [reader] (the SQL dialect, or the reader of
///   another store) and then the entity converter.
/// - The **shape** ([shaped]) is a `List`, a `Set`, or one value: no row
///   is null for a nullable type and an `EmptyResultDataAccessException`
///   otherwise; several rows are an
///   `IncorrectResultSizeDataAccessException`.
///
/// Rows of the entity kind are read by the store (it loads the children),
/// not here.
///
/// Spring (Java): the `ResultProcessor` and `JdbcQueryExecution` of
/// `org.springframework.data.jdbc.repository.query.AbstractJdbcQuery`.
final class QueryResultMapper {
  QueryResultMapper._({
    required this.where,
    required this.kind,
    required this.element,
    required this.converter,
    required this.introspector,
    required this.reader,
    required this.described,
  }) : shaper = element.capture<ResultShaper>(<E>() => TypedResultShaper<E>());

  /// The mapper of the method [where] (`BookRepository.cards`, for
  /// messages) whose rows become [element] (null for a method without a
  /// result: the rows are then dynamic); [custom] says that the method
  /// maps its rows itself. A class that cannot be built from rows is added
  /// to [problems].
  factory QueryResultMapper.of({
    required String where,
    required TypeInfo<Object?>? element,
    required PersistentEntity<Object> entity,
    required EntityConverter converter,
    required BeanIntrospector introspector,
    required List<String> problems,
    ColumnValueReader? reader,
    RelationalMappingContext? mappingContext,
    bool custom = false,
  }) {
    final described = element == null
        ? null
        : mappingContext?.introspectionOf(element.type);
    var kind = QueryResultKind.custom;
    if (element != null && !custom) {
      kind = _kindOf(element, entity, described, introspector, where, problems);
    }
    return QueryResultMapper._(
      where: where,
      kind: kind,
      element: element ?? const DynamicType(),
      converter: converter,
      introspector: introspector,
      reader: reader,
      described: described,
    );
  }

  /// The method, for messages.
  final String where;

  /// What one row becomes.
  final QueryResultKind kind;

  /// The type of what one row becomes (dynamic for a method without a
  /// result).
  final TypeInfo<Object?> element;

  /// Does the enum, reference and widening conversions.
  final EntityConverter converter;

  /// Describes the `@Introspected` classes.
  final BeanIntrospector introspector;

  /// Converts the values as the store gives them, or null for none.
  final ColumnValueReader? reader;

  /// The description of the class the rows become, when the build wrote
  /// one.
  final EntityIntrospection<Object>? described;

  /// Makes the collections of the result with the element type.
  final ResultShaper shaper;

  static QueryResultKind _kindOf(
    TypeInfo<Object?> element,
    PersistentEntity<Object> entity,
    EntityIntrospection<Object>? described,
    BeanIntrospector introspector,
    String where,
    List<String> problems,
  ) {
    if (element.type == entity.type) {
      return QueryResultKind.entity;
    }
    if (element is MapType<Object?, Object?>) {
      return QueryResultKind.map;
    }
    if (element is EnumType<Enum> ||
        element.capture<bool>(<X>() => isSimpleType<X>())) {
      return QueryResultKind.scalar;
    }
    if (described == null && introspector.forType(element.type) == null) {
      problems.add(
        '$where: ${element.type} cannot be built from rows: it is not '
        'described (register its module, or mark the class @Introspected), '
        'or give a rowMapper',
      );
    }
    return QueryResultKind.dto;
  }

  /// The properties of the class the rows are mapped to (a
  /// [QueryResultKind.dto]); empty for the other kinds.
  late final List<String> dtoProperties = [
    if (described case final described?)
      for (final property in described.properties) property.name
    else if (kind == QueryResultKind.dto)
      if (introspector.forType(element.type) case final bean?)
        for (final property in bean.properties) property.name,
  ];

  /// The only column of [row] as the [element] type: converted as a column
  /// of an entity is (the type's own description, so a nullable type still
  /// converts: SQLite's 0/1 into a bool, a text into a DateTime).
  Object? scalar(JdbcRow row) {
    if (row.columns.length != 1) {
      throw IncorrectResultSetColumnCountException(1, row.columns.length);
    }
    final value = row.values.single;
    if (value == null) {
      if (element.nullable) {
        return null;
      }
      throw InvalidDataAccessApiUsageException(
        '$where: column ${row.columns.single} is null; return a nullable '
        'type ($element?)',
      );
    }
    return converter.fromColumnValue(
      reader?.fromDatabase(value, element) ?? value,
      element,
      where: '$where: column ${row.columns.single}',
    );
  }

  /// The mapper of one row for the kinds read row by row
  /// ([QueryResultKind.scalar], [QueryResultKind.map],
  /// [QueryResultKind.dto]); a [StateError] for the others.
  RowMapper<Object?> rowMapper() => switch (kind) {
    QueryResultKind.scalar => scalar,
    QueryResultKind.map => const ColumnMapRowMapper().call,
    QueryResultKind.dto => _dtoMapper(),
    QueryResultKind.entity || QueryResultKind.custom => throw StateError(
      'no row mapper for $kind',
    ),
  };

  RowMapper<Object?> _dtoMapper() {
    if (described case final described?) {
      return EntityRowMapper<Object>(
        described,
        dialect: reader,
        converter: converter,
      ).call;
    }
    return DataClassRowMapper<Object>(
      dialect: reader,
      converter: converter,
      introspector: introspector,
      introspection: introspector.forType(element.type),
    ).call;
  }

  /// The one result among [rows]: null for none when the type is
  /// nullable, else an `EmptyResultDataAccessException`; several are an
  /// `IncorrectResultSizeDataAccessException`.
  Object? single(List<Object?> rows) {
    if (rows.isEmpty) {
      if (element.nullable) {
        return null;
      }
      throw EmptyResultDataAccessException(
        1,
        message:
            '$where: no result, but the method returns a non-null '
            '$element (return it as nullable to get null)',
      );
    }
    if (rows.length > 1) {
      throw IncorrectResultSizeDataAccessException(
        1,
        rows.length,
        message:
            '$where: ${rows.length} results for a method that returns '
            'one (return a List, or limit the query)',
      );
    }
    return rows.single;
  }

  /// [rows] (each already what one row becomes) as [shape] asks: a `List`
  /// or a `Set` of the element type, else the [single] result.
  Object? shaped(QueryShape shape, List<Object?> rows) => switch (shape) {
    QueryShape.list => shaper.list(rows),
    QueryShape.set => shaper.set(rows),
    _ => single(rows),
  };
}
