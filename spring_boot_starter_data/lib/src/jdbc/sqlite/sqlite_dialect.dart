import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';

/// The SQL of SQLite: its column types and the way it stores dates,
/// booleans and big integers, and its result codes as data access
/// exceptions.
///
/// SQLite has no row locks: a `@Lock` query takes the write lock of the
/// whole database when its transaction begins (`BEGIN IMMEDIATE`), and the
/// only isolation level is serializable.
///
/// How values are stored:
///
/// - `int` and `bool` (0 or 1) as `INTEGER`; `double` and `num` as `REAL`;
/// - `String` and enums as `TEXT`;
/// - `DateTime` as an ISO-8601 `TEXT` in UTC (`2026-03-01T10:00:00.000Z`),
///   which sorts like the instant; an integer read back is taken as
///   milliseconds since the epoch;
/// - `Uint8List` and `List<int>` as `BLOB`;
/// - `BigInt` as `TEXT`, because an `INTEGER` holds 64 bits.
///
/// Spring (Java): `org.springframework.data.relational.core.dialect.
/// AnsiDialect` with the error codes of `SQLErrorCodeSQLExceptionTranslator`
/// for SQLite.
final class SqliteDialect extends SqlDialect {
  /// The dialect of SQLite.
  const SqliteDialect();

  // Primary result codes of SQLite (https://sqlite.org/rescode.html).
  static const _error = 1;
  static const _busy = 5;
  static const _locked = 6;
  static const _readOnly = 8;
  static const _interrupt = 9;
  static const _ioError = 10;
  static const _corrupt = 11;
  static const _cantOpen = 14;
  static const _constraint = 19;
  static const _notADatabase = 26;

  // Extended result codes of the constraint family.
  static const _primaryKey = 1555;
  static const _unique = 2067;

  /// The name of the SQL function the driver registers on each connection:
  /// `lower` of Dart's `String.toLowerCase`.
  static const lowerFunction = 'spring_lower';

  @override
  String get name => 'sqlite';

  /// SQLite's own `lower` folds ASCII letters only, so `ignoreCase` would
  /// not match `Ä` with `ä` as the in-memory store does: the driver's
  /// [lowerFunction] folds them all.
  @override
  String lower(String expression) => '$lowerFunction($expression)';

  /// SQLite's default `SQLITE_MAX_VARIABLE_NUMBER` (since 3.32).
  @override
  int? get maxBoundParameters => 32766;

  @override
  List<String> get beforeDropStatements => const [
    'PRAGMA defer_foreign_keys = ON',
  ];

  @override
  bool get likeIgnoresCase => true;

  @override
  LockStrategy get lockStrategy => LockStrategy.databaseLock;

  @override
  String lockClause(
    LockMode mode, {
    Duration? timeout,
    bool skipLocked = false,
  }) => '';

  @override
  String identityColumn(TypeInfo<Object?> type) => 'INTEGER PRIMARY KEY';

  @override
  Set<Isolation> get isolationLevels => const {
    Isolation.defaultLevel,
    Isolation.serializable,
  };

  // --------------------------------------------------------------- schema

  /// Reads `PRAGMA table_info(<table>)`: name, declared type, `notnull`,
  /// `dflt_value` and `pk` of each column. The [schema] is the name of an
  /// attached database.
  @override
  Future<List<ColumnInfo>?> describeTable(
    JdbcConnection connection,
    String table, [
    String? schema,
  ]) async {
    final prefix = schema == null ? '' : '${quote(schema)}.';
    final result = await connection.query(
      'PRAGMA ${prefix}table_info(${quote(table)})',
    );
    return [
      for (final row in result.rows)
        ColumnInfo(
          name: row['name']! as String,
          type: (row['type'] as String?) ?? '',
          notNull: row['notnull'] == 1,
          defaultValue: row['dflt_value'] as String?,
          primaryKey: ((row['pk'] as int?) ?? 0) > 0,
        ),
    ];
  }

