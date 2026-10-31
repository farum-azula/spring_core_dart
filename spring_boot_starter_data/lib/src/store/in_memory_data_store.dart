import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/log_values.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/query/part_tree.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';

/// A [DataStore] that keeps the aggregates in memory, in tables of rows,
/// like a database would: for tests, prototypes and applications whose
/// data may vanish with the process.
///
/// **Rows, not instances.** A table holds, for each aggregate, the row
/// that `EntityConverter.write` makes of the root and the rows of its
/// children (each `@MappedCollection`, with the position of a list element
/// or the key of a map entry). The application's objects are never kept:
/// what a find returns is a new object built from the row, so changing it
/// changes nothing in the store until it is saved, and what was saved is
/// not changed by later changes of the object.
///
/// **Ids.** A null `int` id is generated per table, counting up from 1
/// (an id that is set moves the counter past it); the ids of children
/// that are `int?` are generated the same way, in the stored rows. An id
/// of another type must be set by the application; a duplicate id on
/// insert is a `DuplicateKeyException`.
///
/// **`@Version`.** Insert sets it to 1 (an `int`) or to the current time (a
/// `DateTime`, made strictly greater at each write). Update checks the
/// stored version against the one of the instance, raises it, and throws an
/// `OptimisticLockingFailureException` when it differs or the aggregate is
/// gone; `deleteById` with a version checks it too.
///
/// **Predicates** follow SQL: a comparison with null is false (`isNull`
/// and `isNotNull` aside), `simpleProperty` with a null argument means
/// `isNull` and `negatingSimpleProperty` `isNotNull`; `ignoreCase` lower
/// cases both sides; `like` takes `%` (any text) and `_` (one character)
/// with `\` to escape them; `startingWith`, `endingWith` and `containing`
/// take their argument literally (a `%` in it is a percent sign); `between`
/// is inclusive; `in` and `notIn` take a collection (`notIn` is false
/// for a value when the collection holds a null, as `NOT IN` is in SQL);
/// an `AggregateReference` property is compared by its id, the argument
/// being a reference or the id itself; numbers compare as numbers and a
/// `DateTime` by the moment.
///
/// **Sorting** takes several orders, each with its direction, `ignoreCase`
/// and null handling. By default (`NullHandling.native`) null is the
/// greatest value, as in PostgreSQL: nulls come last in ascending and first
/// in descending order. Equal keys keep the table's order, which is the
/// order of insertion.
///
/// **Atomic operations.** Dart runs one piece of code at a time, but
/// `await` lets others in between. Every operation reads and writes the
/// tables in one go, without waiting in the middle, so two saves of the
/// same version cannot both succeed: one wins, the other gets an
/// `OptimisticLockingFailureException`. There are no transactions beyond
/// that: an operation on several aggregates is not undone when a later
/// step fails.
///
/// Logging, under `spring.data.memory.InMemoryDataStore`: each operation at
/// debug (the table and the counts), the values only at trace.
///
/// Spring (Java): `JdbcAggregateTemplate` over an embedded database such as
/// H2 (`EmbeddedDatabaseBuilder`), which this store replaces for tests.
final class InMemoryDataStore implements DataStore {
  /// A store that converts entities with [converter]. [name] is what
  /// `@UseStore` selects (`memory`) and what the log shows; a store per
  /// `@UseDataSource` name is named `memory:<data source>`.
  InMemoryDataStore({required this.converter, this.name = 'memory'});

  /// Turns the aggregates' instances into rows and back.
  final EntityConverter converter;

  @override
  final String name;

  static const _log = SpringLog('spring.data.memory.InMemoryDataStore');

  final _tables = <String, _Table>{};

  /// The number of aggregates stored for [entity], for tests and logs.
  int size(PersistentEntity<Object> entity) => _table(entity).rows.length;

  /// Removes every row of every table and starts the ids again from 1.
  void clear() {
    _tables.clear();
    _log.debug('$name: cleared');
  }

  // ---------------------------------------------------------------- write

  @override
  Future<T> insert<T extends Object>(PersistentEntity<T> entity, T instance) =>
      Future.sync(() => _insert(entity, instance));

