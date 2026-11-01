import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_binding.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_dialect.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_engine.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_worker.dart';
import 'package:spring_boot_starter_data/src/jdbc/statement_mutex.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_exceptions.dart';

/// The driver of SQLite, written on a [SqliteBinding] (the generator wires
/// one over the `sqlite3` package when the application lists it).
///
/// The URLs it opens:
///
/// - `sqlite:file:books.db`: a file, relative to the `base-directory` of
///   the data source's [ConnectionSettings.properties]
///   (`spring.datasource.sqlite.base-directory`), else to [baseDirectory],
///   else to the working directory; `sqlite:books.db` is the same;
/// - `sqlite:file:/var/data/books.db`: an absolute path;
/// - `sqlite::memory:`: a private in-memory database. **Each connection
///   gets its own**, empty, database, so a data source on it must have one
///   connection (`maximum-pool-size: 1`), or a second connection sees none
///   of the tables of the first. A shared-cache URI
///   (`sqlite:file:name?mode=memory&cache=shared`) is passed on too, but
///   the SQLite that the `sqlite3` package bundles is built without shared
///   cache, so it does not share anything: use one connection, or a file
///   (in a temporary directory) when connections must share a database;
/// - `?mode=ro` (read only), `?mode=rw` (must exist), `?mode=rwc` (create,
///   the default) after a file; any other query (`cache`, `vfs`,
///   `immutable`...) makes the part after `sqlite:` a SQLite URI, passed on
///   as it is.
///
/// When it connects it registers `spring_lower` (a `lower` that folds
/// every letter, which SQLite's own does for ASCII ones only; the dialect
/// uses it for `ignoreCase`) and runs `PRAGMA foreign_keys = ON` (SQLite
/// does not check foreign keys by default), `journal_mode = WAL` for a
/// file that can be written (readers do not block the writer), and
/// `busy_timeout`: how long a connection waits for a lock another one
/// holds before it fails with `SQLITE_BUSY`, 5000 ms or the `busy-timeout` of
/// [ConnectionSettings.properties] (milliseconds). The wait is spent in
/// the driver's synchronous call, so it blocks the isolate: keep it short
/// in an interface, or give each connection an isolate of its own.
///
/// **A worker isolate.** SQLite's calls are synchronous: on Flutter they
/// hold the UI isolate, on a server the event loop. With `isolate: true`
/// (the data source's `spring.datasource.sqlite.isolate`, or the [isolate]
/// option) each connection opens its database inside an isolate of its own
/// and every statement is a message to it: a long query or a busy wait
/// holds that isolate only. The behaviour is the same: transactions,
/// savepoints, read-only mode, streams (read in batches, the cursor closed
/// when the stream is cancelled), the errors with their types. What
/// changes: values are copied between the isolates (a very large result
/// costs a copy), the parameters must be what SQLite stores (`int`,
/// `double`, `String`, `bool`, bytes, `null`; the dialect converts the
/// rest), the [binding] must be sendable (the generated one is), and a
/// connection must be closed, which ends its isolate (the pool does it
/// when the application closes). If the isolate dies, the pending and the
/// later statements fail with a `SqlError` whose `connectionLost` is true.
///
/// Spring (Java): `org.sqlite.JDBC` (xerial's `sqlite-jdbc`), with Spring
/// Boot's `DataSourceProperties` choosing it by the URL.
final class SqliteJdbcDriver implements JdbcDriver {
  /// A driver over [binding]; [baseDirectory] is where relative file names
  /// are looked for; with [isolate], each connection runs on a worker
  /// isolate.
  SqliteJdbcDriver(this.binding, {this.baseDirectory, this.isolate = false});

  /// What opens the databases.
  final SqliteBinding binding;

  /// The directory relative paths (`sqlite:file:books.db`) are resolved
  /// against; null keeps the working directory.
  ///
  /// This is the hook for platforms without a usable working directory;
  /// the Flutter starter sets the property `base-directory` of its data
  /// sources to the application's directory.
  String? baseDirectory;

  /// Whether each connection runs on a worker isolate; the data source's
  /// property `isolate` wins.
  bool isolate;

  static const _log = SpringLog('spring.jdbc.sqlite');

