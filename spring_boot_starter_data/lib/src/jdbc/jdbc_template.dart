import 'dart:async';
import 'dart:collection';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source_utils.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/row_mapper.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_logging.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';

/// Work on a connection, for [JdbcTemplate.executeWithConnection].
///
/// Spring (Java): `org.springframework.jdbc.core.ConnectionCallback`.
typedef ConnectionCallback<T> = Future<T> Function(JdbcConnection connection);

/// Positional parameters that also know their names, so the trace log can
/// say `:id = 42` instead of `?1 = 42`, and mask the value of a `password`.
/// The named-parameter template and the repositories' statements pass them
/// (the name of a repository's value is its column); applications use a
/// plain list, whose values have no name (and are masked when they are
/// logged at info).
final class BoundParameters extends UnmodifiableListView<Object?> {
  /// The values with the [names] they were bound under.
  BoundParameters(super.source, this.names);

  /// The name of each value.
  final List<String> names;
}

/// Runs SQL with `?` parameters through the connection of the current
/// transaction, or a pooled one when there is none, and maps the results.
///
/// - Every method returns a `Future`; values are always sent as
///   parameters, never written into the SQL (a parameter list given where
///   one `?` stands is not expanded: use `NamedParameterJdbcTemplate` for
///   `in (:ids)`).
/// - Values go through the entity converter (an enum as its name, an
///   `AggregateReference` as its id) and the dialect's `toDatabase`;
///   scalar and data-class reads go through the dialect's `fromDatabase`.
/// - A [SqlError] of the driver becomes the dialect's `DataAccessException`
///   (`DuplicateKeyException`, `BadSqlGrammarException`...) carrying the
///   SQL with its `?`, never the values. Errors of your mappers pass as
///   they are.
/// - Inside `@Transactional` / `TransactionTemplate` of a
///   `DataSourceTransactionManager` on the same [DataSource], the
///   transaction's connection is used, across `await`s; the transaction's
///   remaining time bounds each statement. Outside, each call takes a
///   connection from the pool and gives it back.
/// - Logs: the SQL, time and rows at debug (`spring.jdbc.core.JdbcTemplate`),
///   the values at trace (`spring.jdbc.core.StatementCreatorUtils`), slow
///   statements at warn; see [StatementLogger].
///
/// Spring (Java): `org.springframework.jdbc.core.JdbcTemplate`.
class JdbcTemplate {
  /// A template over [dataSource]. [queryTimeout] bounds each statement;
  /// [logSettings] are the `spring.data.jdbc.*` switches; [introspector]
  /// finds the classes of data-class mapping (default
  /// `BeanIntrospector.shared`).
  JdbcTemplate(
    this.dataSource, {
    this.queryTimeout,
    this.logSettings = const JdbcLogSettings(),
    BeanIntrospector? introspector,
  }) : introspector = introspector ?? BeanIntrospector.shared,
       converter = EntityConverter(introspector: introspector),
       _logger = StatementLogger(dataSource, logSettings);

  /// The data source whose connections are used.
  final DataSource dataSource;

  /// The longest a statement may run (null: no limit); within a
  /// transaction the shorter of this and the transaction's time left.
  final Duration? queryTimeout;

  /// The logging switches.
  final JdbcLogSettings logSettings;

  /// The introspector for [dataClassRowMapper].
  final BeanIntrospector introspector;

  /// Converts the values bound and read.
  final EntityConverter converter;

  final StatementLogger _logger;

  /// The SQL of the database.
  SqlDialect get dialect => dataSource.dialect;

  Object? _toDatabase(Object? value) =>
      dialect.toDatabase(converter.toColumnValue(value));

  List<Object?> _bind(List<Object?> params) => [
    for (final value in params) _toDatabase(value),
  ];

  /// The mapper reading the only column of each row as a [T].
  RowMapper<T> singleColumnRowMapper<T>() =>
      SingleColumnRowMapper<T>(dialect: dialect, converter: converter).call;

  /// The mapper building a [T] from each row; [T] must be introspected.
  RowMapper<T> dataClassRowMapper<T extends Object>() => DataClassRowMapper<T>(
    dialect: dialect,
    converter: converter,
    introspector: introspector,
  ).call;

  static bool _acceptsAnything<T>() => <Object?>[] is List<T>;

