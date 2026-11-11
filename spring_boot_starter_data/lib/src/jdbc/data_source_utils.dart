import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_exceptions.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_synchronization_manager.dart';

/// The connection of a running transaction, bound in the transaction's
/// scope with the [DataSource] as its key: every `JdbcTemplate` call of
/// the transaction (across `await`s) finds it there.
///
/// Spring (Java): `org.springframework.jdbc.datasource.ConnectionHolder`.
final class ConnectionHolder {
  /// A holder of [connection], taken from [dataSource].
  ConnectionHolder(
    this.dataSource,
    this.connection, {
    this.readOnly = false,
    this.isolation = Isolation.defaultLevel,
    this.name,
  }) : id = ++_ids;

  static int _ids = 0;

  /// The data source the connection comes from (and the resource key).
  final DataSource dataSource;

  /// The transaction's connection.
  final JdbcConnection connection;

  /// A number for logs (`tx#12`).
  final int id;

  /// The transaction's name, when it has one.
  final String? name;

  /// Whether the transaction is read only.
  final bool readOnly;

  /// The isolation the transaction began with.
  final Isolation isolation;

  /// Whether the transaction has begun (set by the transaction manager).
  bool transactionActive = false;

  /// Whether the transaction must roll back.
  bool rollbackOnly = false;

  /// Whether a commit or rollback failed: the connection's state is
  /// unknown and it is closed instead of going back to the pool.
  bool failed = false;

  /// How many statements the transaction has run.
  int statementCount = 0;

  /// Whether the transaction holds the write lock of the database (after
  /// [requireWriteLock]).
  bool writeLocked = false;

  int _savepointCounter = 0;
  int _openSavepoints = 0;

  /// The next savepoint name: `SAVEPOINT_1`, `SAVEPOINT_2`...
  String nextSavepointName() {
    _openSavepoints++;
    return 'SAVEPOINT_${++_savepointCounter}';
  }

  /// Notes that a savepoint was released.
  void savepointReleased() {
    if (_openSavepoints > 0) {
      _openSavepoints--;
    }
  }

  /// Makes the transaction the writer of a database whose
  /// [LockStrategy] is [LockStrategy.databaseLock] (SQLite) at once, for a
  /// `@Lock` query; does nothing for a database with row locks.
  ///
  /// SQLite begins a transaction as a reader (`DEFERRED`) and takes the
  /// write lock at the first write, and a reader that turns writer after
  /// another writer committed fails. So:
  ///
  /// - if the transaction ran no statement yet and has no savepoint, it
  ///   begins again with `lockForWrite` (`BEGIN IMMEDIATE`): nothing
  ///   was lost, and the lock is held from now on;
  /// - else the dialect's [SqlDialect.writeLockStatement] runs, when it has
  ///   one (a no-op write);
  /// - else it fails with an [IllegalTransactionStateException] saying
  ///   that the `@Lock` query must come first. Limit: in that last case a
  ///   `@Lock` read cannot upgrade a transaction that already read.
  ///
  /// Throws an [IllegalTransactionStateException] outside a transaction
  /// and an [InvalidDataAccessApiUsageException] in a read-only one.
  Future<void> requireWriteLock() async {
    final dialect = dataSource.dialect;
    if (dialect.lockStrategy != LockStrategy.databaseLock || writeLocked) {
      return;
    }
    if (!transactionActive) {
      throw IllegalTransactionStateException(
        'A @Lock query needs a running transaction',
      );
    }
    if (readOnly) {
      throw InvalidDataAccessApiUsageException(
        'A @Lock query cannot run in a read-only transaction',
      );
    }
    try {
      if (statementCount == 0 && _openSavepoints == 0) {
        try {
          await connection.rollback();
          await connection.begin(isolation: isolation, lockForWrite: true);
          // A new transaction: what the hooks set for the first is gone.
          await DataSourceUtils.transactionBegun(this);
        } on Object {
          failed = true;
          rethrow;
        }
      } else if (dialect.writeLockStatement case final statement?) {
        await connection.execute(statement);
      } else {
        throw IllegalTransactionStateException(
          'A @Lock query must be the first statement of its transaction in '
          '${dialect.name}: the transaction already ran $statementCount '
          'statement(s) as a reader and cannot become the writer; put the '
          '@Lock query first',
        );
      }
    } on SqlError catch (error) {
      throw dialect.translate(error);
    }
    writeLocked = true;
  }

  @override
  String toString() => 'ConnectionHolder(tx#$id)';
}

/// Takes and gives back connections the way a transaction wants: inside a
/// transaction of the data source, the transaction's connection; else one
/// of the pool, given back when the operation ends.
///
/// It is also where the data source's `JdbcSessionHook`s run for the work
/// outside a transaction: [getConnection] prepares the pooled connection
/// it hands out (`beforeWork`) and [releaseConnection] cleans it
/// (`afterWork`) before the pool has it back, so every statement of a
/// `JdbcTemplate` runs between the two. [transactionBegun] is the hooks'
/// other door, called by the transaction manager.
///
/// Spring (Java): `org.springframework.jdbc.datasource.DataSourceUtils`.
abstract final class DataSourceUtils {
  static final _applied = Expando<Duration>('statementTimeout');

  // The pooled connections the hooks prepared and have not cleaned yet.
  static final _prepared = Expando<bool>('sessionPrepared');

  static const _log = SpringLog('spring.jdbc.datasource.DataSourceUtils');

  /// The holder of the running transaction on [dataSource], or null when
  /// the code is not in one.
  static ConnectionHolder? currentHolder(DataSource dataSource) {
    final holder = TransactionSynchronizationManager.getResource(dataSource);
    return holder is ConnectionHolder && holder.transactionActive
        ? holder
        : null;
  }

