import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_exceptions.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_synchronization_manager.dart';

/// The base of the transaction managers of the stores: it decides what each
/// [Propagation] does, keeps the synchronizations, and handles the
/// rollback-only marks, so a store implements only [TransactionManagerHooks]
/// (begin, commit, roll back, savepoints).
///
/// The rules, as Spring has them:
///
/// - [getTransaction] must run in a scope (`TransactionTemplate` and
///   `@Transactional` open one per block), else it throws a [StateError].
///   Which transaction a block joins is found through the scopes it is
///   nested in; a transaction that must be independent of the running one
///   (`requiresNew`, `notSupported`) isolates its scope first.
/// - Isolation, timeout and read-only apply to a transaction that starts;
///   a block that joins one keeps the running transaction's.
/// - [commit] of a block that joined does nothing, of a savepoint releases
///   it, of a new transaction runs the synchronizations around the store's
///   commit. A transaction marked rollback-only (by [TransactionStatus.
///   setRollbackOnly], or by a participant that failed) is rolled back
///   instead; for the block that started it, that ends with an
///   [UnexpectedRollbackException]: the caller asked for a commit.
/// - [rollback] of a block that joined marks the running transaction
///   rollback-only (Spring's `globalRollbackOnParticipationFailure`), of a
///   savepoint rolls back to it, of a new transaction rolls it back.
///
/// It logs at debug, as Spring does, in the logger
/// `spring.transaction.<ConcreteClassName>`.
///
/// Spring (Java):
/// `AbstractPlatformTransactionManager` (in
/// `org.springframework.transaction.support`).
/// Differences: no `doSuspend` / `doResume` (the structure of the scopes
/// does it), no `validateExistingTransaction`, no
/// `failEarlyOnGlobalRollbackOnly` and no `rollbackOnCommitFailure` (their
/// Spring defaults apply), and a block without a transaction (`supports`,
/// `notSupported`, `never`) has no synchronizations.
abstract class AbstractPlatformTransactionManager
    implements PlatformTransactionManager, TransactionManagerHooks {
  /// A manager; the logger is named after the concrete class.
  AbstractPlatformTransactionManager();

  late final SpringLog _log = SpringLog('spring.transaction.$runtimeType');

  /// The manager itself, unless a subclass names its store (see
  /// [TransactionManagerHooks.resourceKey]).
  @override
  Object get resourceKey => this;

  @override
  Future<TransactionStatus> getTransaction([
    TransactionDefinition? definition,
  ]) async {
    if (!TransactionSynchronizationManager.hasScope) {
      throw StateError(
        'getTransaction() outside a transaction scope: call it in a '
        'TransactionTemplate, a @Transactional method, or '
        'TransactionSynchronizationManager.runInScope',
      );
    }
    final def = definition ?? TransactionDefinition.defaults;
    if (def.timeout case final timeout? when timeout <= Duration.zero) {
      throw InvalidTimeoutException('Invalid transaction timeout: $timeout');
    }
    final transaction = doGetTransaction();
    if (isExistingTransaction(transaction)) {
      return await _handleExisting(def, transaction);
    }
    switch (def.propagation) {
      case Propagation.mandatory:
        throw IllegalTransactionStateException(
          'No existing transaction found for transaction marked with '
          "propagation 'mandatory'",
        );
      case Propagation.required:
      case Propagation.requiresNew:
      case Propagation.nested:
        return await _begin(def, transaction, suspended: false);
      case Propagation.supports:
      case Propagation.notSupported:
      case Propagation.never:
        if (def.isolation != Isolation.defaultLevel) {
          _log.warning(
            'Custom isolation level specified but no actual transaction '
            'initiated; isolation level will effectively be ignored: $def',
          );
        }
        return DefaultTransactionStatus._(
          hooks: this,
          log: _log,
          transaction: null,
          isNewTransaction: false,
          readOnly: def.readOnly,
          name: def.name,
          suspended: false,
        );
    }
  }

  Future<TransactionStatus> _handleExisting(
    TransactionDefinition def,
    Object transaction,
  ) async {
    switch (def.propagation) {
      case Propagation.never:
        throw IllegalTransactionStateException(
          'Existing transaction found for transaction marked with '
          "propagation 'never'",
        );
      case Propagation.notSupported:
        _log.debug('Suspending current transaction');
        TransactionSynchronizationManager.isolate(resourceKey);
        return DefaultTransactionStatus._(
          hooks: this,
          log: _log,
          transaction: null,
          isNewTransaction: false,
          readOnly: def.readOnly,
          name: def.name,
          suspended: true,
        );
      case Propagation.requiresNew:
        _log.debug(
          'Suspending current transaction, creating new transaction with '
          'name [${def.name}]',
        );
        TransactionSynchronizationManager.isolate(resourceKey);
        return await _begin(def, doGetTransaction(), suspended: true);
      case Propagation.nested:
        if (!supportsSavepoints) {
          throw NestedTransactionNotSupportedException(
            'Transaction manager does not allow nested transactions: '
            '$runtimeType has no savepoints',
          );
        }
        _log.debug('Creating nested transaction with name [${def.name}]');
        final savepoint = await createSavepoint(transaction);
        return DefaultTransactionStatus._(
          hooks: this,
          log: _log,
          transaction: transaction,
          isNewTransaction: false,
          savepoint: savepoint,
          readOnly: def.readOnly,
          name: def.name,
          suspended: false,
        );
      case Propagation.required:
      case Propagation.supports:
      case Propagation.mandatory:
        _log.debug('Participating in existing transaction');
        return DefaultTransactionStatus._(
          hooks: this,
          log: _log,
          transaction: transaction,
          isNewTransaction: false,
          readOnly: def.readOnly,
          name: def.name,
          suspended: false,
        );
    }
  }

  Future<TransactionStatus> _begin(
    TransactionDefinition def,
    Object transaction, {
    required bool suspended,
  }) async {
    if (!suspended) {
      _log.debug(
        'Creating new transaction with name [${def.name}]: $def',
      );
    }
    TransactionSynchronizationManager.initTransaction(def, key: resourceKey);
    final info = TransactionSynchronizationManager.currentTransactionFor(
      resourceKey,
    )!;
    try {
      await doBegin(transaction, def);
    } catch (_) {
      TransactionSynchronizationManager.completeTransaction(info);
      rethrow;
    }
    return DefaultTransactionStatus._(
      hooks: this,
      log: _log,
      transaction: transaction,
      isNewTransaction: true,
      info: info,
      readOnly: def.readOnly,
      name: def.name,
      suspended: suspended,
    );
  }

  @override
  Future<void> commit(TransactionStatus status) async {
    final s = _own(status);
    if (s.isCompleted) {
      throw IllegalTransactionStateException(
        'Transaction is already completed - do not call commit or rollback '
        'more than once per transaction',
      );
    }
    if (s._localRollbackOnly) {
      _log.debug('Transactional code has requested rollback');
      await _processRollback(s, unexpected: false);
      return;
    }
    if (s.isGlobalRollbackOnly) {
      _log.debug(
        'Global transaction is marked as rollback-only but transactional '
        'code requested commit',
      );
      await _processRollback(s, unexpected: true);
      return;
    }
    await _processCommit(s);
  }

  @override
  Future<void> rollback(TransactionStatus status) async {
    final s = _own(status);
    if (s.isCompleted) {
      throw IllegalTransactionStateException(
        'Transaction is already completed - do not call commit or rollback '
        'more than once per transaction',
      );
    }
    await _processRollback(s, unexpected: false);
  }

  DefaultTransactionStatus _own(TransactionStatus status) {
    if (status is DefaultTransactionStatus && identical(status._hooks, this)) {
      return status;
    }
    throw ArgumentError.value(
      status,
      'status',
      'was not created by this transaction manager',
    );
  }

  Future<void> _processCommit(DefaultTransactionStatus s) async {
    var beforeCompletionInvoked = false;
    try {
      try {
        if (s.isNewTransaction) {
          for (final sync in s._synchronizations) {
            await sync.beforeCommit(readOnly: s.isReadOnly);
          }
          await _beforeCompletion(s);
          beforeCompletionInvoked = true;
        }
      } catch (_) {
        if (!beforeCompletionInvoked) {
          await _beforeCompletion(s);
        }
        await _rollbackOnCommitException(s);
        rethrow;
      }
      try {
        if (s.hasSavepoint) {
          await s.releaseHeldSavepoint();
        } else if (s.isNewTransaction) {
          _log.debug('Initiating transaction commit');
          await doCommit(s._transaction!);
        }
      } on TransactionException {
        await _afterCompletion(s, TransactionCompletion.unknown);
        rethrow;
      } on Object catch (error) {
        await _afterCompletion(s, TransactionCompletion.unknown);
        throw TransactionSystemException(
          'Could not commit transaction',
          cause: error,
        );
      }
      try {
        if (s.isNewTransaction) {
          for (final sync in s._synchronizations) {
            await sync.afterCommit();
          }
        }
      } finally {
        await _afterCompletion(s, TransactionCompletion.committed);
      }
    } finally {
      await _cleanup(s);
    }
  }

  Future<void> _processRollback(
    DefaultTransactionStatus s, {
    required bool unexpected,
  }) async {
    var unexpectedRollback = unexpected;
    try {
      try {
        if (s.isNewTransaction) {
          await _beforeCompletion(s);
        }
        if (s.hasSavepoint) {
          _log.debug('Rolling back transaction to savepoint');
          await s.rollbackToHeldSavepoint();
        } else if (s.isNewTransaction) {
          _log.debug('Initiating transaction rollback');
          await doRollback(s._transaction!);
        } else {
          if (s.hasTransaction) {
            _log.debug(
              'Participating transaction failed - marking existing '
              'transaction as rollback-only',
            );
            doSetRollbackOnly(s._transaction!);
          } else {
            _log.debug(
              'Should roll back transaction but cannot - no transaction '
              'available',
            );
          }
          // Spring's failEarlyOnGlobalRollbackOnly is false: the one that
          // started the transaction reports the rollback.
          unexpectedRollback = false;
        }
      } on TransactionException {
        await _afterCompletion(s, TransactionCompletion.unknown);
        rethrow;
      } on Object catch (error) {
        await _afterCompletion(s, TransactionCompletion.unknown);
        throw TransactionSystemException(
          'Could not roll back transaction',
          cause: error,
        );
      }
      await _afterCompletion(s, TransactionCompletion.rolledBack);
      if (unexpectedRollback) {
        throw UnexpectedRollbackException(
          'Transaction rolled back because it has been marked as '
          'rollback-only',
        );
      }
    } finally {
      await _cleanup(s);
    }
  }

  // Spring's doRollbackOnCommitException: a failure before the commit
  // rolls the transaction back; the original error is the one thrown.
  Future<void> _rollbackOnCommitException(DefaultTransactionStatus s) async {
    try {
      if (s.hasSavepoint) {
        await s.rollbackToHeldSavepoint();
      } else if (s.isNewTransaction) {
        _log.debug('Initiating transaction rollback after commit exception');
        await doRollback(s._transaction!);
      } else if (s.hasTransaction) {
        doSetRollbackOnly(s._transaction!);
      }
    } on Object catch (error, stackTrace) {
      _log.error(
        'Commit exception overridden by rollback exception',
        error: error,
        stackTrace: stackTrace,
      );
      await _afterCompletion(s, TransactionCompletion.unknown);
      return;
    }
    await _afterCompletion(s, TransactionCompletion.rolledBack);
  }

  Future<void> _beforeCompletion(DefaultTransactionStatus s) async {
    if (!s.isNewTransaction) {
      return;
    }
    for (final sync in s._synchronizations) {
      try {
        await sync.beforeCompletion();
      } on Object catch (error, stackTrace) {
        _log.error(
          'TransactionSynchronization.beforeCompletion threw an exception',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  // Once per status: the commit failure path may reach it twice.
  Future<void> _afterCompletion(
    DefaultTransactionStatus s,
    TransactionCompletion completion,
  ) async {
    if (!s.isNewTransaction || s._afterCompletionDone) {
      return;
    }
    s._afterCompletionDone = true;
    for (final sync in s._synchronizations) {
      try {
        await sync.afterCompletion(completion);
      } on Object catch (error, stackTrace) {
        _log.error(
          'TransactionSynchronization.afterCompletion threw an exception',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _cleanup(DefaultTransactionStatus s) async {
    s._completed = true;
    try {
      if (s.isNewTransaction) {
        try {
          await doCleanupAfterCompletion(s._transaction!);
        } finally {
          TransactionSynchronizationManager.completeTransaction(s._info);
        }
      }
    } finally {
      if (s._suspended) {
        _log.debug(
          'Resuming suspended transaction after completion of inner '
          'transaction',
        );
      }
    }
  }
}

/// The [TransactionStatus] that [AbstractPlatformTransactionManager]
/// creates.
///
/// Spring (Java):
/// `org.springframework.transaction.support.DefaultTransactionStatus`.
final class DefaultTransactionStatus implements TransactionStatus {
  DefaultTransactionStatus._({
    required this._hooks,
    required this._log,
    required this._transaction,
    required this.isNewTransaction,
    required this.readOnly,
    required this.name,
    required this._suspended,
    this._savepoint,
    this._info,
  });

  final TransactionManagerHooks _hooks;
  final SpringLog _log;
  final Object? _transaction;
  final Object? _savepoint;
  final TransactionInfo? _info;
  final bool _suspended;

  /// Whether the block asked for a read-only transaction.
  final bool readOnly;

  /// The name of the block's transaction, for logs.
  final String? name;
  bool _localRollbackOnly = false;
  bool _completed = false;
  bool _afterCompletionDone = false;

  List<TransactionSynchronization> get _synchronizations =>
      _info?.synchronizations ?? const [];

  @override
  final bool isNewTransaction;

  @override
  bool get hasSavepoint => _savepoint != null;

  @override
  bool get hasTransaction => _transaction != null;

  @override
  void setRollbackOnly() {
    if (!_localRollbackOnly) {
      _log.debug('Setting transaction rollback-only');
    }
    _localRollbackOnly = true;
  }

  /// Whether a participant (or this block) marked the running transaction
  /// rollback-only through the store, not through this status.
  bool get isGlobalRollbackOnly =>
      _transaction != null && _hooks.isRollbackOnly(_transaction);

  @override
  bool get isRollbackOnly => _localRollbackOnly || isGlobalRollbackOnly;

  @override
  bool get isCompleted => _completed;

  @override
  bool get isReadOnly => readOnly;

  @override
  String? get transactionName => name;

  @override
  Future<Object> createSavepoint() async =>
      await _hooks.createSavepoint(_requireTx());

  @override
  Future<void> rollbackToSavepoint(Object savepoint) async {
    await _hooks.rollbackToSavepoint(_requireTx(), savepoint);
  }

  @override
  Future<void> releaseSavepoint(Object savepoint) async {
    await _hooks.releaseSavepoint(_requireTx(), savepoint);
  }

  /// Rolls back to this block's own savepoint and releases it.
  Future<void> rollbackToHeldSavepoint() async {
    final savepoint = _savepoint!;
    await _hooks.rollbackToSavepoint(_transaction!, savepoint);
    await _hooks.releaseSavepoint(_transaction, savepoint);
  }

  /// Releases this block's own savepoint.
  Future<void> releaseHeldSavepoint() =>
      _hooks.releaseSavepoint(_transaction!, _savepoint!);

  Object _requireTx() =>
      _transaction ??
      (throw IllegalTransactionStateException(
        'No transaction: a savepoint needs a running transaction',
      ));

  @override
  String toString() =>
      'TransactionStatus(${name ?? ''}, new: $isNewTransaction, '
      'transaction: $hasTransaction, savepoint: $hasSavepoint)';
}