  /// The key of the base directory in [ConnectionSettings.properties]
  /// (`spring.datasource.sqlite.base-directory`): the directory of one data
  /// source, which wins over [baseDirectory].
  static const baseDirectoryProperty = 'base-directory';

  /// The key of the worker isolate switch in
  /// [ConnectionSettings.properties] (`spring.datasource.sqlite.isolate`,
  /// `true` or `false`): it wins over [isolate].
  static const isolateProperty = 'isolate';

  /// The default `busy_timeout`.
  static const defaultBusyTimeout = Duration(milliseconds: 5000);

  @override
  String get name => 'sqlite3';

  @override
  List<String> get schemes => const ['sqlite'];

  @override
  SqlDialect get dialect => const SqliteDialect();

  @override
  Future<JdbcConnection> connect(ConnectionSettings settings) async {
    final target = _Target.parse(
      settings.url,
      settings.properties[baseDirectoryProperty] ?? baseDirectory,
    );
    final busyTimeout = _busyTimeout(settings);
    final onWorker = _onWorker(settings);
    final request = SqliteOpenRequest(
      filename: target.filename,
      mode: target.mode,
      uri: target.uri,
      wal: target.writable && !target.memory,
      busyTimeout: busyTimeout,
    );
    final engine = onWorker
        ? await WorkerSqliteEngine.start(binding, request)
        : LocalSqliteEngine(binding, request);
    _log.debug(
      () =>
          'Opened ${settings.safeUrl} (busy timeout '
          '${busyTimeout.inMilliseconds} ms'
          '${onWorker ? ', on a worker isolate' : ''})',
    );
    return _SqliteConnection(engine);
  }

  bool _onWorker(ConnectionSettings settings) {
    final text = settings.properties[isolateProperty];
    if (text == null) {
      return isolate;
    }
    return switch (text.trim().toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => throw ArgumentError.value(
        text,
        isolateProperty,
        'Must be true or false',
      ),
    };
  }

  static Duration _busyTimeout(ConnectionSettings settings) {
    final text = settings.properties['busy-timeout'];
    if (text == null) {
      return defaultBusyTimeout;
    }
    final millis = int.tryParse(text.trim());
    if (millis == null || millis < 0) {
      throw ArgumentError.value(
        text,
        'busy-timeout',
        'Must be a number of milliseconds, zero or more',
      );
    }
    return Duration(milliseconds: millis);
  }
}

// Where a URL points, as the binding opens it.
final class _Target {
  _Target(
    this.filename,
    this.mode, {
    required this.uri,
    required this.memory,
  });

  final String filename;
  final SqliteOpenMode mode;
  final bool uri;
  final bool memory;

  bool get writable => mode != SqliteOpenMode.readOnly;

  static _Target parse(Uri url, String? baseDirectory) {
    var path = url.path;
    if (path.startsWith('file:')) {
      path = path.substring('file:'.length);
    }
    final query = url.queryParameters;
    final mode = switch (query['mode']) {
      null || 'rwc' => SqliteOpenMode.readWriteCreate,
      'rw' => SqliteOpenMode.readWrite,
      'ro' => SqliteOpenMode.readOnly,
      'memory' => SqliteOpenMode.readWriteCreate,
      final other => throw ArgumentError.value(
        other,
        'mode',
        'Unknown mode in ${url.toString().split('?').first}: expected '
            'ro, rw, rwc or memory',
      ),
    };
    if (path.isEmpty) {
      throw ArgumentError.value(
        url.toString(),
        'url',
        'No database: use sqlite:file:books.db or sqlite::memory:',
      );
    }
    if (path == ':memory:') {
      return _Target(':memory:', mode, uri: false, memory: true);
    }
    final memory = query['mode'] == 'memory';
    final resolved = memory ? path : _resolve(path, baseDirectory);
    final plain = query.keys.every((key) => key == 'mode') && !memory;
    if (plain) {
      return _Target(resolved, mode, uri: false, memory: false);
    }
    return _Target(
      'file:$resolved?${url.query}',
      mode,
      uri: true,
      memory: memory,
    );
  }

