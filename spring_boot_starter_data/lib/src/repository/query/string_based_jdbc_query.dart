import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/named_parameter_utils.dart';
import 'package:spring_boot_starter_data/src/jdbc/row_mapper.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/naming_strategy.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/repository/page.dart';
import 'package:spring_boot_starter_data/src/repository/query/query_method.dart';
import 'package:spring_boot_starter_data/src/repository/query/query_result_mapper.dart';
import 'package:spring_boot_starter_data/src/repository/query/query_text.dart';
import 'package:spring_boot_starter_data/src/repository/query/result_shaper.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';
import 'package:spring_boot_starter_data/src/store/jdbc/jdbc_data_store.dart';

/// Runs a repository method's `@Query`: the SQL of the annotation, with
/// its parameters bound by name, on the JDBC store.
///
/// The build has checked the method and the text (see the generator's
/// `QueryTextChecker`): each `:name` is a parameter, a plain `?` and a
/// `#{...}` other than `#{#entityName}` are refused, the result type can be
/// read from rows, a `Page` has its `Pageable`, a misspelled table or column
/// is found. What depends on the run time is done when the repository is
/// created ([compile]), and every problem of the method is reported with
/// the other problems of the repository:
///
/// - the text is prepared once: `${property:default}` placeholders are
///   resolved from the environment (configuration, not user input),
///   `#{#entityName}` becomes the quoted table, `{Book}` and
///   `{Book.authorId}` the quoted table of the entity and the quoted column
///   of its property (as its mapping names them), `:#{expression}` becomes a
///   marker bound to the value of an expression at each call: the one the
///   build compiled, else SpEL, which reads the method's parameters as its
///   variables `#name`, `#p0`, `#a0` (`#root` is the list of the arguments),
///   `@bean` names a bean, and the `environment` bean answers
///   `@environment.getProperty('x')`;
/// - a DTO result must be described (its module registered).
///
/// **Values are always bound**, never written into the SQL text: a list
/// becomes `in (?, ?, ...)` (an empty one is refused with a clear message,
/// as `in ()` is not SQL), an enum its name, an `AggregateReference` its
/// id. A `Pageable` or `Sort` parameter is not bound: its sort is written
/// as quoted column names (anything that is not an identifier is refused)
/// and its window as `LIMIT`/`OFFSET` of the dialect, after the query's
/// own `order by` (joined with a comma) or after the query.
///
/// **A sort is checked against what the result is mapped from**, and a name
/// that is not there is a `PropertyReferenceException` (a 400 through the
/// web glue), not a database error:
///
/// - an entity result: the properties of the entity (by property name, or by
///   the name of its column), `alias.column` too for a joined table;
/// - a DTO result: the properties of the DTO, sorted by the column of the
///   same name in snake case (`authorName` by `author_name`, as the row
///   mapper matches them), or a column written as the select names it
///   (`author_name`), and the entity's properties as above;
/// - a single column, a `Map`, a `rowMapper` or a `resultSetExtractor`:
///   nothing is known about the columns, so the name only has to be an
///   identifier and is quoted: the database decides, and an unknown column
///   is its error.
///
/// **Results** by the return type of the method:
///
/// - the entity: the columns of its table are mapped, and then its
///   children are loaded (one select for each collection) so the aggregate
///   is whole. This deviates from Spring Data JDBC, which maps only what
///   the query returns; a query returning an entity with children must
///   select its id;
/// - a class of the application (a DTO, which the build describes as a
///   projection, or an `@Introspected` class): columns by name through the
///   `EntityRowMapper` (or the `DataClassRowMapper` of an `@Introspected`
///   class: `author_name` into `authorName`), a column the constructor needs
///   and the result lacks is a `MappingException` naming the columns there
///   are;
/// - one column: `int`, `String`, `bool`, `double`, `DateTime`, an enum...
///   (a `Map<String, Object?>` is a row as a map);
/// - with `rowMapper` of the annotation: what the function returns for each
///   row; with `resultSetExtractor`: what it returns for the whole result;
/// - as a collection: `List`, `Set`, `Iterable`; a `Stream` is read as the
///   database sends the rows (the connection is held until it ends or is
///   cancelled; an entity with children is read whole first); `Page` and
///   `Slice` need a `Pageable` parameter: the page's count is the
///   `countQuery` or `select count(*) from (<the query>)`, skipped when the
///   page is not full; a slice reads one more row to know about the next
///   one;
/// - one result: the value (nullable types give null for no row, the
///   others an `EmptyResultDataAccessException`; several rows are an
///   `IncorrectResultSizeDataAccessException`);
/// - with `@Modifying`: `int` (the rows changed), `bool` (any), or nothing;
///   run in the repository's transaction.
///
/// Spring (Java):
/// `org.springframework.data.jdbc.repository.query.StringBasedJdbcQuery`.
final class StringBasedJdbcQuery {
  StringBasedJdbcQuery._({
    required this._where,
    required this._store,
    required this._entity,
    required this._method,
    required this._main,
    required this._countStatement,
    required this._result,
    required this._table,
    required this._introspector,
    required this._expressionContext,
    required this._beanFactory,
    required this._inTransaction,
    required this._translateError,
    required this._naming,
  });

