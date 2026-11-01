import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/log_values.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/query/part_tree.dart';
import 'package:spring_boot_starter_data/src/query/query_arguments.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_transaction.dart';
import 'package:spring_boot_starter_data/src/store/row_locks.dart';
import 'package:spring_boot_starter_data/src/store/stored_aggregate.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_exceptions.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_synchronization_manager.dart';

/// A [DataStore] that keeps the aggregates in memory, in tables of rows,
/// like a database would: for tests, prototypes and applications whose
/// data may vanish with the process.
///
/// **Rows, not instances.** A table holds, for each aggregate, the row
/// that `EntityConverter.write` makes of the root and the rows of its
/// children (each `@MappedCollection`, with the position of a list element
/// or the key of a map entry). The application's objects are never kept:
/// what a find returns is a new object built from the row, so changing it
/// changes nothing in the store until it is saved, and what was saved is
/// not changed by later changes of the object.
///
/// **Ids.** A null `int` id is generated per table, counting up from 1
/// (an id that is set moves the counter past it); the ids of children
/// that are `int?` are generated the same way, in the stored rows. An id
/// of another type must be set by the application; a duplicate id on
/// insert is a `DuplicateKeyException`. A generated id is taken at the
/// insert and never given again, even when the transaction is rolled back
/// (like a sequence).
///
/// **`@Version`.** Insert sets it to 1 (an `int`) or to the current time (a
/// `DateTime`, made strictly greater at each write). Update checks the
/// stored version against the one of the instance, raises it, and throws an
/// `OptimisticLockingFailureException` when it differs or the aggregate is
/// gone; `deleteById` with a version checks it too.
///
/// **References and unique keys** behave as SQLite does with
/// `PRAGMA foreign_keys = ON` (the driver turns it on), so a test that
/// passes here does not fail in production: an insert or update of an
/// aggregate (or of one of its children) that references an aggregate that
/// does not exist throws a `DataIntegrityViolationException` (a null
/// reference is never checked; a row may reference itself); deleting an
/// aggregate that others reference follows the `@OnDelete` of the
/// reference: `noAction` (the default) fails at the end of the statement
/// when referencing rows remain, `restrict` fails at once, row by row (so a
/// delete of rows that reference each other may fail where `noAction`
/// passes), `cascade` deletes the referencing aggregates (or child rows) too,
/// recursively, `setNull`, `setDefault` (the property's default value)
/// sets their reference to null. A violated `@Unique` or `@UniqueConstraint`
/// is a `DuplicateKeyException`; rows with a null among the columns never
/// conflict. All of it runs inside the store's transactions (a rollback
/// undoes the cascades) and takes row locks: a reference locks the
/// referenced row shared, a unique value locks its value exclusively, so
/// concurrent transactions wait for each other as in PostgreSQL. A
/// statement is all or nothing. Like the database, a cascade or a `setNull`
/// does not go through the repository: no `@Version` check, no auditing on
/// the affected rows. The store knows the aggregates that reference others
/// from the ones it has written: an aggregate never saved has no rows to
/// cascade to. A reference must point to an aggregate root.
///
/// **Predicates** follow SQL: a comparison with null is false (`isNull`
/// and `isNotNull` aside), `simpleProperty` with a null argument means
/// `isNull` and `negatingSimpleProperty` `isNotNull`; `ignoreCase` lower
/// cases both sides; `like` takes `%` (any text) and `_` (one character)
/// with `\` to escape them; `startingWith`, `endingWith` and `containing`
/// take their argument literally (a `%` in it is a percent sign); `between`
/// is inclusive; `in` and `notIn` take a collection (`notIn` is false
/// for a value when the collection holds a null, as `NOT IN` is in SQL);
/// an `AggregateReference` property is compared by its id, the argument
/// being a reference or the id itself; numbers compare as numbers and a
/// `DateTime` by the moment.
///
/// **Sorting** takes several orders, each with its direction, `ignoreCase`
/// and null handling. By default (`NullHandling.native`) null is the
/// greatest value, as in PostgreSQL: nulls come last in ascending and first
/// in descending order. Equal keys keep the table's order, which is the
/// order of insertion.
///
/// **Transactions.** Without a transaction bound for the store (see
/// below) each operation runs alone, as a database does in auto-commit:
/// it reads and writes the tables in one go, without waiting in the
/// middle, so two saves of the same version cannot both succeed (one wins,
/// the other gets an `OptimisticLockingFailureException`); it waits for the
/// row locks of open transactions, as a database does.
///
/// With a transaction ([begin], bound as the resource of the store in
/// `TransactionSynchronizationManager`) the store is read committed:
///
/// - reads see the committed rows overlaid with the transaction's own
///   writes, never what other open transactions wrote (no dirty reads); a
///   row read twice may differ (non-repeatable reads are allowed);
/// - writes go to a private write set that [commit] applies in one
///   synchronous section and [rollback] throws away; the children of an
///   aggregate go with their root;
/// - a write takes an exclusive lock on its row, held until the
///   transaction ends. A write to a row locked by another transaction
///   waits, first come first served, then reads the row again as it is
///   after that transaction ended (as PostgreSQL does in read committed):
///   the second writer of a lost-update race gets an
///   `OptimisticLockingFailureException` with a `@Version`, and without
///   one writes over the fresh row. Inserting an id another open
///   transaction inserted waits, then fails with `DuplicateKeyException`
///   when that one committed;
/// - a wait ends after the smaller of the transaction's time left and the
///   [lockTimeout]: `CannotAcquireLockException`, or `QueryTimeoutException`
///   when the transaction's deadline cut it. A wait that would close a
///   cycle of waiting transactions fails at once with
///   `DeadlockLoserDataAccessException` (the caller then rolls back);
/// - a find with a lock ([LockMode]) locks the rows it reads: exclusive
///   for `pessimisticWrite`, shared for `pessimisticRead`; only inside a
///   transaction;
/// - savepoints ([createSavepoint]) restore the write set and release the
///   locks taken after them;
/// - a read-only transaction refuses writes and locking reads.
///
/// Differences from PostgreSQL: only row locks exist (no table locks, no
/// predicate locks, so no phantom protection for `deleteWhere` or a
/// locking `find`: a row that starts to match after the read is not
/// locked); a locking read locks the rows it returns and the ones it
/// skips for `offset`, like PostgreSQL, but `distinct` is allowed with a
/// lock; a transaction that lost a deadlock is not marked aborted (the
/// caller must roll it back); the isolation levels above read committed
/// are refused instead of being offered.
///
/// Logging, under `spring.data.memory.InMemoryDataStore`: each operation at
/// debug (the table and the counts), the transaction statements (`begin`,
/// `commit`, `rollback`, lock waits) at debug too, the values only at
/// trace.
///
/// Spring (Java): `JdbcAggregateTemplate` over an embedded database such as
/// H2 (`EmbeddedDatabaseBuilder`), which this store replaces for tests; the
/// transactions are what `DataSourceTransactionManager` gets from the
/// connection.
final class InMemoryDataStore implements DataStore {
  /// A store that converts entities with [converter]. [name] is what
  /// `@UseStore` selects (`memory`) and what the log shows; a store per
  /// `@UseDataSource` name is named `memory:<data source>`. [lockTimeout]
  /// is the longest a write or a lock waits for a row another transaction
  /// locked.
  InMemoryDataStore({
    required this.converter,
    this.name = 'memory',
    this.lockTimeout = const Duration(seconds: 10),
  });