  /// Reads `PRAGMA foreign_key_list(<table>)`.
  @override
  Future<List<ForeignKeyInfo>?> describeForeignKeys(
    JdbcConnection connection,
    String table, [
    String? schema,
  ]) async {
    final prefix = schema == null ? '' : '${quote(schema)}.';
    final result = await connection.query(
      'PRAGMA ${prefix}foreign_key_list(${quote(table)})',
    );
    // A composite key has one row for each column; the starter writes
    // single column keys only, so those are the ones listed.
    final sizes = <Object?, int>{};
    for (final row in result.rows) {
      sizes[row['id']] = (sizes[row['id']] ?? 0) + 1;
    }
    return [
      for (final row in result.rows)
        if (sizes[row['id']] == 1)
          ForeignKeyInfo(
            column: row['from']! as String,
            parentTable: row['table']! as String,
            parentColumn: row['to'] as String?,
            onDelete: switch ((row['on_delete'] as String?)?.toUpperCase()) {
              'NO ACTION' => OnDeleteAction.noAction,
              'RESTRICT' => OnDeleteAction.restrict,
              'CASCADE' => OnDeleteAction.cascade,
              'SET NULL' => OnDeleteAction.setNull,
              'SET DEFAULT' => OnDeleteAction.setDefault,
              _ => null,
            },
          ),
    ];
  }

  /// Reads `PRAGMA index_list(<table>)` and `index_info(<index>)`: the
  /// unique indexes that are not partial, which include the `UNIQUE`
  /// constraints (SQLite makes them `sqlite_autoindex_*` indexes) and the
  /// primary key of a table that is not a rowid alias.
  @override
  Future<List<UniqueInfo>?> describeUniqueKeys(
    JdbcConnection connection,
    String table, [
    String? schema,
  ]) async {
    final prefix = schema == null ? '' : '${quote(schema)}.';
    final indexes = await connection.query(
      'PRAGMA ${prefix}index_list(${quote(table)})',
    );
    final keys = <UniqueInfo>[];
    for (final index in indexes.rows) {
      if (index['unique'] != 1 || index['partial'] == 1) {
        continue;
      }
      final name = index['name']! as String;
      final info = await connection.query(
        'PRAGMA ${prefix}index_info(${quote(name)})',
      );
      keys.add(
        UniqueInfo([
          for (final column in info.rows) column['name']! as String,
        ], name: name),
      );
    }
    // An `INTEGER PRIMARY KEY` is the rowid itself and has no index.
    final columns = await describeTable(connection, table, schema);
    final primary = [
      for (final column in columns ?? const <ColumnInfo>[])
        if (column.primaryKey) column.name,
    ];
    if (primary.length == 1 &&
        !keys.any(
          (k) => k.columns.length == 1 && k.columns.single == primary.single,
        )) {
      keys.add(UniqueInfo(primary));
    }
    return keys;
  }

  @override
  Future<List<String>?> listTables(JdbcConnection connection) async {
    final result = await connection.query(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      r"AND name NOT LIKE 'sqlite\_%' ESCAPE '\' ORDER BY name",
    );
    return [for (final row in result.rows) row['name']! as String];
  }

  // ---------------------------------------------------------------- types

  @override
  String? columnType(TypeInfo<Object?> type) => switch (_Affinity.of(type)) {
    _Affinity.integer => 'INTEGER',
    _Affinity.real => 'REAL',
    _Affinity.text => 'TEXT',
    _Affinity.blob => 'BLOB',
    null => null,
  };

  /// Applies SQLite's rules for the affinity of a declared type: `INT`
  /// makes it integer; `CHAR`, `CLOB` or `TEXT` text; `BLOB` or nothing
  /// none (any value fits); `REAL`, `FLOA` or `DOUB` real; anything else
  /// numeric. A numeric column holds integers and reals alike; a declared
  /// `DATE`, `DATETIME` or `TIMESTAMP` also fits a `DateTime`.
  @override
  bool columnFits(String declared, TypeInfo<Object?> type) {
    final wanted = _Affinity.of(type);
    if (wanted == null) {
      return false;
    }
    final upper = declared.toUpperCase();
    // `DATETIME` and `TIMESTAMP` have numeric affinity, which keeps the
    // ISO text of a DateTime as it is.
    if (type.type == DateTime &&
        (upper.contains('DATE') || upper.contains('TIME'))) {
      return true;
    }
    if (upper.contains('INT')) {
      return wanted == _Affinity.integer || wanted == _Affinity.real;
    }
    if (upper.contains('CHAR') ||
        upper.contains('CLOB') ||
        upper.contains('TEXT')) {
      return wanted == _Affinity.text;
    }
    if (upper.isEmpty || upper.contains('BLOB')) {
      return true;
    }
    if (upper.contains('REAL') ||
        upper.contains('FLOA') ||
        upper.contains('DOUB')) {
      return wanted == _Affinity.real;
    }
    // Numeric affinity.
    return wanted == _Affinity.integer || wanted == _Affinity.real;
  }

