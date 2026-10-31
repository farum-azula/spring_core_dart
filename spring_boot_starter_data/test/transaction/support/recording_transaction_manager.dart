// Any object may be thrown in Dart; the tests throw strings and plain
// objects on purpose.
// ignore_for_file: only_throw_errors
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

/// A transaction in the fake store: an id, and whether it must roll back.
final class RecordedTransaction {
  RecordedTransaction(this.id);

  final int id;
  bool rollbackOnly = false;
  int savepoints = 0;
}

/// What `doGetTransaction` hands out: the transaction found, if any.
final class RecordingHolder {
  RecordingHolder(this.transaction);

  RecordedTransaction? transaction;
}

/// A manager over a fake store that records what it is asked, one line per
/// call: `begin 1`, `commit 1`, `rollback 1`, `savepoint 1 #1`,
/// `rollbackTo 1 #1`, `release 1 #1`, `rollbackOnly 1`, `cleanup 1`.
///
/// The transaction ids count from 1. [failCommit] and [failRollback] make
/// the store fail; [savepoints] switches the savepoint support off.
class RecordingTransactionManager extends AbstractPlatformTransactionManager {
  RecordingTransactionManager({this.savepoints = true});

  /// The calls so far.
  final events = <String>[];

  /// Whether `nested` works.
  bool savepoints;

  /// An error thrown by the next `doCommit`.
  Object? failCommit;

  /// An error thrown by the next `doRollback`.
  Object? failRollback;

  int _ids = 0;

  /// The id of the transaction the current code is in, or null.
  int? get currentId => current?.id;

  /// The transaction of the current code, or null. Fails like
  /// `getResource` when the transaction has ended.
  RecordedTransaction? get current =>
      TransactionSynchronizationManager.getResource(this)
          as RecordedTransaction?;

  /// The events without the cleanups.
  List<String> get calls => [
    for (final event in events)
      if (!event.startsWith('cleanup')) event,
  ];

  @override
  Object doGetTransaction() => RecordingHolder(current);

  @override
  bool isExistingTransaction(Object transaction) =>
      (transaction as RecordingHolder).transaction != null;

  @override
  Future<void> doBegin(
    Object transaction,
    TransactionDefinition definition,
  ) async {
    final holder = transaction as RecordingHolder;
    final created = holder.transaction = RecordedTransaction(++_ids);
    TransactionSynchronizationManager.bindResource(this, created);
    events.add('begin ${created.id}');
  }

  RecordedTransaction _tx(Object transaction) =>
      (transaction as RecordingHolder).transaction!;

  @override
  Future<void> doCommit(Object transaction) async {
    events.add('commit ${_tx(transaction).id}');
    if (failCommit case final error?) {
      failCommit = null;
      throw error;
    }
  }

  @override
  Future<void> doRollback(Object transaction) async {
    events.add('rollback ${_tx(transaction).id}');
    if (failRollback case final error?) {
      failRollback = null;
      throw error;
    }
  }

  @override
  void doSetRollbackOnly(Object transaction) {
    _tx(transaction).rollbackOnly = true;
    events.add('rollbackOnly ${_tx(transaction).id}');
  }

  @override
  bool isRollbackOnly(Object transaction) =>
      (transaction as RecordingHolder).transaction?.rollbackOnly ?? false;

  @override
  Future<void> doCleanupAfterCompletion(Object transaction) async {
    TransactionSynchronizationManager.unbindResource(this);
    events.add('cleanup ${_tx(transaction).id}');
  }

  @override
  bool get supportsSavepoints => savepoints;

  @override
  Future<Object> createSavepoint(Object transaction) async {
    final tx = _tx(transaction);
    final id = ++tx.savepoints;
    events.add('savepoint ${tx.id} #$id');
    return id;
  }

  @override
  Future<void> rollbackToSavepoint(Object transaction, Object savepoint) async {
    events.add('rollbackTo ${_tx(transaction).id} #$savepoint');
  }

  @override
  Future<void> releaseSavepoint(Object transaction, Object savepoint) async {
    events.add('release ${_tx(transaction).id} #$savepoint');
  }
}

/// A synchronization that records its callbacks in [log].
final class RecordingSynchronization extends TransactionSynchronization {
  RecordingSynchronization(this.log, [this.name = 's']);

  final List<String> log;
  final String name;

  @override
  void beforeCommit({required bool readOnly}) =>
      log.add('$name beforeCommit readOnly=$readOnly');

  @override
  void beforeCompletion() => log.add('$name beforeCompletion');

  @override
  void afterCommit() => log.add('$name afterCommit');

  @override
  void afterCompletion(TransactionCompletion status) =>
      log.add('$name afterCompletion ${status.name}');
}