  /// The mapper a [T] asks for: a column for a simple type (`int`,
  /// `String`, `DateTime`, an enum...), a map for `Map<String, Object?>`
  /// or `Object?`, else the data-class mapper of the introspected class.
  RowMapper<T> rowMapperFor<T>() {
    if (isSimpleType<T>()) {
      return singleColumnRowMapper<T>();
    }
    if (_acceptsAnything<T>() || <T>[] is List<Map<String, Object?>?>) {
      return (row) => row.toMap() as T;
    }
    final introspection = introspector.forTypeArgument<T>();
    if (introspection == null) {
      throw InvalidDataAccessApiUsageException(
        '$T is not introspected: mark it @Introspected, or '
        'pass a RowMapper',
      );
    }
    final mapper = DataClassRowMapper<Object>(
      dialect: dialect,
      converter: converter,
      introspector: introspector,
      introspection: introspection,
    );
    return (row) => mapper(row) as T;
  }

  // ----------------------------------------------------------- the core

  Future<R> _run<R>(
    String sql,
    List<Object?> params,
    Future<(R, int?)> Function(JdbcConnection connection, List<Object?> bound)
    body, {
    List<List<Object?>>? batch,
  }) async {
    final bound = _bind(params);
    final connection = await DataSourceUtils.getConnection(dataSource);
    final watch = Stopwatch()..start();
    try {
      await DataSourceUtils.prepare(
        connection,
        dataSource,
        queryTimeout: queryTimeout,
      );
      _logValues(params, batch);
      final (result, rows) = await body(connection, bound);
      _logger.executed(sql, watch.elapsed, rows: rows);
      return result;
    } on SqlError catch (error) {
      _logger.failed(sql, watch.elapsed, error);
      throw dialect.translate(error, sql: sql);
    } finally {
      await DataSourceUtils.releaseConnection(connection, dataSource);
    }
  }

  void _logValues(List<Object?> params, List<List<Object?>>? batch) {
    if (batch != null) {
      for (final row in batch) {
        _logger.parameters(row, row is BoundParameters ? row.names : null);
      }
    } else {
      _logger.parameters(
        params,
        params is BoundParameters ? params.names : null,
      );
    }
  }

  // ------------------------------------------------------------- queries

  /// Runs the query [sql] with [params] (each `?` in order) and maps each
  /// row with [mapper].
  Future<List<T>> query<T>(
    String sql,
    List<Object?> params,
    RowMapper<T> mapper,
  ) => _run(sql, params, (connection, bound) async {
    final result = await connection.query(sql, bound);
    return ([for (final row in result.rows) mapper(row)], result.rows.length);
  });

  /// Runs the query [sql] and gives the whole result to [extractor]
  /// (one-to-many: group the rows of a join into parents with children).
  Future<T> queryWithExtractor<T>(
    String sql,
    List<Object?> params,
    ResultSetExtractor<T> extractor,
  ) => _run(sql, params, (connection, bound) async {
    final result = await connection.query(sql, bound);
    return (extractor(result), result.rows.length);
  });

  /// The one row of the query, mapped with [mapper], or, without a mapper,
  /// its one column as a [T] (`queryForObject<int>('select count(*) ...')`).
  ///
  /// No row: an [EmptyResultDataAccessException]; more than one: an
  /// [IncorrectResultSizeDataAccessException]; a scalar read of a result
  /// with other than one column: an [IncorrectResultSetColumnCountException].
  Future<T> queryForObject<T>(
    String sql, [
    List<Object?> params = const [],
    RowMapper<T>? mapper,
  ]) async {
    final rows = await query<T>(
      sql,
      params,
      mapper ?? singleColumnRowMapper<T>(),
    );
    // The lint takes T for a Future; it is a plain value.
    // ignore: async_return_with_no_await
    return requiredSingleResult(rows, sql: sql);
  }

  /// The values of the only column of each row, as [T]s (or each row
  /// mapped with [mapper]).
  Future<List<T>> queryForList<T>(
    String sql, [
    List<Object?> params = const [],
    RowMapper<T>? mapper,
  ]) => query<T>(sql, params, mapper ?? singleColumnRowMapper<T>());

  /// The one row of the query as a map of column to value; sizes as
  /// [queryForObject].
  Future<Map<String, Object?>> queryForMap(
    String sql, [
    List<Object?> params = const [],
  ]) => queryForObject<Map<String, Object?>>(
    sql,
    params,
    const ColumnMapRowMapper().call,
  );