  /// Turns the aggregates' instances into rows and back.
  final EntityConverter converter;

  @override
  final String name;

  /// The longest a statement waits for a row lock (the transaction's time
  /// left may cut it shorter); `Duration.zero` fails at once.
  final Duration lockTimeout;

  static const _log = SpringLog('spring.data.memory.InMemoryDataStore');

  final _tables = <String, _Table>{};
  final _entities = <String, PersistentEntity<Object>>{};
  List<_Node>? _nodeList;
  final _locks = RowLockManager();
  var _transactionCount = 0;

  /// The number of aggregates committed for [entity], for tests and logs.
  int size(PersistentEntity<Object> entity) => _table(entity).rows.length;

  /// How many statements wait for a row lock now, for tests and logs.
  int get waitingCount => _locks.waiting;

  /// Removes every committed row of every table and starts the ids again
  /// from 1.
  void clear() {
    _tables.clear();
    _log.debug('$name: cleared');
  }

  // --------------------------------------------------------- transactions

  /// Starts a transaction: [isolation] is `defaultLevel` or
  /// `readCommitted` (the same here), any other level is an
  /// `InvalidIsolationLevelException`, never a weaker one given silently.
  /// A [readOnly] transaction refuses writes and locking reads. [name] is
  /// for logs.
  ///
  /// Bind the result with
  /// `TransactionSynchronizationManager.bindResource(store, transaction)`
  /// so the operations of the store find it; end it with [commit] or
  /// [rollback].
  InMemoryTransaction begin({
    Isolation isolation = Isolation.defaultLevel,
    bool readOnly = false,
    String? name,
  }) {
    if (isolation != Isolation.defaultLevel &&
        isolation != Isolation.readCommitted) {
      throw InvalidIsolationLevelException(
        'The ${this.name} store offers read committed only: ${isolation.name} '
        'is refused',
      );
    }
    final tx = _newTransaction(
      name: name,
      readOnly: readOnly,
      isolation: isolation,
    );
    _log.debug(
      '${this.name}: begin ${tx.label}${readOnly ? ' read only' : ''}',
    );
    return tx;
  }

  InMemoryTransaction _newTransaction({
    String? name,
    bool readOnly = false,
    Isolation isolation = Isolation.defaultLevel,
  }) => InMemoryTransaction.internal(
    id: ++_transactionCount,
    name: name,
    readOnly: readOnly,
    isolation: isolation,
  );

  /// Makes the writes of [tx] visible to everyone, in one synchronous
  /// section, then releases its locks and wakes the transactions waiting
  /// for them.
  ///
  /// Throws an `IllegalTransactionStateException` when [tx] has ended, and
  /// when it is rollback-only (then it stays active: roll it back).
  Future<void> commit(InMemoryTransaction tx) => Future.sync(() {
    _requireActive(tx, 'commit');
    if (tx.rollbackOnly) {
      throw IllegalTransactionStateException(
        'The transaction ${tx.label} is rollback-only: roll it back instead '
        'of committing',
      );
    }
    _commit(tx);
  });

  void _commit(InMemoryTransaction tx) {
    var rows = 0;
    for (final MapEntry(:key, :value) in tx.writes.entries) {
      final table = _tables.putIfAbsent(key, _Table.new);
      for (final MapEntry(key: id, value: stored) in value.entries) {
        rows++;
        if (stored == null) {
          table.rows.remove(id);
        } else {
          table.rows[id] = stored;
        }
      }
    }
    _finish(tx, InMemoryTransactionState.committed);
    _log.debug('$name: commit ${tx.label}, $rows row(s) written');
  }

  /// Throws the writes of [tx] away, releases its locks and wakes the
  /// transactions waiting for them. Throws an
  /// `IllegalTransactionStateException` when [tx] has ended.
  Future<void> rollback(InMemoryTransaction tx) => Future.sync(() {
    _requireActive(tx, 'roll back');
    _rollback(tx);
  });

  void _rollback(InMemoryTransaction tx) {
    _finish(tx, InMemoryTransactionState.rolledBack);
    _log.debug('$name: rollback ${tx.label}');
  }

  void _finish(InMemoryTransaction tx, InMemoryTransactionState state) {
    tx
      ..state = state
      ..writes = {};
    for (final savepoint in tx.savepoints) {
      savepoint.released = true;
    }
    tx.savepoints.clear();
    _locks.releaseAll(tx);
  }

  /// Marks a point in [tx] that [rollbackToSavepoint] can return to.
  InMemorySavepoint createSavepoint(InMemoryTransaction tx) {
    _requireActive(tx, 'create a savepoint');
    final savepoint = InMemorySavepoint.internal(
      tx,
      _copyWrites(tx.writes),
      tx.acquisitions.length,
    );
    tx.savepoints.add(savepoint);
    _log.debug('$name: savepoint in ${tx.label}');
    return savepoint;
  }

  /// Puts the writes of [tx] back as they were at [savepoint] and releases
  /// the locks taken since (a lock made exclusive since is shared again),
  /// as PostgreSQL does for a rolled-back subtransaction. The savepoints
  /// made after it are gone; it stays usable.
  void rollbackToSavepoint(
    InMemoryTransaction tx,
    InMemorySavepoint savepoint,
  ) {
    _requireSavepoint(tx, savepoint, 'roll back to');
    tx.writes = _copyWrites(savepoint.writes);
    _locks.undoTo(tx, savepoint.acquisitionMark);
    _dropSavepointsAfter(tx, savepoint);
    _log.debug('$name: rollback to savepoint in ${tx.label}');
  }

  /// Forgets [savepoint] and the ones made after it; the writes and the
  /// locks stay.
  void releaseSavepoint(InMemoryTransaction tx, InMemorySavepoint savepoint) {
    _requireSavepoint(tx, savepoint, 'release');
    _dropSavepointsAfter(tx, savepoint);
    tx.savepoints.remove(savepoint);
    savepoint.released = true;
    _log.debug('$name: release savepoint in ${tx.label}');
  }

  void _dropSavepointsAfter(
    InMemoryTransaction tx,
    InMemorySavepoint savepoint,
  ) {
    final index = tx.savepoints.indexOf(savepoint);
    for (final later in tx.savepoints.sublist(index + 1)) {
      later.released = true;
    }
    tx.savepoints.removeRange(index + 1, tx.savepoints.length);
  }

  void _requireSavepoint(
    InMemoryTransaction tx,
    InMemorySavepoint savepoint,
    String what,
  ) {
    _requireActive(tx, what);
    if (savepoint.owner != tx || savepoint.released) {
      throw IllegalTransactionStateException(
        'Cannot $what a savepoint that belongs to another transaction or '
        'was released',
      );
    }
  }

  Map<String, Map<Object?, StoredAggregate?>> _copyWrites(
    Map<String, Map<Object?, StoredAggregate?>> writes,
  ) => {
    for (final MapEntry(:key, :value) in writes.entries) key: {...value},
  };

