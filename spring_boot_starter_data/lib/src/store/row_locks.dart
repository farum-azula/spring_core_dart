import 'dart:async';

import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_transaction.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_exceptions.dart';

/// The identity of a row: its table and its id.
typedef RowKey = (String table, Object? id);

/// The lock of one row: at most one exclusive holder, or several shared
/// ones, and the transactions waiting in order. Internal to
/// [RowLockManager].
final class RowLock {
  /// The transaction holding the lock exclusively, or null.
  InMemoryTransaction? writer;

  /// The transactions holding it shared.
  final readers = <InMemoryTransaction>{};

  /// The waits in progress, first come first served.
  final queue = <LockWaiter>[];

  /// Whether [tx] holds the lock in any mode.
  bool holds(InMemoryTransaction tx) => writer == tx || readers.contains(tx);

  /// Whether [tx] already has what it asks for.
  bool satisfies(InMemoryTransaction tx, {required bool exclusive}) =>
      exclusive ? writer == tx : holds(tx);

  /// Whether the holders other than [tx] leave room for the request.
  bool compatible(InMemoryTransaction tx, {required bool exclusive}) =>
      (writer == null || writer == tx) &&
      (!exclusive || readers.every((reader) => reader == tx));

  /// Whether nobody holds or waits for it.
  bool get isIdle => writer == null && readers.isEmpty && queue.isEmpty;
}

/// One lock taken by a transaction, kept to undo it (when a savepoint is
/// rolled back).
final class LockAcquisition {
  /// The lock of [key] taken by [tx].
  LockAcquisition(this.tx, this.key, this.lock, {required this.exclusive})
    : upgraded = exclusive && lock.readers.contains(tx);

  /// Who took it.
  final InMemoryTransaction tx;

  /// The row.
  final RowKey key;

  /// The lock.
  final RowLock lock;

  /// Exclusive, or shared.
  final bool exclusive;

  /// Whether [tx] held it shared before and this made it exclusive.
  final bool upgraded;
}

/// A transaction waiting for a lock.
final class LockWaiter {
  /// A wait of [tx] for [key].
  LockWaiter(this.tx, this.key, this.lock, {required this.exclusive});

  /// Who waits.
  final InMemoryTransaction tx;

  /// The row.
  final RowKey key;

  /// The lock.
  final RowLock lock;

  /// Whether an exclusive lock is wanted.
  final bool exclusive;

  /// Completes when the lock is granted, or with the error that ended the
  /// wait.
  final completer = Completer<void>();

  /// Whether the wait is over.
  bool done = false;
}

/// The row locks of the in-memory store: exclusive and shared, held by
/// transactions until they end, with a first-come first-served queue per
/// row, a wait-for graph that finds deadlocks, and bounded waits.
///
/// A lock is requested with [tryAcquire] (never waits) or [acquire] (waits
/// at most [Duration] given). A transaction asking again for a lock it
/// holds gets it at once; shared becomes exclusive when it is the only
/// holder (an upgrade, which may wait for the other readers).
///
/// Spring (Java): none; it is what the database does for `select ... for
/// update`, `for share` and updates (PostgreSQL's row locks and its
/// deadlock detector).
final class RowLockManager {
  final _locks = <RowKey, RowLock>{};

  /// How many rows are locked, for tests and logs.
  int get lockedRows => _locks.length;

  /// How many lock waits are in progress, for tests and logs.
  int get waiting =>
      _locks.values.fold(0, (sum, lock) => sum + lock.queue.length);

  /// Whether [tx] holds the lock of [key] (in any mode).
  bool holds(InMemoryTransaction tx, RowKey key) =>
      _locks[key]?.holds(tx) ?? false;

  /// Takes the lock at once when nobody conflicts, and tells whether it
  /// did. A request does not jump the queue, except an upgrade by a holder.
  bool tryAcquire(
    InMemoryTransaction tx,
    RowKey key, {
    required bool exclusive,
  }) {
    final lock = _locks.putIfAbsent(key, RowLock.new);
    if (lock.satisfies(tx, exclusive: exclusive)) {
      return true;
    }
    if (lock.compatible(tx, exclusive: exclusive) &&
        (lock.queue.isEmpty || lock.holds(tx))) {
      _grant(tx, key, lock, exclusive: exclusive);
      return true;
    }
    _forget(key, lock);
    return false;
  }