  T _insert<T extends Object>(PersistentEntity<T> entity, T instance) {
    final idProperty = _requireId(entity);
    final table = _table(entity);
    var id = converter.toColumnValue(idProperty.getValue(instance));
    final generated = id == null;
    if (generated) {
      if (idProperty.type.type != int) {
        throw InvalidDataAccessApiUsageException(
          'The id ${_where(entity, idProperty)} is null and a '
          '${idProperty.type.type} cannot be generated: set it before '
          'saving',
        );
      }
      id = table.nextId++;
    } else if (table.rows.containsKey(id)) {
      throw DuplicateKeyException(
        'Duplicate id in table ${entity.tableName}',
        constraint: '${entity.tableName}_pkey',
      );
    } else if (id is int && id >= table.nextId) {
      table.nextId = id + 1;
    }
    final versionProperty = entity.versionProperty;
    final version = versionProperty == null
        ? null
        : _nextVersion(versionProperty, null);
    final stored = _store(entity, instance);
    stored.values[idProperty.columnName] = id;
    if (versionProperty != null) {
      stored.values[versionProperty.columnName] = converter.toColumnValue(
        version,
      );
    }
    table.rows[id] = stored;
    _log.debug('$name: insert into ${entity.tableName}');
    _trace('insert', entity, stored.values);
    return _withIdAndVersion(
      entity,
      instance,
      idProperty,
      generated ? id : null,
      versionProperty,
      version,
    );
  }

  @override
  Future<T> update<T extends Object>(
    PersistentEntity<T> entity,
    T instance, {
    Object? expectedVersion,
  }) => Future.sync(
    () => _update(entity, instance, expectedVersion: expectedVersion),
  );

  T _update<T extends Object>(
    PersistentEntity<T> entity,
    T instance, {
    Object? expectedVersion,
  }) {
    final idProperty = _requireId(entity);
    final table = _table(entity);
    final id = converter.toColumnValue(idProperty.getValue(instance));
    if (id == null) {
      throw InvalidDataAccessApiUsageException(
        'Cannot update ${entity.introspection.className}: its id is null',
      );
    }
    final versionProperty = entity.versionProperty;
    final existing = table.rows[id];
    Object? version;
    if (versionProperty != null) {
      final expected = converter.toColumnValue(
        expectedVersion ?? versionProperty.getValue(instance),
      );
      if (existing == null ||
          !_equals(existing.values[versionProperty.columnName], expected)) {
        throw OptimisticLockingFailureException(
          'Failed to update ${entity.introspection.className} in table '
          '${entity.tableName}: it was changed or deleted since it was '
          'loaded (its version no longer matches)',
        );
      }
      version = _nextVersion(
        versionProperty,
        existing.values[versionProperty.columnName],
      );
    } else if (existing == null) {
      throw IncorrectUpdateSemanticsDataAccessException(
        'Failed to update ${entity.introspection.className} in table '
        '${entity.tableName}: no row has this id (an entity with an id is '
        'updated, not inserted; give an entity whose id is set by the '
        'application a @Version property)',
      );
    }
    final stored = _store(entity, instance);
    stored.values[idProperty.columnName] = id;
    if (versionProperty != null) {
      stored.values[versionProperty.columnName] = converter.toColumnValue(
        version,
      );
    }
    table.rows[id] = stored;
    _log.debug('$name: update ${entity.tableName}');
    _trace('update', entity, stored.values);
    return _withIdAndVersion(
      entity,
      instance,
      idProperty,
      null,
      versionProperty,
      version,
    );
  }

  @override
  Future<bool> deleteById<T extends Object>(
    PersistentEntity<T> entity,
    Object id, {
    Object? expectedVersion,
  }) => Future.sync(() {
    final table = _table(entity);
    final existing = table.rows[converter.toColumnValue(id)];
    final versionProperty = entity.versionProperty;
    if (expectedVersion != null && versionProperty != null) {
      if (existing == null ||
          !_equals(
            existing.values[versionProperty.columnName],
            converter.toColumnValue(expectedVersion),
          )) {
        throw OptimisticLockingFailureException(
          'Failed to delete ${entity.introspection.className} from table '
          '${entity.tableName}: it was changed or deleted since it was '
          'loaded (its version no longer matches)',
        );
      }
    }
    final removed = table.rows.remove(converter.toColumnValue(id)) != null;
    _log.debug(
      '$name: delete from ${entity.tableName}, ${removed ? 1 : 0} row(s)',
    );
    return removed;
  });