  void _requireActive(InMemoryTransaction tx, String what) {
    if (!tx.isActive) {
      throw IllegalTransactionStateException(
        'Cannot $what: the transaction ${tx.label} has already ended '
        '(${tx.state.name})',
      );
    }
  }

  // The transaction bound for this store in the current scope, if any,
  // after the checks every operation makes: the transaction's deadline,
  // that it is active, and that it may write when [write].
  InMemoryTransaction? _enter(String operation, {bool write = false}) {
    TransactionSynchronizationManager.currentTransactionFor(
      this,
    )?.checkDeadline(
      markRollbackOnly: () {
        if (TransactionSynchronizationManager.getResource(this)
            case final InMemoryTransaction timedOut) {
          timedOut.setRollbackOnly();
        }
      },
    );
    final bound = TransactionSynchronizationManager.getResource(this);
    if (bound == null) {
      return null;
    }
    if (bound is! InMemoryTransaction) {
      throw IllegalTransactionStateException(
        'The resource bound for the $name store is a '
        '${bound.runtimeType}, not an InMemoryTransaction',
      );
    }
    _requireActive(bound, operation);
    if (write && bound.readOnly) {
      throw InvalidDataAccessResourceUsageException(
        'cannot execute $operation in a read-only transaction',
      );
    }
    return bound;
  }

  // Runs a write in the bound transaction or, without one, in a
  // transaction of its own that commits when the write is done.
  Future<R> _write<R>(
    String operation,
    Future<R> Function(InMemoryTransaction tx) body,
  ) async {
    final bound = _enter(operation, write: true);
    if (bound != null) {
      return await _atomic(bound, () => body(bound));
    }
    final tx = _newTransaction(name: 'auto-commit');
    try {
      final result = await body(tx);
      _commit(tx);
      return result;
    } on Object {
      _finish(tx, InMemoryTransactionState.rolledBack);
      rethrow;
    }
  }

  // Runs a statement of [tx] so that it is all or nothing: its writes are
  // undone when it fails (the locks it took stay, as in a database).
  Future<R> _atomic<R>(
    InMemoryTransaction tx,
    Future<R> Function() body,
  ) async {
    if (tx.journal != null) {
      return await body();
    }
    final journal = tx.journal = [];
    try {
      return await body();
    } on Object {
      for (final entry in journal.reversed) {
        final written = tx.writes[entry.table] ??= {};
        if (entry.existed) {
          written[entry.id] = entry.previous;
        } else {
          written.remove(entry.id);
        }
      }
      rethrow;
    } finally {
      tx.journal = null;
    }
  }

  // The longest a wait for a lock lasts: the smaller of the lock timeout
  // (the call's, else the store's) and the transaction's time left.
  Future<void> _lock(
    InMemoryTransaction tx,
    RowKey key, {
    required bool exclusive,
    Duration? timeout,
  }) {
    final limit = timeout ?? lockTimeout;
    final left = TransactionSynchronizationManager.currentTransactionFor(
      this,
    )?.timeLeft;
    final byDeadline = left != null && left < limit;
    return _locks.acquire(
      tx,
      key,
      exclusive: exclusive,
      wait: byDeadline ? left : limit,
      deadlineBound: byDeadline,
      onWait: (blockedBy) => _log.debug(
        '$name: ${tx.label} waits for a lock on ${key.$1}, held by '
        '${blockedBy.join(', ')}',
      ),
    );
  }

  RowKey _key(PersistentEntity<Object> entity, Object? id) =>
      (_tableKey(entity), id);

  // ---------------------------------------------------------------- write

  @override
  Future<T> insert<T extends Object>(PersistentEntity<T> entity, T instance) =>
      _write('insert', (tx) => _insert(tx, entity, instance));

  Future<T> _insert<T extends Object>(
    InMemoryTransaction tx,
    PersistentEntity<T> entity,
    T instance,
  ) async {
    final idProperty = _requireId(entity);
    final table = _table(entity);
    var id = converter.toColumnValue(idProperty.getValue(instance));
    final generated = id == null;
    if (generated) {
      if (idProperty.type.type != int) {
        throw InvalidDataAccessApiUsageException(
          'The id ${_where(entity, idProperty)} is null and a '
          '${idProperty.type.type} cannot be generated: set it before '
          'saving',
        );
      }
      id = table.nextId++;
    } else if (id is int && id >= table.nextId) {
      table.nextId = id + 1;
    }
    // The lock of the id, also for a generated one: nobody can know it, but
    // an insert of the same id by hand must wait.
    await _lock(tx, _key(entity, id), exclusive: true);
    if (!generated && _get(tx, entity, id) != null) {
      throw DuplicateKeyException(
        'Duplicate id in table ${entity.tableName}',
        constraint: '${entity.tableName}_pkey',
      );
    }
    final versionProperty = entity.versionProperty;
    final version = versionProperty == null
        ? null
        : _nextVersion(versionProperty, null);
    final stored = _store(entity, instance);
    stored.values[idProperty.columnName] = id;
    if (versionProperty != null) {
      stored.values[versionProperty.columnName] = converter.toColumnValue(
        version,
      );
    }
    _register(entity);
    _put(tx, entity, id, stored);
    await _checkWrite(tx, entity, stored);
    _log.debug('$name: insert into ${entity.tableName}');
    _trace('insert', entity, stored.values);
    return await _withIdAndVersion(
      entity,
      instance,
      idProperty,
      generated ? id : null,
      versionProperty,
      version,
    );
  }

  @override
  Future<T> update<T extends Object>(
    PersistentEntity<T> entity,
    T instance, {
    Object? expectedVersion,
  }) => _write(
    'update',
    (tx) => _update(tx, entity, instance, expectedVersion: expectedVersion),
  );

  Future<T> _update<T extends Object>(
    InMemoryTransaction tx,
    PersistentEntity<T> entity,
    T instance, {
    Object? expectedVersion,
  }) async {
    final idProperty = _requireId(entity);
    final id = converter.toColumnValue(idProperty.getValue(instance));
    if (id == null) {
      throw InvalidDataAccessApiUsageException(
        'Cannot update ${entity.introspection.className}: its id is null',
      );
    }
    final versionProperty = entity.versionProperty;
    // A row that is not there or has another version is not waited for: no
    // row matches the statement, as `update ... where version = ?` finds
    // none. The row is checked again once the lock is had.
    _checkUpdate(entity, instance, _get(tx, entity, id), expectedVersion);
    await _lock(tx, _key(entity, id), exclusive: true);
    final version = _checkUpdate(
      entity,
      instance,
      _get(tx, entity, id),
      expectedVersion,
    );
    final stored = _store(entity, instance);
    stored.values[idProperty.columnName] = id;
    if (versionProperty != null) {
      stored.values[versionProperty.columnName] = converter.toColumnValue(
        version,
      );
    }
    _register(entity);
    _put(tx, entity, id, stored);
    await _checkWrite(tx, entity, stored);
    _log.debug('$name: update ${entity.tableName}');
    _trace('update', entity, stored.values);
    return await _withIdAndVersion(
      entity,
      instance,
      idProperty,
      null,
      versionProperty,
      version,
    );
  }

