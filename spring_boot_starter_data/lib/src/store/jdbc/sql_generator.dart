import 'package:spring_boot_dart/spring_boot_dart.dart' show LogFormatUtils;
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_template.dart';
import 'package:spring_boot_starter_data/src/jdbc/json_storage.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/query/part_tree.dart';
import 'package:spring_boot_starter_data/src/query/query_arguments.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';

/// A SQL statement with the values to bind to its `?` markers, in order.
///
/// The values are column values (as `EntityConverter.toColumnValue` gives
/// them); the `JdbcTemplate` that runs the statement applies the
/// dialect's conversion. Nothing of a value is ever written into [sql].
/// The generator's statements carry the column each value is bound to
/// ([BoundParameters]), so the trace log masks the values of a `password`
/// column as it does a named `@Query` parameter.
///
/// Spring (Java): none; Spring Data JDBC's `Sql` plus the
/// `SqlParameterSource` of `NamedParameterJdbcOperations`.
final class BoundSql {
  /// A statement running [sql] with [parameters].
  const BoundSql(this.sql, [this.parameters = const []]);

  /// The SQL, with `?` for each value.
  final String sql;

  /// The values of the markers, in order (a [BoundParameters], with the
  /// column of each, for the statements the generator writes).
  final List<Object?> parameters;

  @override
  String toString() => sql;
}

/// Writes the SQL of the repositories' operations for an entity, in the
/// syntax of a [SqlDialect]: inserts, updates, deletes, selects by id and
/// by a [Criteria], counts, and the statements of the child tables of a
/// `@MappedCollection`.
///
/// Every table and column name is quoted by the dialect, and every value is
/// a bind parameter: a value can never change the statement, only the
/// names of the entity (which come from the application's classes and
/// annotations) are written into it. The conditions of a [Criteria] mean
/// what they mean in the in-memory store:
///
/// - a `null` argument of a simple property is `is null` (of the negated
///   one `is not null`); any other comparison with null matches nothing;
/// - `ignoreCase` compares `lower(column)` with `lower(?)` ([SqlDialect.lower]:
///   SQLite's driver registers a `lower` that folds every letter);
/// - the `like` family uses `ESCAPE '\'`: `startingWith`, `endingWith` and
///   `containing` take their argument literally (its `%`, `_` and `\` are
///   escaped), `like` takes `%` and `_` as wildcards and `\` as the escape
///   character; a dialect whose `LIKE` ignores case (SQLite) gets its case
///   sensitive operator ([SqlDialect.globOperator]) with the pattern
///   translated;
/// - `between` is inclusive; `in` of an empty collection matches nothing
///   and `notIn` of one everything, without an invalid `in ()`;
/// - an `AggregateReference` is its id, an enum its name.
///
/// The column of a `@Json` property is written as the dialect's
/// `jsonStorage` says (its marker, and the decoded JSON of the row turned
/// into what the marker binds); a condition or an order on one is refused
/// (the repository says so before the store is asked).
///
/// Sorting names the null placement of every key (`NULLS FIRST` for
/// descending and `NULLS LAST` for ascending unless the order says
/// otherwise), as the in-memory store sorts, and ends with the id so equal
/// keys keep a stable order. `distinct` is left out when the entity has an
/// id: its rows are distinct already.
///
/// Spring (Java):
/// `org.springframework.data.jdbc.core.convert.SqlGenerator` (with
/// `org.springframework.data.relational.core.sql.render.SqlRenderer`).
final class SqlGenerator {
  /// A generator for [dialect], converting argument values with
  /// [converter].
  SqlGenerator({required this.dialect, required this.converter});

  /// The database's syntax.
  final SqlDialect dialect;

  /// Turns argument values into column values.
  final EntityConverter converter;

  /// The quoted table of [entity].
  String table(PersistentEntity<Object> entity) =>
      dialect.table(entity.tableName, entity.schema);

  String _q(String name) => dialect.quote(name);

  /// The quoted columns of [entity]'s own table, separated by commas.
  String columnList(PersistentEntity<Object> entity) =>
      entity.columns.map((p) => _q(p.columnName)).join(', ');