  @override
  Future<int> deleteWhere<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => Future.sync(() => _deleteWhere(entity, criteria).length);

  @override
  Future<List<T>> deleteWhereAndReturn<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => Future.sync(() {
    final removed = _deleteWhere(entity, criteria);
    return [for (final stored in removed) _read(entity, stored)];
  });

  List<_Stored> _deleteWhere(
    PersistentEntity<Object> entity,
    Criteria? criteria,
  ) {
    final table = _table(entity);
    final matches = _matching(entity, criteria);
    final idColumn = _requireId(entity).columnName;
    for (final stored in matches) {
      table.rows.remove(stored.values[idColumn]);
    }
    _log.debug(
      '$name: delete from ${entity.tableName} where '
      '${criteria ?? 'all'}, ${matches.length} row(s)',
    );
    return matches;
  }

  // ----------------------------------------------------------------- read

  @override
  Future<T?> findById<T extends Object>(
    PersistentEntity<T> entity,
    Object id,
  ) => Future<T?>.sync(() {
    final stored = _table(entity).rows[converter.toColumnValue(id)];
    _log.debug(
      '$name: select from ${entity.tableName} by id, '
      '${stored == null ? 0 : 1} row(s)',
    );
    return stored == null ? null : _read<T>(entity, stored);
  });

  @override
  Future<List<T>> findAllById<T extends Object>(
    PersistentEntity<T> entity,
    Iterable<Object> ids,
  ) => Future.sync(() {
    final wanted = {for (final id in ids) converter.toColumnValue(id)};
    final found = [
      for (final MapEntry(:key, :value) in _table(entity).rows.entries)
        if (wanted.contains(key)) value,
    ];
    _log.debug(
      '$name: select from ${entity.tableName} by ${wanted.length} id(s), '
      '${found.length} row(s)',
    );
    return [for (final stored in found) _read(entity, stored)];
  });

