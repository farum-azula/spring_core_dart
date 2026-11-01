import 'dart:async';

import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_binding.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_dialect.dart';

// What the SQLite connection runs on a database, in two places: in the
// isolate that asks (LocalSqliteEngine) or on a worker isolate of its own
// (WorkerSqliteEngine, in sqlite_worker.dart). Both run the same commands
// over the same SqliteSession, so a connection behaves the same on either.

/// The rows of a query: the column names and the values of each row.
typedef SqliteRows = ({List<String> columns, List<List<Object?>> rows});

/// A batch of the rows of a cursor; `done` when there are no more.
typedef SqliteBatch = ({
  List<String> columns,
  List<List<Object?>> rows,
  bool done,
});

/// What to open and how to set it up.
///
/// It crosses to a worker isolate, so it holds plain values only.
final class SqliteOpenRequest {
  /// Opens [filename] in [mode] (as a SQLite URI when [uri]); [wal] switches
  /// the journal to WAL, [busyTimeout] is how long a lock is waited for.
  const SqliteOpenRequest({
    required this.filename,
    required this.mode,
    required this.uri,
    required this.wal,
    required this.busyTimeout,
  });

  /// The path, `:memory:` or the `file:` URI.
  final String filename;

  /// How the file is opened.
  final SqliteOpenMode mode;

  /// Whether [filename] is a SQLite URI.
  final bool uri;

  /// Whether to switch the database to the WAL journal.
  final bool wal;

  /// The `busy_timeout`.
  final Duration busyTimeout;
}

/// Opens the database of [request] through [binding] and sets it up: the
/// pragmas and the functions the driver relies on.
SqliteDatabase openSqliteDatabase(
  SqliteBinding binding,
  SqliteOpenRequest request,
) {
  final database = binding.open(
    request.filename,
    mode: request.mode,
    uri: request.uri,
  );
  try {
    database
      ..execute('PRAGMA busy_timeout = ${request.busyTimeout.inMilliseconds}')
      ..execute('PRAGMA foreign_keys = ON')
      ..createFunction(
        SqliteDialect.lowerFunction,
        1,
        (arguments) => switch (arguments.first) {
          final String text => text.toLowerCase(),
          final other => other,
        },
      );
    if (request.wal) {
      database.execute('PRAGMA journal_mode = WAL');
    }
  } on Object {
    database.close();
    rethrow;
  }
  return database;
}

/// One open database and what a connection does on it, synchronously.
///
/// It keeps what lives between two calls: the open cursor of a stream and
/// the read-only mode of a transaction.
final class SqliteSession {
  /// A session on a database.
  SqliteSession(this._database);

  final SqliteDatabase _database;
  SqliteCursor? _cursor;
  bool _readOnlyTransaction = false;
  bool _closed = false;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// Runs [sql] and returns its rows.
  SqliteRows select(String sql, List<Object?> parameters) =>
      _database.select(sql, parameters);

  /// Runs the change [sql]; with [returnGeneratedKey], the new row's key.
  JdbcUpdate update(
    String sql,
    List<Object?> parameters,
    bool returnGeneratedKey,
  ) {
    _database.execute(sql, parameters);
    return JdbcUpdate(
      _database.updatedRows,
      returnGeneratedKey ? _database.lastInsertRowId : null,
    );
  }

  /// Runs [sql] for each of [batch]; returns the rows each changed.
  List<int> batch(String sql, List<List<Object?>> batch) => [
    for (final parameters in batch)
      (_database..execute(sql, parameters)).updatedRows,
  ];

  /// Runs [sql] without parameters.
  void execute(String sql) => _database.execute(sql);

  /// Starts a transaction.
  void begin({required bool readOnly, required bool lockForWrite}) {
    if (readOnly) {
      _database.execute('PRAGMA query_only = ON');
      _readOnlyTransaction = true;
    }
    try {
      _database.execute(lockForWrite ? 'BEGIN IMMEDIATE' : 'BEGIN DEFERRED');
    } on Object {
      _endReadOnly();
      rethrow;
    }
  }

  /// Commits the transaction.
  void commit() {
    try {
      _database.execute('COMMIT');
    } finally {
      // A failed COMMIT (BUSY) leaves the transaction open: the caller
      // rolls it back, which ends the read-only mode.
      if (_database.autocommit) {
        _endReadOnly();
      }
    }
  }

  /// Rolls the transaction back.
  void rollback() {
    try {
      // After some errors SQLite has already rolled back.
      if (!_database.autocommit) {
        _database.execute('ROLLBACK');
      }
    } finally {
      _endReadOnly();
    }
  }

  void _endReadOnly() {
    if (_readOnlyTransaction) {
      _readOnlyTransaction = false;
      _database.execute('PRAGMA query_only = OFF');
    }
  }

  /// Starts [sql] as the session's cursor.
  void openCursor(String sql, List<Object?> parameters) {
    closeCursor();
    _cursor = _database.cursor(sql, parameters);
  }

  /// Reads up to [count] rows of the cursor.
  SqliteBatch fetch(int count) {
    final cursor = _cursor;
    if (cursor == null) {
      throw StateError('No cursor is open');
    }
    final rows = <List<Object?>>[];
    var done = false;
    while (rows.length < count) {
      final row = cursor.next();
      if (row == null) {
        done = true;
        break;
      }
      rows.add(row);
    }
    // Reliable after the first read, which has happened by now.
    return (columns: cursor.columns, rows: rows, done: done);
  }

