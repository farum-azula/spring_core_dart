import 'dart:async';
import 'dart:collection';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_session_hook.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';

/// A connection could not be had: the database is down, the pool is
/// closed, or every connection of the pool stayed in use for the whole
/// `connection-timeout`.
///
/// Spring (Java): `org.springframework.jdbc.CannotGetJdbcConnectionException`.
class CannotGetJdbcConnectionException
    extends DataAccessResourceFailureException {
  /// A connection not had, described by [message].
  CannotGetJdbcConnectionException(super.message, {super.cause});
}

/// A source of connections to one database: its [name] for logs, the
/// [driver] that opens them and the connection [settings].
///
/// Code takes a connection with [getConnection] and gives it back with
/// [releaseConnection]; it does not close it. Inside a transaction use
/// `DataSourceUtils`, which hands out the transaction's connection.
///
/// Spring (Java): `javax.sql.DataSource`.
abstract class DataSource {
  /// A data source called [name] over [driver], connecting as [settings].
  DataSource({
    required this.name,
    required this.driver,
    required this.settings,
  });

  /// The name in logs (`shop`); `default` for the main database.
  final String name;

  /// The driver opening the connections.
  final JdbcDriver driver;

  /// Where and how to connect.
  final ConnectionSettings settings;

  /// The SQL of the database.
  SqlDialect get dialect => driver.dialect;

  /// The hooks that prepare the sessions of this data source's
  /// connections, in the order they run: `DataSourceTransactionManager`
  /// calls them when a transaction begins and `DataSourceUtils` around
  /// the work outside one. The starter fills it with the
  /// `JdbcSessionHook` beans; empty for none.
  final List<JdbcSessionHook> sessionHooks = [];

  /// A connection to use; hand it back with [releaseConnection].
  ///
  /// Throws a [CannotGetJdbcConnectionException] when there is none.
  Future<JdbcConnection> getConnection();

  /// Gives back a connection taken with [getConnection]. A closed
  /// (broken) one is dropped.
  Future<void> releaseConnection(JdbcConnection connection);

  /// Closes the data source and its connections.
  Future<void> close();

  @override
  String toString() => 'DataSource($name, ${settings.safeUrl})';
}

/// A data source without a pool: opens a connection for each
/// [getConnection] and closes it on release.
///
/// Spring (Java): `org.springframework.jdbc.datasource.
/// DriverManagerDataSource`.
class DriverDataSource extends DataSource {
  /// A data source called [name] opening connections with [driver].
  DriverDataSource({
    required super.name,
    required super.driver,
    required super.settings,
  });

  @override
  Future<JdbcConnection> getConnection() async {
    try {
      return await driver.connect(settings);
    } on SqlError catch (error) {
      throw _cannotConnect(this, error);
    }
  }

  @override
  Future<void> releaseConnection(JdbcConnection connection) =>
      connection.close();

  @override
  Future<void> close() async {}
}

CannotGetJdbcConnectionException _cannotConnect(
  DataSource source,
  SqlError error,
) => CannotGetJdbcConnectionException(
  'Failed to obtain a connection to ${source.settings.safeUrl}: '
  '${error.message}',
  cause: error,
);

/// The settings of a [PooledDataSource], named after Spring Boot's
/// `spring.datasource.hikari.*` (here `spring.datasource.pool.*`).
///
/// Spring (Java): `HikariConfig`.
final class PoolSettings {
  /// Pool settings; the defaults are Spring Boot's (Hikari's), except
  /// [minIdle], which is 0 here.
  const PoolSettings({
    this.maxSize = 10,
    this.minIdle = 0,
    this.connectionTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(minutes: 10),
    this.maxLifetime = const Duration(minutes: 30),
    this.validation = true,
  }) : assert(maxSize > 0, 'max-size must be at least 1'),
       assert(minIdle >= 0, 'min-idle must not be negative');

  /// Most connections at once (default 10).
  final int maxSize;

  /// Connections kept open when idle (default 0; Hikari keeps as many as
  /// [maxSize]).
  final int minIdle;

  /// The longest wait for a connection (default 30 s), then a
  /// [CannotGetJdbcConnectionException].
  final Duration connectionTimeout;

  /// An idle connection above [minIdle] older than this is closed (default
  /// 10 min; zero keeps them forever).
  final Duration idleTimeout;

  /// A connection older than this is closed when it comes back to the pool
  /// (default 30 min; zero: no limit).
  final Duration maxLifetime;

  /// Whether a connection that waited in the pool is checked with `isValid`
  /// before it is handed out (default true).
  final bool validation;
}

