import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/named_parameter_utils.dart';
import 'package:spring_boot_starter_data/src/jdbc/row_mapper.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/repository/page.dart';
import 'package:spring_boot_starter_data/src/repository/query/query_text.dart';
import 'package:spring_boot_starter_data/src/repository/query/result_shaper.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';
import 'package:spring_boot_starter_data/src/store/jdbc/jdbc_data_store.dart';

/// Runs a repository method's `@Query`: the SQL of the annotation, with
/// its parameters bound by name, on the JDBC store.
///
/// Everything that can be checked is checked when the repository is
/// created ([compile]), and every problem of the method is reported
/// together with the other problems of the repository:
///
/// - the text is prepared once: `${property:default}` placeholders are
///   resolved from the environment (configuration, not user input),
///   `#{#entityName}` becomes the quoted table, `:#{expression}` becomes a
///   marker bound to the value of a SpEL expression at each call (the
///   method's parameters are its variables `#name`, `#p0`, `#a0`, and
///   `#root` is the list of the arguments; `@bean` names a bean, and the
///   `environment` bean answers `@environment.getProperty('x')`);
/// - each `:name` must be a parameter of the method (or an expression), a
///   plain `?` is refused, a method must be asynchronous, and the return
///   type must be one of those below.
///
/// **Values are always bound**, never written into the SQL text: a list
/// becomes `in (?, ?, ...)` (an empty one is refused with a clear message,
/// as `in ()` is not SQL), an enum its name, an `AggregateReference` its
/// id. A `Pageable` or `Sort` parameter is not bound: its sort is written
/// as quoted column names (anything that is not an identifier is refused)
/// and its window as `LIMIT`/`OFFSET` of the dialect, after the query's
/// own `order by` (joined with a comma) or after the query.
///
/// **Results** by the return type of the method:
///
/// - the entity: the columns of its table are mapped, and then its
///   children are loaded (one select for each collection) so the aggregate
///   is whole. This deviates from Spring Data JDBC, which maps only what
///   the query returns; a query returning an entity with children must
///   select its id;
/// - a class of the application (a DTO, `@Introspected`): columns by name
///   through the `DataClassRowMapper` (`author_name` into `authorName`),
///   a column the constructor needs and the result lacks is a
///   `MappingException` naming the columns there are;
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
    required this._query,
    required this._main,
    required this._countStatement,
    required this._kind,
    required this._shape,
    required this._element,
    required this._shaper,
    required this._nullable,
    required this._parameterNames,
    required this._pageable,
    required this._sort,
    required this._modifying,
    required this._table,
    required this._introspector,
    required this._beanFactory,
    required this._inTransaction,
    required this._translateError,
  });

  final String _where;
  final JdbcDataStore _store;
  final PersistentEntity<Object> _entity;
  final ProxyMethod _method;
  final Query _query;
  final _Statement _main;
  final _Statement? _countStatement;
  final _Kind _kind;
  final _Shape _shape;
  final TypeInfo<Object?> _element;
  final ResultShaper _shaper;
  final bool _nullable;

  // The method's parameters (by position) that are bound by name: all but
  // the Pageable and the Sort.
  final Map<String, int> _parameterNames;
  final int? _pageable;
  final int? _sort;
  final bool _modifying;
  final String _table;
  final BeanIntrospector _introspector;
  final BeanFactory? _beanFactory;

  final Future<Object?> Function(Future<Object?> Function() body)
  _inTransaction;
  final DataAccessException Function(Object error) _translateError;

  // One column as the property type of the method wants it: converted as a
  // column of an entity is (the type's own description, so a nullable type
  // still converts: SQLite's 0/1 into a bool, a text into a DateTime).
  Object? _scalar(JdbcRow row) {
    if (row.columns.length != 1) {
      throw IncorrectResultSetColumnCountException(1, row.columns.length);
    }
    final value = row.values.single;
    if (value == null) {
      if (_element.nullable) {
        return null;
      }
      throw InvalidDataAccessApiUsageException(
        '$_where: column ${row.columns.single} is null; return a nullable '
        'type ($_element?)',
      );
    }
    return _store.converter.fromColumnValue(
      _store.dialect.fromDatabase(value, _element),
      _element,
      where: '$_where: column ${row.columns.single}',
    );
  }

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
  /// arguments and maps DTOs.
  static StringBasedJdbcQuery? compile({
    required String typeName,
    required ProxyMethod method,
    required Query query,
    required PersistentEntity<Object> entity,
    required JdbcDataStore store,
    required Future<Object?> Function(Future<Object?> Function() body)
    inTransaction,
    required DataAccessException Function(Object error) translateError,
    required List<String> problems,
    Environment? environment,
    BeanFactory? beanFactory,
    BeanIntrospector? introspector,
  }) {
    final where = '$typeName.${method.name}';
    final before = problems.length;
    void problem(String text) => problems.add('$where: $text');
    final intro = introspector ?? store.converter.introspector;

    // ---- the annotation
    if (query.value.trim().isEmpty) {
      problem(
        query.name != null
            ? 'named queries (@Query(name: ...)) are not supported yet; '
                  'give the SQL as the value'
            : '@Query has no SQL',
      );
    }
    final rowMapper = query.rowMapper;
    final extractor = query.resultSetExtractor;
    if (rowMapper != null && extractor != null) {
      problem('@Query has both rowMapper and resultSetExtractor: use one');
    }
    if (rowMapper != null && rowMapper is! Object? Function(JdbcRow)) {
      problem(
        'the rowMapper is a ${rowMapper.runtimeType}: it must be a function '
        'that takes a JdbcRow (a static method or a top-level function)',
      );
    }
    if (extractor != null && extractor is! Object? Function(JdbcResult)) {
      problem(
        'the resultSetExtractor is a ${extractor.runtimeType}: it must be '
        'a function that takes a JdbcResult (a static method or a '
        'top-level function)',
      );
    }

    // ---- the method
    final isStream = _isStream(method.returnType);
    if (!method.isFuture && !isStream) {
      problem(
        'a repository method is asynchronous: return a Future '
        '(Future<${method.returnType}>) or a Stream',
      );
    }
    if (method.annotation<Lock>() != null) {
      problem(
        '@Lock is for the derived find methods and findById; in a @Query '
        'write the lock in the SQL (select ... for update) and call it '
        'in a transaction',
      );
    }
    int? pageableIndex;
    int? sortIndex;
    final names = <String, int>{};
    for (final (index, parameter) in method.parameters.indexed) {
      final type = parameter.type.type;
      if (type == Pageable || type == PageRequest) {
        if (pageableIndex != null) {
          problem('more than one Pageable parameter');
        }
        pageableIndex = index;
      } else if (type == Sort) {
        sortIndex = index;
      } else {
        names[parameter.name] = index;
      }
    }

    final returnType = method.returnType;
    final modifying = method.annotation<Modifying>() != null;
    var shape = _Shape.single;
    var kind = _Kind.custom;
    var element = returnType;
    if (modifying) {
      final type = returnType.type;
      if (!method.isVoid && type != int && type != bool) {
        problem(
          '@Modifying returns the rows changed (Future<int>), whether any '
          'changed (Future<bool>) or nothing (Future<void>), not '
          '$returnType',
        );
      }
      if (rowMapper != null || extractor != null) {
        problem('@Modifying has no result to map: drop the rowMapper');
      }
      if (pageableIndex != null) {
        problem('@Modifying cannot take a Pageable');
      }
    } else {
      if (method.isVoid) {
        problem(
          'the method returns nothing: a change needs @Modifying, a read a '
          'result type',
        );
      }
      (shape, element) = _shapeOf(returnType);
      if ((shape == _Shape.page || shape == _Shape.slice) &&
          pageableIndex == null) {
        problem(
          'a ${shape.name} needs a Pageable parameter (the window to read)',
        );
      }
      if (extractor != null) {
        if (shape != _Shape.single &&
            shape != _Shape.list &&
            shape != _Shape.set) {
          problem(
            'a resultSetExtractor gives the whole result: return what it '
            'returns, or a List or Set of it, not a ${shape.name}',
          );
        }
        if (pageableIndex != null) {
          problem(
            'a resultSetExtractor reads the whole result: it cannot be '
            'paged',
          );
        }
      }
      if (rowMapper != null || extractor != null) {
        kind = _Kind.custom;
      } else {
        kind = _kindOf(element, entity, intro, where, problems);
      }
    }

    // ---- the text
    final table = store.sql.table(entity);
    _Statement? count;
    final mainText = QueryTextPreparer.prepare(
      query.value,
      quotedTable: table,
      environment: environment,
      where: where,
      problems: problems,
    );
    final main = _Statement.compile(
      mainText,
      where: where,
      names: names.keys.toSet(),
      problems: problems,
    );
    if (query.countQuery != null) {
      if (shape != _Shape.page) {
        problem('countQuery is for a method that returns a Page');
      }
      final countText = QueryTextPreparer.prepare(
        query.countQuery!,
        quotedTable: table,
        environment: environment,
        where: '$where (countQuery)',
        problems: problems,
      );
      count = _Statement.compile(
        countText,
        where: '$where (countQuery)',
        names: names.keys.toSet(),
        problems: problems,
      );
    }
    if (problems.length > before) {
      return null;
    }
    return StringBasedJdbcQuery._(
      where: where,
      store: store,
      entity: entity,
      method: method,
      query: query,
      main: main,
      countStatement: count,
      kind: kind,
      shape: modifying ? _Shape.single : shape,
      element: element,
      shaper: element.capture<ResultShaper>(<E>() => TypedResultShaper<E>()),
      nullable: returnType.nullable,
      parameterNames: names,
      pageable: pageableIndex,
      sort: sortIndex,
      modifying: modifying,
      table: table,
      introspector: intro,
      beanFactory: beanFactory,
      inTransaction: inTransaction,
      translateError: translateError,
    );
  }

  static bool _isStream(TypeInfo<Object?> type) =>
      type is GenericType<Object?> && type.isSubtypeOf<Stream<Object?>>();

  static (_Shape, TypeInfo<Object?>) _shapeOf(TypeInfo<Object?> type) {
    switch (type) {
      case ListType(:final element):
        return (_Shape.list, element);
      case SetType(:final element):
        return (_Shape.set, element);
      case final GenericType<Object?> generic
          when generic.arguments.length == 1:
        if (generic.isSubtypeOf<Page<Object?>>()) {
          return (_Shape.page, generic.arguments.single);
        }
        if (generic.isSubtypeOf<Slice<Object?>>()) {
          return (_Shape.slice, generic.arguments.single);
        }
        if (generic.isSubtypeOf<Stream<Object?>>()) {
          return (_Shape.stream, generic.arguments.single);
        }
        if (generic.isSubtypeOf<Iterable<Object?>>()) {
          return (_Shape.list, generic.arguments.single);
        }
      case _:
        break;
    }
    return (_Shape.single, type);
  }

  static _Kind _kindOf(
    TypeInfo<Object?> element,
    PersistentEntity<Object> entity,
    BeanIntrospector introspector,
    String where,
    List<String> problems,
  ) {
    if (element.type == entity.type) {
      return _Kind.entity;
    }
    if (element is MapType<Object?, Object?>) {
      return _Kind.map;
    }
    if (element is EnumType<Enum> ||
        element.capture<bool>(<X>() => isSimpleType<X>())) {
      return _Kind.scalar;
    }
    if (element is DynamicType) {
      problems.add(
        '$where: the result type is not known (dynamic): return the '
        'entity, a class of yours, a column type or a Map, or give a '
        'rowMapper',
      );
      return _Kind.custom;
    }
    if (introspector.forType(element.type) == null) {
      problems.add(
        '$where: ${element.type} cannot be built from rows: mark the class '
        '@Introspected (and register its module), or give a rowMapper',
      );
    }
    return _Kind.dto;
  }

  // ------------------------------------------------------------- running

  /// Whether the method returns a `Stream` (its [call] returns the stream
  /// itself, not a `Future`).
  bool get isStream => _shape == _Shape.stream;

  /// Runs the query with the method's [arguments]: a `Future` of the
  /// result, or for a `Stream` method the stream (which runs the query
  /// when listened to).
  Object? call(List<Object?> arguments) {
    if (_shape == _Shape.stream) {
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
      case _Shape.page:
        return await _page(arguments, window!);
      case _Shape.slice:
        return await _slice(arguments, window!);
      case _Shape.stream:
        throw StateError('a stream is not run as a future');
      case _Shape.list || _Shape.set || _Shape.single:
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
    final rows = await _fetch(sql, source);
    return switch (_shape) {
      _Shape.list => _shaper.list(rows),
      _Shape.set => _shaper.set(rows),
      _ => _single(rows),
    };
  }

  Object? _extracted(Object? result) {
    if (result == null) {
      if (_shape == _Shape.single && !_nullable) {
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
      (_Shape.list, final Iterable<Object?> items) => _shaper.list(items),
      (_Shape.set, final Iterable<Object?> items) => _shaper.set(items),
      _ => result,
    };
  }

  Object? _single(List<Object?> rows) {
    if (rows.isEmpty) {
      if (_nullable) {
        return null;
      }
      throw EmptyResultDataAccessException(
        1,
        message:
            '$_where: no result, but the method returns a non-null '
            '$_element (return it as nullable to get null)',
      );
    }
    if (rows.length > 1) {
      throw IncorrectResultSizeDataAccessException(
        1,
        rows.length,
        message:
            '$_where: ${rows.length} results for a method that returns '
            'one (return a List, or limit the query)',
      );
    }
    return rows.single;
  }

  Future<Object?> _change(List<Object?> arguments) async {
    final (sql, source) = _prepare(arguments, null, windowed: false);
    final changed =
        (await _inTransaction(() => _store.named.update(sql, source)))! as int;
    if (_method.isVoid) {
      return null;
    }
    return _method.returnType.type == bool ? changed > 0 : changed;
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

  String _column(String name) {
    if (!_identifier.hasMatch(name)) {
      throw InvalidDataAccessApiUsageException(
        "'$name' cannot be a sort property of $_where: use the name of a "
        'column or property (a, a.b), nothing else',
      );
    }
    return name.split('.').map(_store.dialect.quote).join('.');
  }

  RowMapper<Object?> _rowMapper() {
    if (_query.rowMapper case final mapper?) {
      return (row) => Function.apply(mapper, [row]);
    }
    return switch (_kind) {
      _Kind.scalar => _scalar,
      _Kind.map => const ColumnMapRowMapper().call,
      _Kind.dto => _dtoMapper(),
      _Kind.entity || _Kind.custom => throw StateError(
        'no row mapper for $_kind',
      ),
    };
  }

  RowMapper<Object?> _dtoMapper() => DataClassRowMapper<Object>(
    dialect: _store.dialect,
    converter: _store.converter,
    introspector: _introspector,
    introspection: _introspector.forType(_element.type),
  ).call;

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
    if (statement.expressions.isNotEmpty) {
      final context = _context(arguments);
      for (final MapEntry(:key, :value) in statement.expressions.entries) {
        try {
          values[key] = value.getValue(context);
        } on Object catch (error) {
          throw InvalidDataAccessApiUsageException(
            '$_where: the expression :#{${statement.sources[key]}} failed: '
            '$error',
          );
        }
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
        context.setVariable(_method.parameters[i].name, arguments[i]);
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

enum _Shape { list, set, page, slice, stream, single }

enum _Kind { entity, dto, scalar, map, custom }

// One SQL text of a method: its markers checked and its expressions
// parsed.
final class _Statement {
  _Statement(this.sql, this.expressions, this.sources);

  factory _Statement.compile(
    QueryText text, {
    required String where,
    required Set<String> names,
    required List<String> problems,
  }) {
    final expressions = <String, Expression>{};
    for (final MapEntry(:key, :value) in text.expressions.entries) {
      try {
        expressions[key] = _parser.parseExpression(value);
      } on Object catch (error) {
        problems.add('$where: the expression :#{$value} is invalid: $error');
      }
    }
    try {
      final parsed = NamedParameterUtils.parse(text.sql);
      if (parsed.unnamedCount > 0) {
        problems.add(
          '$where: the query has a plain ? marker: write :name and bind '
          'it by the name of a parameter of the method',
        );
      }
      final known = {...names, ...text.expressions.keys};
      for (final name in parsed.names.toSet()) {
        if (!known.contains(name)) {
          final hint = name.contains('.')
              ? ' (to read a property write :#{#$name})'
              : '';
          problems.add(
            '$where: :$name matches no parameter of the method (it has '
            '${names.isEmpty ? 'none' : names.join(', ')})$hint',
          );
        }
      }
    } on DataAccessException catch (error) {
      problems.add('$where: ${error.message}');
    }
    return _Statement(text.sql, expressions, text.expressions);
  }

  static final _parser = SpelExpressionParser();

  final String sql;
  final Map<String, Expression> expressions;

  // The text of each expression, by marker, for messages.
  final Map<String, String> sources;
}