  /// Releases the cursor, if there is one.
  void closeCursor() {
    final cursor = _cursor;
    _cursor = null;
    cursor?.close();
  }

  /// Closes the database.
  void close() {
    if (!_closed) {
      _closed = true;
      _database.close();
    }
  }
}

/// One thing a connection asks of its [SqliteSession], with what it needs.
///
/// A command crosses to a worker isolate, so its fields are plain values
/// and its result is made of lists, records and `JdbcUpdate`.
abstract base class SqliteCommand<T> {
  /// A command.
  const SqliteCommand();

  /// Runs the command on [session].
  T run(SqliteSession session);
}

/// Runs a query and returns all its rows.
final class SelectCommand extends SqliteCommand<SqliteRows> {
  /// Selects [sql] with [parameters].
  const SelectCommand(this.sql, [this.parameters = const []]);

  /// The query.
  final String sql;

  /// Its values.
  final List<Object?> parameters;

  @override
  SqliteRows run(SqliteSession session) => session.select(sql, parameters);
}

/// Runs an insert, update or delete.
final class UpdateCommand extends SqliteCommand<JdbcUpdate> {
  /// Runs [sql] with [parameters].
  const UpdateCommand(this.sql, this.parameters, this.returnGeneratedKey);

  /// The statement.
  final String sql;

  /// Its values.
  final List<Object?> parameters;

  /// Whether to return the key of the inserted row.
  final bool returnGeneratedKey;

  @override
  JdbcUpdate run(SqliteSession session) =>
      session.update(sql, parameters, returnGeneratedKey);
}

/// Runs one statement for several lists of values.
final class BatchCommand extends SqliteCommand<List<int>> {
  /// Runs [sql] for each of [batch].
  const BatchCommand(this.sql, this.batch);

  /// The statement.
  final String sql;

  /// The values of each run.
  final List<List<Object?>> batch;

  @override
  List<int> run(SqliteSession session) => session.batch(sql, batch);
}

/// Runs statements without values and without results.
final class ExecuteCommand extends SqliteCommand<void> {
  /// Runs [sql].
  const ExecuteCommand(this.sql);

  /// The statements.
  final String sql;

  @override
  void run(SqliteSession session) => session.execute(sql);
}

/// Starts a transaction.
final class BeginCommand extends SqliteCommand<void> {
  /// Starts a transaction, read only or taking the write lock at once.
  const BeginCommand({required this.readOnly, required this.lockForWrite});

  /// Whether the transaction refuses writes.
  final bool readOnly;

  /// Whether it takes the write lock at once.
  final bool lockForWrite;

  @override
  void run(SqliteSession session) =>
      session.begin(readOnly: readOnly, lockForWrite: lockForWrite);
}

/// Commits the transaction.
final class CommitCommand extends SqliteCommand<void> {
  /// A commit.
  const CommitCommand();

  @override
  void run(SqliteSession session) => session.commit();
}

/// Rolls the transaction back.
final class RollbackCommand extends SqliteCommand<void> {
  /// A rollback.
  const RollbackCommand();

  @override
  void run(SqliteSession session) => session.rollback();
}

/// Starts a query whose rows [FetchCommand] reads.
final class OpenCursorCommand extends SqliteCommand<void> {
  /// Opens a cursor on [sql] with [parameters].
  const OpenCursorCommand(this.sql, this.parameters);

  /// The query.
  final String sql;

  /// Its values.
  final List<Object?> parameters;

  @override
  void run(SqliteSession session) => session.openCursor(sql, parameters);
}

/// Reads the next rows of the open cursor.
final class FetchCommand extends SqliteCommand<SqliteBatch> {
  /// Reads up to [count] rows.
  const FetchCommand(this.count);

  /// How many rows at most.
  final int count;

  @override
  SqliteBatch run(SqliteSession session) => session.fetch(count);
}

/// Releases the open cursor (none: nothing to do).
final class CloseCursorCommand extends SqliteCommand<void> {
  /// A close of the cursor.
  const CloseCursorCommand();

  @override
  void run(SqliteSession session) => session.closeCursor();
}

/// Closes the database. On a worker isolate, this ends the isolate too.
final class CloseCommand extends SqliteCommand<void> {
  /// A close.
  const CloseCommand();

  @override
  void run(SqliteSession session) => session.close();
}

/// Where a connection's commands run.
///
/// The connection gives it one command at a time.
abstract interface class SqliteEngine {
  /// How many rows a stream reads in one command.
  int get fetchSize;

  /// Whether the engine is gone for a reason other than [close] (the worker
  /// isolate died).
  bool get isBroken;

  /// Runs [command]; throws what the database or the binding throws.
  Future<T> run<T>(SqliteCommand<T> command);

  /// Closes the database and everything the engine holds.
  Future<void> close();
}

/// The engine that runs the commands in the isolate that asks: the calls to
/// SQLite are synchronous, so they hold that isolate.
final class LocalSqliteEngine implements SqliteEngine {
  /// Opens the database of [request] through [binding].
  LocalSqliteEngine(SqliteBinding binding, SqliteOpenRequest request)
    : _session = SqliteSession(openSqliteDatabase(binding, request));

  final SqliteSession _session;

  @override
  // A stream reads one row at a time, as the cursor is asked for it.
  int get fetchSize => 1;

  @override
  bool get isBroken => false;

  @override
  Future<T> run<T>(SqliteCommand<T> command) async => command.run(_session);

  @override
  Future<void> close() async => _session.close();
}
