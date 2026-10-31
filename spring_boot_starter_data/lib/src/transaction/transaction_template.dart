import 'dart:async';

import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_exceptions.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_synchronization_manager.dart';

/// Runs code in a transaction without annotations: the code commits when
/// its `Future` completes and rolls back when it fails.
///
/// Each call opens its own scope, so the transaction follows the `await`s
/// of the code and never leaks into a call running at the same time. A call
/// made inside another one's action follows the [TransactionDefinition]'s
/// propagation (joins the running transaction by default).
///
/// Any exception or error thrown by the action rolls the transaction back
/// and is thrown again. When the rollback itself fails, a
/// [TransactionSystemException] carries both errors (its
/// [TransactionSystemException.applicationException] is the action's).
///
/// ```dart
/// final template = TransactionTemplate(manager);
/// final order = await template.execute((status) async {
///   final row = await stock.findByBookId(id);
///   if (row!.available == 0) {
///     status.setRollbackOnly(); // roll back without throwing
///   }
///   return orders.save(Order(bookId: id));
/// });
/// ```
///
/// Spring (Java):
/// ```java
/// new TransactionTemplate(manager).execute(status -> { ...; return order; });
/// ```
class TransactionTemplate {
  /// A template that runs actions with [manager] in a transaction defined
  /// by [definition] (by default [TransactionDefinition.defaults]).
  TransactionTemplate(
    this.manager, [
    this.definition = TransactionDefinition.defaults,
  ]);

  /// The manager that starts, commits and rolls back the transactions.
  final PlatformTransactionManager manager;

  /// The settings of the transactions it runs.
  final TransactionDefinition definition;

  /// Runs [action] in a transaction and returns its result once the
  /// transaction has committed.
  ///
  /// The action may call `status.setRollbackOnly()` to have the transaction
  /// rolled back instead of committed, without throwing. Throws what the
  /// action throws, after rolling back; throws
  /// [UnexpectedRollbackException] when the transaction was rolled back
  /// although the action finished (a participant failed).
  Future<T> execute<T>(FutureOr<T> Function(TransactionStatus status) action) =>
      runInTransaction<T>(manager, definition, action);

  /// Like [execute] for an action with no result.
  Future<void> executeWithoutResult(
    FutureOr<void> Function(TransactionStatus status) action,
  ) => execute<void>(action);

  @override
  String toString() => 'TransactionTemplate($definition)';
}

/// Runs [action] in a new scope inside a transaction of [manager] defined
/// by [definition]: the code behind [TransactionTemplate] and the
/// `@Transactional` interceptor.
///
/// An error of the action rolls back when [rollbackOn] is null or returns
/// true for it; else the transaction commits and the error is thrown again.
/// When the rollback fails, a [TransactionSystemException] carries the
/// action's error.
Future<T> runInTransaction<T>(
  PlatformTransactionManager manager,
  TransactionDefinition definition,
  FutureOr<T> Function(TransactionStatus status) action, {
  bool Function(Object error)? rollbackOn,
}) => TransactionSynchronizationManager.runInScope<T>(() async {
  final status = await manager.getTransaction(definition);
  final T result;
  try {
    result = await action(status);
  } catch (error, stackTrace) {
    await _completeAfterThrowing(manager, status, error, rollbackOn);
    Error.throwWithStackTrace(error, stackTrace);
  }
  await manager.commit(status);
  return result;
});

Future<void> _completeAfterThrowing(
  PlatformTransactionManager manager,
  TransactionStatus status,
  Object error,
  bool Function(Object error)? rollbackOn,
) async {
  if (rollbackOn == null || rollbackOn(error)) {
    try {
      await manager.rollback(status);
    } catch (rollbackError) {
      throw TransactionSystemException(
        'Application exception overridden by rollback exception: '
        '$rollbackError',
        cause: rollbackError,
        applicationException: error,
      );
    }
  } else {
    // The error is one the transaction survives: commit; a failing commit
    // is the one thrown (Spring does the same).
    await manager.commit(status);
  }
}