  @override
  Future<List<T>> find<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
    Sort sort = Sort.unsorted,
    int? offset,
    int? limit,
    bool distinct = false,
  }) => Future.sync(() {
    var rows = _matching(entity, criteria);
    if (sort.isSorted) {
      rows = _sorted(entity, rows, sort);
    }
    if (distinct) {
      rows = _distinct(rows);
    }
    if (offset != null && offset > 0) {
      rows = rows.length <= offset ? const [] : rows.sublist(offset);
    }
    if (limit != null && limit < rows.length) {
      rows = rows.sublist(0, limit < 0 ? 0 : limit);
    }
    _log.debug(
      '$name: select from ${entity.tableName} where ${criteria ?? 'all'}'
      '${sort.isSorted ? ' order by $sort' : ''}'
      '${offset == null ? '' : ' offset $offset'}'
      '${limit == null ? '' : ' limit $limit'}, ${rows.length} row(s)',
    );
    if (criteria != null &&
        criteria.arguments.isNotEmpty &&
        _log.isEnabled(SpringLogLevel.trace)) {
      _log.trace('$name: arguments ${LogValues.criteria(criteria)}');
    }
    return [for (final stored in rows) _read(entity, stored)];
  });

  @override
  Future<int> count<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => Future.sync(() {
    final count = _matching(entity, criteria).length;
    _log.debug(
      '$name: count ${entity.tableName} where ${criteria ?? 'all'}: $count',
    );
    return count;
  });

  @override
  Future<bool> exists<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => Future.sync(() {
    final exists = _matching(entity, criteria).isNotEmpty;
    _log.debug(
      '$name: exists ${entity.tableName} where ${criteria ?? 'all'}: '
      '$exists',
    );
    return exists;
  });

  // ------------------------------------------------------------- internals

  _Table _table(PersistentEntity<Object> entity) => _tables.putIfAbsent(
    '${entity.schema == null ? '' : '${entity.schema}.'}${entity.tableName}',
    _Table.new,
  );

  PersistentProperty _requireId(PersistentEntity<Object> entity) =>
      entity.idProperty ??
      (throw InvalidDataAccessApiUsageException(
        '${entity.introspection.className} has no @Id property: the '
        'in-memory store keeps aggregates by id',
      ));

  String _where(PersistentEntity<Object> entity, PersistentProperty p) =>
      '${entity.introspection.className}.${p.name}';

  void _trace(
    String what,
    PersistentEntity<Object> entity,
    Map<String, Object?> values,
  ) {
    if (_log.isEnabled(SpringLogLevel.trace)) {
      _log.trace('$name: $what ${entity.tableName} ${LogValues.map(values)}');
    }
  }

  Object _nextVersion(PersistentProperty property, Object? old) {
    if (property.type.type == DateTime) {
      var now = DateTime.now();
      if (old is DateTime && !now.isAfter(old)) {
        now = old.add(const Duration(microseconds: 1));
      }
      return now;
    }
    return (old is int ? old : 0) + 1;
  }

  // The instance as saved: with the generated id and the new version. The
  // changes are applied last, so a failed write leaves the application's
  // instance untouched.
  T _withIdAndVersion<T extends Object>(
    PersistentEntity<T> entity,
    T instance,
    PersistentProperty idProperty,
    Object? generatedId,
    PersistentProperty? versionProperty,
    Object? version,
  ) {
    final changes = <String, Object?>{
      idProperty.name: ?generatedId,
      if (versionProperty != null) versionProperty.name: version,
    };
    return changes.isEmpty
        ? instance
        : converter.withValues(entity, instance, changes);
  }

  // The row of [instance] and of its children.
  _Stored _store(PersistentEntity<Object> entity, Object instance) {
    final values = converter.write(entity, instance);
    for (final key in values.keys.toList()) {
      values[key] = _copy(values[key]);
    }
    final children = <String, List<_Child>>{};
    for (final property in entity.properties) {
      if (!property.isMappedCollection) {
        continue;
      }
      final value = property.getValue(instance);
      if (value == null) {
        continue;
      }
      final child = property.childEntity!;
      final childTable = _table(child);
      final childId = child.idProperty;
      _Child make(Object? key, Object element) {
        final stored = _store(child, element);
        if (childId != null) {
          final id = stored.values[childId.columnName];
          if (id == null && childId.type.type == int) {
            stored.values[childId.columnName] = childTable.nextId++;
          } else if (id is int && id >= childTable.nextId) {
            childTable.nextId = id + 1;
          }
        }
        return _Child(key, stored);
      }

      children[property.name] = switch (value) {
        final Map<Object?, Object?> map => [
          for (final entry in map.entries) make(entry.key, entry.value!),
        ],
        final List<Object?> list => [
          for (final (index, element) in list.indexed) make(index, element!),
        ],
        final Iterable<Object?> items => [
          for (final element in items) make(null, element!),
        ],
        _ => throw MappingException(
          '${_where(entity, property)}: a mapped collection must be a '
          'List, a Set or a Map, not a ${value.runtimeType}',
        ),
      };
    }
    return _Stored(values, children);
  }

  // A new instance of the aggregate stored as [stored].
  T _read<T extends Object>(PersistentEntity<T> entity, _Stored stored) {
    final children = <String, Object?>{};
    for (final property in entity.properties) {
      if (!property.isMappedCollection) {
        continue;
      }
      final rows = stored.children[property.name];
      if (rows == null) {
        continue;
      }
      final child = property.childEntity!;
      children[property.name] = property.type is MapType<Object?, Object?>
          ? {for (final row in rows) row.key: _read(child, row.stored)}
          : [for (final row in rows) _read(child, row.stored)];
    }
    return converter.read(
      entity,
      {
        for (final MapEntry(:key, :value) in stored.values.entries)
          key: _copy(value),
      },
      children: children,
    );
  }

  static Object? _copy(Object? value) =>
      value is Uint8List ? Uint8List.fromList(value) : value;

  // ------------------------------------------------------------ predicates

  List<_Stored> _matching(PersistentEntity<Object> entity, Criteria? criteria) {
    final rows = _table(entity).rows.values;
    if (criteria == null || criteria.isEmpty) {
      return rows.toList();
    }
    final matches = _compile(entity, criteria);
    return [
      for (final stored in rows)
        if (matches(stored.values)) stored,
    ];
  }

  bool Function(Map<String, Object?> row) _compile(
    PersistentEntity<Object> entity,
    Criteria criteria,
  ) {
    var next = 0;
    final alternatives = <List<bool Function(Map<String, Object?>)>>[];
    for (final or in criteria.predicate) {
      final conjunction = <bool Function(Map<String, Object?>)>[];
      for (final part in or.parts) {
        final property = _column(entity, part.path.first, 'a condition');
        final count = part.type.argumentCount;
        final arguments = criteria.arguments.sublist(next, next + count);
        next += count;
        final test = _test(entity, property, part, arguments);
        final column = property.columnName;
        conjunction.add((row) => test(row[column]));
      }
      alternatives.add(conjunction);
    }
    return (row) => alternatives.any((all) => all.every((test) => test(row)));
  }

  PersistentProperty _column(
    PersistentEntity<Object> entity,
    String name,
    String where,
  ) {
    final property = entity.property(name);
    if (property == null || property.isMappedCollection) {
      throw InvalidDataAccessApiUsageException(
        "No column '$name' of ${entity.introspection.className} for $where",
      );
    }
    return property;
  }

  Object? _fold(Object? value, {required bool ignoreCase}) =>
      ignoreCase && value is String ? value.toLowerCase() : value;

  bool Function(Object? value) _test(
    PersistentEntity<Object> entity,
    PersistentProperty property,
    Part part,
    List<Object?> arguments,
  ) {
    final ic = part.ignoreCase;
    Object? argument(int index) =>
        _fold(converter.toColumnValue(arguments[index]), ignoreCase: ic);
    Object? fold(Object? value) => _fold(value, ignoreCase: ic);
    bool compare(Object? value, Object? other, bool Function(int c) holds) {
      if (value == null || other == null) {
        return false;
      }
      final c = _compare(fold(value), other);
      return c != null && holds(c);
    }

    switch (part.type) {
      case PartType.isNull:
        return (value) => value == null;
      case PartType.isNotNull:
        return (value) => value != null;
      case PartType.isTrue:
        return (value) => value == true;
      case PartType.isFalse:
        return (value) => value == false;
      case PartType.simpleProperty:
        final other = argument(0);
        return other == null
            ? (value) => value == null
            : (value) => value != null && _equals(fold(value), other);
      case PartType.negatingSimpleProperty:
        final other = argument(0);
        return other == null
            ? (value) => value != null
            : (value) => value != null && !_equals(fold(value), other);
      case PartType.lessThan:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c < 0);
      case PartType.lessThanEqual:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c <= 0);
      case PartType.greaterThan:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c > 0);
      case PartType.greaterThanEqual:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c >= 0);
      case PartType.between:
        final low = argument(0);
        final high = argument(1);
        return (value) =>
            compare(value, low, (c) => c >= 0) &&
            compare(value, high, (c) => c <= 0);
      case PartType.like || PartType.notLike:
        final pattern = argument(0);
        final negate = part.type == PartType.notLike;
        final regex = pattern is String ? _likeRegex(pattern) : null;
        return (value) {
          if (value is! String || regex == null) {
            return false;
          }
          return regex.hasMatch(fold(value)! as String) != negate;
        };
      case PartType.startingWith:
        return _literal(argument(0), fold, (v, a) => v.startsWith(a));
      case PartType.endingWith:
        return _literal(argument(0), fold, (v, a) => v.endsWith(a));
      case PartType.containing:
        return _literal(argument(0), fold, (v, a) => v.contains(a));
      case PartType.notContaining:
        return _literal(argument(0), fold, (v, a) => !v.contains(a));
      case PartType.in_ || PartType.notIn:
        final raw = arguments[0];
        if (raw is! Iterable<Object?>) {
          throw InvalidDataAccessApiUsageException(
            "'${property.name}' ${part.type.name} needs a collection, not "
            '${raw == null ? 'null' : raw.runtimeType}',
          );
        }
        final elements = [
          for (final element in raw)
            _fold(converter.toColumnValue(element), ignoreCase: ic),
        ];
        if (part.type == PartType.in_) {
          return (value) =>
              value != null &&
              elements.any((e) => e != null && _equals(fold(value), e));
        }
        final hasNull = elements.contains(null);
        return (value) {
          if (elements.isEmpty) {
            return true;
          }
          return value != null &&
              !hasNull &&
              !elements.any((e) => _equals(fold(value), e));
        };
    }
  }

  bool Function(Object? value) _literal(
    Object? argument,
    Object? Function(Object?) fold,
    bool Function(String value, String argument) holds,
  ) =>
      (value) =>
          value is String &&
          argument is String &&
          holds(fold(value)! as String, argument);

  // `%` any text, `_` one character, `\` makes the next one literal.
  RegExp? _likeRegex(String pattern) {
    final out = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == r'\' && i + 1 < pattern.length) {
        out.write(RegExp.escape(pattern[++i]));
      } else if (c == '%') {
        out.write('.*');
      } else if (c == '_') {
        out.write('.');
      } else {
        out.write(RegExp.escape(c));
      }
    }
    out.write(r'$');
    return RegExp(out.toString(), dotAll: true);
  }

  // ----------------------------------------------------------------- sort

  List<_Stored> _sorted(
    PersistentEntity<Object> entity,
    List<_Stored> rows,
    Sort sort,
  ) {
    final keys = [
      for (final order in sort.orders)
        (order, _column(entity, order.property, 'sorting').columnName),
    ];
    final indexed = rows.indexed.toList()
      ..sort((a, b) {
        for (final (order, column) in keys) {
          final c = _order(order, a.$2.values[column], b.$2.values[column]);
          if (c != 0) {
            return c;
          }
        }
        return a.$1.compareTo(b.$1);
      });
    return [for (final (_, stored) in indexed) stored];
  }

  int _order(SortOrder order, Object? a, Object? b) {
    // Null is the greatest value unless the order says otherwise.
    final nullsFirst = switch (order.nullHandling) {
      NullHandling.nullsFirst => true,
      NullHandling.nullsLast => false,
      NullHandling.native => order.isDescending,
    };
    if (a == null || b == null) {
      if (a == null && b == null) {
        return 0;
      }
      return (a == null) == nullsFirst ? -1 : 1;
    }
    final c =
        _compare(
          _fold(a, ignoreCase: order.ignoreCase),
          _fold(b, ignoreCase: order.ignoreCase),
        ) ??
        0;
    return order.isDescending ? -c : c;
  }

  List<_Stored> _distinct(List<_Stored> rows) {
    final seen = <int, List<_Stored>>{};
    final out = <_Stored>[];
    for (final stored in rows) {
      final bucket = seen.putIfAbsent(
        Object.hashAll(stored.values.values.map(_hash)),
        () => [],
      );
      if (!bucket.any((other) => _sameRow(other.values, stored.values))) {
        bucket.add(stored);
        out.add(stored);
      }
    }
    return out;
  }

  static int _hash(Object? value) => switch (value) {
    final DateTime d => d.microsecondsSinceEpoch,
    final Uint8List b => Object.hashAll(b),
    final num n => n.toDouble().hashCode,
    _ => value.hashCode,
  };

  static bool _sameRow(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.entries.every(
        (e) => b.containsKey(e.key) && _equals(e.value, b[e.key]),
      );

  // The order of two column values of one type; null when they cannot be
  // compared (different types).
  static int? _compare(Object? a, Object? b) {
    if (a is num && b is num) {
      return a.compareTo(b);
    }
    if (a is String && b is String) {
      return a.compareTo(b);
    }
    if (a is DateTime && b is DateTime) {
      return a.compareTo(b);
    }
    if (a is bool && b is bool) {
      return (a ? 1 : 0).compareTo(b ? 1 : 0);
    }
    if (a is BigInt && b is BigInt) {
      return a.compareTo(b);
    }
    return null;
  }

  static bool _equals(Object? a, Object? b) {
    if (a == null || b == null) {
      return a == null && b == null;
    }
    final c = _compare(a, b);
    if (c != null) {
      return c == 0;
    }
    if (a is List<int> && b is List<int>) {
      return a.length == b.length &&
          Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
    }
    return a == b;
  }
}

// One table: the stored aggregates by id, in insertion order, and the
// counter of generated ids (children's tables only use the counter).
final class _Table {
  final rows = <Object?, _Stored>{};
  int nextId = 1;
}

// The row of an aggregate (a root or a child) and the rows of its
// children, by the name of the mapped property.
final class _Stored {
  _Stored(this.values, this.children);

  final Map<String, Object?> values;
  final Map<String, List<_Child>> children;
}

// A child row with its position in a list (an int), its key in a map, or
// null in a set.
final class _Child {
  _Child(this.key, this.stored);

  final Object? key;
  final _Stored stored;
}
