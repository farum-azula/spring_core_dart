import 'dart:async';

import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';

/// A database driver, as the starter sees it: opens connections for the
/// URLs of its [schemes].
///
/// The starter has no driver inside. The application lists the driver
/// package it wants (`sqlite3`, `postgres`), and the generator, seeing it
/// among the application's dependencies, writes the adapter implementing
/// this interface into the generated module (Spring Boot's
/// `@ConditionalOnClass` on the JDBC driver). `spring.datasource.url`
/// chooses the driver by its scheme (`sqlite:`, `postgresql:`).
///
/// Spring (Java): `java.sql.Driver`.
abstract interface class JdbcDriver {
  /// The driver package's name, for messages (`sqlite3`).
  String get name;

  /// The URL schemes it opens (`sqlite`).
  List<String> get schemes;

  /// The SQL of its database.
  SqlDialect get dialect;

  /// Opens a connection to the database of [settings].
  ///
  /// Throws a [SqlError] (translated by the caller) when it cannot.
  Future<JdbcConnection> connect(ConnectionSettings settings);
}

/// Where and how to connect: the parsed `spring.datasource.*` (or
/// `spring.datasources.<name>.*`) properties.
///
/// Spring (Java): `DataSourceProperties`.
final class ConnectionSettings {
  /// The settings of a database at [url].
  const ConnectionSettings({
    required this.url,
    this.username,
    this.password,
    this.properties = const {},
  });

  /// The URL: `sqlite:file:books.db`, `sqlite::memory:`,
  /// `postgresql://db:5432/shop`.
  final Uri url;

  /// The user, when the URL does not carry it.
  final String? username;

  /// The password, when the URL does not carry it. Never logged.
  final String? password;

  /// Driver-specific settings (`spring.datasource.<driver>.*`), by name.
  final Map<String, String> properties;

  /// The URL as it may be logged: without its password.
  String get safeUrl {
    if (url.userInfo.isEmpty) {
      return url.toString();
    }
    final user = url.userInfo.split(':').first;
    return url.replace(userInfo: user.isEmpty ? '' : user).toString();
  }

  @override
  String toString() => 'ConnectionSettings($safeUrl)';
}

/// One open connection to a database.
///
/// Statements use `?` for each parameter, in order, whatever the database
/// (an adapter rewrites them to its own markers, `$1` for PostgreSQL);
/// values are always sent as parameters, never written into the SQL text.
/// The values are the database's own Dart types, as the [SqlDialect]
/// converts them (`int`, `double`, `String`, `bool`, `Uint8List`,
/// `DateTime`, `BigInt`, `null`).
///
/// A connection runs one statement at a time: two statements started at
/// once (`Future.wait` in one transaction) run in turn, never interleaved
/// on the wire. Every failure is a [SqlError].
///
/// Spring (Java): `java.sql.Connection`.
abstract interface class JdbcConnection {
  /// Runs the query [sql] with [parameters] and returns its rows.
  Future<JdbcResult> query(String sql, [List<Object?> parameters = const []]);

  /// Runs the query [sql] and gives its rows one by one, without holding
  /// them all in memory; cancelling the subscription ends the query.
  Stream<JdbcRow> queryStream(
    String sql, [
    List<Object?> parameters = const [],
  ]);

  /// Runs the change [sql] (insert, update, delete) and returns the rows
  /// changed and, with [returnGeneratedKey], the key the database gave an
  /// inserted row: SQLite's `rowid`; PostgreSQL's `RETURNING` of
  /// [keyColumn] (the first column of the row without it).
  Future<JdbcUpdate> update(
    String sql, [
    List<Object?> parameters = const [],
    bool returnGeneratedKey = false,
    String? keyColumn,
  ]);

  /// Runs [sql] once for each parameter list of [batch]; returns the rows
  /// changed by each.
  Future<List<int>> batchUpdate(String sql, List<List<Object?>> batch);

  /// Runs [sql] without parameters and without results: DDL, `PRAGMA`,
  /// several statements separated by `;` (a migration).
  Future<void> execute(String sql);

  /// Begins a transaction with [isolation] (a level the database does not
  /// offer: `InvalidIsolationLevelException`, never a weaker one), read
  /// only when [readOnly]; with [lockForWrite], the database's way to take
  /// the write lock at once (SQLite's `BEGIN IMMEDIATE`, used for `@Lock`).
  Future<void> begin({
    Isolation isolation = Isolation.defaultLevel,
    bool readOnly = false,
    bool lockForWrite = false,
  });

  /// Commits the transaction.
  Future<void> commit();

  /// Rolls the transaction back.
  Future<void> rollback();

  /// Creates the savepoint [name] in the transaction.
  Future<void> savepoint(String name);

  /// Rolls back to the savepoint [name].
  Future<void> rollbackToSavepoint(String name);

