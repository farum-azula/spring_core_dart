import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_template.dart';
import 'package:spring_boot_starter_data/src/jdbc/named_parameter_jdbc_template.dart';
import 'package:spring_boot_starter_data/src/jdbc/named_parameter_utils.dart';
import 'package:spring_boot_starter_data/src/jdbc/row_mapper.dart';

/// The fluent API of Spring 6.1 over [JdbcTemplate] and
/// [NamedParameterJdbcTemplate]:
///
/// ```dart
/// final book = await client
///     .sql('select * from books where id = :id')
///     .param('id', 42)
///     .query<Book>()
///     .optional();
/// final count = await client
///     .sql('select count(*) from books where year > ?')
///     .param(2000)
///     .query<int>()
///     .single();
/// await client.sql('delete from books where id = :id')
///     .param('id', 1)
///     .update();
/// ```
///
/// Parameters are either named (`:name`, set with `param(name, value)`,
/// `params(map)` or `paramSource(bean)`) or positional (`?`, `param(value)`
/// or `params(list)`); one statement does not mix them. Everything the
/// templates do (transactions, error translation, logs) applies.
///
/// Spring (Java): `org.springframework.jdbc.core.simple.JdbcClient`.
class JdbcClient {
  /// A client over a new template on [dataSource].
  JdbcClient(DataSource dataSource)
    : this.fromTemplate(JdbcTemplate(dataSource));

  /// A client over [template].
  JdbcClient.fromTemplate(this.template)
    : named = NamedParameterJdbcTemplate(template);

  /// The template that runs the statements.
  final JdbcTemplate template;

  /// The named-parameter template over it.
  final NamedParameterJdbcTemplate named;

  /// Starts a statement with the SQL [sql].
  StatementSpec sql(String sql) => StatementSpec._(this, sql);
}

const _absent = Object();

/// A statement being described: its parameters, then how it runs.
///
/// Spring (Java): `JdbcClient.StatementSpec`.
class StatementSpec {
  StatementSpec._(this._client, this._sql);

  final JdbcClient _client;
  final String _sql;
  final _positional = <Object?>[];
  final _namedValues = <String, Object?>{};
  final _sources = <SqlParameterSource>[];

  /// Adds a parameter: with one argument, the next `?`; with a name and a
  /// value, `:name`. (A null [value] with a name is a null parameter.)
  StatementSpec param(Object? nameOrValue, [Object? value = _absent]) {
    if (identical(value, _absent)) {
      _positional.add(nameOrValue);
    } else if (nameOrValue is String) {
      _namedValues[nameOrValue] = value;
    } else {
      throw ArgumentError.value(
        nameOrValue,
        'name',
        'A parameter name is a String; for a positional parameter pass '
            'the value alone',
      );
    }
    return this;
  }

  /// Adds many parameters: a `List` is positional (each its `?`), a `Map`
  /// named.
  StatementSpec params(Object params) {
    switch (params) {
      case final List<Object?> list:
        _positional.addAll(list);
      case final Map<Object?, Object?> map:
        map.forEach((k, v) => _namedValues['$k'] = v);
      default:
        throw ArgumentError.value(
          params,
          'params',
          'Expected a List (positional) or a Map (named); for a bean use '
              'paramSource',
        );
    }
    return this;
  }

  /// Adds a source of named values: a [SqlParameterSource] or an
  /// introspected bean (`:title` reads `book.title`). Names set with
  /// [param] win over it.
  StatementSpec paramSource(Object source) {
    _sources.add(
      SqlParameterSource.of(
        source,
        introspector: _client.template.introspector,
      ),
    );
    return this;
  }

  bool get _isNamed =>
      _namedValues.isNotEmpty || _sources.isNotEmpty || _positional.isEmpty;

  (String, List<Object?>) _prepare() {
    if (_positional.isNotEmpty &&
        (_namedValues.isNotEmpty || _sources.isNotEmpty)) {
      throw InvalidDataAccessApiUsageException(
        'The statement has positional and named parameters; use one kind',
        sql: _sql,
      );
    }
    if (!_isNamed) {
      return (_sql, _positional);
    }
    final parsed = NamedParameterUtils.parse(_sql);
    if (parsed.names.isEmpty && parsed.unnamedCount > 0) {
      return (_sql, const []);
    }
    final source = _CombinedSource(_namedValues, _sources);
    final substituted = NamedParameterUtils.substitute(parsed, source);
    return (
      substituted.sql,
      BoundParameters(substituted.values, substituted.names),
    );
  }

  /// A query mapping each row with [mapper], or, without one, by the type
  /// [T]: the only column for a simple type (`int`, `String`, an enum...),
  /// a map for `Map<String, Object?>` (or no type), a data-class mapping for
  /// an introspected class (`author_name` fills `authorName`).
  ResultQuerySpec<T> query<T>([RowMapper<T>? mapper]) =>
      ResultQuerySpec<T>._(this, mapper ?? _client.template.rowMapperFor<T>());

  /// Runs the change and returns the rows changed.
  Future<int> update([KeyHolder? keyHolder]) => Future.sync(() {
    final (text, values) = _prepare();
    return keyHolder == null
        ? _client.template.update(text, values)
        : _client.template.updateWithKeyHolder(text, values, keyHolder);
  });
}

/// A query with its row mapping, ready to run.
///
/// Spring (Java): `JdbcClient.MappedQuerySpec`.
class ResultQuerySpec<T> {
  ResultQuerySpec._(this._statement, this._mapper);

  final StatementSpec _statement;
  final RowMapper<T> _mapper;

  /// All rows.
  Future<List<T>> list() => Future.sync(() {
    final (text, values) = _statement._prepare();
    return _statement._client.template.query<T>(text, values, _mapper);
  });

  /// All rows as a set.
  Future<Set<T>> set() async => (await list()).toSet();

  /// The one row; none: an [EmptyResultDataAccessException], more: an
  /// [IncorrectResultSizeDataAccessException].
  Future<T> single() async {
    final rows = await list();
    // The lint takes T for a Future; it is a plain value.
    // ignore: async_return_with_no_await
    return JdbcTemplate.requiredSingleResult(rows, sql: _statement._sql);
  }

  /// The one row, or null for none; more than one is an
  /// [IncorrectResultSizeDataAccessException].
  Future<T?> optional() async {
    final rows = await list();
    if (rows.length > 1) {
      throw IncorrectResultSizeDataAccessException(
        1,
        rows.length,
        sql: _statement._sql,
      );
    }
    return rows.isEmpty ? null : rows.single;
  }

  /// The rows one by one; see `JdbcTemplate.queryForStream`.
  Stream<T> stream() async* {
    final (text, values) = _statement._prepare();
    yield* _statement._client.template.queryForStream<T>(
      text,
      values,
      _mapper,
    );
  }

  /// The whole result given to [extractor].
  Future<R> extract<R>(ResultSetExtractor<R> extractor) => Future.sync(() {
    final (text, values) = _statement._prepare();
    return _statement._client.template.queryWithExtractor<R>(
      text,
      values,
      extractor,
    );
  });
}

// Names set one by one first, then the sources in the order added.
final class _CombinedSource implements SqlParameterSource {
  _CombinedSource(this._values, this._sources);

  final Map<String, Object?> _values;
  final List<SqlParameterSource> _sources;

  @override
  bool hasValue(String name) =>
      _values.containsKey(name) || _sources.any((s) => s.hasValue(name));

  @override
  Object? getValue(String name) {
    if (_values.containsKey(name)) {
      return _values[name];
    }
    return _sources.firstWhere((s) => s.hasValue(name)).getValue(name);
  }
}