  /// Takes the lock, waiting at most [wait] when another transaction holds
  /// it.
  ///
  /// Throws a `CannotAcquireLockException` when [wait] passes (at once for
  /// zero), a `QueryTimeoutException` instead when [deadlineBound] (the
  /// transaction's own deadline is what cut [wait]), and a
  /// `DeadlockLoserDataAccessException` at once when waiting would close a
  /// cycle of transactions waiting for each other. [onWait] is called
  /// with the names of the transactions waited for, when the wait starts.
  Future<void> acquire(
    InMemoryTransaction tx,
    RowKey key, {
    required bool exclusive,
    required Duration wait,
    bool deadlineBound = false,
    void Function(List<String> blockedBy)? onWait,
  }) async {
    if (tryAcquire(tx, key, exclusive: exclusive)) {
      return;
    }
    final lock = _locks[key]!;
    if (wait <= Duration.zero) {
      throw CannotAcquireLockException(
        'Could not obtain the lock on a row of ${key.$1} at once (no '
        'wait)',
      );
    }
    final waiter = LockWaiter(tx, key, lock, exclusive: exclusive);
    if (_closesCycle(waiter)) {
      throw DeadlockLoserDataAccessException(
        'Deadlock detected: ${tx.label} waits for a lock on a row of '
        '${key.$1} held by a transaction that waits for ${tx.label}',
      );
    }
    final blockers = _blockers(waiter);
    lock.queue.add(waiter);
    tx.pending.add(waiter);
    onWait?.call([for (final blocker in blockers) blocker.label]);
    final timer = Timer(wait, () {
      if (waiter.done) {
        return;
      }
      _end(
        waiter,
        deadlineBound
            ? QueryTimeoutException(
                'The transaction ran out of time waiting for a lock on a '
                'row of ${key.$1}',
              )
            : CannotAcquireLockException(
                'Could not obtain the lock on a row of ${key.$1} within '
                '${wait.inMilliseconds} ms',
              ),
      );
    });
    try {
      await waiter.completer.future;
    } finally {
      timer.cancel();
    }
  }

  /// Releases every lock of [tx] and cancels its waits; wakes the
  /// transactions that can go on.
  void releaseAll(InMemoryTransaction tx) {
    for (final waiter in List.of(tx.pending)) {
      _end(
        waiter,
        IllegalTransactionStateException(
          'The transaction ${tx.label} ended while an operation of it was '
          'still waiting for a lock',
        ),
      );
    }
    undoTo(tx, 0);
  }

  /// Releases the locks [tx] took after its first [mark] acquisitions (the
  /// ones taken since a savepoint), downgrading an upgraded lock back to
  /// shared; wakes the transactions that can go on.
  void undoTo(InMemoryTransaction tx, int mark) {
    final touched = <RowKey, RowLock>{};
    while (tx.acquisitions.length > mark) {
      final taken = tx.acquisitions.removeLast();
      if (taken.exclusive) {
        taken.lock.writer = null;
        if (taken.upgraded) {
          taken.lock.readers.add(tx);
        }
      } else {
        taken.lock.readers.remove(tx);
      }
      touched[taken.key] = taken.lock;
    }
    for (final MapEntry(:key, :value) in touched.entries) {
      _wake(value);
      _forget(key, value);
    }
  }

  // ------------------------------------------------------------ internals

  void _grant(
    InMemoryTransaction tx,
    RowKey key,
    RowLock lock, {
    required bool exclusive,
  }) {
    tx.acquisitions.add(LockAcquisition(tx, key, lock, exclusive: exclusive));
    if (exclusive) {
      lock.readers.remove(tx);
      lock.writer = tx;
    } else {
      lock.readers.add(tx);
    }
  }

  void _forget(RowKey key, RowLock lock) {
    if (lock.isIdle && identical(_locks[key], lock)) {
      _locks.remove(key);
    }
  }

  // Grants the waits that can go on: a holder's upgrade as soon as it
  // fits, the others in order.
  void _wake(RowLock lock) {
    var progress = true;
    while (progress && lock.queue.isNotEmpty) {
      progress = false;
      for (final waiter in lock.queue) {
        final fits = lock.compatible(waiter.tx, exclusive: waiter.exclusive);
        if (fits &&
            (lock.holds(waiter.tx) || identical(waiter, lock.queue.first))) {
          waiter.done = true;
          lock.queue.remove(waiter);
          waiter.tx.pending.remove(waiter);
          _grant(waiter.tx, waiter.key, lock, exclusive: waiter.exclusive);
          waiter.completer.complete();
          progress = true;
          break;
        }
      }
    }
  }

  // Ends a wait with [error], and lets those queued behind it go on.
  void _end(LockWaiter waiter, Object error) {
    waiter.done = true;
    waiter.lock.queue.remove(waiter);
    waiter.tx.pending.remove(waiter);
    waiter.completer.completeError(error);
    _wake(waiter.lock);
    _forget(waiter.key, waiter.lock);
  }

  // The transactions [waiter] has to wait for: the holders in its way and
  // the conflicting waits ahead of it in the queue.
  Set<InMemoryTransaction> _blockers(LockWaiter waiter) {
    final lock = waiter.lock;
    final tx = waiter.tx;
    final out = <InMemoryTransaction>{};
    if (lock.writer case final writer? when writer != tx) {
      out.add(writer);
    }
    if (waiter.exclusive) {
      out.addAll(lock.readers.where((reader) => reader != tx));
    }
    if (!lock.holds(tx)) {
      for (final ahead in lock.queue) {
        if (identical(ahead, waiter)) {
          break;
        }
        if (ahead.tx != tx && (waiter.exclusive || ahead.exclusive)) {
          out.add(ahead.tx);
        }
      }
    }
    return out;
  }

  // Whether waiting would put [waiter]'s transaction behind itself.
  bool _closesCycle(LockWaiter waiter) {
    final seen = <InMemoryTransaction>{};
    final todo = [..._blockers(waiter)];
    while (todo.isNotEmpty) {
      final next = todo.removeLast();
      if (next == waiter.tx) {
        return true;
      }
      if (seen.add(next)) {
        for (final waiting in next.pending) {
          todo.addAll(_blockers(waiting));
        }
      }
    }
    return false;
  }
}
