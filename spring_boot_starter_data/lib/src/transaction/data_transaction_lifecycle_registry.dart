import 'package:spring_boot_dart/spring_boot_dart.dart'
    show TransactionLifecycleListener, TransactionLifecycleRegistry;
import 'package:spring_boot_starter_data/src/transaction/transaction_synchronization_manager.dart';

/// The data starter's [TransactionLifecycleRegistry]: the current
/// transaction of [TransactionSynchronizationManager], whose listeners are
/// registered as synchronizations of it.
///
/// Spring (Java): `TransactionSynchronizationManager.registerSynchronization`.
final class DataTransactionLifecycleRegistry
    implements TransactionLifecycleRegistry {
  /// The registry.
  const DataTransactionLifecycleRegistry();

  @override
  Object? get transactionKey =>
      TransactionSynchronizationManager.currentTransaction;

  @override
  void registerListener(TransactionLifecycleListener listener) =>
      TransactionSynchronizationManager.registerSynchronization(
        _ListenerSynchronization(listener),
      );
}

final class _ListenerSynchronization extends TransactionSynchronization {
  _ListenerSynchronization(this.listener);

  final TransactionLifecycleListener listener;

  @override
  void savepoint(Object savepoint) => listener.savepoint(savepoint);

  @override
  void savepointRollback(Object savepoint) =>
      listener.savepointRollback(savepoint);

  @override
  void afterCommit() => listener.afterCommit();

  @override
  void afterCompletion(TransactionCompletion status) {
    if (status != TransactionCompletion.committed) {
      listener.afterRollbackOrUnknown();
    }
  }
}
