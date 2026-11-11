import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source_utils.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/transaction/abstract_platform_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_exceptions.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_synchronization_manager.dart';

/// What [DataSourceTransactionManager] works on: the holder of the
/// connection, when the code is already in a transaction.
final class DataSourceTransactionObject {
  /// A transaction object around [holder] (null: no transaction yet).
  DataSourceTransactionObject(this.holder);

  /// The connection of the transaction, once begun.
  ConnectionHolder? holder;
}

/// The transaction manager of a JDBC [DataSource]: a transaction is one
/// connection of the data source, begun with the transaction's isolation
/// and read-only flag, bound in the scope (`ConnectionHolder`) so the
/// `JdbcTemplate`s and the repositories of the transaction share it.
///
/// - The propagation rules are the base class's; here `requiresNew` takes a
///   second connection of the pool (so a pool of one connection cannot run
///   it: it waits, then fails with a `CannotGetJdbcConnectionException`),
///   `nested` uses savepoints named `SAVEPOINT_1`, `SAVEPOINT_2`...
/// - An isolation level the dialect does not offer is refused with an
///   `InvalidIsolationLevelException` before any connection is taken.
/// - The connection goes back to the pool when the transaction ends; one
///   whose commit or rollback failed is closed.
/// - The transaction's timeout bounds every statement
///   (`DataSourceUtils.prepare`).
///
/// It logs at debug, in `spring.jdbc.datasource.DataSourceTransactionManager`.
///
/// Spring (Java): `org.springframework.jdbc.support.JdbcTransactionManager`
/// / `DataSourceTransactionManager`.
class DataSourceTransactionManager extends AbstractPlatformTransactionManager {
  /// A manager of the transactions of [dataSource].
  DataSourceTransactionManager(this.dataSource);

  /// The data source whose connections the transactions use.
  final DataSource dataSource;

  static const _log = SpringLog(
    'spring.jdbc.datasource.DataSourceTransactionManager',
  );

  @override
  Object get resourceKey => dataSource;

  @override
  Object doGetTransaction() {
    final holder = TransactionSynchronizationManager.getResource(dataSource);
    return DataSourceTransactionObject(
      holder is ConnectionHolder ? holder : null,
    );
  }

  @override
  bool isExistingTransaction(Object transaction) =>
      (transaction as DataSourceTransactionObject).holder?.transactionActive ??
      false;

  ConnectionHolder _holder(Object transaction) =>
      (transaction as DataSourceTransactionObject).holder!;

  @override
  Future<void> doBegin(
    Object transaction,
    TransactionDefinition definition,
  ) async {
    final dialect = dataSource.dialect;
    if (!dialect.isolationLevels.contains(definition.isolation)) {
      throw InvalidIsolationLevelException(
        '${dialect.name} does not offer the isolation level '
        '${definition.isolation.name}; it offers '
        '${dialect.isolationLevels.map((l) => l.name).join(', ')}',
      );
    }
    final JdbcConnection connection;
    try {
      connection = await dataSource.getConnection();
    } on DataAccessException catch (error) {
      throw CannotCreateTransactionException(
        'Could not open JDBC Connection for transaction',
        cause: error,
      );
    }
    final holder = ConnectionHolder(
      dataSource,
      connection,
      readOnly: definition.readOnly,
      isolation: definition.isolation,
      name: definition.name,
    );
    _log.debug(
      () =>
          'Acquired Connection for JDBC transaction tx#${holder.id} '
          '[${dataSource.name}]',
    );
    try {
      await connection.begin(
        isolation: definition.isolation,
        readOnly: definition.readOnly,
      );
      // The session hooks first: no statement of the application runs on
      // a transaction they have not prepared.
      await DataSourceUtils.transactionBegun(holder);
      holder.transactionActive = true;
      TransactionSynchronizationManager.bindResource(dataSource, holder);
      (transaction as DataSourceTransactionObject).holder = holder;
    } on Object catch (error) {
      holder.failed = true;
      await _release(holder);
      if (error is SqlError) {
        throw CannotCreateTransactionException(
          'Could not begin JDBC transaction: ${error.message}',
          cause: error,
        );
      }
      rethrow;
    }
    _log.debug(
      () =>
          'Began JDBC transaction tx#${holder.id}'
          '${definition.name == null ? '' : ' [${definition.name}]'} '
          '[${dataSource.name}]: $definition',
    );
  }

  @override
  Future<void> doCommit(Object transaction) async {
    final holder = _holder(transaction);
    _log.debug(() => 'Committing JDBC transaction tx#${holder.id}');
    try {
      await holder.connection.commit();
    } on SqlError catch (error) {
      holder.failed = true;
      throw dataSource.dialect.translate(error);
    }
  }

  @override
  Future<void> doRollback(Object transaction) async {
    final holder = _holder(transaction);
    _log.debug(() => 'Rolling back JDBC transaction tx#${holder.id}');
    try {
      await holder.connection.rollback();
    } on SqlError catch (error) {
      holder.failed = true;
      throw dataSource.dialect.translate(error);
    }
  }

  @override
  void doSetRollbackOnly(Object transaction) {
    final holder = _holder(transaction);
    _log.debug(
      () => 'Setting JDBC transaction tx#${holder.id} rollback-only',
    );
    holder.rollbackOnly = true;
  }

  @override
  bool isRollbackOnly(Object transaction) =>
      (transaction as DataSourceTransactionObject).holder?.rollbackOnly ??
      false;

  @override
  Future<void> doCleanupAfterCompletion(Object transaction) async {
    final holder = _holder(transaction);
    TransactionSynchronizationManager.unbindResource(dataSource);
    await _release(holder);
  }

  Future<void> _release(ConnectionHolder holder) async {
    final connection = holder.connection;
    _log.debug(() => 'Releasing JDBC Connection of tx#${holder.id}');
    try {
      if (holder.failed) {
        await connection.close();
      } else {
        await DataSourceUtils.resetStatementTimeout(connection);
      }
    } on Object {
      // Closing a broken connection may fail again; the pool drops it.
    }
    await dataSource.releaseConnection(connection);
  }

  @override
  bool get supportsSavepoints => dataSource.dialect.supportsSavepoints;

  @override
  Future<Object> createSavepoint(Object transaction) async {
    final holder = _holder(transaction);
    final name = holder.nextSavepointName();
    try {
      await holder.connection.savepoint(name);
    } on SqlError catch (error) {
      holder.savepointReleased();
      throw dataSource.dialect.translate(error);
    }
    return name;
  }

  @override
  Future<void> rollbackToSavepoint(Object transaction, Object savepoint) async {
    try {
      await _holder(
        transaction,
      ).connection.rollbackToSavepoint(savepoint as String);
    } on SqlError catch (error) {
      throw dataSource.dialect.translate(error);
    }
  }

  @override
  Future<void> releaseSavepoint(Object transaction, Object savepoint) async {
    final holder = _holder(transaction)..savepointReleased();
    try {
      await holder.connection.releaseSavepoint(savepoint as String);
    } on SqlError catch (error) {
      throw dataSource.dialect.translate(error);
    }
  }
}