  static String _resolve(String path, String? baseDirectory) {
    final absolute =
        path.startsWith('/') ||
        path.startsWith(r'\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
    if (absolute || baseDirectory == null || baseDirectory.isEmpty) {
      return path;
    }
    return baseDirectory.endsWith('/')
        ? '$baseDirectory$path'
        : '$baseDirectory/$path';
  }
}

final class _SqliteConnection implements JdbcConnection {
  _SqliteConnection(this._engine);

  final SqliteEngine _engine;
  final _mutex = StatementMutex();
  bool _closed = false;

  // Runs [command] when it is this call's turn.
  Future<T> _run<T>(SqliteCommand<T> command) {
    if (_closed) {
      throw const SqlError('The connection is closed', connectionLost: true);
    }
    return _engine.run(command);
  }

  @override
  bool get isClosed => _closed || _engine.isBroken;

  @override
  Future<JdbcResult> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) => _mutex.run(() async {
    final result = await _run(SelectCommand(sql, parameters));
    return JdbcResult(result.columns, result.rows);
  });

  @override
  Stream<JdbcRow> queryStream(
    String sql, [
    List<Object?> parameters = const [],
  ]) async* {
    // The cursor is live on the connection until the stream ends or is
    // cancelled: nothing else runs meanwhile.
    final release = await _mutex.acquire();
    try {
      await _run(OpenCursorCommand(sql, parameters));
      var done = false;
      while (!done) {
        final batch = await _run(FetchCommand(_engine.fetchSize));
        done = batch.done;
        for (final row in batch.rows) {
          yield JdbcRow(batch.columns, row);
        }
      }
    } finally {
      try {
        await _run(const CloseCursorCommand());
      } finally {
        release();
      }
    }
  }

  @override
  Future<JdbcUpdate> update(
    String sql, [
    List<Object?> parameters = const [],
    bool returnGeneratedKey = false,
    String? keyColumn,
  ]) => _mutex.run(
    () => _run(UpdateCommand(sql, parameters, returnGeneratedKey)),
  );

  @override
  Future<List<int>> batchUpdate(String sql, List<List<Object?>> batch) =>
      _mutex.run(() => _run(BatchCommand(sql, batch)));

  @override
  Future<void> execute(String sql) =>
      _mutex.run(() => _run(ExecuteCommand(sql)));

  @override
  Future<void> begin({
    Isolation isolation = Isolation.defaultLevel,
    bool readOnly = false,
    bool lockForWrite = false,
  }) async {
    const dialect = SqliteDialect();
    if (!dialect.isolationLevels.contains(isolation)) {
      throw InvalidIsolationLevelException(
        'SQLite offers only the serializable isolation level, not '
        '${isolation.name}',
      );
    }
    await _mutex.run(
      () => _run(BeginCommand(readOnly: readOnly, lockForWrite: lockForWrite)),
    );
  }

  @override
  Future<void> commit() => _mutex.run(() => _run(const CommitCommand()));

  @override
  Future<void> rollback() => _mutex.run(() => _run(const RollbackCommand()));

  @override
  Future<void> savepoint(String name) =>
      _mutex.run(() => _run(ExecuteCommand('SAVEPOINT ${_quote(name)}')));

  @override
  Future<void> rollbackToSavepoint(String name) =>
      _mutex.run(() => _run(ExecuteCommand('ROLLBACK TO ${_quote(name)}')));

  @override
  Future<void> releaseSavepoint(String name) =>
      _mutex.run(() => _run(ExecuteCommand('RELEASE ${_quote(name)}')));

  static String _quote(String name) => '"${name.replaceAll('"', '""')}"';

  /// Ignored: the `sqlite3` package has no way to interrupt a statement
  /// (no `sqlite3_interrupt`, no progress handler), and its calls are
  /// synchronous, so nothing could run to cancel one. A statement past a
  /// timeout runs to its end; only the `busy_timeout` bounds waiting for a
  /// lock.
  @override
  Future<void> setStatementTimeout(Duration? timeout) async {}

  @override
  Future<bool> isValid() async {
    if (isClosed) {
      return false;
    }
    try {
      await _mutex.run(() => _run(const SelectCommand('SELECT 1')));
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    // After the statement running now.
    await _mutex.run(() {
      if (_closed) {
        return null;
      }
      _closed = true;
      return _engine.close();
    });
  }
}