  PersistentProperty _id(PersistentEntity<Object> entity) =>
      entity.idProperty ??
      (throw InvalidDataAccessApiUsageException(
        '${entity.introspection.className} has no @Id property: the JDBC '
        'store keeps aggregates by id',
      ));

  // ---------------------------------------------------------------- write

  final _jsonColumns =
      Map<PersistentEntity<Object>, Map<String, JsonStorage>>.identity();

  // How the dialect keeps the `@Json` columns of [entity], by column.
  Map<String, JsonStorage> _json(PersistentEntity<Object> entity) =>
      _jsonColumns[entity] ??= {
        for (final property in entity.columns)
          if (property.json case final json?)
            property.columnName: dialect.jsonStorage(json),
      };

  // The value of a row as its marker binds it: the decoded JSON of a
  // `@Json` column as the dialect keeps it, any other as it is.
  static Object? _bound(JsonStorage? storage, Object? value) =>
      storage == null || value == null ? value : storage.toDatabase(value);

  /// `insert into t (columns) values (?, ...)` for the columns of [row]
  /// (its keys, in order; leave out an id the database generates). The
  /// column of a `@Json` property holds decoded JSON in [row], as
  /// `EntityConverter.write` gives it.
  BoundSql insert(
    PersistentEntity<Object> entity,
    Map<String, Object?> row,
  ) {
    if (row.isEmpty) {
      return BoundSql('insert into ${table(entity)} default values');
    }
    final json = _json(entity);
    final columns = row.keys.map(_q).join(', ');
    final markers = [
      for (final column in row.keys) json[column]?.marker ?? '?',
    ].join(', ');
    return BoundSql(
      'insert into ${table(entity)} ($columns) values ($markers)',
      BoundParameters([
        for (final MapEntry(:key, :value) in row.entries)
          _bound(json[key], value),
      ], row.keys.toList()),
    );
  }

  /// `update t set column = ?, ... where id = ? [and version = ?]`: every
  /// column of [row] but the id is set; the version condition is added when
  /// the entity has a `@Version` (the row carries the raised version, and
  /// [expectedVersion] is the version the stored row must still have).
  BoundSql update(
    PersistentEntity<Object> entity,
    Map<String, Object?> row, {
    required Object? id,
    Object? expectedVersion,
  }) {
    final idColumn = _id(entity).columnName;
    final sets = [
      for (final entry in row.entries)
        if (entry.key != idColumn) entry,
    ];
    final json = _json(entity);
    final parameters = _Binder();
    final assignments = sets.isEmpty
        ? '${_q(idColumn)} = ${_q(idColumn)}'
        : sets
              .map((e) {
                final storage = json[e.key];
                parameters.add(e.key, _bound(storage, e.value));
                return '${_q(e.key)} = ${storage?.marker ?? '?'}';
              })
              .join(', ');
    final where = _byIdWhere(
      entity,
      id,
      expectedVersion,
      parameters,
      checkVersion: true,
    );
    return BoundSql(
      'update ${table(entity)} set $assignments$where',
      parameters.bound,
    );
  }

  /// `delete from t where id = ? [and version = ?]`; the version condition
  /// only when [expectedVersion] is given.
  BoundSql deleteById(
    PersistentEntity<Object> entity,
    Object? id, {
    Object? expectedVersion,
  }) {
    final parameters = _Binder();
    final where = _byIdWhere(
      entity,
      id,
      expectedVersion,
      parameters,
      checkVersion: expectedVersion != null,
    );
    return BoundSql('delete from ${table(entity)}$where', parameters.bound);
  }

  String _byIdWhere(
    PersistentEntity<Object> entity,
    Object? id,
    Object? expectedVersion,
    _Binder parameters, {
    required bool checkVersion,
  }) {
    final idColumn = _id(entity).columnName;
    parameters.add(idColumn, id);
    final buffer = StringBuffer(' where ${_q(idColumn)} = ?');
    if (checkVersion && entity.versionProperty != null) {
      // A null expected version never matches (`= null`): bound as it is.
      final versionColumn = entity.versionProperty!.columnName;
      parameters.add(versionColumn, expectedVersion);
      buffer.write(' and ${_q(versionColumn)} = ?');
    }
    return buffer.toString();
  }

