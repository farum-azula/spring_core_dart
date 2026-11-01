import 'package:spring_boot_starter_data/src/store/in_memory_data_store.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_transaction.dart';
import 'package:spring_boot_starter_data/src/transaction/abstract_platform_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_synchronization_manager.dart';

/// What [InMemoryTransactionManager.doGetTransaction] hands out for one
/// scope: the transaction of the store found there, if any.
final class InMemoryTransactionObject {
  /// An object holding [transaction], null when none is running.
  InMemoryTransactionObject(this.transaction);

  /// The running transaction of the store, or null before `doBegin`.
  InMemoryTransaction? transaction;
}

/// The transaction manager of one [InMemoryDataStore]: it begins, commits
/// and rolls back the store's transactions, with the propagation rules of
/// `AbstractPlatformTransactionManager` (joining, `requiresNew`, `nested`
/// as a savepoint, `readOnly`, timeouts).
///
/// The transaction is bound as the resource of the store, so every
/// operation of the store, whichever repository makes it, finds it. Two
/// managers over the same store share their transactions (a manager only
/// looks for the resource of the store), which is how a repository's own
/// manager joins the one of a `@Transactional` service.
///
/// The store offers read committed only: another isolation level is an
/// `InvalidIsolationLevelException` when the transaction begins.
///
/// The starter declares one as the `transactionManager` bean for the
/// default memory store, and one per `@UseDataSource` name, found with
/// `@Transactional(transactionManager: 'name')`.
///
/// Spring (Java): `DataSourceTransactionManager` (and
/// `JdbcTransactionManager`): the store stands for the `DataSource`, its
/// transaction for the `ConnectionHolder`.
final class InMemoryTransactionManager
    extends AbstractPlatformTransactionManager {
  /// A manager of [store].
  InMemoryTransactionManager(this.store);

  /// The store whose transactions the manager runs.
  final InMemoryDataStore store;

  /// The store: every manager of it shares its transaction.
  @override
  Object get resourceKey => store;

  @override
  Object doGetTransaction() => InMemoryTransactionObject(
    TransactionSynchronizationManager.getResource(store)
        as InMemoryTransaction?,
  );

  @override
  bool isExistingTransaction(Object transaction) =>
      (transaction as InMemoryTransactionObject).transaction != null;

  InMemoryTransaction _tx(Object transaction) =>
      (transaction as InMemoryTransactionObject).transaction!;

  @override
  Future<void> doBegin(
    Object transaction,
    TransactionDefinition definition,
  ) async {
    final created = store.begin(
      isolation: definition.isolation,
      readOnly: definition.readOnly,
      name: definition.name,
    );
    TransactionSynchronizationManager.bindResource(store, created);
    (transaction as InMemoryTransactionObject).transaction = created;
  }

  @override
  Future<void> doCommit(Object transaction) => store.commit(_tx(transaction));

  @override
  Future<void> doRollback(Object transaction) =>
      store.rollback(_tx(transaction));

  @override
  void doSetRollbackOnly(Object transaction) =>
      _tx(transaction).setRollbackOnly();

  @override
  bool isRollbackOnly(Object transaction) =>
      (transaction as InMemoryTransactionObject).transaction?.rollbackOnly ??
      false;

  @override
  Future<void> doCleanupAfterCompletion(Object transaction) async {
    TransactionSynchronizationManager.unbindResource(store);
  }

  @override
  bool get supportsSavepoints => true;

  @override
  Future<Object> createSavepoint(Object transaction) async =>
      store.createSavepoint(_tx(transaction));

  @override
  Future<void> rollbackToSavepoint(
    Object transaction,
    Object savepoint,
  ) async => store.rollbackToSavepoint(
    _tx(transaction),
    savepoint as InMemorySavepoint,
  );

  @override
  Future<void> releaseSavepoint(Object transaction, Object savepoint) async =>
      store.releaseSavepoint(_tx(transaction), savepoint as InMemorySavepoint);
}