/// The connection pool, Spring Boot's default one (Hikari).
///
/// - At most [PoolSettings.maxSize] connections, opened on demand.
/// - A caller waits for a free one at most [PoolSettings.connectionTimeout],
///   in arrival order (FIFO), then gets a
///   [CannotGetJdbcConnectionException]; so nested `requiresNew`
///   transactions that use up the pool fail, they never hang.
/// - A released connection goes to the first waiter, else idles. One that
///   [JdbcConnection.isClosed] (broken) is dropped, and its place is free
///   for a new one.
/// - With [PoolSettings.validation], an idle connection is checked with
///   `isValid` before it is handed out; a dead one is dropped.
/// - Idle and lifetime limits are checked when connections move, not by a
///   timer (a timer would keep the process alive): a stale connection is
///   closed at the next take or release.
/// - It logs at info, in `spring.jdbc.datasource.PooledDataSource`, when
///   it starts and stops, with the URL without its password.
///
/// Spring (Java): `com.zaxxer.hikari.HikariDataSource`.
class PooledDataSource extends DataSource {
  /// A pool called [name] over [driver].
  PooledDataSource({
    required super.name,
    required super.driver,
    required super.settings,
    this.pool = const PoolSettings(),
  });

  /// The pool's settings.
  final PoolSettings pool;

  static const _log = SpringLog('spring.jdbc.datasource.PooledDataSource');

  final _idle = ListQueue<_Idle>();
  final _inUse = <JdbcConnection>{};
  final _born = Expando<DateTime>('born');
  final _waiters = ListQueue<_Waiter>();
  int _total = 0;
  bool _closed = false;
  Future<void>? _starting;

  /// Connections open, idle or in use (and those being opened).
  int get totalCount => _total;

  /// Connections waiting in the pool.
  int get idleCount => _idle.length;

  /// Connections handed out and not yet released.
  int get activeCount => _inUse.length;