  // Throws when [existing] cannot be updated by [instance]; returns the
  // version it gets (null without a @Version).
  Object? _checkUpdate(
    PersistentEntity<Object> entity,
    Object instance,
    StoredAggregate? existing,
    Object? expectedVersion,
  ) {
    final versionProperty = entity.versionProperty;
    if (versionProperty == null) {
      if (existing == null) {
        throw IncorrectUpdateSemanticsDataAccessException(
          'Failed to update ${entity.introspection.className} in table '
          '${entity.tableName}: no row has this id (an entity with an id is '
          'updated, not inserted; give an entity whose id is set by the '
          'application a @Version property)',
        );
      }
      return null;
    }
    final expected = converter.toColumnValue(
      expectedVersion ?? versionProperty.getValue(instance),
    );
    if (existing == null ||
        !_equals(existing.values[versionProperty.columnName], expected)) {
      throw OptimisticLockingFailureException(
        'Failed to update ${entity.introspection.className} in table '
        '${entity.tableName}: it was changed or deleted since it was '
        'loaded (its version no longer matches)',
      );
    }
    return _nextVersion(
      versionProperty,
      existing.values[versionProperty.columnName],
    );
  }

  @override
  Future<bool> deleteById<T extends Object>(
    PersistentEntity<T> entity,
    Object id, {
    Object? expectedVersion,
  }) => _write('delete', (tx) async {
    final columnId = converter.toColumnValue(id);
    final versionProperty = entity.versionProperty;
    void check(StoredAggregate? existing) {
      if (expectedVersion != null && versionProperty != null) {
        if (existing == null ||
            !_equals(
              existing.values[versionProperty.columnName],
              converter.toColumnValue(expectedVersion),
            )) {
          throw OptimisticLockingFailureException(
            'Failed to delete ${entity.introspection.className} from table '
            '${entity.tableName}: it was changed or deleted since it was '
            'loaded (its version no longer matches)',
          );
        }
      }
    }

    var existing = _get(tx, entity, columnId);
    check(existing);
    if (existing != null) {
      await _lock(tx, _key(entity, columnId), exclusive: true);
      existing = _get(tx, entity, columnId);
      check(existing);
    }
    if (existing != null) {
      await _removeRows(tx, entity, [existing]);
    }
    _log.debug(
      '$name: delete from ${entity.tableName}, ${existing == null ? 0 : 1} '
      'row(s)',
    );
    return existing != null;
  });

  @override
  Future<int> deleteWhere<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => _write(
    'delete',
    (tx) async => (await _deleteWhere(tx, entity, criteria)).length,
  );

  @override
  Future<List<T>> deleteWhereAndReturn<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => _write('delete', (tx) async {
    final removed = await _deleteWhere(tx, entity, criteria);
    return [for (final stored in removed) _read(entity, stored)];
  });

  // Locks the rows that match, one after the other; when a wait happened
  // the rows are looked for again, as they may have changed meanwhile.
  Future<List<StoredAggregate>> _deleteWhere(
    InMemoryTransaction tx,
    PersistentEntity<Object> entity,
    Criteria? criteria,
  ) async {
    final idColumn = _requireId(entity).columnName;
    while (true) {
      final matches = _matching(entity, criteria, tx);
      var waited = false;
      for (final stored in matches) {
        final key = _key(entity, stored.values[idColumn]);
        if (!_locks.tryAcquire(tx, key, exclusive: true)) {
          await _lock(tx, key, exclusive: true);
          waited = true;
          break;
        }
      }
      if (!waited) {
        await _removeRows(tx, entity, matches);
        _log.debug(
          '$name: delete from ${entity.tableName} where '
          '${criteria ?? 'all'}, ${matches.length} row(s)',
        );
        return matches;
      }
    }
  }

  // ----------------------------------------------------------------- read

  @override
  Future<T?> findById<T extends Object>(
    PersistentEntity<T> entity,
    Object id, {
    LockMode? lock,
    Duration? lockTimeout,
    bool skipLocked = false,
  }) async {
    final tx = _enter('select', write: lock != null);
    final columnId = converter.toColumnValue(id);
    var stored = _get(tx, entity, columnId);
    if (lock != null && stored != null) {
      final key = _key(entity, columnId);
      final exclusive = lock == LockMode.pessimisticWrite;
      if (!_locks.tryAcquire(
        _requireLockTx(tx, lock),
        key,
        exclusive: exclusive,
      )) {
        if (skipLocked) {
          stored = null;
        } else {
          await _lock(tx!, key, exclusive: exclusive, timeout: lockTimeout);
          stored = _get(tx, entity, columnId);
        }
      }
    } else if (lock != null) {
      _requireLockTx(tx, lock);
    }
    _log.debug(
      '$name: select from ${entity.tableName} by id'
      '${_lockSuffix(lock, skipLocked)}, ${stored == null ? 0 : 1} row(s)',
    );
    return stored == null ? null : _read<T>(entity, stored);
  }

  // A locking read needs a transaction: it never runs unlocked.
  InMemoryTransaction _requireLockTx(InMemoryTransaction? tx, LockMode lock) =>
      tx ??
      (throw IllegalTransactionStateException(
        'A read with ${lock.name} needs a transaction: it never runs '
        'without its lock',
      ));

  String _lockSuffix(LockMode? lock, bool skipLocked) => lock == null
      ? ''
      : ' for ${lock == LockMode.pessimisticWrite ? 'update' : 'share'}'
            '${skipLocked ? ' skip locked' : ''}';

  @override
  Future<List<T>> findAllById<T extends Object>(
    PersistentEntity<T> entity,
    Iterable<Object> ids,
  ) => Future.sync(() {
    final tx = _enter('select');
    final wanted = {for (final id in ids) converter.toColumnValue(id)};
    final idColumn = _requireId(entity).columnName;
    final found = [
      for (final stored in _rows(entity, tx))
        if (wanted.contains(stored.values[idColumn])) stored,
    ];
    _log.debug(
      '$name: select from ${entity.tableName} by ${wanted.length} id(s), '
      '${found.length} row(s)',
    );
    return [for (final stored in found) _read(entity, stored)];
  });

