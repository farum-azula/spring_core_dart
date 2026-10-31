import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_binding.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_dialect.dart';
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
/// in an interface.
///
/// Spring (Java): `org.sqlite.JDBC` (xerial's `sqlite-jdbc`), with Spring
/// Boot's `DataSourceProperties` choosing it by the URL.
final class SqliteJdbcDriver implements JdbcDriver {
  /// A driver over [binding]; [baseDirectory] is where relative file names
  /// are looked for.
  SqliteJdbcDriver(this.binding, {this.baseDirectory});

  /// What opens the databases.
  final SqliteBinding binding;

  /// The directory relative paths (`sqlite:file:books.db`) are resolved
  /// against; null keeps the working directory.
  ///
  /// This is the hook for platforms without a usable working directory:
  /// the Flutter starter will set it to the application's documents
  /// directory.
  String? baseDirectory;

  static const _log = SpringLog('spring.jdbc.sqlite');

  /// The key of the base directory in [ConnectionSettings.properties]
  /// (`spring.datasource.sqlite.base-directory`): the directory of one data
  /// source, which wins over [baseDirectory].
  static const baseDirectoryProperty = 'base-directory';

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
    final database = binding.open(
      target.filename,
      mode: target.mode,
      uri: target.uri,
    );
    try {
      database
        ..execute('PRAGMA busy_timeout = ${busyTimeout.inMilliseconds}')
        ..execute('PRAGMA foreign_keys = ON')
        ..createFunction(
          SqliteDialect.lowerFunction,
          1,
          (arguments) => switch (arguments.first) {
            final String text => text.toLowerCase(),
            final other => other,
          },
        );
      if (target.writable && !target.memory) {
        database.execute('PRAGMA journal_mode = WAL');
      }
    } on Object {
      database.close();
      rethrow;
    }
    _log.debug(
      () =>
          'Opened ${settings.safeUrl} (busy timeout '
          '${busyTimeout.inMilliseconds} ms)',
    );
    return _SqliteConnection(database);
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

// Runs one action at a time, in the order they were asked.
final class _Mutex {
  Future<void> _tail = Future.value();

  // The action's turn: completes once the earlier ones are done; the
  // returned function gives the turn up.
  Future<void Function()> acquire() {
    final done = Completer<void>();
    final turn = _tail.then(
      (_) =>
          () => done.complete(),
    );
    _tail = done.future;
    return turn;
  }

  Future<T> run<T>(FutureOr<T> Function() action) async {
    final release = await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }
}

final class _SqliteConnection implements JdbcConnection {
  _SqliteConnection(this._database);

  final SqliteDatabase _database;
  final _mutex = _Mutex();
  bool _closed = false;
  bool _readOnlyTransaction = false;

  SqliteDatabase get _open {
    if (_closed) {
      throw const SqlError('The connection is closed', connectionLost: true);
    }
    return _database;
  }

  @override
  bool get isClosed => _closed;

  @override
  Future<JdbcResult> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) => _mutex.run(() {
    final result = _open.select(sql, parameters);
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
    SqliteCursor? cursor;
    try {
      cursor = _open.cursor(sql, parameters);
      var row = cursor.next();
      final columns = cursor.columns;
      while (row != null) {
        yield JdbcRow(columns, row);
        row = cursor.next();
      }
    } finally {
      try {
        cursor?.close();
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
  ]) => _mutex.run(() {
    final database = _open..execute(sql, parameters);
    return JdbcUpdate(
      database.updatedRows,
      returnGeneratedKey ? database.lastInsertRowId : null,
    );
  });

  @override
  Future<List<int>> batchUpdate(String sql, List<List<Object?>> batch) =>
      _mutex.run(() {
        final database = _open;
        return [
          for (final parameters in batch)
            (database..execute(sql, parameters)).updatedRows,
        ];
      });

  @override
  Future<void> execute(String sql) => _mutex.run(() => _open.execute(sql));

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
    await _mutex.run(() {
      final database = _open;
      if (readOnly) {
        database.execute('PRAGMA query_only = ON');
        _readOnlyTransaction = true;
      }
      try {
        database.execute(lockForWrite ? 'BEGIN IMMEDIATE' : 'BEGIN DEFERRED');
      } on Object {
        _endReadOnly(database);
        rethrow;
      }
    });
  }

  @override
  Future<void> commit() => _mutex.run(() {
    final database = _open;
    try {
      database.execute('COMMIT');
    } finally {
      // A failed COMMIT (BUSY) leaves the transaction open: the caller
      // rolls it back, which ends the read-only mode.
      if (database.autocommit) {
        _endReadOnly(database);
      }
    }
  });

  @override
  Future<void> rollback() => _mutex.run(() {
    final database = _open;
    try {
      // After some errors SQLite has already rolled back.
      if (!database.autocommit) {
        database.execute('ROLLBACK');
      }
    } finally {
      _endReadOnly(database);
    }
  });

  void _endReadOnly(SqliteDatabase database) {
    if (_readOnlyTransaction) {
      _readOnlyTransaction = false;
      database.execute('PRAGMA query_only = OFF');
    }
  }

  @override
  Future<void> savepoint(String name) =>
      _mutex.run(() => _open.execute('SAVEPOINT ${_quote(name)}'));

  @override
  Future<void> rollbackToSavepoint(String name) =>
      _mutex.run(() => _open.execute('ROLLBACK TO ${_quote(name)}'));

  @override
  Future<void> releaseSavepoint(String name) =>
      _mutex.run(() => _open.execute('RELEASE ${_quote(name)}'));

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
    if (_closed) {
      return false;
    }
    try {
      await _mutex.run(() => _open.select('SELECT 1'));
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
        return;
      }
      _closed = true;
      _database.close();
    });
  }
}