  final String _where;
  final JdbcDataStore _store;
  final PersistentEntity<Object> _entity;
  final QueryMethod _method;
  final _Statement _main;
  final _Statement? _countStatement;

  // Reads the rows as the method's result: shared with the @Procedure methods.
  final QueryResultMapper _result;

  final String _table;
  final BeanIntrospector _introspector;
  final QueryExpressionContext _expressionContext;
  final BeanFactory? _beanFactory;

  final Future<Object?> Function(Future<Object?> Function() body)
  _inTransaction;
  final DataAccessException Function(Object error) _translateError;

  // Names the columns of a DTO's properties, as the mapping does.
  final NamingStrategy _naming;

  Query get _query => _method.query;
  QueryShape get _shape => _method.shape;
  int? get _pageable => _method.pageable;
  int? get _sort => _method.sort;
  bool get _modifying => _method.change != null;

  // The method's parameters (by position) that are bound by name: all but
  // the Pageable and the Sort.
  late final Map<String, int> _parameterNames = _method.boundParameters;

  _Kind get _kind => _result.kind;

  // What one row becomes (dynamic for a change, which has no rows).
  TypeInfo<Object?> get _element => _result.element;
  ResultShaper get _shaper => _result.shaper;

  static final _identifier = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
  );

  /// Compiles the `@Query` of [method] on [entity] for [store], or returns
  /// null after adding to [problems] every mistake found.
  ///
  /// [inTransaction] runs a `@Modifying` query in the repository's write
  /// transaction; [translateError] wraps what a stream fails with in a
  /// `DataAccessException`. [environment] resolves `${...}` and answers
  /// SpEL's `@environment`; [beanFactory] gives SpEL its `@bean`s;
  /// [introspector] lets SpEL read the properties of `@Introspected`
  /// arguments and maps `@Introspected` DTOs; [mappingContext] describes
  /// the other DTOs and the entities of `{Entity}` placeholders.
  static StringBasedJdbcQuery? compile({
    required String typeName,
    required QueryMethod method,
    required PersistentEntity<Object> entity,
    required JdbcDataStore store,
    required Future<Object?> Function(Future<Object?> Function() body)
    inTransaction,
    required DataAccessException Function(Object error) translateError,
    required List<String> problems,
    Environment? environment,
    BeanFactory? beanFactory,
    BeanIntrospector? introspector,
    RelationalMappingContext? mappingContext,
  }) {
    final where = '$typeName.${method.name}';
    final before = problems.length;
    final intro = introspector ?? store.converter.introspector;
    final query = method.query;

    // ---- the result
    final result = QueryResultMapper.of(
      where: where,
      element: method.element,
      entity: entity,
      converter: store.converter,
      introspector: intro,
      problems: problems,
      reader: store.dialect,
      mappingContext: mappingContext,
      custom: query.rowMapper != null || query.resultSetExtractor != null,
    );

    // ---- the text
    final table = store.sql.table(entity);
    final mainText = QueryTextPreparer.prepare(
      query.value,
      quotedTable: table,
      environment: environment,
      where: where,
      problems: problems,
      entityName: _entityNames(method, mappingContext, store),
    );
    final countText = query.countQuery == null
        ? null
        : QueryTextPreparer.prepare(
            query.countQuery!,
            quotedTable: table,
            environment: environment,
            where: '$where (countQuery)',
            problems: problems,
            entityName: _entityNames(method, mappingContext, store),
          );
    final markers =
        mainText.expressions.length + (countText?.expressions.length ?? 0);
    if (method.expressions.isNotEmpty && method.expressions.length != markers) {
      problems.add(
        '$where: the method has ${method.expressions.length} compiled '
        'expression(s) for $markers `:#{...}` marker(s)',
      );
    }
    final main = _Statement.compile(
      mainText,
      where: where,
      compiled: method.expressions.take(mainText.expressions.length).toList(),
      problems: problems,
    );
    final count = countText == null
        ? null
        : _Statement.compile(
            countText,
            where: '$where (countQuery)',
            compiled: method.expressions
                .skip(mainText.expressions.length)
                .toList(),
            problems: problems,
          );
    if (problems.length > before) {
      return null;
    }
    return StringBasedJdbcQuery._(
      where: where,
      store: store,
      entity: entity,
      method: method,
      main: main,
      countStatement: count,
      result: result,
      table: table,
      introspector: intro,
      expressionContext: QueryExpressionContext(
        entityName: table,
        methodName: method.name,
        beanFactory: beanFactory,
        environment: environment,
      ),
      beanFactory: beanFactory,
      inTransaction: inTransaction,
      translateError: translateError,
      naming: mappingContext?.namingStrategy ?? const NamingStrategy(),
    );
  }

  // Names the table or the column of an `{Entity}` placeholder as the
  // mapping does.
  static String Function(String, String?) _entityNames(
    QueryMethod method,
    RelationalMappingContext? mappingContext,
    JdbcDataStore store,
  ) => (name, property) {
    final type = method.entities[name];
    final entity = type == null
        ? null
        : mappingContext?.getPersistentEntity(type);
    if (entity == null) {
      throw MappingException(
        '{$name} names an entity that is not described: register the '
        'module of $name',
      );
    }
    if (property == null) {
      return store.sql.table(entity);
    }
    final stored = entity.property(property);
    if (stored == null || stored.isMappedCollection) {
      throw MappingException(
        '{$name.$property}: $name has no column for $property',
      );
    }
    return store.dialect.quote(stored.columnName);
  };

  // ------------------------------------------------------------- running

  /// Whether the method returns a `Stream` (its [call] returns the stream
  /// itself, not a `Future`).
  bool get isStream => _shape == QueryShape.stream;

  /// Runs the query with the method's [arguments]: a `Future` of the
  /// result, or for a `Stream` method the stream (which runs the query
  /// when listened to).
  Object? call(List<Object?> arguments) {
    if (_shape == QueryShape.stream) {
      return _shaper.streamOf(_stream(arguments));
    }
    return _run(arguments);
  }

  Stream<Object?> _stream(List<Object?> arguments) async* {
    try {
      final (sql, source) = _prepare(arguments, null);
      if (_kind == _Kind.entity && _query.rowMapper == null) {
        yield* Stream<Object?>.fromIterable(await _fetch(sql, source));
      } else {
        yield* _store.named.queryForStream<Object?>(sql, source, _rowMapper());
      }
    } on DataAccessException {
      rethrow;
    } on Exception catch (error, stackTrace) {
      Error.throwWithStackTrace(_translateError(error), stackTrace);
    }
  }

  Future<Object?> _run(List<Object?> arguments) async {
    if (_modifying) {
      return await _change(arguments);
    }
    final window = _windowOf(arguments);
    switch (_shape) {
      case QueryShape.page:
        return await _page(arguments, window!);
      case QueryShape.slice:
        return await _slice(arguments, window!);
      case QueryShape.stream:
        throw StateError('a stream is not run as a future');
      case QueryShape.list || QueryShape.set || QueryShape.single:
        break;
    }
    final (sql, source) = _prepare(
      arguments,
      window != null && window.isPaged
          ? (window.offset, window.pageSize)
          : null,
    );
    if (_query.resultSetExtractor case final extractor?) {
      final result = await _store.named.queryWithExtractor<Object?>(
        sql,
        source,
        (result) => Function.apply(extractor, [result]),
      );
      return _extracted(result);
    }
    return _result.shaped(_shape, await _fetch(sql, source));
  }

  Object? _extracted(Object? result) {
    if (result == null) {
      if (_shape == QueryShape.single && !_element.nullable) {
        throw EmptyResultDataAccessException(
          1,
          message:
              '$_where: the resultSetExtractor returned null for a method '
              'that returns a non-null $_element',
        );
      }
      return null;
    }
    return switch ((_shape, result)) {
      (QueryShape.list, final Iterable<Object?> items) => _shaper.list(items),
      (QueryShape.set, final Iterable<Object?> items) => _shaper.set(items),
      _ => result,
    };
  }

  Future<Object?> _change(List<Object?> arguments) async {
    final (sql, source) = _prepare(arguments, null, windowed: false);
    final changed =
        (await _inTransaction(() => _store.named.update(sql, source)))! as int;
    return switch (_method.change!) {
      QueryChange.rows => changed,
      QueryChange.any => changed > 0,
      QueryChange.nothing => null,
    };
  }

  Future<Object?> _page(List<Object?> arguments, Pageable window) async {
    if (window.isUnpaged) {
      final (sql, source) = _prepare(arguments, null);
      final rows = await _fetch(sql, source);
      return _shaper.page(rows, window, rows.length);
    }
    final size = window.pageSize;
    final offset = window.offset;
    final (sql, source) = _prepare(arguments, (offset, size));
    final rows = await _fetch(sql, source);
    // A page that is not full tells the total without counting, as
    // Spring's PageableExecutionUtils does.
    if (rows.length < size && (rows.isNotEmpty || offset == 0)) {
      return _shaper.page(rows, window, offset + rows.length);
    }
    return _shaper.page(rows, window, await _count(arguments));
  }

  Future<int> _count(List<Object?> arguments) {
    if (_countStatement case final statement?) {
      return _store.named.queryForObject<int>(
        statement.sql,
        _source(statement, arguments),
      );
    }
    // Derived: the query as it is, counted. Its own order by (if any) does
    // no harm in a subquery.
    final alias = _store.dialect.quote('spring_count');
    return _store.named.queryForObject<int>(
      'select count(*) from (${QueryTextSupport.trim(_main.sql)}) as $alias',
      _source(_main, arguments),
    );
  }

  Future<Object?> _slice(List<Object?> arguments, Pageable window) async {
    if (window.isUnpaged) {
      final (sql, source) = _prepare(arguments, null);
      final rows = await _fetch(sql, source);
      return _shaper.slice(rows, window, false);
    }
    final size = window.pageSize;
    final (sql, source) = _prepare(arguments, (window.offset, size + 1));
    final rows = await _fetch(sql, source);
    final hasNext = rows.length > size;
    return _shaper.slice(
      hasNext ? rows.sublist(0, size) : rows,
      window,
      hasNext,
    );
  }

  Pageable? _windowOf(List<Object?> arguments) {
    final index = _pageable;
    if (index == null) {
      return null;
    }
    return switch (arguments[index]) {
      final Pageable value => value,
      _ => throw InvalidDataAccessApiUsageException(
        '$_where: the Pageable must not be null (use Pageable.unpaged())',
      ),
    };
  }

  Sort _sortOf(List<Object?> arguments) {
    var result = _windowOf(arguments)?.sort ?? Sort.unsorted;
    if (_sort case final index?) {
      if (arguments[index] case final Sort given) {
        result = result.and(given);
      }
    }
    return result;
  }

  // The statement to run and its values: the query with the sort and the
  // window ([window] is the offset and the limit) put on its text.
  (String, SqlParameterSource) _prepare(
    List<Object?> arguments,
    (int, int)? window, {
    bool windowed = true,
  }) {
    if (window != null && window.$1 < 0) {
      throw InvalidDataAccessApiUsageException(
        '$_where: the offset must not be negative: ${window.$1}',
      );
    }
    var text = QueryTextSupport.trim(_main.sql);
    if (windowed) {
      final sort = _sortOf(arguments);
      if (sort.isSorted) {
        final order = _store.sql.orderBy(
          _entity,
          sort,
          tieBreak: false,
          free: _column,
        );
        text = QueryTextSupport.hasTopLevelOrderBy(text)
            ? '$text, ${order.substring(' order by '.length)}'
            : '$text$order';
      }
      if (window != null) {
        text = '$text ${_store.dialect.limitOffset(window.$2, window.$1)}';
      }
    }
    return (text, _source(_main, arguments));
  }

  // A sort name of the Sort or Pageable as SQL: an identifier, checked
  // against what the result is mapped from when that is known (see the
  // class's documentation).
  String _column(String name) {
    if (!_identifier.hasMatch(name)) {
      throw PropertyReferenceException(
        name,
        _where,
        hint: 'use the name of a column or property (a, a.b), nothing else',
      );
    }
    final parts = name.split('.');
    final String column;
    switch (_kind) {
      case _Kind.entity || _Kind.dto:
        final known = _knownColumn(parts.last);
        if (known == null) {
          throw PropertyReferenceException(
            name,
            _where,
            hint:
                'the result has no such property or column; '
                'known: ${_sortNames.join(', ')}',
          );
        }
        column = known;
      case _Kind.scalar || _Kind.map || _Kind.custom:
        column = parts.last;
    }
    return [
      ...parts.take(parts.length - 1),
      column,
    ].map(_store.dialect.quote).join('.');
  }

  // The column [name] stands for in a sort of the entity or DTO result, or
  // null for a name that is none of its properties or columns.
  String? _knownColumn(String name) {
    final lower = name.toLowerCase();
    if (_kind == _Kind.dto) {
      if (_dtoProperties.contains(name)) {
        return _naming.snakeCase(name);
      }
      // A column as the select names it: matched as the row mapper does.
      final normalized = _normalizeName(name);
      if (_dtoProperties.any((p) => _normalizeName(p) == normalized)) {
        return name;
      }
    }
    if (_entity.property(name) case final property?
        when !property.isMappedCollection) {
      return property.columnName;
    }
    for (final property in _entity.columns) {
      if (property.columnName.toLowerCase() == lower) {
        return property.columnName;
      }
    }
    return null;
  }

  static String _normalizeName(String name) =>
      name.replaceAll('_', '').toLowerCase();

  // The properties of the DTO the rows are mapped to.
  List<String> get _dtoProperties => _result.dtoProperties;

  // What a sort of the entity or DTO result may name, for the message.
  late final List<String> _sortNames = [
    if (_kind == _Kind.dto) ..._dtoProperties,
    for (final property in _entity.columns) property.name,
  ];

  RowMapper<Object?> _rowMapper() {
    if (_query.rowMapper case final mapper?) {
      return (row) => Function.apply(mapper, [row]);
    }
    return _result.rowMapper();
  }

  Future<List<Object?>> _fetch(String sql, SqlParameterSource source) async {
    final result = await _store.named.queryWithExtractor<JdbcResult>(
      sql,
      source,
      (result) => result,
    );
    if (_kind == _Kind.entity && _query.rowMapper == null) {
      return await _store.readAggregates<Object>(_entity, result.rows);
    }
    final mapper = _rowMapper();
    return [for (final row in result.rows) mapper(row)];
  }

  // ------------------------------------------------------------- binding

  SqlParameterSource _source(_Statement statement, List<Object?> arguments) {
    final values = <String, Object?>{
      for (final MapEntry(:key, :value) in _parameterNames.entries)
        key: arguments[value],
    };
    EvaluationContext? interpreted;
    for (final MapEntry(:key, :value) in statement.sources.entries) {
      try {
        values[key] = switch (statement.compiled[key]) {
          final compiled? => compiled(arguments, _expressionContext),
          _ => statement.parsed[key]!.getValue(
            interpreted ??= _context(arguments),
          ),
        };
      } on Object catch (error) {
        throw InvalidDataAccessApiUsageException(
          '$_where: the expression :#{$value} failed: $error',
        );
      }
    }
    return MapSqlParameterSource(values);
  }

  EvaluationContext _context(List<Object?> arguments) {
    final context = StandardEvaluationContext(arguments)
      ..addPropertyAccessor(const EnvironmentAccessor())
      ..addPropertyAccessor(IntrospectionPropertyAccessor(_introspector))
      ..addMethodResolver(const EnvironmentMethodResolver())
      ..addMethodResolver(IntrospectionMethodResolver(_introspector));
    if (_beanFactory case final factory?) {
      context.beanResolver = BeanFactoryResolver(factory);
    }
    for (var i = 0; i < arguments.length; i++) {
      context
        ..setVariable('p$i', arguments[i])
        ..setVariable('a$i', arguments[i]);
      if (i < _method.parameters.length) {
        context.setVariable(_method.parameters[i], arguments[i]);
      }
    }
    context
      ..setVariable('entityName', _table)
      ..setVariable('methodName', _method.name);
    return context;
  }

  @override
  String toString() => 'StringBasedJdbcQuery($_where)';
}