  /// `delete from t [where criteria]`.
  BoundSql deleteWhere(
    PersistentEntity<Object> entity,
    Criteria? criteria,
  ) {
    final parameters = _Binder();
    final where = _where(entity, criteria, parameters);
    return BoundSql('delete from ${table(entity)}$where', parameters.bound);
  }

  // ----------------------------------------------------------------- read

  /// `select columns from t where id = ?` with [lock] (a lock clause, or
  /// empty).
  BoundSql selectById(
    PersistentEntity<Object> entity,
    Object? id, {
    String lock = '',
  }) => BoundSql(
    'select ${columnList(entity)} from ${table(entity)} '
    'where ${_q(_id(entity).columnName)} = ?${_suffix(lock)}',
    BoundParameters([id], [_id(entity).columnName]),
  );

  /// `select columns from t where id in (?, ...) order by id` for [ids]
  /// (not empty).
  BoundSql selectByIds(
    PersistentEntity<Object> entity,
    List<Object?> ids,
  ) {
    final idColumn = _q(_id(entity).columnName);
    return BoundSql(
      'select ${columnList(entity)} from ${table(entity)} '
      'where $idColumn in (${List.filled(ids.length, '?').join(', ')}) '
      'order by $idColumn',
      BoundParameters(ids, List.filled(ids.length, _id(entity).columnName)),
    );
  }

  /// The select of the aggregates that match [criteria] (all without it):
  /// ordered by [sort], without duplicates when [distinct], skipping
  /// [offset] rows and keeping [limit], followed by [lock].
  ///
  /// Without a sort but with an offset or a limit the rows are ordered by
  /// id, so the pages are stable.
  BoundSql select(
    PersistentEntity<Object> entity, {
    Criteria? criteria,
    Sort sort = Sort.unsorted,
    int? offset,
    int? limit,
    bool distinct = false,
    String lock = '',
  }) {
    if (offset != null && offset < 0) {
      throw InvalidDataAccessApiUsageException(
        'The offset must not be negative: $offset',
      );
    }
    final parameters = _Binder();
    final where = _where(entity, criteria, parameters);
    final paged = (offset != null && offset > 0) || limit != null;
    final order = sort.isSorted || paged
        ? orderBy(entity, sort, alwaysTieBreak: true)
        : '';
    final window = dialect.limitOffset(
      limit == null ? null : (limit < 0 ? 0 : limit),
      offset == null || offset <= 0 ? null : offset,
    );
    final keyword = distinct && entity.idProperty == null
        ? 'select distinct'
        : 'select';
    return BoundSql(
      '$keyword ${columnList(entity)} from ${table(entity)}$where$order'
      '${_suffix(window)}${_suffix(lock)}',
      parameters.bound,
    );
  }

  /// `select count(*) from t [where criteria]`.
  BoundSql count(PersistentEntity<Object> entity, Criteria? criteria) {
    final parameters = _Binder();
    final where = _where(entity, criteria, parameters);
    return BoundSql(
      'select count(*) from ${table(entity)}$where',
      parameters.bound,
    );
  }

  /// `select 1 from t [where criteria] limit 1`.
  BoundSql exists(PersistentEntity<Object> entity, Criteria? criteria) {
    final parameters = _Binder();
    final where = _where(entity, criteria, parameters);
    return BoundSql(
      'select 1 from ${table(entity)}$where '
      '${dialect.limitOffset(1, null)}',
      parameters.bound,
    );
  }

  String _suffix(String clause) => clause.isEmpty ? '' : ' $clause';

  // ------------------------------------------------------------- children

  /// `delete from child where reverse = ?`: the children of one root.
  BoundSql deleteChildren(
    PersistentEntity<Object> child,
    String reverseColumn,
    Object? rootId,
  ) => BoundSql(
    'delete from ${table(child)} where ${_q(reverseColumn)} = ?',
    BoundParameters([rootId], [reverseColumn]),
  );

