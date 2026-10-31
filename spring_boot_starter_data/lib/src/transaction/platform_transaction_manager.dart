import 'dart:async';

import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';

/// Starts, commits and rolls back transactions of one store (or one
/// database).
///
/// The current transaction lives in a zone
/// (`TransactionSynchronizationManager`), so [getTransaction] must be
/// called inside a scope: `TransactionTemplate` and `@Transactional` open
/// one for their body. Applications use those two; a manager is called
/// directly only by them and by tests.
///
/// Spring (Java):
/// `org.springframework.transaction.PlatformTransactionManager`. The
/// methods return `Future`s: beginning, committing and rolling back talk
/// to the database.
abstract interface class PlatformTransactionManager {
  /// Returns the transaction for [definition] (by default
  /// [TransactionDefinition.defaults]) as its propagation decides: a new
  /// one, the running one joined, a savepoint in it, or none.
  Future<TransactionStatus> getTransaction([TransactionDefinition? definition]);

  /// Commits the transaction of [status] (or does what its propagation
  /// says: nothing for a joined one, release for a savepoint). A
  /// transaction marked rollback-only is rolled back instead, with an
  /// `UnexpectedRollbackException` when a participant marked it.
  Future<void> commit(TransactionStatus status);

  /// Rolls back the transaction of [status] (or marks a joined one
  /// rollback-only, or rolls back to a savepoint).
  Future<void> rollback(TransactionStatus status);
}

/// The state of one transactional block: whether it started the
/// transaction, whether it must roll back, its savepoint.
///
/// Spring (Java): `org.springframework.transaction.TransactionStatus`
/// (with `SavepointManager`).
abstract interface class TransactionStatus {
  /// Whether this block started the transaction (else it joined one, or
  /// runs without).
  bool get isNewTransaction;

  /// Whether this block runs in a savepoint of the outer transaction
  /// (`nested`).
  bool get hasSavepoint;

  /// Whether a transaction is running for this block at all (not for
  /// `supports` without one, `notSupported`, `never`).
  bool get hasTransaction;

  /// Marks the transaction to be rolled back instead of committed, without
  /// throwing.
  void setRollbackOnly();

  /// Whether the transaction will roll back (marked here or by a
  /// participant).
  bool get isRollbackOnly;

  /// Whether the block has been committed or rolled back.
  bool get isCompleted;

  /// Whether the transaction only reads.
  bool get isReadOnly;

  /// The transaction's name, for logs.
  String? get transactionName;

  /// Creates a savepoint in the running transaction and returns it.
  Future<Object> createSavepoint();

  /// Rolls back to [savepoint] (from [createSavepoint]).
  Future<void> rollbackToSavepoint(Object savepoint);

  /// Releases [savepoint] (from [createSavepoint]).
  Future<void> releaseSavepoint(Object savepoint);
}

/// What a store's transaction manager implements; the propagation rules,
/// the synchronizations and the rollback-only handling are
/// `AbstractPlatformTransactionManager`'s.
///
/// The `transaction` object of each method is what [doGetTransaction]
/// returned for the current scope.
///
/// Spring (Java): the template methods of
/// `AbstractPlatformTransactionManager`. There are no `doSuspend` /
/// `doResume`: a transaction set aside stays bound in the outer scope, and
/// the new one is bound in an isolated scope (see
/// `TransactionSynchronizationManager`).
abstract interface class TransactionManagerHooks {
  /// The key the manager binds its transaction under: the store or the
  /// database, so two managers of the same store share a transaction and
  /// a `requiresNew` of this manager sets aside only its own.
  Object get resourceKey;

  /// The store's transaction object for the current scope: holds the
  /// resource found with `TransactionSynchronizationManager.getResource`,
  /// or none.
  Object doGetTransaction();

  /// Whether [transaction] holds a running transaction.
  bool isExistingTransaction(Object transaction);

  /// Begins a transaction for [definition] and binds its resource in the
  /// current scope (`TransactionSynchronizationManager.bindResource`).
  /// Throws `InvalidIsolationLevelException` for a level the store does
  /// not offer.
  Future<void> doBegin(Object transaction, TransactionDefinition definition);

  /// Commits [transaction].
  Future<void> doCommit(Object transaction);

  /// Rolls back [transaction].
  Future<void> doRollback(Object transaction);

  /// Marks [transaction] rollback-only, for a participant that failed.
  void doSetRollbackOnly(Object transaction);

  /// Whether [transaction] was marked rollback-only.
  bool isRollbackOnly(Object transaction);

  /// Unbinds the resource of [transaction] and frees it (returns the
  /// connection), after the commit or the rollback.
  Future<void> doCleanupAfterCompletion(Object transaction);

  /// Whether `nested` works (savepoints).
  bool get supportsSavepoints;

  /// Creates a savepoint in [transaction].
  Future<Object> createSavepoint(Object transaction);

  /// Rolls [transaction] back to [savepoint].
  Future<void> rollbackToSavepoint(Object transaction, Object savepoint);

  /// Releases [savepoint] of [transaction].
  Future<void> releaseSavepoint(Object transaction, Object savepoint);
}
