import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_supabase/src/data/postgrest_query.dart';
import 'package:spring_boot_starter_supabase/src/http/supabase_http.dart';
import 'package:spring_boot_starter_supabase/src/supabase_exception.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// One change of a row as Realtime reports it: the columns as they are
/// now (`record`; `null` for a delete) and as they were (`oldRecord`;
/// only the key unless the table's replica identity is full).
typedef PostgrestRowChange = ({
  RowChangeKind kind,
  Map<String, Object?>? record,
  Map<String, Object?>? oldRecord,
});

/// Where the changes of a table come from (Realtime): every change of
/// [table] of [schema] the caller may see.
typedef PostgrestChanges = Stream<PostgrestRowChange> Function({
  required String schema,
  required String table,
});

/// The data store over the project's REST API (PostgREST), named
/// `supabase`: the store of the repositories when `spring.supabase.db.url`
/// is not set.
///
/// Every call is one HTTP request made as the current user
/// (`SupabaseCredentials`), so the database applies its row-level
/// security. What follows from one request per call:
///
/// - **No transactions and no locks** ([capabilities]): a repository with
///   `@Transactional`, `@Lock` or a SQL `@Query` on this store fails when
///   the application starts, with the reason. For work that must be
///   atomic, write a database function and call it with `@Procedure`, or set
///   `spring.supabase.db.url` and use SQL.
/// - **No aggregates with `@MappedCollection`**: their rows are written
///   together, in a transaction. Such an entity is refused with the
///   reason.
/// - `@Version` works: an update names the version it read, and no row
///   updated is an `OptimisticLockingFailureException`.
///
/// **Changes of rows** ([changes], behind `watchBy…` and `changesBy…`)
/// come from Realtime, as one subscription to the whole table, without a
/// filter of Realtime, whatever the criteria: a subscription with a
/// filter gets no delete at all and no update that takes a row out of
/// the filter, so a watched query would keep rows that are gone. The
/// criteria are applied on this side ([filtersChanges] is false for
/// them, `CriteriaMatcher.concerns`), with what a change carries:
///
/// - an insert, and an update whose new row matches, concern the criteria;
/// - an update whose new row does not match concerns them too, since the
///   row may have matched before: Realtime sends only the key of the old
///   row. With `alter table … replica identity full` it sends the whole
///   old row (`RowChange.previous`), and only the updates of rows that
///   matched before or match now are left;
/// - a delete carries only the id (`RowChange.id`; `row` is null, and
///   `previous` too without `replica identity full`), so every delete of
///   the table concerns every criteria. Realtime does not apply
///   row-level security to deletes: the ids of rows the user could not
///   read arrive as well.
///
/// The cost: every change of the table the user may read travels to this
/// client, and a watched query runs again (once per burst of changes)
/// after updates and deletes of rows it never held. All the streams of
/// one table share one channel.
///
/// Errors are the data starter's exceptions: the database's own code is
/// translated as on the SQL path (`23505` is a `DuplicateKeyException`,
/// `42501` a `PermissionDeniedDataAccessException`, ...).
final class PostgrestDataStore
    implements FunctionDataStore, ChangeStreamDataStore {
  /// A store over [http]; [schema] is the schema asked for (the API's
  /// default when `null`), `changes` where the changes of rows come from
  /// (none: the store has no `changes`).
  PostgrestDataStore({
    required this.http,
    required this.converter,
    this.schema,
    this._changes,
    this.name = storeName,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _query = PostgrestQuery(converter);

  /// The name `@UseStore` selects this store by.
  static const storeName = 'supabase';

  /// The project.
  final SupabaseHttp http;

  /// What turns rows into entities and back.
  final EntityConverter converter;

  /// The schema of the tables; the API's default (`public`) when `null`.
  final String? schema;

  final PostgrestChanges? _changes;
  final DateTime Function() _clock;
  final PostgrestQuery _query;

  @override
  final String name;

  @override
  DataStoreCapabilities get capabilities =>
      DataStoreCapabilities(functions: true, changes: _changes != null);

  // ---------------------------------------------------------------- write

  @override
  Future<T> insert<T extends Object>(
    PersistentEntity<T> entity,
    T instance,
  ) async {
    _noChildren(entity);
    final row = converter.write(entity, instance);
    final id = entity.idProperty;
    if (id != null && row[id.columnName] == null) {
      // The database generates it (an identity column, a default).
      row.remove(id.columnName);
    }
    if (entity.versionProperty case final version?) {
      row[version.columnName] = _firstVersion(version);
    }
    final rows = await _rows(
      HttpMethod.post,
      entity,
      json: _json(row),
      representation: true,
    );
    if (rows.isEmpty) {
      throw PermissionDeniedDataAccessException(
        'The row was inserted into ${entity.tableName} but could not be '
        'read back: the policies of row-level security let the caller '
        'insert it and not select it',
      );
    }
    return converter.read<T>(entity, rows.first);
  }

  @override
  Future<T> update<T extends Object>(
    PersistentEntity<T> entity,
    T instance, {
    Object? expectedVersion,
  }) async {
    _noChildren(entity);
    final id = _idOf(entity, instance);
    final row = converter.write(entity, instance)
      ..remove(entity.idProperty!.columnName);
    final filters = [_idFilter(entity, id)];
    if (entity.versionProperty case final version?) {
      final expected = expectedVersion ?? converter.versionOf(entity, instance);
      filters.add(
        MapEntry(
          version.columnName,
          expected == null ? 'is.null' : 'eq.${_query.scalar(expected)}',
        ),
      );
      row[version.columnName] = _nextVersion(version, expected);
    }
    final rows = await _rows(
      HttpMethod.patch,
      entity,
      query: filters,
      json: _json(row),
      representation: true,
    );
    if (rows.isEmpty) {
      if (entity.hasVersion) {
        throw OptimisticLockingFailureException(
          'The ${entity.type} with id $id was changed or removed by '
          'someone else (or the caller may not update it)',
        );
      }
      throw IncorrectUpdateSemanticsDataAccessException(
        'No ${entity.type} with id $id to update (or the caller may not '
        'update it)',
      );
    }
    return converter.read<T>(entity, rows.first);
  }

  @override
  Future<bool> deleteById<T extends Object>(
    PersistentEntity<T> entity,
    Object id, {
    Object? expectedVersion,
  }) async {
    _noChildren(entity);
    final version = entity.versionProperty;
    final rows = await _rows(
      HttpMethod.delete,
      entity,
      query: [
        _idFilter(entity, id),
        if (version != null && expectedVersion != null)
          MapEntry(
            version.columnName,
            'eq.${_query.scalar(expectedVersion)}',
          ),
        _select(entity),
      ],
      representation: true,
    );
    if (rows.isEmpty && version != null && expectedVersion != null) {
      throw OptimisticLockingFailureException(
        'The ${entity.type} with id $id was changed or removed by '
        'someone else (or the caller may not delete it)',
      );
    }
    return rows.isNotEmpty;
  }

  @override
  Future<int> deleteWhere<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) async {
    _noChildren(entity);
    final rows = await _rows(
      HttpMethod.delete,
      entity,
      query: [..._where(entity, criteria), _select(entity)],
      representation: true,
    );
    return rows.length;
  }

  @override
  Future<List<T>> deleteWhereAndReturn<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) async {
    _noChildren(entity);
    final rows = await _rows(
      HttpMethod.delete,
      entity,
      query: _where(entity, criteria),
      representation: true,
    );
    return [for (final row in rows) converter.read<T>(entity, row)];
  }

  // ----------------------------------------------------------------- read

  @override
  Future<T?> findById<T extends Object>(
    PersistentEntity<T> entity,
    Object id, {
    LockMode? lock,
    Duration? lockTimeout,
    bool skipLocked = false,
  }) async {
    _noLock(lock);
    _noChildren(entity);
    final rows = await _rows(
      HttpMethod.get,
      entity,
      query: [_idFilter(entity, id), const MapEntry('limit', '1')],
    );
    return rows.isEmpty ? null : converter.read<T>(entity, rows.first);
  }

  @override
  Future<List<T>> findAllById<T extends Object>(
    PersistentEntity<T> entity,
    Iterable<Object> ids,
  ) async {
    _noChildren(entity);
    final all = ids.toList();
    if (all.isEmpty) {
      return const [];
    }
    final idName = _id(entity).name;
    final rows = await _rows(
      HttpMethod.get,
      entity,
      query: _query.filters(
        entity,
        Criteria(
          [
            OrPart([Part(idName, PartType.in_)]),
          ],
          [all],
        ),
      ),
    );
    return [for (final row in rows) converter.read<T>(entity, row)];
  }

  @override
  Future<List<T>> find<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
    Sort sort = Sort.unsorted,
    int? offset,
    int? limit,
    bool distinct = false,
    LockMode? lock,
    Duration? lockTimeout,
    bool skipLocked = false,
  }) async {
    _noLock(lock);
    _noChildren(entity);
    if (distinct) {
      throw InvalidDataAccessApiUsageException(
        "Distinct cannot be asked of the database's REST API: use a "
        'database function with @Procedure, or the SQL path '
        '(spring.supabase.db.url)',
      );
    }
    final order =
        _query.order(entity, sort) ??
        // A window of rows needs an order to be the same twice.
        ((offset != null && offset > 0) || limit != null
            ? entity.idProperty?.columnName
            : null);
    final rows = await _rows(
      HttpMethod.get,
      entity,
      query: [
        ..._query.filters(entity, criteria),
        if (order != null) MapEntry('order', order),
        if (offset != null && offset > 0) MapEntry('offset', '$offset'),
        if (limit != null) MapEntry('limit', '$limit'),
      ],
    );
    return [for (final row in rows) converter.read<T>(entity, row)];
  }

  @override
  Future<int> count<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) async {
    // A GET of no row, not a HEAD: the count is in the same header, and
    // a connection is not closed under the next call, as some servers
    // and proxies do after answering a HEAD.
    final response = await _send(
      HttpMethod.get,
      entity,
      query: [
        ..._query.filters(entity, criteria),
        _select(entity),
        const MapEntry('limit', '0'),
      ],
      prefer: 'count=exact',
    );
    // `0-24/3573`, or `*/0` for no row.
    final range = response.headers[HttpHeaders.contentRangeHeader] ?? '';
    final total = int.tryParse(range.substring(range.indexOf('/') + 1));
    if (total == null) {
      throw DataAccessResourceFailureException(
        'The count of ${entity.tableName} did not come back '
        '(Content-Range: "$range")',
      );
    }
    return total;
  }

  @override
  Future<bool> exists<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) async {
    final rows = await _rows(
      HttpMethod.get,
      entity,
      query: [
        ..._query.filters(entity, criteria),
        _select(entity),
        const MapEntry('limit', '1'),
      ],
    );
    return rows.isNotEmpty;
  }

  // ------------------------------------------------------------ functions

  @override
  Future<List<Map<String, Object?>>> callFunction(
    String name,
    Map<String, Object?> arguments,
  ) async {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
      throw InvalidDataAccessApiUsageException(
        '"$name" is not the name of a database function',
      );
    }
    final response = _checked(
      await _guard(
        () => http.send(
          SupabaseService.rest,
          HttpMethod.post,
          '/rpc/$name',
          headers: {'Content-Profile': ?schema},
          json: _json(arguments),
        ),
      ),
      'function $name',
    );
    return switch (_decode(response)) {
      null => const [],
      final Map<String, Object?> row => [row],
      final List<Object?> list => [
        for (final item in list)
          if (item is Map<String, Object?>) item else {name: item},
      ],
      final scalar => [
        {name: scalar},
      ],
    };
  }

  // -------------------------------------------------------------- changes

  /// False for any criteria: Realtime is not asked to filter (see the
  /// class), the caller narrows the changes itself.
  @override
  bool filtersChanges<T extends Object>(
    PersistentEntity<T> entity,
    Criteria criteria,
  ) => criteria.isEmpty;

  /// Every change of the rows of [entity]'s table the user may see,
  /// whatever the [criteria] (see the class for why Realtime's filter is
  /// not used): `row` for an insert and an update, `previous` only when
  /// the table has `replica identity full`, and for a delete the `id`
  /// alone.
  @override
  Stream<RowChange<T>> changes<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) {
    final source = _changes;
    if (source == null) {
      throw InvalidDataAccessApiUsageException(
        'The $name store has no changes of rows: Realtime is not available',
      );
    }
    final id = entity.idProperty;
    T? read(Map<String, Object?>? row, {required bool whole}) {
      if (row == null) {
        return null;
      }
      // An old record is only the key unless the table's replica identity
      // is full: then it is no entity.
      if (!whole &&
          !entity.columns.every((p) => row.containsKey(p.columnName))) {
        return null;
      }
      return converter.read<T>(entity, row);
    }

    return source(schema: schema ?? 'public', table: entity.tableName).map((
      change,
    ) {
      final key = id == null
          ? null
          : (change.record ?? change.oldRecord)?[id.columnName];
      return RowChange<T>(
        change.kind,
        row: read(change.record, whole: true),
        previous: read(change.oldRecord, whole: false),
        id: key == null ? null : converter.fromColumnValue(key, id!.type),
      );
    });
  }

  // -------------------------------------------------------------- helpers

  PersistentProperty _id(PersistentEntity<Object> entity) =>
      entity.idProperty ??
      (throw InvalidDataAccessApiUsageException(
        '${entity.type} has no @Id property',
      ));

  Object _idOf(PersistentEntity<Object> entity, Object instance) {
    _id(entity);
    return converter.idOf(entity, instance) ??
        (throw InvalidDataAccessApiUsageException(
          'The ${entity.type} to update has no id',
        ));
  }

  MapEntry<String, String> _idFilter(
    PersistentEntity<Object> entity,
    Object id,
  ) => MapEntry(_id(entity).columnName, 'eq.${_query.scalar(id)}');

  // Only the key comes back where the rows themselves are not needed.
  MapEntry<String, String> _select(PersistentEntity<Object> entity) =>
      MapEntry('select', entity.idProperty?.columnName ?? '*');

  // The rows of a criteria; every row when there is none. The database of
  // a project refuses an UPDATE or a DELETE without a WHERE, so "every
  // row" is written as a condition every row meets.
  List<MapEntry<String, String>> _where(
    PersistentEntity<Object> entity,
    Criteria? criteria,
  ) {
    final filters = _query.filters(entity, criteria);
    return filters.isNotEmpty
        ? filters
        : [MapEntry(_id(entity).columnName, 'not.is.null')];
  }

  Object _firstVersion(PersistentProperty version) =>
      version.type.type == DateTime ? _clock().toUtc() : 1;

  Object _nextVersion(PersistentProperty version, Object? current) =>
      switch (current) {
        final int number => number + 1,
        _ => version.type.type == DateTime ? _clock().toUtc() : 1,
      };

  static void _noLock(LockMode? lock) {
    if (lock != null) {
      throw InvalidDataAccessApiUsageException(
        "A lock cannot be taken through the database's REST API (every "
        'call is a transaction of its own): use a database function with '
        '@Procedure, or the SQL path (spring.supabase.db.url)',
      );
    }
  }

  static void _noChildren(PersistentEntity<Object> entity) {
    if (entity.properties.any((property) => property.isMappedCollection)) {
      throw InvalidDataAccessApiUsageException(
        '${entity.type} has a @MappedCollection: the rows of an aggregate '
        "are written together, in a transaction, which the database's "
        'REST API does not have. Use the SQL path '
        '(spring.supabase.db.url), or keep the children as an entity with '
        'a repository of its own',
      );
    }
  }

  Future<List<Map<String, Object?>>> _rows(
    HttpMethod method,
    PersistentEntity<Object> entity, {
    List<MapEntry<String, String>> query = const [],
    Object? json,
    bool representation = false,
  }) async {
    final response = await _send(
      method,
      entity,
      query: query,
      json: json,
      prefer: representation ? 'return=representation' : null,
    );
    return switch (_decode(response)) {
      final List<Object?> list => [
        for (final row in list)
          if (row is Map<String, Object?>) row,
      ],
      final Map<String, Object?> row => [row],
      _ => const [],
    };
  }

  Future<HttpResponse> _send(
    HttpMethod method,
    PersistentEntity<Object> entity, {
    List<MapEntry<String, String>> query = const [],
    Object? json,
    String? prefer,
  }) async {
    final tableSchema = entity.schema ?? schema;
    final reads = method == HttpMethod.get || method == HttpMethod.head;
    return _checked(
      await _guard(
        () => http.send(
          SupabaseService.rest,
          method,
          '/${Uri.encodeComponent(entity.tableName)}',
          query: query,
          headers: {
            (reads ? 'Accept-Profile' : 'Content-Profile'): ?tableSchema,
            'Prefer': ?prefer,
          },
          json: json,
        ),
      ),
      entity.tableName,
    );
  }

  static Future<HttpResponse> _guard(
    Future<HttpResponse> Function() call,
  ) async {
    try {
      return await call();
    } on SupabaseUnavailableException catch (error) {
      if (error.isTimeout) {
        throw QueryTimeoutException(error.message, cause: error);
      }
      throw DataAccessResourceFailureException(error.message, cause: error);
    }
  }

  static Object? _decode(HttpResponse response) {
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(response.bodyText);
    } on FormatException {
      return null;
    }
  }

  // The response when it succeeded, else the data starter's exception of
  // its failure.
  static HttpResponse _checked(HttpResponse response, String what) {
    if (response.isSuccess) {
      return response;
    }
    final status = response.statusCode.value;
    final body = switch (_decode(response)) {
      final Map<String, Object?> map => map,
      _ => const <String, Object?>{},
    };
    final code = switch (body['code']) {
      final String text when text.isNotEmpty => text,
      _ => null,
    };
    final said = [
      for (final key in const ['message', 'details', 'hint'])
        if (body[key] case final String text when text.isNotEmpty) text,
    ].join('; ');
    final message =
        '$what: ${said.isEmpty ? 'the REST API answered $status' : said}'
        '${code == null ? '' : ' [$code]'}';
    if (code != null && RegExp(r'^[0-9A-Z]{5}$').hasMatch(code)) {
      // The database's own code: the same exception as on the SQL path.
      throw const PostgresDialect().translate(
        SqlError(message, sqlState: code),
      );
    }
    throw switch ((code, status)) {
      // The token: expired, not accepted, no role.
      ('PGRST301' || 'PGRST302' || 'PGRST303', _) ||
      (_, 401 || 403) => PermissionDeniedDataAccessException(message),
      // A table, a column or a function the API does not know.
      ('PGRST200' || 'PGRST202' || 'PGRST204' || 'PGRST205', _) ||
      (_, 404) => InvalidDataAccessResourceUsageException(message),
      (_, 409) => DataIntegrityViolationException(message),
      (_, >= 500) => DataAccessResourceFailureException(message),
      // The request itself: a filter, an order or a body it cannot read.
      _ => InvalidDataAccessApiUsageException(message),
    };
  }

  // A row or the arguments of a function as JSON.
  static Object? _json(Object? value) => switch (value) {
    null || num() || bool() || String() => value,
    final DateTime time => time.toUtc().toIso8601String(),
    final Enum value => value.name,
    final BigInt number => '$number',
    final Duration duration => '${duration.inMicroseconds} microseconds',
    final Uint8List bytes =>
      '\\x${[for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join()}',
    final Map<Object?, Object?> map => {
      for (final entry in map.entries) '${entry.key}': _json(entry.value),
    },
    final Iterable<Object?> list => [for (final item in list) _json(item)],
    _ => '$value',
  };
}