  /// `delete from child where reverse in (select id from root where
  /// criteria)`: the children of the roots that match.
  BoundSql deleteChildrenWhere(
    PersistentEntity<Object> child,
    String reverseColumn,
    PersistentEntity<Object> root,
    Criteria? criteria,
  ) {
    final parameters = _Binder();
    final where = _where(root, criteria, parameters);
    return BoundSql(
      'delete from ${table(child)} where ${_q(reverseColumn)} in '
      '(select ${_q(_id(root).columnName)} from ${table(root)}$where)',
      parameters.bound,
    );
  }

  /// The children of the roots [rootIds] (not empty) in one select:
  /// `select columns, reverse[, key] from child where reverse in (...)
  /// order by reverse[, key]`.
  BoundSql selectChildren(
    PersistentEntity<Object> child,
    String reverseColumn,
    String? keyColumn,
    List<Object?> rootIds,
  ) {
    final own = {for (final p in child.columns) p.columnName};
    final columns = [
      columnList(child),
      if (!own.contains(reverseColumn)) _q(reverseColumn),
      if (keyColumn != null && !own.contains(keyColumn)) _q(keyColumn),
    ].where((c) => c.isNotEmpty).join(', ');
    final markers = List.filled(rootIds.length, '?').join(', ');
    final order = keyColumn == null
        ? ' order by ${_q(reverseColumn)}'
        : ' order by ${_q(reverseColumn)}, ${_q(keyColumn)}';
    return BoundSql(
      'select $columns from ${table(child)} '
      'where ${_q(reverseColumn)} in ($markers)$order',
      BoundParameters(rootIds, List.filled(rootIds.length, reverseColumn)),
    );
  }

  // ---------------------------------------------------------------- order

  /// The `order by` clause (with its leading space) of [sort]: each key
  /// with its direction and explicit null placement, `lower(...)` for an
  /// order that ignores case, and the id last (when [tieBreak] and the
  /// entity has an id) so equal keys keep a stable order; [alwaysTieBreak]
  /// adds it without a sort too.
  ///
  /// A property of the sort that is no column of [entity] is an
  /// `InvalidDataAccessApiUsageException`, unless [free] is given: it then
  /// turns the name into SQL (the `@Query` methods sort by the columns of
  /// their own result).
  String orderBy(
    PersistentEntity<Object> entity,
    Sort sort, {
    bool alwaysTieBreak = false,
    bool tieBreak = true,
    String Function(String name)? free,
  }) {
    final terms = <String>[];
    for (final order in sort.orders) {
      final property = entity.property(order.property);
      final String column;
      if (property != null && !property.isMappedCollection) {
        column = _q(property.columnName);
      } else if (free != null) {
        column = free(order.property);
      } else {
        throw PropertyReferenceException(
          order.property,
          entity.introspection.className,
        );
      }
      final nullsFirst = switch (order.nullHandling) {
        NullHandling.nullsFirst => true,
        NullHandling.nullsLast => false,
        NullHandling.native => order.isDescending,
      };
      terms.add(
        '${order.ignoreCase ? dialect.lower(column) : column} '
        '${order.isDescending ? 'DESC' : 'ASC'} '
        'NULLS ${nullsFirst ? 'FIRST' : 'LAST'}',
      );
    }
    if (entity.idProperty case final id?
        when tieBreak && (alwaysTieBreak || sort.isSorted)) {
      terms.add('${_q(id.columnName)} ASC');
    }
    return terms.isEmpty ? '' : ' order by ${terms.join(', ')}';
  }

  // ---------------------------------------------------------------- where

  String _where(
    PersistentEntity<Object> entity,
    Criteria? criteria,
    _Binder parameters,
  ) {
    if (criteria == null || criteria.isEmpty) {
      return '';
    }
    var next = 0;
    final alternatives = <String>[];
    for (final or in criteria.predicate) {
      final conjunction = <String>[];
      for (final part in or.parts) {
        final property = _column(entity, part.path.first);
        final count = part.type.argumentCount;
        final arguments = criteria.arguments.sublist(next, next + count);
        next += count;
        conjunction.add(_condition(property, part, arguments, parameters));
      }
      alternatives.add(
        conjunction.isEmpty ? '1 = 1' : '(${conjunction.join(' and ')})',
      );
    }
    return ' where ${alternatives.join(' or ')}';
  }