  @override
  Future<List<T>> find<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
    Sort sort = Sort.unsorted,
    int? offset,
    int? limit,
    bool distinct = false,
    LockMode? lock,
    Duration? lockTimeout,
    bool skipLocked = false,
  }) async {
    if (offset != null && offset < 0) {
      throw InvalidDataAccessApiUsageException(
        'The offset must not be negative: $offset',
      );
    }
    final tx = _enter('select', write: lock != null);
    if (lock != null) {
      _requireLockTx(tx, lock);
    }
    List<StoredAggregate> selected;
    if (lock == null) {
      selected = _slice(
        _ordered(entity, criteria, sort, distinct, tx),
        offset,
        limit,
      );
    } else {
      selected = await _selectLocking(
        tx!,
        entity,
        lock,
        criteria: criteria,
        sort: sort,
        offset: offset,
        limit: limit,
        distinct: distinct,
        timeout: lockTimeout,
        skipLocked: skipLocked,
      );
    }
    _log.debug(
      '$name: select from ${entity.tableName} where ${criteria ?? 'all'}'
      '${sort.isSorted ? ' order by $sort' : ''}'
      '${offset == null ? '' : ' offset $offset'}'
      '${limit == null ? '' : ' limit $limit'}'
      '${_lockSuffix(lock, skipLocked)}, ${selected.length} row(s)',
    );
    if (criteria != null &&
        criteria.arguments.isNotEmpty &&
        _log.isEnabled(SpringLogLevel.trace)) {
      _log.trace('$name: arguments ${LogValues.criteria(criteria)}');
    }
    return [for (final stored in selected) _read(entity, stored)];
  }

  List<StoredAggregate> _ordered(
    PersistentEntity<Object> entity,
    Criteria? criteria,
    Sort sort,
    bool distinct,
    InMemoryTransaction? tx,
  ) {
    var rows = _matching(entity, criteria, tx);
    if (sort.isSorted) {
      rows = _sorted(entity, rows, sort);
    }
    return distinct ? _distinct(rows) : rows;
  }

  List<StoredAggregate> _slice(
    List<StoredAggregate> rows,
    int? offset,
    int? limit,
  ) {
    var out = rows;
    if (offset != null && offset > 0) {
      out = out.length <= offset ? const [] : out.sublist(offset);
    }
    if (limit != null && limit < out.length) {
      out = out.sublist(0, limit < 0 ? 0 : limit);
    }
    return out;
  }

  // The rows of a read with a lock, locked in order. Rows another
  // transaction holds are skipped (and do not count for offset or limit)
  // with [skipLocked], else waited for; after a wait the rows are looked
  // for again, as they may have changed meanwhile. The locks already taken
  // are kept.
  Future<List<StoredAggregate>> _selectLocking(
    InMemoryTransaction tx,
    PersistentEntity<Object> entity,
    LockMode lock, {
    required Criteria? criteria,
    required Sort sort,
    required int? offset,
    required int? limit,
    required bool distinct,
    required Duration? timeout,
    required bool skipLocked,
  }) async {
    final idColumn = _requireId(entity).columnName;
    final exclusive = lock == LockMode.pessimisticWrite;
    while (true) {
      final rows = _ordered(entity, criteria, sort, distinct, tx);
      final taken = <StoredAggregate>[];
      var toSkip = offset == null || offset < 0 ? 0 : offset;
      var waited = false;
      for (final stored in rows) {
        if (limit != null && taken.length >= (limit < 0 ? 0 : limit)) {
          break;
        }
        final key = _key(entity, stored.values[idColumn]);
        if (!_locks.tryAcquire(tx, key, exclusive: exclusive)) {
          if (skipLocked) {
            continue;
          }
          await _lock(tx, key, exclusive: exclusive, timeout: timeout);
          waited = true;
          break;
        }
        if (toSkip > 0) {
          toSkip--;
        } else {
          taken.add(stored);
        }
      }
      if (!waited) {
        return taken;
      }
    }
  }

  @override
  Future<int> count<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => Future.sync(() {
    final tx = _enter('select');
    final count = _matching(entity, criteria, tx).length;
    _log.debug(
      '$name: count ${entity.tableName} where ${criteria ?? 'all'}: $count',
    );
    return count;
  });

  @override
  Future<bool> exists<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => Future.sync(() {
    final tx = _enter('select');
    final exists = _matching(entity, criteria, tx).isNotEmpty;
    _log.debug(
      '$name: exists ${entity.tableName} where ${criteria ?? 'all'}: '
      '$exists',
    );
    return exists;
  });

  // ------------------------------------------------------------- internals

  String _tableKey(PersistentEntity<Object> entity) =>
      '${entity.schema == null ? '' : '${entity.schema}.'}${entity.tableName}';

  _Table _table(PersistentEntity<Object> entity) =>
      _tables.putIfAbsent(_tableKey(entity), _Table.new);

  // ------------------------------------------- references and constraints

  // Remembers that [entity] was written: its rows may reference others.
  void _register(PersistentEntity<Object> entity) {
    final key = _tableKey(entity);
    if (!_entities.containsKey(key)) {
      _entities[key] = entity;
      _nodeList = null;
    }
  }

  // Every table the written aggregates have: the roots and their children.
  List<_Node> get _nodes => _nodeList ??= [
    for (final root in _entities.values) ..._nodesOf(root, root, const []),
  ];

  List<_Node> _nodesOf(
    PersistentEntity<Object> root,
    PersistentEntity<Object> entity,
    List<PersistentProperty> path,
  ) => [
    _Node(_tableKey(entity), entity, root, path),
    for (final p in entity.properties)
      if (p.isMappedCollection) ..._nodesOf(root, p.childEntity!, [...path, p]),
  ];

  // The rows of [node]'s table as [tx] sees them, each with its root.
  Iterable<(StoredAggregate root, StoredAggregate row)> _nodeRows(
    _Node node,
    InMemoryTransaction? tx,
  ) sync* {
    for (final root in _rows(node.root, tx)) {
      for (final row in _descend(root, node.path, 0)) {
        yield (root, row);
      }
    }
  }

  Iterable<StoredAggregate> _descend(
    StoredAggregate aggregate,
    List<PersistentProperty> path,
    int depth,
  ) sync* {
    if (depth == path.length) {
      yield aggregate;
      return;
    }
    for (final child
        in aggregate.children[path[depth].name] ?? const <StoredChild>[]) {
      yield* _descend(child.stored, path, depth + 1);
    }
  }

  // [aggregate] with [edit] applied to the rows of [path]'s table: [edit]
  // returns the row to keep (the same one to leave it), or null to remove
  // it. The aggregate itself when nothing changed.
  StoredAggregate _rewrite(
    StoredAggregate aggregate,
    List<PersistentProperty> path,
    int depth,
    StoredAggregate? Function(StoredAggregate row) edit,
  ) {
    if (depth == path.length) {
      return edit(aggregate) ?? aggregate;
    }
    final property = path[depth];
    final children = aggregate.children[property.name];
    if (children == null) {
      return aggregate;
    }
    var changed = false;
    final kept = <StoredChild>[];
    for (final child in children) {
      final next = depth + 1 == path.length
          ? edit(child.stored)
          : _rewrite(child.stored, path, depth + 1, edit);
      if (!identical(next, child.stored)) {
        changed = true;
      }
      if (next != null) {
        kept.add(next == child.stored ? child : StoredChild(child.key, next));
      }
    }
    return changed
        ? StoredAggregate(aggregate.values, {
            ...aggregate.children,
            property.name: kept,
          })
        : aggregate;
  }

  // The nodes' references to [entity].
  List<(_Node, PersistentProperty)> _referencesTo(
    PersistentEntity<Object> entity,
  ) => [
    for (final node in _nodes)
      for (final p in node.entity.references)
        if (p.referencedEntityType == entity.type) (node, p),
  ];

  // The root rows that hold a row of [node] whose [property] is [value].
  List<StoredAggregate> _referencing(
    InMemoryTransaction? tx,
    _Node node,
    PersistentProperty property,
    Object? value,
  ) => [
    for (final root in _rows(node.root, tx))
      if (_descend(root, node.path, 0).any(
        (row) => _equals(row.values[property.columnName], value),
      ))
        root,
  ];

  // The checks that follow a write of [aggregate]: its references exist, its
  // unique values are unique. They come after the write, so that a row may
  // reference itself, as in SQL.
  Future<void> _checkWrite(
    InMemoryTransaction tx,
    PersistentEntity<Object> entity,
    StoredAggregate aggregate,
  ) async {
    for (final p in entity.references) {
      final value = aggregate.values[p.columnName];
      if (value == null) {
        continue;
      }
      final target = p.referencedEntity!();
      await _lock(tx, _key(target, value), exclusive: false);
      if (_get(tx, target, value) == null) {
        throw DataIntegrityViolationException(
          'FOREIGN KEY constraint failed: ${entity.tableName}.'
          '${p.columnName} references ${target.tableName}, which has no '
          'such row',
          constraint: 'fk_${entity.tableName}_${p.columnName}',
        );
      }
    }
    for (final constraint in entity.uniqueConstraints) {
      final values = [
        for (final p in constraint.properties) aggregate.values[p.columnName],
      ];
      if (values.contains(null)) {
        continue;
      }
      final key = _tableKey(entity);
      await _lock(
        tx,
        ('unique:$key:${constraint.name}', _tupleKey(values)),
        exclusive: true,
      );
      final clash = [
        for (final node in _nodes)
          if (node.tableKey == key)
            for (final (_, row) in _nodeRows(node, tx))
              if (!identical(row, aggregate) &&
                  constraint.properties.every(
                    (p) => _equals(
                      row.values[p.columnName],
                      aggregate.values[p.columnName],
                    ),
                  ))
                row,
      ];
      if (clash.isNotEmpty) {
        final columns = [
          for (final p in constraint.properties)
            '${entity.tableName}.${p.columnName}',
        ];
        throw DuplicateKeyException(
          'UNIQUE constraint failed: ${columns.join(', ')}',
          constraint: constraint.name,
        );
      }
    }
    for (final p in entity.properties) {
      if (!p.isMappedCollection) {
        continue;
      }
      for (final child in aggregate.children[p.name] ?? const <StoredChild>[]) {
        await _checkWrite(tx, p.childEntity!, child.stored);
      }
    }
  }

  static String _tupleKey(List<Object?> values) => [
    for (final v in values) '${v.runtimeType}:$v',
  ].join('\u0000');

  // Removes [rows] of [entity] (one statement) and does what the
  // references to them ask. The delete of an aggregate that others
  // reference follows the `@OnDelete` of each reference: see the class
  // comment.
  Future<void> _removeRows(
    InMemoryTransaction tx,
    PersistentEntity<Object> entity,
    List<StoredAggregate> rows,
  ) async {
    final deferred = <(_Node, PersistentProperty, Object?)>[];
    await _removeRowsIn(tx, entity, rows, deferred);
    // `noAction` is checked when the statement ends, `restrict` at once.
    for (final (node, property, id) in deferred) {
      if (_referencing(tx, node, property, id).isNotEmpty) {
        throw _stillReferenced(entity, node, property);
      }
    }
  }

  Future<void> _removeRowsIn(
    InMemoryTransaction tx,
    PersistentEntity<Object> entity,
    List<StoredAggregate> rows,
    List<(_Node, PersistentProperty, Object?)> deferred,
  ) async {
    final idColumn = _requireId(entity).columnName;
    for (final stored in rows) {
      final id = stored.values[idColumn];
      _put(tx, entity, id, null);
      for (final (node, property) in _referencesTo(entity)) {
        await _followDelete(tx, entity, id, node, property, deferred);
      }
    }
  }

  // What the reference [property] of [node] does when the row [id] of
  // [entity] is gone.
  Future<void> _followDelete(
    InMemoryTransaction tx,
    PersistentEntity<Object> entity,
    Object? id,
    _Node node,
    PersistentProperty property,
    List<(_Node, PersistentProperty, Object?)> deferred,
  ) async {
    final action = property.onDelete;
    if (_referencing(tx, node, property, id).isEmpty) {
      return;
    }
    if (action == OnDeleteAction.restrict) {
      throw _stillReferenced(entity, node, property);
    }
    if (action == OnDeleteAction.noAction) {
      deferred.add((node, property, id));
      return;
    }
    // The aggregates to change are locked; after a wait they are looked for
    // again, as they may have changed meanwhile.
    List<StoredAggregate> affected;
    while (true) {
      affected = _referencing(tx, node, property, id);
      final rootId = _requireId(node.root).columnName;
      var waited = false;
      for (final root in affected) {
        final key = _key(node.root, root.values[rootId]);
        if (!_locks.tryAcquire(tx, key, exclusive: true)) {
          await _lock(tx, key, exclusive: true);
          waited = true;
          break;
        }
      }
      if (!waited) {
        break;
      }
    }
    if (affected.isEmpty) {
      return;
    }
    final rootEntity = node.root;
    final rootId = _requireId(rootEntity).columnName;
    if (action == OnDeleteAction.cascade && node.path.isEmpty) {
      await _removeRowsIn(tx, rootEntity, affected, deferred);
      return;
    }
    final column = property.columnName;
    // setDefault: the property's default (as its column holds it); null
    // without one, as SQLite without a DEFAULT clause.
    final replacement =
        action == OnDeleteAction.setDefault && property.hasDefaultValue
        ? converter.toColumnValue(property.defaultValue)
        : null;
    if (action == OnDeleteAction.setDefault &&
        replacement != null &&
        (_equals(replacement, id) || _get(tx, entity, replacement) == null)) {
      throw _stillReferenced(entity, node, property);
    }
    if (action != OnDeleteAction.cascade &&
        replacement == null &&
        !property.isNullable) {
      throw DataIntegrityViolationException(
        'NOT NULL constraint failed: ${node.entity.tableName}.$column '
        'cannot be set to null when ${entity.tableName} is deleted '
        '($action)',
        constraint: 'fk_${node.entity.tableName}_$column',
      );
    }
    for (final root in affected) {
      final next = _rewrite(
        root,
        node.path,
        0,
        (row) => !_equals(row.values[column], id)
            ? row
            : action == OnDeleteAction.cascade
            ? null
            : StoredAggregate({
                ...row.values,
                column: replacement,
              }, row.children),
      );
      _put(tx, rootEntity, root.values[rootId], next);
    }
  }

  DataIntegrityViolationException _stillReferenced(
    PersistentEntity<Object> entity,
    _Node node,
    PersistentProperty property,
  ) => DataIntegrityViolationException(
    'FOREIGN KEY constraint failed: ${node.entity.tableName}.'
    '${property.columnName} still references ${entity.tableName}',
    constraint: 'fk_${node.entity.tableName}_${property.columnName}',
  );

  // The row with [id] as [tx] sees it: its own write, else the committed
  // row.
  StoredAggregate? _get(
    InMemoryTransaction? tx,
    PersistentEntity<Object> entity,
    Object? id,
  ) {
    final written = tx?.writes[_tableKey(entity)];
    if (written != null && written.containsKey(id)) {
      return written[id];
    }
    return _table(entity).rows[id];
  }

  // Records a write of [tx], or of nobody (null [stored] removes the row).
  void _put(
    InMemoryTransaction tx,
    PersistentEntity<Object> entity,
    Object? id,
    StoredAggregate? stored,
  ) {
    final key = _tableKey(entity);
    final written = tx.writes[key] ??= {};
    tx.journal?.add((
      table: key,
      id: id,
      existed: written.containsKey(id),
      previous: written[id],
    ));
    written[id] = stored;
  }

  // The rows of the table as [tx] sees them (the committed ones without
  // a transaction): the committed rows, the ones [tx] changed replaced and
  // the ones it removed left out, then the ones it inserted.
  List<StoredAggregate> _rows(
    PersistentEntity<Object> entity,
    InMemoryTransaction? tx,
  ) {
    final committed = _table(entity).rows;
    final written = tx?.writes[_tableKey(entity)];
    if (written == null || written.isEmpty) {
      return committed.values.toList();
    }
    return [
      for (final MapEntry(:key, :value) in committed.entries)
        if (!written.containsKey(key)) value else ?written[key],
      for (final MapEntry(:key, :value) in written.entries)
        if (value != null && !committed.containsKey(key)) value,
    ];
  }

  List<StoredAggregate> _matching(
    PersistentEntity<Object> entity,
    Criteria? criteria,
    InMemoryTransaction? tx,
  ) {
    final rows = _rows(entity, tx);
    if (criteria == null || criteria.isEmpty) {
      return rows;
    }
    final matches = _compile(entity, criteria);
    return [
      for (final stored in rows)
        if (matches(stored.values)) stored,
    ];
  }

  PersistentProperty _requireId(PersistentEntity<Object> entity) =>
      entity.idProperty ??
      (throw InvalidDataAccessApiUsageException(
        '${entity.introspection.className} has no @Id property: the '
        'in-memory store keeps aggregates by id',
      ));

  String _where(PersistentEntity<Object> entity, PersistentProperty p) =>
      '${entity.introspection.className}.${p.name}';

  void _trace(
    String what,
    PersistentEntity<Object> entity,
    Map<String, Object?> values,
  ) {
    if (_log.isEnabled(SpringLogLevel.trace)) {
      _log.trace('$name: $what ${entity.tableName} ${LogValues.map(values)}');
    }
  }

  Object _nextVersion(PersistentProperty property, Object? old) {
    if (property.type.type == DateTime) {
      var now = DateTime.now();
      if (old is DateTime && !now.isAfter(old)) {
        now = old.add(const Duration(microseconds: 1));
      }
      return now;
    }
    return (old is int ? old : 0) + 1;
  }

  // The instance as saved: with the generated id and the new version. The
  // changes are applied last, so a failed write leaves the application's
  // instance untouched.
  T _withIdAndVersion<T extends Object>(
    PersistentEntity<T> entity,
    T instance,
    PersistentProperty idProperty,
    Object? generatedId,
    PersistentProperty? versionProperty,
    Object? version,
  ) {
    final changes = <String, Object?>{
      idProperty.name: ?generatedId,
      if (versionProperty != null) versionProperty.name: version,
    };
    return changes.isEmpty
        ? instance
        : converter.withValues(entity, instance, changes);
  }

  // The row of [instance] and of its children.
  StoredAggregate _store(PersistentEntity<Object> entity, Object instance) {
    final values = converter.write(entity, instance);
    for (final key in values.keys.toList()) {
      values[key] = _copy(values[key]);
    }
    final children = <String, List<StoredChild>>{};
    for (final property in entity.properties) {
      if (!property.isMappedCollection) {
        continue;
      }
      final value = property.getValue(instance);
      if (value == null) {
        continue;
      }
      final child = property.childEntity!;
      final childTable = _table(child);
      final childId = child.idProperty;
      StoredChild make(Object? key, Object element) {
        final stored = _store(child, element);
        if (childId != null) {
          final id = stored.values[childId.columnName];
          if (id == null && childId.type.type == int) {
            stored.values[childId.columnName] = childTable.nextId++;
          } else if (id is int && id >= childTable.nextId) {
            childTable.nextId = id + 1;
          }
        }
        return StoredChild(key, stored);
      }

      children[property.name] = switch (value) {
        final Map<Object?, Object?> map => [
          for (final entry in map.entries) make(entry.key, entry.value!),
        ],
        final List<Object?> list => [
          for (final (index, element) in list.indexed) make(index, element!),
        ],
        final Iterable<Object?> items => [
          for (final element in items) make(null, element!),
        ],
        _ => throw MappingException(
          '${_where(entity, property)}: a mapped collection must be a '
          'List, a Set or a Map, not a ${value.runtimeType}',
        ),
      };
    }
    return StoredAggregate(values, children);
  }

  // A new instance of the aggregate stored as [stored].
  T _read<T extends Object>(
    PersistentEntity<T> entity,
    StoredAggregate stored,
  ) {
    final children = <String, Object?>{};
    for (final property in entity.properties) {
      if (!property.isMappedCollection) {
        continue;
      }
      final rows = stored.children[property.name];
      if (rows == null) {
        continue;
      }
      final child = property.childEntity!;
      children[property.name] = property.type is MapType<Object?, Object?>
          ? {for (final row in rows) row.key: _read(child, row.stored)}
          : [for (final row in rows) _read(child, row.stored)];
    }
    return converter.read(
      entity,
      {
        for (final MapEntry(:key, :value) in stored.values.entries)
          key: _copy(value),
      },
      children: children,
    );
  }

  static Object? _copy(Object? value) =>
      value is Uint8List ? Uint8List.fromList(value) : value;

  // ------------------------------------------------------------ predicates

  // ------------------------------------------------------------ predicates

  bool Function(Map<String, Object?> row) _compile(
    PersistentEntity<Object> entity,
    Criteria criteria,
  ) {
    var next = 0;
    final alternatives = <List<bool Function(Map<String, Object?>)>>[];
    for (final or in criteria.predicate) {
      final conjunction = <bool Function(Map<String, Object?>)>[];
      for (final part in or.parts) {
        final property = _column(entity, part.path.first, 'a condition');
        final count = part.type.argumentCount;
        final arguments = criteria.arguments.sublist(next, next + count);
        next += count;
        final test = _test(entity, property, part, arguments);
        final column = property.columnName;
        conjunction.add((row) => test(row[column]));
      }
      alternatives.add(conjunction);
    }
    return (row) => alternatives.any((all) => all.every((test) => test(row)));
  }

  PersistentProperty _column(
    PersistentEntity<Object> entity,
    String name,
    String where,
  ) {
    final property = entity.property(name);
    if (property == null || property.isMappedCollection) {
      if (where == 'sorting') {
        throw PropertyReferenceException(name, entity.introspection.className);
      }
      throw InvalidDataAccessApiUsageException(
        'No column ${LogFormatUtils.formatValue(name)} of '
        '${entity.introspection.className} for $where',
      );
    }
    return property;
  }

  Object? _fold(Object? value, {required bool ignoreCase}) =>
      ignoreCase && value is String ? value.toLowerCase() : value;

  bool Function(Object? value) _test(
    PersistentEntity<Object> entity,
    PersistentProperty property,
    Part part,
    List<Object?> arguments,
  ) {
    final ic = part.ignoreCase;
    Object? argument(int index) {
      final value = converter.toColumnValue(arguments[index]);
      rejectNul(value, property.name);
      return _fold(value, ignoreCase: ic);
    }

    Object? fold(Object? value) => _fold(value, ignoreCase: ic);
    bool compare(Object? value, Object? other, bool Function(int c) holds) {
      if (value == null || other == null) {
        return false;
      }
      final c = _compare(fold(value), other);
      return c != null && holds(c);
    }

    switch (part.type) {
      case PartType.isNull:
        return (value) => value == null;
      case PartType.isNotNull:
        return (value) => value != null;
      case PartType.isTrue:
        return (value) => value == true;
      case PartType.isFalse:
        return (value) => value == false;
      case PartType.simpleProperty:
        final other = argument(0);
        return other == null
            ? (value) => value == null
            : (value) => value != null && _equals(fold(value), other);
      case PartType.negatingSimpleProperty:
        final other = argument(0);
        return other == null
            ? (value) => value != null
            : (value) => value != null && !_equals(fold(value), other);
      case PartType.lessThan:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c < 0);
      case PartType.lessThanEqual:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c <= 0);
      case PartType.greaterThan:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c > 0);
      case PartType.greaterThanEqual:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c >= 0);
      case PartType.between:
        final low = argument(0);
        final high = argument(1);
        return (value) =>
            compare(value, low, (c) => c >= 0) &&
            compare(value, high, (c) => c <= 0);
      case PartType.like || PartType.notLike:
        final pattern = argument(0);
        final negate = part.type == PartType.notLike;
        final regex = pattern is String ? _likeRegex(pattern) : null;
        return (value) {
          if (value is! String || regex == null) {
            return false;
          }
          return regex.hasMatch(fold(value)! as String) != negate;
        };
      case PartType.startingWith:
        return _literal(argument(0), fold, (v, a) => v.startsWith(a));
      case PartType.endingWith:
        return _literal(argument(0), fold, (v, a) => v.endsWith(a));
      case PartType.containing:
        return _literal(argument(0), fold, (v, a) => v.contains(a));
      case PartType.notContaining:
        return _literal(argument(0), fold, (v, a) => !v.contains(a));
      case PartType.in_ || PartType.notIn:
        final raw = arguments[0];
        if (raw is! Iterable<Object?>) {
          throw InvalidDataAccessApiUsageException(
            "'${property.name}' ${part.type.name} needs a collection, not "
            '${raw == null ? 'null' : raw.runtimeType}',
          );
        }
        final elements = [
          for (final element in raw)
            _fold(converter.toColumnValue(element), ignoreCase: ic),
        ];
        for (final element in elements) {
          rejectNul(element, property.name);
        }
        if (part.type == PartType.in_) {
          return (value) =>
              value != null &&
              elements.any((e) => e != null && _equals(fold(value), e));
        }
        final hasNull = elements.contains(null);
        return (value) {
          if (elements.isEmpty) {
            return true;
          }
          return value != null &&
              !hasNull &&
              !elements.any((e) => _equals(fold(value), e));
        };
    }
  }

  bool Function(Object? value) _literal(
    Object? argument,
    Object? Function(Object?) fold,
    bool Function(String value, String argument) holds,
  ) =>
      (value) =>
          value is String &&
          argument is String &&
          holds(fold(value)! as String, argument);

  // `%` any text, `_` one character, `\` makes the next one literal.
  RegExp? _likeRegex(String pattern) {
    final out = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == r'\' && i + 1 < pattern.length) {
        out.write(RegExp.escape(pattern[++i]));
      } else if (c == '%') {
        out.write('.*');
      } else if (c == '_') {
        out.write('.');
      } else {
        out.write(RegExp.escape(c));
      }
    }
    out.write(r'$');
    return RegExp(out.toString(), dotAll: true);
  }

  // ----------------------------------------------------------------- sort

  List<StoredAggregate> _sorted(
    PersistentEntity<Object> entity,
    List<StoredAggregate> rows,
    Sort sort,
  ) {
    final keys = [
      for (final order in sort.orders)
        (order, _column(entity, order.property, 'sorting').columnName),
    ];
    final indexed = rows.indexed.toList()
      ..sort((a, b) {
        for (final (order, column) in keys) {
          final c = _order(order, a.$2.values[column], b.$2.values[column]);
          if (c != 0) {
            return c;
          }
        }
        return a.$1.compareTo(b.$1);
      });
    return [for (final (_, stored) in indexed) stored];
  }

  int _order(SortOrder order, Object? a, Object? b) {
    // Null is the greatest value unless the order says otherwise.
    final nullsFirst = switch (order.nullHandling) {
      NullHandling.nullsFirst => true,
      NullHandling.nullsLast => false,
      NullHandling.native => order.isDescending,
    };
    if (a == null || b == null) {
      if (a == null && b == null) {
        return 0;
      }
      return (a == null) == nullsFirst ? -1 : 1;
    }
    final c =
        _compare(
          _fold(a, ignoreCase: order.ignoreCase),
          _fold(b, ignoreCase: order.ignoreCase),
        ) ??
        0;
    return order.isDescending ? -c : c;
  }

  List<StoredAggregate> _distinct(List<StoredAggregate> rows) {
    final seen = <int, List<StoredAggregate>>{};
    final out = <StoredAggregate>[];
    for (final stored in rows) {
      final bucket = seen.putIfAbsent(
        Object.hashAll(stored.values.values.map(_hash)),
        () => [],
      );
      if (!bucket.any((other) => _sameRow(other.values, stored.values))) {
        bucket.add(stored);
        out.add(stored);
      }
    }
    return out;
  }

  static int _hash(Object? value) => switch (value) {
    final DateTime d => d.microsecondsSinceEpoch,
    final Uint8List b => Object.hashAll(b),
    final num n => n.toDouble().hashCode,
    _ => value.hashCode,
  };

  static bool _sameRow(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.entries.every(
        (e) => b.containsKey(e.key) && _equals(e.value, b[e.key]),
      );

  // The order of two column values of one type; null when they cannot be
  // compared (different types).
  static int? _compare(Object? a, Object? b) {
    if (a is num && b is num) {
      return a.compareTo(b);
    }
    if (a is String && b is String) {
      return a.compareTo(b);
    }
    if (a is DateTime && b is DateTime) {
      return a.compareTo(b);
    }
    if (a is bool && b is bool) {
      return (a ? 1 : 0).compareTo(b ? 1 : 0);
    }
    if (a is BigInt && b is BigInt) {
      return a.compareTo(b);
    }
    return null;
  }

  static bool _equals(Object? a, Object? b) {
    if (a == null || b == null) {
      return a == null && b == null;
    }
    final c = _compare(a, b);
    if (c != null) {
      return c == 0;
    }
    if (a is List<int> && b is List<int>) {
      return a.length == b.length &&
          Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
    }
    return a == b;
  }
}

// One table: the stored aggregates by id, in insertion order, and the
// counter of generated ids (children's tables only use the counter).
final class _Table {
  final rows = <Object?, StoredAggregate>{};
  int nextId = 1;
}

// A table of the written aggregates: a root's, or one of its children's
// (reached from the root by the mapped properties of [path]).
final class _Node {
  _Node(this.tableKey, this.entity, this.root, this.path);

  final String tableKey;
  final PersistentEntity<Object> entity;
  final PersistentEntity<Object> root;
  final List<PersistentProperty> path;
}