  /// Callers waiting for a connection.
  int get waitingCount => _waiters.length;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// Starts the pool: logs it and opens [PoolSettings.minIdle] connections.
  /// Called by the first [getConnection]; calling it earlier fails fast
  /// when the database is down.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    _log.info(
      '$name - Starting... (${settings.safeUrl}, max-size '
      '${pool.maxSize})',
    );
    try {
      for (var i = 0; i < pool.minIdle && _total < pool.maxSize; i++) {
        _total++;
        final connection = await _connectCounted(pool.connectionTimeout);
        _idle.add(_Idle(connection, DateTime.now()));
      }
    } on Object {
      _starting = null;
      rethrow;
    }
    _log.info('$name - Start completed.');
  }

  @override
  Future<JdbcConnection> getConnection() async {
    _checkOpen();
    await start();
    final deadline = DateTime.now().add(pool.connectionTimeout);
    while (true) {
      _checkOpen();
      JdbcConnection? connection;
      var fresh = false;
      final idle = _takeIdle();
      if (idle != null) {
        connection = idle;
      } else if (_waiters.isEmpty && _total < pool.maxSize) {
        _total++;
        connection = await _connectCounted(_remaining(deadline));
        fresh = true;
      } else {
        final handoff = await _wait(deadline);
        if (handoff.permit) {
          connection = await _connectCounted(_remaining(deadline));
          fresh = true;
        } else {
          connection = handoff.connection;
        }
      }
      if (connection == null) {
        continue;
      }
      if (fresh || await _usable(connection)) {
        _inUse.add(connection);
        return connection;
      }
      _drop(connection);
    }
  }

  Duration _remaining(DateTime deadline) {
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _checkOpen() {
    if (_closed) {
      throw CannotGetJdbcConnectionException(
        '$name - The connection pool is closed',
      );
    }
  }

  // Takes a connection that waited in the pool, closing the stale ones.
  JdbcConnection? _takeIdle() {
    while (_idle.isNotEmpty) {
      final idle = _idle.removeLast();
      if (idle.connection.isClosed || _expired(idle.connection)) {
        _drop(idle.connection);
        continue;
      }
      return idle.connection;
    }
    return null;
  }

  bool _expired(JdbcConnection connection) {
    final born = _born[connection];
    return born != null &&
        pool.maxLifetime > Duration.zero &&
        DateTime.now().difference(born) >= pool.maxLifetime;
  }

  Future<bool> _usable(JdbcConnection connection) async {
    if (connection.isClosed) {
      return false;
    }
    if (!pool.validation) {
      return true;
    }
    try {
      return await connection.isValid();
    } on Object {
      return false;
    }
  }

  // A slot is already counted in _total; gives it back when it fails.
  Future<JdbcConnection> _connectCounted(Duration timeout) async {
    final attempt = driver.connect(settings);
    try {
      final connection = await attempt.timeout(timeout);
      _born[connection] = DateTime.now();
      if (_closed) {
        _total--;
        unawaited(_closeQuietly(connection));
        throw CannotGetJdbcConnectionException(
          '$name - The connection pool is closed',
        );
      }
      return connection;
    } on TimeoutException catch (error) {
      unawaited(
        attempt.then(
          _closeQuietly,
          onError: (Object _) => Future<void>.value(),
        ),
      );
      _total--;
      _wake();
      throw CannotGetJdbcConnectionException(
        '$name - Connection is not available, request timed out after '
        '${pool.connectionTimeout.inMilliseconds} ms (connecting to '
        '${settings.safeUrl})',
        cause: error,
      );
    } on SqlError catch (error) {
      _total--;
      _wake();
      throw _cannotConnect(this, error);
    }
  }

  Future<_Handoff> _wait(DateTime deadline) {
    final left = _remaining(deadline);
    if (left == Duration.zero) {
      throw _timedOut();
    }
    final waiter = _Waiter();
    _waiters.add(waiter);
    waiter.timer = Timer(left, () {
      if (_waiters.remove(waiter)) {
        waiter.completer.completeError(_timedOut());
      }
    });
    return waiter.completer.future;
  }

  CannotGetJdbcConnectionException _timedOut() =>
      CannotGetJdbcConnectionException(
        '$name - Connection is not available, request timed out after '
        '${pool.connectionTimeout.inMilliseconds} ms (pool: '
        '$activeCount in use of ${pool.maxSize}, $waitingCount waiting)',
      );

  @override
  Future<void> releaseConnection(JdbcConnection connection) async {
    if (!_inUse.remove(connection)) {
      return;
    }
    if (connection.isClosed || _expired(connection)) {
      _drop(connection);
      return;
    }
    if (_closed) {
      _total--;
      await _closeQuietly(connection);
      return;
    }
    if (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      waiter.timer?.cancel();
      waiter.completer.complete(_Handoff.connection(connection));
      return;
    }
    _idle.add(_Idle(connection, DateTime.now()));
    _evictIdle();
  }

  // Closes the connections idle for longer than the idle timeout, down to
  // min-idle.
  void _evictIdle() {
    if (pool.idleTimeout <= Duration.zero) {
      return;
    }
    final now = DateTime.now();
    final kept = <_Idle>[];
    var open = _idle.length;
    for (final idle in _idle) {
      if (open > pool.minIdle &&
          now.difference(idle.since) >= pool.idleTimeout) {
        open--;
        _total--;
        unawaited(_closeQuietly(idle.connection));
      } else {
        kept.add(idle);
      }
    }
    _idle
      ..clear()
      ..addAll(kept);
  }

  // Forgets a connection (broken, stale, invalid): closes it, frees its
  // place, lets a waiter open a new one.
  void _drop(JdbcConnection connection) {
    _total--;
    unawaited(_closeQuietly(connection));
    _wake();
  }

  // A place is free: the first waiter gets the right to open a connection.
  void _wake() {
    if (_waiters.isNotEmpty && _total < pool.maxSize && !_closed) {
      final waiter = _waiters.removeFirst();
      waiter.timer?.cancel();
      _total++;
      waiter.completer.complete(const _Handoff.permit());
    }
  }

  Future<void> _closeQuietly(JdbcConnection connection) async {
    try {
      await connection.close();
    } on Object {
      // Already gone.
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _log.info('$name - Shutdown initiated... (${settings.safeUrl})');
    for (final waiter in _waiters) {
      waiter.timer?.cancel();
      waiter.completer.completeError(
        CannotGetJdbcConnectionException(
          '$name - The connection pool is closed',
        ),
      );
    }
    _waiters.clear();
    final idle = _idle.toList();
    _idle.clear();
    _total -= idle.length;
    for (final entry in idle) {
      await _closeQuietly(entry.connection);
    }
    _log.info('$name - Shutdown completed.');
  }
}

final class _Idle {
  _Idle(this.connection, this.since);

  final JdbcConnection connection;
  final DateTime since;
}

// What a waiter gets: a released connection, or the right to open one.
final class _Handoff {
  const _Handoff.connection(JdbcConnection this.connection) : permit = false;

  const _Handoff.permit() : connection = null, permit = true;

  final JdbcConnection? connection;
  final bool permit;
}

final class _Waiter {
  final completer = Completer<_Handoff>();
  Timer? timer;
}