  PersistentProperty _column(PersistentEntity<Object> entity, String name) {
    final property = entity.property(name);
    if (property == null || property.isMappedCollection) {
      throw InvalidDataAccessApiUsageException(
        'No column ${LogFormatUtils.formatValue(name)} of '
        '${entity.introspection.className} for a condition',
      );
    }
    return property;
  }

  static const _never = '1 = 0';
  static const _always = '1 = 1';

  String _condition(
    PersistentProperty property,
    Part part,
    List<Object?> arguments,
    _Binder parameters,
  ) {
    final ic = part.ignoreCase;
    final name = property.columnName;
    final column = _q(name);
    final left = ic ? dialect.lower(column) : column;
    final marker = ic ? dialect.lower('?') : '?';
    Object? argument(int index) {
      final value = converter.toColumnValue(arguments[index]);
      rejectNul(value, property.name);
      return value;
    }

    String compare(String operator) {
      final value = argument(0);
      if (value == null) {
        return _never;
      }
      parameters.add(name, value);
      return '$left $operator $marker';
    }

    switch (part.type) {
      case PartType.isNull:
        return '$column is null';
      case PartType.isNotNull:
        return '$column is not null';
      case PartType.isTrue:
        parameters.add(name, true);
        return '$column = ?';
      case PartType.isFalse:
        parameters.add(name, false);
        return '$column = ?';
      case PartType.simpleProperty:
        return argument(0) == null ? '$column is null' : compare('=');
      case PartType.negatingSimpleProperty:
        return argument(0) == null ? '$column is not null' : compare('<>');
      case PartType.lessThan:
        return compare('<');
      case PartType.lessThanEqual:
        return compare('<=');
      case PartType.greaterThan:
        return compare('>');
      case PartType.greaterThanEqual:
        return compare('>=');
      case PartType.between:
        final low = argument(0);
        final high = argument(1);
        if (low == null || high == null) {
          return _never;
        }
        parameters
          ..add(name, low)
          ..add(name, high);
        return '$left between $marker and $marker';
      case PartType.like:
        return _like(column, name, part, _parse(argument(0)), parameters);
      case PartType.notLike:
        return _like(
          column,
          name,
          part,
          _parse(argument(0)),
          parameters,
          negate: true,
        );
      case PartType.startingWith:
        return _like(
          column,
          name,
          part,
          _literal(argument(0), end: true),
          parameters,
        );
      case PartType.endingWith:
        return _like(
          column,
          name,
          part,
          _literal(argument(0), start: true),
          parameters,
        );
      case PartType.containing:
        return _like(
          column,
          name,
          part,
          _literal(argument(0), start: true, end: true),
          parameters,
        );
      case PartType.notContaining:
        return _like(
          column,
          name,
          part,
          _literal(argument(0), start: true, end: true),
          parameters,
          negate: true,
        );
      case PartType.in_ || PartType.notIn:
        final raw = arguments[0];
        if (raw is! Iterable<Object?>) {
          throw InvalidDataAccessApiUsageException(
            "'${property.name}' ${part.type.name} needs a collection, not "
            '${raw == null ? 'null' : raw.runtimeType}',
          );
        }
        final elements = [
          for (final element in raw) converter.toColumnValue(element),
        ];
        for (final element in elements) {
          rejectNul(element, property.name);
        }
        final isIn = part.type == PartType.in_;
        if (isIn) {
          // A null never equals anything: it takes no part.
          final values = elements.nonNulls.toList();
          if (values.isEmpty) {
            return _never;
          }
          final array = _array(column, ic, false, values.length);
          if (array != null) {
            parameters.add(name, values);
            return array;
          }
          parameters.addAll(name, values);
          return '$left in (${List.filled(values.length, marker).join(', ')})';
        }
        if (elements.isEmpty) {
          return _always;
        }
        if (elements.contains(null)) {
          // `x not in (..., null)` is never true.
          return _never;
        }
        final array = _array(column, ic, true, elements.length);
        if (array != null) {
          parameters.add(name, elements);
          return array;
        }
        parameters.addAll(name, elements);
        return '$left not in '
            '(${List.filled(elements.length, marker).join(', ')})';
    }
  }