  /// The connection to use for [dataSource]: the transaction's, or a new
  /// one from the pool (give it back with [releaseConnection]), prepared
  /// by the data source's session hooks (`JdbcSessionHook.beforeWork`, in
  /// order).
  ///
  /// A hook that fails fails the call (an error of the database
  /// translated by the dialect); the connection is closed and given back,
  /// so it is never used half prepared.
  static Future<JdbcConnection> getConnection(DataSource dataSource) {
    final holder = currentHolder(dataSource);
    if (holder != null) {
      return Future.value(holder.connection);
    }
    if (dataSource.sessionHooks.isEmpty) {
      return dataSource.getConnection();
    }
    return _preparedConnection(dataSource);
  }

  static Future<JdbcConnection> _preparedConnection(
    DataSource dataSource,
  ) async {
    final connection = await dataSource.getConnection();
    try {
      for (final hook in dataSource.sessionHooks) {
        await hook.beforeWork(dataSource, connection);
      }
    } on Object catch (error, stackTrace) {
      await _discard(connection, dataSource);
      if (error is SqlError) {
        Error.throwWithStackTrace(
          dataSource.dialect.translate(error),
          stackTrace,
        );
      }
      rethrow;
    }
    _prepared[connection] = true;
    return connection;
  }

  // Closes a connection whose session state is unknown and gives it back:
  // the pool drops a closed connection.
  static Future<void> _discard(
    JdbcConnection connection,
    DataSource dataSource,
  ) async {
    try {
      await connection.close();
    } on Object {
      // Closing a broken connection may fail again.
    }
    await dataSource.releaseConnection(connection);
  }

  /// Runs the session hooks of the data source of [transaction] right
  /// after its transaction began (`JdbcSessionHook.afterBegin`, in
  /// order). The transaction manager calls it; an error is the caller's
  /// to handle (it closes the connection).
  static Future<void> transactionBegun(ConnectionHolder transaction) async {
    for (final hook in transaction.dataSource.sessionHooks) {
      await hook.afterBegin(transaction);
    }
  }

  /// Whether [connection] is the connection of the running transaction on
  /// [dataSource].
  static bool isConnectionTransactional(
    JdbcConnection connection,
    DataSource dataSource,
  ) => identical(currentHolder(dataSource)?.connection, connection);

  /// Gives back [connection] taken with [getConnection]: nothing for the
  /// transaction's (its manager releases it), the pool's otherwise, after
  /// the session hooks that prepared it cleaned it
  /// (`JdbcSessionHook.afterWork`, in reverse order). A hook that fails
  /// is logged and the connection is closed, so it does not go back to
  /// the pool with state left on it.
  static Future<void> releaseConnection(
    JdbcConnection connection,
    DataSource dataSource,
  ) async {
    if (isConnectionTransactional(connection, dataSource)) {
      return;
    }
    if (_prepared[connection] ?? false) {
      _prepared[connection] = null;
      await _clean(connection, dataSource);
    }
    await resetStatementTimeout(connection);
    await dataSource.releaseConnection(connection);
  }

  static Future<void> _clean(
    JdbcConnection connection,
    DataSource dataSource,
  ) async {
    for (final hook in dataSource.sessionHooks.reversed) {
      if (connection.isClosed) {
        return;
      }
      try {
        await hook.afterWork(dataSource, connection);
      } on Object catch (error) {
        _log.warning(
          'A session hook (${hook.runtimeType}) failed to clean a '
          'connection of ${dataSource.name}; the connection is closed '
          'instead of going back to the pool: $error',
        );
        try {
          await connection.close();
        } on Object {
          // Closing a broken connection may fail again.
        }
        return;
      }
    }
  }

  /// Gets [connection] ready for a statement: throws a
  /// `TransactionTimedOutException` when the transaction's time is spent,
  /// and bounds the statement by the time left (or by [queryTimeout] when
  /// shorter), as Spring's `applyTransactionTimeout`. Counts the statement
  /// for [ConnectionHolder.statementCount].
  static Future<void> prepare(
    JdbcConnection connection,
    DataSource dataSource, {
    Duration? queryTimeout,
  }) async {
    var timeout = queryTimeout;
    final holder = currentHolder(dataSource);
    if (holder != null && identical(holder.connection, connection)) {
      holder.statementCount++;
      final info = TransactionSynchronizationManager.currentTransactionFor(
        dataSource,
      );
      info?.checkDeadline(markRollbackOnly: () => holder.rollbackOnly = true);
      if (info?.timeLeft case final left?
          when timeout == null || left < timeout) {
        timeout = left;
      }
    }
    if (timeout != _applied[connection]) {
      await connection.setStatementTimeout(timeout);
      _applied[connection] = timeout;
    }
  }

  /// Removes the statement timeout [prepare] set on [connection], so the
  /// next user of the pooled connection does not inherit it.
  static Future<void> resetStatementTimeout(JdbcConnection connection) async {
    if (_applied[connection] != null) {
      _applied[connection] = null;
      if (!connection.isClosed) {
        try {
          await connection.setStatementTimeout(null);
        } on SqlError {
          // The connection is broken: the pool drops a closed one.
          await connection.close();
        }
      }
    }
  }

  /// Makes the running transaction on [dataSource] the writer when the
  /// database needs it for a `@Lock` query; see
  /// [ConnectionHolder.requireWriteLock].
  static Future<void> requireWriteLock(DataSource dataSource) async {
    final holder = currentHolder(dataSource);
    if (holder == null) {
      if (dataSource.dialect.lockStrategy == LockStrategy.databaseLock) {
        throw IllegalTransactionStateException(
          'A @Lock query needs a running transaction',
        );
      }
      return;
    }
    await holder.requireWriteLock();
  }
}