  /// Each row of the query as a map of column to value.
  Future<List<Map<String, Object?>>> queryForMaps(
    String sql, [
    List<Object?> params = const [],
  ]) => query<Map<String, Object?>>(
    sql,
    params,
    const ColumnMapRowMapper().call,
  );

  /// The rows of the query one by one, mapped with [mapper], without
  /// holding them all in memory.
  ///
  /// The query starts when the stream is listened to and its connection is
  /// held until the stream ends, fails or is cancelled (inside a
  /// transaction, the transaction's connection is used). A connection runs
  /// one statement at a time: do not start another statement of the same
  /// transaction inside the loop that reads the stream; collect the keys
  /// first, or use another connection.
  Stream<T> queryForStream<T>(
    String sql,
    List<Object?> params,
    RowMapper<T> mapper,
  ) async* {
    final bound = _bind(params);
    final connection = await DataSourceUtils.getConnection(dataSource);
    final watch = Stopwatch()..start();
    var rows = 0;
    try {
      await DataSourceUtils.prepare(
        connection,
        dataSource,
        queryTimeout: queryTimeout,
      );
      _logValues(params, null);
      await for (final row in connection.queryStream(sql, bound)) {
        rows++;
        yield mapper(row);
      }
      _logger.executed(sql, watch.elapsed, rows: rows);
    } on SqlError catch (error) {
      _logger.failed(sql, watch.elapsed, error);
      throw dialect.translate(error, sql: sql);
    } finally {
      await DataSourceUtils.releaseConnection(connection, dataSource);
    }
  }

  // ------------------------------------------------------------- changes

  /// Runs the change [sql] (insert, update, delete) and returns the rows
  /// changed.
  Future<int> update(String sql, [List<Object?> params = const []]) =>
      _run(sql, params, (connection, bound) async {
        final update = await connection.update(sql, bound);
        return (update.affectedRows, update.affectedRows);
      });

  /// Runs the insert [sql] and returns the key the database generated
  /// (null when it gave none).
  Future<Object?> updateReturningKey(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final holder = KeyHolder();
    await updateWithKeyHolder(sql, params, holder);
    return holder.key;
  }

  /// Runs the insert [sql], puts the generated key in [holder] and returns
  /// the rows changed. [keyColumn] names the column that holds the key, for
  /// a database that returns a column (PostgreSQL); without it the first
  /// column of the inserted row is the key.
  Future<int> updateWithKeyHolder(
    String sql,
    List<Object?> params,
    KeyHolder holder, {
    String? keyColumn,
  }) => _run(sql, params, (connection, bound) async {
    final update = await connection.update(sql, bound, true, keyColumn);
    holder.key = update.generatedKey;
    return (update.affectedRows, update.affectedRows);
  });

  /// Runs [sql] once for each list of [batch]; returns the rows changed by
  /// each.
  Future<List<int>> batchUpdate(String sql, List<List<Object?>> batch) {
    final bound = [for (final params in batch) _bind(params)];
    return _run(
      sql,
      const [],
      (connection, _) async {
        final counts = await connection.batchUpdate(sql, bound);
        return (counts, counts.fold<int>(0, (sum, n) => sum + n));
      },
      batch: batch,
    );
  }

  /// Runs [sql] without parameters and results: DDL, `PRAGMA`.
  Future<void> execute(String sql) => _run<void>(sql, const [], (
    connection,
    _,
  ) async {
    await connection.execute(sql);
    return (null, null);
  });

  /// Runs [action] with the connection (the transaction's, or a pooled
  /// one given back after); a [SqlError] becomes a `DataAccessException`.
  /// Nothing is logged: it is for what the template does not cover.
  Future<T> executeWithConnection<T>(ConnectionCallback<T> action) async {
    final connection = await DataSourceUtils.getConnection(dataSource);
    try {
      return await action(connection);
    } on SqlError catch (error) {
      throw dialect.translate(error);
    } finally {
      await DataSourceUtils.releaseConnection(connection, dataSource);
    }
  }

  /// [rows] as the one result: throws an [EmptyResultDataAccessException]
  /// for none and an [IncorrectResultSizeDataAccessException] for more than
  /// one.
  static T requiredSingleResult<T>(List<T> rows, {String? sql}) {
    if (rows.isEmpty) {
      throw EmptyResultDataAccessException(1, sql: sql);
    }
    if (rows.length > 1) {
      throw IncorrectResultSizeDataAccessException(1, rows.length, sql: sql);
    }
    return rows.single;
  }

  @override
  String toString() => 'JdbcTemplate(${dataSource.name})';
}