typedef _Kind = QueryResultKind;

// One SQL text of a method: its expressions, each compiled by the build or
// parsed here.
final class _Statement {
  _Statement(this.sql, this.sources, this.compiled, this.parsed);

  // [compiled] has an entry for each marker of [text], in order: the
  // expression compiled by the build, or null to interpret its text.
  factory _Statement.compile(
    QueryText text, {
    required String where,
    required List<QueryExpression?> compiled,
    required List<String> problems,
  }) {
    final ready = <String, QueryExpression>{};
    final parsed = <String, Expression>{};
    for (final (index, MapEntry(:key, :value))
        in text.expressions.entries.indexed) {
      if (index < compiled.length && compiled[index] != null) {
        ready[key] = compiled[index]!;
        continue;
      }
      try {
        parsed[key] = _parser.parseExpression(value);
      } on Object catch (error) {
        problems.add('$where: the expression :#{$value} is invalid: $error');
      }
    }
    return _Statement(text.sql, text.expressions, ready, parsed);
  }

  static final _parser = SpelExpressionParser();

  final String sql;

  // The text of each expression, by marker.
  final Map<String, String> sources;

  // The expressions the build compiled, by marker.
  final Map<String, QueryExpression> compiled;

  // The others, parsed, by marker.
  final Map<String, Expression> parsed;
}