  // --------------------------------------------------------------- values

  @override
  Object? toDatabase(Object? value) => switch (value) {
    DateTime() => value.toUtc().toIso8601String(),
    bool() => value ? 1 : 0,
    BigInt() => value.toString(),
    Uint8List() => value,
    List<int>() => Uint8List.fromList(value),
    _ => value,
  };

  @override
  Object? fromDatabase(Object? value, TypeInfo<Object?> type) {
    if (value == null) {
      return null;
    }
    final wanted = type.type;
    if (wanted == DateTime) {
      return switch (value) {
        String() => _utc(DateTime.parse(value)),
        int() => DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
        _ => value,
      };
    }
    if (wanted == bool) {
      return switch (value) {
        int() => value != 0,
        String() => value == '1' || value.toLowerCase() == 'true',
        _ => value,
      };
    }
    if (wanted == BigInt) {
      return switch (value) {
        String() => BigInt.parse(value),
        int() => BigInt.from(value),
        _ => value,
      };
    }
    if (wanted == double) {
      return value is int ? value.toDouble() : value;
    }
    if (wanted == Uint8List || type is ListType<int>) {
      return value is List<int> && value is! Uint8List
          ? Uint8List.fromList(value)
          : value;
    }
    return value;
  }

  // A date without a zone is UTC here, as it was written.
  static DateTime _utc(DateTime parsed) => parsed.isUtc
      ? parsed
      : DateTime.utc(
          parsed.year,
          parsed.month,
          parsed.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
          parsed.millisecond,
          parsed.microsecond,
        );

  // --------------------------------------------------------------- errors

  @override
  DataAccessException translate(SqlError error, {String? sql}) {
    final statement = sql ?? error.sql;
    final code =
        error.vendorCode ??
        (error.extendedCode == null ? null : error.extendedCode! & 0xFF);
    final message = error.message;
    switch (code) {
      case _constraint:
        final constraint = error.constraint ?? _constraintOf(message);
        return switch (error.extendedCode) {
          _primaryKey || _unique => DuplicateKeyException(
            message,
            cause: error,
            sql: statement,
            constraint: constraint,
          ),
          _ => DataIntegrityViolationException(
            message,
            cause: error,
            sql: statement,
            constraint: constraint,
          ),
        };
      case _busy || _locked:
        return CannotAcquireLockException(
          message,
          cause: error,
          sql: statement,
        );
      case _interrupt:
        return QueryTimeoutException(message, cause: error, sql: statement);
      case _readOnly:
        return InvalidDataAccessResourceUsageException(
          message,
          cause: error,
          sql: statement,
        );
      case _error when _isGrammar(message):
        return BadSqlGrammarException(message, cause: error, sql: statement);
      case _cantOpen || _ioError || _corrupt || _notADatabase:
        return DataAccessResourceFailureException(
          message,
          cause: error,
          sql: statement,
        );
    }
    return unknown(error, sql: statement);
  }

  // `UNIQUE constraint failed: books.isbn` -> `books.isbn`; the messages of
  // foreign keys carry no name.
  static String? _constraintOf(String message) {
    final colon = message.indexOf(' constraint failed: ');
    if (colon < 0) {
      return null;
    }
    final name = message.substring(colon + ' constraint failed: '.length);
    return name.isEmpty ? null : name;
  }

  static bool _isGrammar(String message) {
    final text = message.toLowerCase();
    return text.contains('no such table') ||
        text.contains('no such column') ||
        text.contains('no such function') ||
        text.contains('has no column named') ||
        text.contains('syntax error') ||
        text.contains('incomplete input');
  }
}

// The affinity a property type asks of its column.
enum _Affinity {
  integer,
  real,
  text,
  blob;

  static _Affinity? of(TypeInfo<Object?> type) {
    if (type is EnumType) {
      return text;
    }
    if (type is ListType<int>) {
      return blob;
    }
    final dart = type.type;
    if (dart == int || dart == bool) {
      return integer;
    }
    if (dart == double || dart == num) {
      return real;
    }
    if (dart == String || dart == DateTime || dart == BigInt) {
      return text;
    }
    if (dart == Uint8List) {
      return blob;
    }
    return null;
  }
}
