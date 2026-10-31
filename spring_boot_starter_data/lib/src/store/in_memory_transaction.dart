import 'package:spring_boot_starter_data/src/store/row_locks.dart';
import 'package:spring_boot_starter_data/src/store/stored_aggregate.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';

/// Where an [InMemoryTransaction] is in its life.
enum InMemoryTransactionState {
  /// Operations are accepted.
  active,

  /// Committed: its writes are visible to all.
  committed,

  /// Rolled back: its writes are gone.
  rolledBack,
}

/// A transaction of the in-memory store: a private write set (the rows it
/// inserted, replaced and removed, with their children), the row locks it
/// holds, and a stack of savepoints. Isolation is read committed: its reads
/// see the committed rows overlaid with its own writes, and nothing of the
/// transactions still open.
///
/// The transaction manager of the store creates one with
/// `InMemoryDataStore.begin`, binds it with
/// `TransactionSynchronizationManager.bindResource(store, transaction)`
/// and ends it with `commit` or `rollback` of the store. Every operation of
/// the store finds it through the bound resource.
///
/// Spring (Java): `org.springframework.jdbc.datasource.ConnectionHolder`
/// (the resource a `DataSourceTransactionManager` binds), standing for the
/// connection with its open transaction.
final class InMemoryTransaction {
  /// A transaction, made by the store; use `InMemoryDataStore.begin`.
  InMemoryTransaction.internal({
    required this.id,
    required this.name,
    required this.readOnly,
    required this.isolation,
  });

  /// A number, unique in the store, for logs.
  final int id;

  /// The name in logs; null for none.
  final String? name;

  /// Whether it refuses writes.
  final bool readOnly;

  /// Its isolation level: `defaultLevel` or `readCommitted`, which are the
  /// same here.
  final Isolation isolation;

  /// Where it is in its life.
  InMemoryTransactionState state = InMemoryTransactionState.active;

  /// Whether it can only be rolled back.
  bool rollbackOnly = false;

  /// The rows written, by table, by id; null is a removed row. Internal to
  /// the store.
  Map<String, Map<Object?, StoredAggregate?>> writes = {};

  /// The writes of the statement running, to undo it when it fails (a
  /// statement is all or nothing, as in SQL); null between statements.
  /// Internal to the store.
  List<JournalEntry>? journal;

  /// The lock acquisitions, in order. Internal to the store.
  final acquisitions = <LockAcquisition>[];

  /// The lock waits in progress. Internal to the store.
  final pending = <LockWaiter>[];

  /// The savepoints, oldest first. Internal to the store.
  final savepoints = <InMemorySavepoint>[];

  /// Whether operations are accepted.
  bool get isActive => state == InMemoryTransactionState.active;

  /// Marks the transaction as one that can only be rolled back: a commit
  /// is then refused.
  void setRollbackOnly() => rollbackOnly = true;

  /// What logs show: `name#id` or `tx#id`.
  String get label => '${name ?? 'tx'}#$id';

  @override
  String toString() => 'InMemoryTransaction($label, $state)';
}

/// One write of a statement, with what the row was before it: kept to undo
/// a statement that failed. Internal to the in-memory store.
typedef JournalEntry = ({
  String table,
  Object? id,
  bool existed,
  StoredAggregate? previous,
});

/// A point in a transaction that it can return to, with the writes as they
/// were and without the locks taken since.
///
/// Spring (Java): `java.sql.Savepoint`.
final class InMemorySavepoint {
  /// A savepoint of [owner], made by the store.
  InMemorySavepoint.internal(this.owner, this.writes, this.acquisitionMark);

  /// The transaction it belongs to.
  final InMemoryTransaction owner;

  /// A copy of the write set at the moment of the savepoint. Internal.
  final Map<String, Map<Object?, StoredAggregate?>> writes;

  /// How many lock acquisitions had been made. Internal.
  final int acquisitionMark;

  /// Whether it was released or rolled past.
  bool released = false;
}