  /// Releases the savepoint [name].
  Future<void> releaseSavepoint(String name);

  /// Bounds the next statements to [timeout] (null: none); a statement
  /// past it is cancelled with a [SqlError] the dialect translates into a
  /// `QueryTimeoutException`. A database without it ignores it.
  Future<void> setStatementTimeout(Duration? timeout);

  /// Whether the connection still works (for the pool before handing it
  /// out).
  Future<bool> isValid();

  /// Whether [close] was called or the connection broke.
  bool get isClosed;

  /// Closes the connection.
  Future<void> close();
}

/// The rows of a query.
///
/// Spring (Java): `java.sql.ResultSet`, read whole.
final class JdbcResult {
  /// [rows] of the [columns] (labels, in the query's order).
  JdbcResult(List<String> columns, List<List<Object?>> rows)
    : columns = List.unmodifiable(columns),
      rows = [
        for (final values in rows) JdbcRow._(columns, values),
      ];

  /// The column labels, in order.
  final List<String> columns;

  /// The rows.
  final List<JdbcRow> rows;

  /// Whether there are no rows.
  bool get isEmpty => rows.isEmpty;
}

/// One row of a query: its values by position or by column label (labels
/// compared without case, as JDBC does).
///
/// Spring (Java): one row of `java.sql.ResultSet`.
final class JdbcRow {
  /// A row of [values] for [columns].
  JdbcRow(List<String> columns, List<Object?> values) : this._(columns, values);

  JdbcRow._(this.columns, List<Object?> values)
    : values = List.unmodifiable(values) {
    if (values.length != columns.length) {
      throw ArgumentError(
        '${values.length} value(s) for ${columns.length} column(s)',
      );
    }
  }

  /// The column labels, in order.
  final List<String> columns;

  /// The values, in the order of [columns].
  final List<Object?> values;

  /// The value of the column labelled [column] (any case); throws an
  /// [ArgumentError] when there is none.
  Object? operator [](String column) {
    final index = indexOf(column);
    if (index < 0) {
      throw ArgumentError.value(
        column,
        'column',
        'No such column; the row has ${columns.join(', ')}',
      );
    }
    return values[index];
  }

  /// The position of the column labelled [column] (any case), or -1.
  int indexOf(String column) {
    final wanted = column.toLowerCase();
    for (var i = 0; i < columns.length; i++) {
      if (columns[i].toLowerCase() == wanted) {
        return i;
      }
    }
    return -1;
  }

  /// Whether the row has a column labelled [column] (any case).
  bool has(String column) => indexOf(column) >= 0;

  /// The row as a map from column label to value.
  Map<String, Object?> toMap() => {
    for (var i = 0; i < columns.length; i++) columns[i]: values[i],
  };

  @override
  String toString() => 'JdbcRow(${columns.join(', ')})';
}

/// What a change did.
final class JdbcUpdate {
  /// [affectedRows] changed; [generatedKey] given to an inserted row.
  const JdbcUpdate(this.affectedRows, [this.generatedKey]);

  /// The number of rows changed.
  final int affectedRows;

  /// The key the database gave the inserted row (SQLite's `rowid`, a
  /// PostgreSQL identity through `RETURNING`), when asked for.
  final Object? generatedKey;
}

/// A driver's error, in the same shape for every database: the starter's
/// dialect translates it into a `DataAccessException`.
///
/// It carries what is needed to understand the error, never the values of
/// the statement.
///
/// Spring (Java): `java.sql.SQLException`.
final class SqlError implements Exception {
  /// An error of the database, described by [message].
  const SqlError(
    this.message, {
    this.sqlState,
    this.vendorCode,
    this.extendedCode,
    this.constraint,
    this.sql,
    this.cause,
    this.connectionLost = false,
  });

  /// The database's message.
  final String message;

  /// The SQL state (PostgreSQL's five characters, `23505`); null when the
  /// database has none (SQLite).
  final String? sqlState;

  /// The database's own error code (SQLite's primary result code, `19`
  /// for a constraint).
  final int? vendorCode;

  /// A finer code when the database has one (SQLite's extended result
  /// code, `2067` for a unique constraint).
  final int? extendedCode;

  /// The name of the broken constraint, when the database gives it.
  final String? constraint;

  /// The statement, with its `?` markers and without values.
  final String? sql;

  /// The driver's exception.
  final Object? cause;

  /// Whether the connection is gone (the pool must drop it).
  final bool connectionLost;

  @override
  String toString() {
    final out = StringBuffer('SqlError: $message');
    if (sqlState case final state?) {
      out.write(' (SQL state $state)');
    }
    if (vendorCode case final code?) {
      out.write(' (code $code${extendedCode == null ? '' : '/$extendedCode'})');
    }
    return out.toString();
  }
}
