import 'package:spring_boot_starter_data/src/jdbc/jdbc_template.dart';
import 'package:spring_boot_starter_data/src/jdbc/named_parameter_utils.dart';
import 'package:spring_boot_starter_data/src/jdbc/row_mapper.dart';

/// A [JdbcTemplate] with `:name` parameters instead of `?`.
///
/// The parameters are a `Map` of names to values, a [SqlParameterSource],
/// or an introspected bean (its properties by name): every `params`
/// argument takes any of the three. The same name may occur many times in
/// the statement; a list or set value is expanded for `in (:ids)`; an
/// empty list is refused with a clear error, as [NamedParameterUtils]
/// explains. A name without a value is an
/// `InvalidDataAccessApiUsageException`.
///
/// The statement is sent to the database with `?`, and the parsed form is
/// cached. The trace log names each value (`id = 42`), and masks those
/// whose name looks secret.
///
/// Spring (Java): `org.springframework.jdbc.core.namedparam.
/// NamedParameterJdbcTemplate`.
class NamedParameterJdbcTemplate {
  /// A named-parameter template over [jdbc].
  NamedParameterJdbcTemplate(this.jdbc);

  /// The template that runs the statements.
  final JdbcTemplate jdbc;

  static const _cacheLimit = 256;
  final _cache = <String, ParsedSql>{};

  ParsedSql _parse(String sql) {
    final cached = _cache.remove(sql);
    if (cached != null) {
      return _cache[sql] = cached;
    }
    final parsed = NamedParameterUtils.parse(sql);
    if (_cache.length >= _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    return _cache[sql] = parsed;
  }

  SubstitutedSql _prepare(String sql, Object params) =>
      NamedParameterUtils.substitute(
        _parse(sql),
        SqlParameterSource.of(params, introspector: jdbc.introspector),
      );

  (String, BoundParameters) _bound(String sql, Object params) {
    final substituted = _prepare(sql, params);
    return (
      substituted.sql,
      BoundParameters(substituted.values, substituted.names),
    );
  }

  // Errors in the parameters reach the caller through the Future, like
  // every other failure.
  Future<R> _future<R>(
    String sql,
    Object params,
    Future<R> Function(String sql, BoundParameters values) run,
  ) => Future.sync(() {
    final (text, values) = _bound(sql, params);
    return run(text, values);
  });

  /// Runs the query [sql] and maps each row with [mapper].
  Future<List<T>> query<T>(
    String sql,
    Object params,
    RowMapper<T> mapper,
  ) => _future(
    sql,
    params,
    (text, values) => jdbc.query<T>(text, values, mapper),
  );

  /// Runs the query and gives the whole result to [extractor].
  Future<T> queryWithExtractor<T>(
    String sql,
    Object params,
    ResultSetExtractor<T> extractor,
  ) => _future(
    sql,
    params,
    (text, values) => jdbc.queryWithExtractor<T>(text, values, extractor),
  );

  /// The one row of the query (mapped, or its single column as a [T]);
  /// see [JdbcTemplate.queryForObject].
  Future<T> queryForObject<T>(
    String sql,
    Object params, [
    RowMapper<T>? mapper,
  ]) => _future(
    sql,
    params,
    (text, values) => jdbc.queryForObject<T>(text, values, mapper),
  );

  /// The values of the only column of each row; see
  /// [JdbcTemplate.queryForList].
  Future<List<T>> queryForList<T>(
    String sql,
    Object params, [
    RowMapper<T>? mapper,
  ]) => _future(
    sql,
    params,
    (text, values) => jdbc.queryForList<T>(text, values, mapper),
  );

  /// The one row as a map; see [JdbcTemplate.queryForMap].
  Future<Map<String, Object?>> queryForMap(String sql, Object params) =>
      _future(sql, params, (text, values) => jdbc.queryForMap(text, values));

  /// Each row as a map.
  Future<List<Map<String, Object?>>> queryForMaps(String sql, Object params) =>
      _future(sql, params, (text, values) => jdbc.queryForMaps(text, values));

  /// The rows one by one; see [JdbcTemplate.queryForStream].
  Stream<T> queryForStream<T>(
    String sql,
    Object params,
    RowMapper<T> mapper,
  ) async* {
    final (text, values) = _bound(sql, params);
    yield* jdbc.queryForStream<T>(text, values, mapper);
  }

  /// Runs the change [sql] and returns the rows changed.
  Future<int> update(String sql, Object params) =>
      _future(sql, params, (text, values) => jdbc.update(text, values));

  /// Runs the insert and returns the generated key.
  Future<Object?> updateReturningKey(String sql, Object params) => _future(
    sql,
    params,
    (text, values) => jdbc.updateReturningKey(text, values),
  );

  /// Runs the insert, puts the generated key in [holder], returns the rows
  /// changed.
  Future<int> updateWithKeyHolder(
    String sql,
    Object params,
    KeyHolder holder, {
    String? keyColumn,
  }) => _future(
    sql,
    params,
    (text, values) =>
        jdbc.updateWithKeyHolder(text, values, holder, keyColumn: keyColumn),
  );

  /// Runs [sql] once for each of [batch] (each a map, source or bean);
  /// returns the rows changed by each.
  Future<List<int>> batchUpdate(String sql, List<Object> batch) =>
      Future.sync(() {
        if (batch.isEmpty) {
          return const <int>[];
        }
        final prepared = [for (final params in batch) _prepare(sql, params)];
        return jdbc.batchUpdate(prepared.first.sql, [
          for (final item in prepared) BoundParameters(item.values, item.names),
        ]);
      });

  /// Runs [sql] without parameters: DDL.
  Future<void> execute(String sql) => jdbc.execute(sql);

  @override
  String toString() => 'NamedParameterJdbcTemplate($jdbc)';
}