  // The condition that binds [count] values as one array parameter, or null
  // when the dialect writes a marker for each; a list a dialect without
  // arrays cannot bind is refused here, clearly.
  String? _array(String column, bool ignoreCase, bool negate, int count) {
    final array = dialect.arrayMembership(
      column,
      ignoreCase: ignoreCase,
      negate: negate,
    );
    if (array != null) {
      return array;
    }
    final limit = dialect.maxBoundParameters;
    if (limit != null && count > limit) {
      throw InvalidDataArgumentException(
        'A list of $count values is more than ${dialect.name} binds in one '
        'statement ($limit): split it into smaller lists, or query by a '
        'join or a range',
      );
    }
    return null;
  }

  // ----------------------------------------------------------------- like

  // A pattern: text, with `%` (any text) and `_` (one character) as
  // wildcards; null when the argument is not a text (nothing matches).
  List<Object>? _parse(Object? argument) {
    if (argument is! String) {
      return null;
    }
    final tokens = <Object>[];
    final text = StringBuffer();
    void flush() {
      if (text.isNotEmpty) {
        tokens.add(text.toString());
        text.clear();
      }
    }

    for (var i = 0; i < argument.length; i++) {
      final c = argument[i];
      if (c == r'\' && i + 1 < argument.length) {
        text.write(argument[++i]);
      } else if (c == '%') {
        flush();
        tokens.add(_Wildcard.any);
      } else if (c == '_') {
        flush();
        tokens.add(_Wildcard.one);
      } else {
        text.write(c);
      }
    }
    flush();
    return tokens;
  }

  // The argument as literal text, with a wildcard before and/or after.
  List<Object>? _literal(
    Object? argument, {
    bool start = false,
    bool end = false,
  }) {
    if (argument is! String) {
      return null;
    }
    return [
      if (start) _Wildcard.any,
      if (argument.isNotEmpty) argument,
      if (end) _Wildcard.any,
    ];
  }

  String _like(
    String column,
    String name,
    Part part,
    List<Object>? tokens,
    _Binder parameters, {
    bool negate = false,
  }) {
    if (tokens == null) {
      return _never;
    }
    final not = negate ? 'not ' : '';
    if (part.ignoreCase) {
      parameters.add(name, _likeText(tokens));
      return '${dialect.lower(column)} ${not}like ${dialect.lower('?')} '
          r"escape '\'";
    }
    if (dialect.likeIgnoresCase) {
      parameters.add(name, _globText(tokens));
      return '$column $not${dialect.globOperator} ?';
    }
    parameters.add(name, _likeText(tokens));
    return "$column ${not}like ? escape '\\'";
  }

  // The pattern for `like ... escape '\'`.
  String _likeText(List<Object> tokens) {
    final out = StringBuffer();
    for (final token in tokens) {
      switch (token) {
        case _Wildcard.any:
          out.write('%');
        case _Wildcard.one:
          out.write('_');
        case final String text:
          out.write(
            text
                .replaceAll(r'\', r'\\')
                .replaceAll('%', r'\%')
                .replaceAll('_', r'\_'),
          );
      }
    }
    return out.toString();
  }

  // The same pattern for `glob`: `*` and `?` are the wildcards, and a
  // special character is a one-character class.
  String _globText(List<Object> tokens) {
    final out = StringBuffer();
    for (final token in tokens) {
      switch (token) {
        case _Wildcard.any:
          out.write('*');
        case _Wildcard.one:
          out.write('?');
        case final String text:
          out.write(
            text
                .replaceAll('[', '[[]')
                .replaceAll('*', '[*]')
                .replaceAll('?', '[?]'),
          );
      }
    }
    return out.toString();
  }
}

enum _Wildcard { any, one }

// The values of a statement under construction, with the column each is
// bound to.
final class _Binder {
  final _values = <Object?>[];
  final _names = <String>[];

  void add(String name, Object? value) {
    _values.add(value);
    _names.add(name);
  }

  void addAll(String name, Iterable<Object?> values) {
    for (final value in values) {
      add(name, value);
    }
  }

  BoundParameters get bound => BoundParameters(_values, _names);
}
