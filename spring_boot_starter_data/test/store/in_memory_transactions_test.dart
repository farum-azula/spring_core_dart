import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../support/app.dart';

// The transactions of the in-memory store, below the transaction manager:
// the tests bind the transactions by hand. Every race is ordered by gates
// (completers) and by the store's count of waiting statements, never by
// sleeps, so it happens the same way on every run.

/// A one-shot signal between the test and a transaction body.
final class Gate {
  final _completer = Completer<void>();
  Future<void> get wait => _completer.future;
  void open() => _completer.complete();
}

/// The value or the error of [future], so a failure that comes before the
/// test looks at it is not reported as unhandled.
Future<Object?> settle(Future<Object?> future) =>
    future.then<Object?>((value) => value, onError: (Object e) => e);

Criteria where(PartType type, String property, List<Object?> arguments) =>
    Criteria([
      OrPart([
        Part(property, type),
      ]),
    ], arguments);

void main() {
  late Example app;
  late InMemoryDataStore store;
  late PersistentEntity<Book> books;
  late PersistentEntity<Author> authors;
  late PersistentEntity<Account> accounts;
  late PersistentEntity<PurchaseOrder> orders;

  Future<void> run(
    Future<void> Function() body, {
    Duration lockTimeout = const Duration(seconds: 5),
  }) => withExample((example) async {
    app = example;
    store = InMemoryDataStore(
      converter: example.context.getBean(),
      lockTimeout: lockTimeout,
    );
    books = example.entity<Book>();
    authors = example.entity<Author>();
    accounts = example.entity<Account>();
    orders = example.entity<PurchaseOrder>();
    await body();
  });

  /// Runs [body] in a transaction of the store, bound as the manager
  /// binds it: committed when [body] ends, rolled back when it fails (or
  /// when [rollback]).
  Future<R> inTx<R>(
    Future<R> Function(InMemoryTransaction tx) body, {
    bool readOnly = false,
    Duration? timeout,
    bool rollback = false,
  }) => TransactionSynchronizationManager.runInScope(() async {
    TransactionSynchronizationManager.isolate(store);
    TransactionSynchronizationManager.initTransaction(
      TransactionDefinition(readOnly: readOnly, timeout: timeout, name: 't'),
      key: store,
    );
    final tx = store.begin(readOnly: readOnly, name: 't');
    TransactionSynchronizationManager.bindResource(store, tx);
    try {
      final result = await body(tx);
      if (tx.isActive) {
        await (rollback ? store.rollback(tx) : store.commit(tx));
      }
      return result;
    } on Object {
      if (tx.isActive) {
        await store.rollback(tx);
      }
      rethrow;
    } finally {
      TransactionSynchronizationManager.completeTransaction();
      TransactionSynchronizationManager.unbindResource(store);
    }
  });

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 10000; i++) {
      if (condition()) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
    fail('the condition did not come true');
  }

  Future<void> waiting(int count) => until(() => store.waitingCount == count);

  Future<Book> addBook(String title) =>
      store.insert(books, Book(title: title, year: 2000));

  Book retitled(Book book, String title) =>
      Book(id: book.id, title: title, year: book.year, version: book.version);

  Future<List<Author>> addAuthors([int count = 3]) async => [
    for (var i = 1; i <= count; i++)
      await store.insert(authors, Author(name: 'a$i')),
  ];

  Future<int> bookCount() => store.count(books);

  Future<String> bookTitle(int id) async =>
      (await store.findById(books, id))!.title;

  Future<String> authorName(int id) async =>
      (await store.findById(authors, id))!.name;

  group('reads', () {
    test('a transaction sees its own writes, others see them at commit', () {
      return run(() async {
        final inserted = Gate();
        final release = Gate();
        final writer = inTx((tx) async {
          await addBook('mine');
          expect(await bookCount(), 1);
          inserted.open();
          await release.wait;
        });
        await inserted.wait;
        expect(await bookCount(), 0, reason: 'outside any transaction');
        expect(await inTx((_) => bookCount()), 0, reason: 'another one');
        expect(store.size(books), 0);
        release.open();
        await writer;
        expect(await bookCount(), 1);
      });
    });

    test('a rolled-back transaction leaves nothing, its own delete too', () {
      return run(() async {
        final kept = await addBook('kept');
        await inTx((tx) async {
          await addBook('gone');
          await store.deleteById(books, kept.id!);
          expect(await bookCount(), 1);
        }, rollback: true);
        expect(await bookCount(), 1);
        expect(await bookTitle(kept.id!), 'kept');
      });
    });

    test('a row read twice may differ: no repeatable read', () {
      return run(() async {
        final book = await addBook('first');
        final read = Gate();
        final changed = Gate();
        late String second;
        final reader = inTx((tx) async {
          expect(await bookTitle(book.id!), 'first');
          read.open();
          await changed.wait;
          second = await bookTitle(book.id!);
        });
        await read.wait;
        await store.update(books, retitled(book, 'second'));
        changed.open();
        await reader;
        expect(second, 'second');
      });
    });

    test('deleted by another transaction: seen after its commit only', () {
      return run(() async {
        final book = await addBook('x');
        final deleted = Gate();
        final release = Gate();
        final deleter = inTx((_) async {
          await store.deleteById(books, book.id!);
          deleted.open();
          await release.wait;
        });
        await deleted.wait;
        expect(await bookCount(), 1);
        release.open();
        await deleter;
        expect(await bookCount(), 0);
      });
    });
  });

  group('row locks', () {
    test('lost update with @Version: the second writer waits, then fails', () {
      return run(() async {
        final seeded = await addBook('t');
        final updated = Gate();
        final release = Gate();
        final first = inTx((_) async {
          await store.update(books, retitled(seeded, 'first'));
          updated.open();
          await release.wait;
        });
        await updated.wait;
        final second = settle(
          inTx((_) => store.update(books, retitled(seeded, 'second'))),
        );
        await waiting(1);
        release.open();
        await first;
        expect(await second, isA<OptimisticLockingFailureException>());
        expect(await bookTitle(seeded.id!), 'first');
        expect((await store.findById(books, seeded.id!))!.version, 2);
        expect(store.waitingCount, 0);
      });
    });

    test('without @Version the second writer applies on the fresh row', () {
      return run(() async {
        final [author, ...] = await addAuthors(1);
        final updated = Gate();
        final release = Gate();
        final first = inTx((_) async {
          await store.update(authors, Author(id: author.id, name: 'first'));
          updated.open();
          await release.wait;
        });
        await updated.wait;
        final second = settle(
          inTx(
            (_) => store.update(authors, Author(id: author.id, name: 'second')),
          ),
        );
        await waiting(1);
        expect(await authorName(author.id!), 'a1', reason: 'still waiting');
        release.open();
        await first;
        expect(await second, isA<Author>());
        expect(await authorName(author.id!), 'second');
      });
    });

    test('the wait ends when the first rolls back', () {
      return run(() async {
        final seeded = await addBook('t');
        final updated = Gate();
        final release = Gate();
        final first = inTx((_) async {
          await store.update(books, retitled(seeded, 'first'));
          updated.open();
          await release.wait;
        }, rollback: true);
        await updated.wait;
        final second = settle(
          inTx((_) => store.update(books, retitled(seeded, 'second'))),
        );
        await waiting(1);
        release.open();
        await first;
        expect(await second, isA<Book>());
        expect(await bookTitle(seeded.id!), 'second');
        expect((await store.findById(books, seeded.id!))!.version, 2);
      });
    });

    test('a waiting writer re-reads: a row deleted meanwhile is gone', () {
      return run(() async {
        final seeded = await addBook('t');
        final deleted = Gate();
        final release = Gate();
        final first = inTx((_) async {
          await store.deleteById(books, seeded.id!);
          deleted.open();
          await release.wait;
        });
        await deleted.wait;
        final second = settle(
          inTx((_) => store.update(books, retitled(seeded, 'second'))),
        );
        await waiting(1);
        release.open();
        await first;
        expect(await second, isA<OptimisticLockingFailureException>());
        expect(await bookCount(), 0);
      });
    });

    test('writers are served first come first served', () {
      return run(() async {
        final [author, ...] = await addAuthors(1);
        final updated = Gate();
        final release = Gate();
        final order = <String>[];
        final first = inTx((_) async {
          await store.update(authors, Author(id: author.id, name: 'first'));
          updated.open();
          await release.wait;
        });
        await updated.wait;
        Future<Object?> writer(String name) => settle(
          inTx<void>((_) async {
            await store.update(authors, Author(id: author.id, name: name));
            order.add(name);
          }),
        );
        final b = writer('b');
        await waiting(1);
        final c = writer('c');
        await waiting(2);
        release.open();
        await first;
        await b;
        await c;
        expect(order, ['b', 'c']);
        expect(await authorName(author.id!), 'c');
      });
    });

    test('DuplicateKey when a concurrent insert of the id commits', () {
      return run(() async {
        final inserted = Gate();
        final release = Gate();
        final first = inTx((_) async {
          await store.insert(accounts, const Account(iban: 'DE1', owner: 'a'));
          inserted.open();
          await release.wait;
        });
        await inserted.wait;
        final second = settle(
          inTx(
            (_) => store.insert(
              accounts,
              const Account(iban: 'DE1', owner: 'b'),
            ),
          ),
        );
        await waiting(1);
        release.open();
        await first;
        expect(await second, isA<DuplicateKeyException>());
        expect(store.size(accounts), 1);
      });
    });

    test('the same insert goes through when the first one rolls back', () {
      return run(() async {
        final inserted = Gate();
        final release = Gate();
        final first = inTx((_) async {
          await store.insert(accounts, const Account(iban: 'DE1', owner: 'a'));
          inserted.open();
          await release.wait;
        }, rollback: true);
        await inserted.wait;
        final second = settle(
          inTx(
            (_) => store.insert(
              accounts,
              const Account(iban: 'DE1', owner: 'b'),
            ),
          ),
        );
        await waiting(1);
        release.open();
        await first;
        expect(await second, isA<Account>());
        expect((await store.findById(accounts, 'DE1'))!.owner, 'b');
      });
    });

    test('an auto-commit write waits for the lock of a transaction', () {
      return run(() async {
        final [author, ...] = await addAuthors(1);
        final updated = Gate();
        final release = Gate();
        final tx = inTx((_) async {
          await store.update(authors, Author(id: author.id, name: 'tx'));
          updated.open();
          await release.wait;
        });
        await updated.wait;
        final alone = settle(
          store.update(authors, Author(id: author.id, name: 'alone')),
        );
        final removal = settle(store.deleteById(authors, 99));
        await waiting(1);
        expect(await removal, false, reason: 'no row, no lock to wait for');
        release.open();
        await tx;
        expect(await alone, isA<Author>());
        expect(await authorName(author.id!), 'alone');
      });
    });

    test('deleteWhere waits, then looks for the rows again', () {
      return run(() async {
        await addAuthors(2);
        final updated = Gate();
        final release = Gate();
        final first = inTx((_) async {
          await store.update(authors, Author(id: 1, name: 'renamed'));
          updated.open();
          await release.wait;
        });
        await updated.wait;
        final removal = settle(
          store.deleteWhere(
            authors,
            criteria: where(PartType.simpleProperty, 'name', ['a1']),
          ),
        );
        await waiting(1);
        release.open();
        await first;
        expect(await removal, 0, reason: 'the row no longer matches');
        expect(await authorName(1), 'renamed');
      });
    });
  });

  group('waits', () {
    test('a lock timeout: CannotAcquireLockException', () {
      return run(lockTimeout: const Duration(milliseconds: 30), () async {
        await addAuthors(1);
        final updated = Gate();
        final release = Gate();
        final holder = inTx((_) async {
          await store.update(authors, Author(id: 1, name: 'x'));
          updated.open();
          await release.wait;
        });
        await updated.wait;
        final waiter = settle(
          inTx((_) => store.update(authors, Author(id: 1, name: 'y'))),
        );
        expect(await waiter, isA<CannotAcquireLockException>());
        expect(store.waitingCount, 0);
        release.open();
        await holder;
        expect(await authorName(1), 'x');
      });
    });

    test('a zero lock timeout fails at once', () {
      return run(lockTimeout: Duration.zero, () async {
        await addAuthors(1);
        final updated = Gate();
        final release = Gate();
        final holder = inTx((_) async {
          await store.update(authors, Author(id: 1, name: 'x'));
          updated.open();
          await release.wait;
        });
        await updated.wait;
        expect(
          await settle(store.update(authors, Author(id: 1, name: 'y'))),
          isA<CannotAcquireLockException>(),
        );
        expect(store.waitingCount, 0);
        release.open();
        await holder;
      });
    });

    test('the transaction deadline cuts the wait: QueryTimeoutException', () {
      return run(() async {
        await addAuthors(1);
        final updated = Gate();
        final release = Gate();
        final holder = inTx((_) async {
          await store.update(authors, Author(id: 1, name: 'x'));
          updated.open();
          await release.wait;
        });
        await updated.wait;
        final waiter = settle(
          inTx(
            timeout: const Duration(milliseconds: 40),
            (_) => store.update(authors, Author(id: 1, name: 'y')),
          ),
        );
        expect(await waiter, isA<QueryTimeoutException>());
        expect(store.waitingCount, 0);
        release.open();
        await holder;
      });
    });

    test('a timed-out transaction whose error was caught only rolls back', () {
      return run(() async {
        await addAuthors(1);
        final result = await settle(
          inTx(timeout: const Duration(milliseconds: 20), (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 60));
            try {
              return await store.count(authors);
            } on TransactionTimedOutException {
              // Caught: the commit still must not happen.
              return -1;
            }
          }),
        );
        // The store refuses the commit of a rollback-only transaction (the
        // transaction manager turns that into an UnexpectedRollbackException).
        expect(result, isA<IllegalTransactionStateException>());
      });
    });

    test('an operation after the deadline: TransactionTimedOutException', () {
      return run(() async {
        await addAuthors(1);
        final result = await settle(
          inTx(timeout: const Duration(milliseconds: 20), (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 60));
            return await store.count(authors);
          }),
        );
        expect(result, isA<TransactionTimedOutException>());
      });
    });

    test('a deadlock: the waiter that closes the cycle fails at once', () {
      return run(() async {
        await addAuthors(2);
        final aHolds = Gate();
        final bHolds = Gate();
        final bGo = Gate();
        final a = settle(
          inTx<void>((_) async {
            await store.update(authors, Author(id: 1, name: 'a'));
            aHolds.open();
            await bHolds.wait;
            await store.update(authors, Author(id: 2, name: 'a'));
          }),
        );
        final b = settle(
          inTx<void>((_) async {
            await aHolds.wait;
            await store.update(authors, Author(id: 2, name: 'b'));
            bHolds.open();
            await bGo.wait;
            await store.update(authors, Author(id: 1, name: 'b'));
          }),
        );
        await waiting(1); // a waits for b's row
        bGo.open();
        expect(await b, isA<DeadlockLoserDataAccessException>());
        expect(await a, isNull, reason: 'goes on once b rolled back');
        expect(await authorName(1), 'a');
        expect(await authorName(2), 'a');
        expect(store.waitingCount, 0);
      });
    });
  });

  group('pessimistic locks', () {
    test('pessimisticWrite blocks writers and other lockers', () {
      return run(() async {
        await addAuthors(1);
        final locked = Gate();
        final release = Gate();
        final holder = inTx((_) async {
          final found = await store.findById(
            authors,
            1,
            lock: LockMode.pessimisticWrite,
          );
          expect(found!.name, 'a1');
          locked.open();
          await release.wait;
        });
        await locked.wait;
        expect(await authorName(1), 'a1', reason: 'plain reads do not wait');
        expect(
          await settle(
            inTx(
              (_) => store.findById(
                authors,
                1,
                lock: LockMode.pessimisticRead,
                lockTimeout: Duration.zero,
              ),
            ),
          ),
          isA<CannotAcquireLockException>(),
        );
        expect(
          await settle(
            inTx(
              (_) => store.find(
                authors,
                lock: LockMode.pessimisticWrite,
                lockTimeout: Duration.zero,
              ),
            ),
          ),
          isA<CannotAcquireLockException>(),
        );
        final writer = settle(
          inTx((_) => store.update(authors, Author(id: 1, name: 'w'))),
        );
        await waiting(1);
        release.open();
        await holder;
        expect(await writer, isA<Author>());
        expect(await authorName(1), 'w');
      });
    });

    test('a locker waits for a writer, then reads the fresh row', () {
      return run(() async {
        await addAuthors(1);
        final updated = Gate();
        final release = Gate();
        final writer = inTx((_) async {
          await store.update(authors, Author(id: 1, name: 'new'));
          updated.open();
          await release.wait;
        });
        await updated.wait;
        final locker = settle(
          inTx(
            (_) => store.find(
              authors,
              criteria: where(PartType.simpleProperty, 'name', ['a1']),
              lock: LockMode.pessimisticWrite,
            ),
          ),
        );
        await waiting(1);
        release.open();
        await writer;
        expect(await locker, isEmpty, reason: 'it no longer matches');
      });
    });

    test('pessimisticRead is shared; a writer waits for all readers', () {
      return run(() async {
        await addAuthors(1);
        final aLocked = Gate();
        final bLocked = Gate();
        final releaseA = Gate();
        final releaseB = Gate();
        Future<void> reader(Gate locked, Gate release) => inTx((_) async {
          final rows = await store.find(
            authors,
            lock: LockMode.pessimisticRead,
            lockTimeout: Duration.zero,
          );
          expect(rows, hasLength(1));
          locked.open();
          await release.wait;
        });
        final a = reader(aLocked, releaseA);
        await aLocked.wait;
        final b = reader(bLocked, releaseB);
        await bLocked.wait;
        var written = false;
        final writer = settle(
          inTx<void>((_) async {
            await store.update(authors, Author(id: 1, name: 'w'));
            written = true;
          }),
        );
        await waiting(1);
        releaseA.open();
        await a;
        // The second reader still holds: let the event loop turn.
        await Future<void>.delayed(Duration.zero);
        expect(written, isFalse);
        releaseB.open();
        await b;
        expect(await writer, isNull);
        expect(written, isTrue);
      });
    });

    test('a reader waits for a writer and gives up with a zero timeout', () {
      return run(() async {
        await addAuthors(1);
        final updated = Gate();
        final release = Gate();
        final writer = inTx((_) async {
          await store.update(authors, Author(id: 1, name: 'w'));
          updated.open();
          await release.wait;
        });
        await updated.wait;
        expect(
          await settle(
            inTx(
              (_) => store.findById(
                authors,
                1,
                lock: LockMode.pessimisticRead,
                lockTimeout: Duration.zero,
              ),
            ),
          ),
          isA<CannotAcquireLockException>(),
        );
        release.open();
        await writer;
      });
    });

    test('skipLocked: two workers of a queue take different rows', () {
      return run(() async {
        await addAuthors();
        final aTook = Gate();
        final bTook = Gate();
        final release = Gate();
        Future<List<int>> worker(Gate took, {int? limit}) => inTx((_) async {
          final rows = await store.find(
            authors,
            sort: Sort.by(['id']),
            limit: limit,
            lock: LockMode.pessimisticWrite,
            skipLocked: true,
          );
          took.open();
          await release.wait;
          return [for (final row in rows) row.id!];
        });
        final a = worker(aTook, limit: 1);
        await aTook.wait;
        final b = worker(bTook, limit: 1);
        await bTook.wait;
        final c = worker(Gate());
        release.open();
        expect(await a, [1]);
        expect(await b, [2]);
        expect(await c, [3]);
      });
    });

    test('skipLocked on a row by id gives null', () {
      return run(() async {
        await addAuthors(1);
        final locked = Gate();
        final release = Gate();
        final holder = inTx((_) async {
          await store.findById(authors, 1, lock: LockMode.pessimisticWrite);
          locked.open();
          await release.wait;
        });
        await locked.wait;
        expect(
          await inTx(
            (_) => store.findById(
              authors,
              1,
              lock: LockMode.pessimisticWrite,
              skipLocked: true,
            ),
          ),
          isNull,
        );
        release.open();
        await holder;
      });
    });

    test('a locking read outside a transaction fails, never unlocked', () {
      return run(() async {
        await addAuthors(1);
        expect(
          () => store.find(authors, lock: LockMode.pessimisticRead),
          throwsA(isA<IllegalTransactionStateException>()),
        );
        expect(
          () => store.findById(authors, 1, lock: LockMode.pessimisticWrite),
          throwsA(isA<IllegalTransactionStateException>()),
        );
        expect(
          () => store.findById(authors, 99, lock: LockMode.pessimisticWrite),
          throwsA(isA<IllegalTransactionStateException>()),
        );
        // In a scope, but with no transaction bound.
        await expectLater(
          TransactionSynchronizationManager.runInScope(
            () => store.find(authors, lock: LockMode.pessimisticWrite),
          ),
          throwsA(isA<IllegalTransactionStateException>()),
        );
        expect(store.waitingCount, 0);
      });
    });

    test('the locks of a transaction are released when it ends', () {
      return run(() async {
        await addAuthors(2);
        await inTx((_) async {
          await store.find(authors, lock: LockMode.pessimisticWrite);
        });
        await inTx(
          (_) => store.find(
            authors,
            lock: LockMode.pessimisticWrite,
            lockTimeout: Duration.zero,
          ),
        );
      });
    });
  });

  group('savepoints', () {
    test('rollback restores the writes and releases the later locks', () {
      return run(() async {
        await addAuthors(2);
        final rolledBack = Gate();
        final release = Gate();
        final holder = inTx((tx) async {
          await store.update(authors, Author(id: 1, name: 'kept'));
          final savepoint = store.createSavepoint(tx);
          await store.update(authors, Author(id: 2, name: 'undone'));
          await addBook('undone');
          expect(await authorName(2), 'undone');
          store.rollbackToSavepoint(tx, savepoint);
          expect(await authorName(2), 'a2');
          expect(await bookCount(), 0);
          expect(await authorName(1), 'kept');
          rolledBack.open();
          await release.wait;
        });
        await rolledBack.wait;
        // Row 2 is free again: no wait (it would fail at the timeout).
        await store.update(authors, Author(id: 2, name: 'other'));
        // Row 1 is still locked.
        final writer = settle(
          store.update(authors, Author(id: 1, name: 'later')),
        );
        await waiting(1);
        release.open();
        await holder;
        expect(await writer, isA<Author>());
        expect(await authorName(1), 'later');
        expect(await authorName(2), 'other');
        expect(await bookCount(), 0);
      });
    });

    test('release keeps the writes and the locks', () {
      return run(() async {
        await addAuthors(1);
        final released = Gate();
        final release = Gate();
        final holder = inTx((tx) async {
          final savepoint = store.createSavepoint(tx);
          await store.update(authors, Author(id: 1, name: 'kept'));
          store.releaseSavepoint(tx, savepoint);
          expect(
            () => store.rollbackToSavepoint(tx, savepoint),
            throwsA(isA<IllegalTransactionStateException>()),
          );
          released.open();
          await release.wait;
        });
        await released.wait;
        final writer = settle(
          store.update(authors, Author(id: 1, name: 'later')),
        );
        await waiting(1);
        release.open();
        await holder;
        expect(await writer, isA<Author>());
        expect(await authorName(1), 'later');
      });
    });

    test('rollback to a savepoint drops the savepoints after it', () {
      return run(() async {
        await inTx((tx) async {
          final first = store.createSavepoint(tx);
          await addBook('one');
          final second = store.createSavepoint(tx);
          await addBook('two');
          store.rollbackToSavepoint(tx, first);
          expect(await bookCount(), 0);
          expect(
            () => store.rollbackToSavepoint(tx, second),
            throwsA(isA<IllegalTransactionStateException>()),
          );
          // The savepoint itself stays usable.
          await addBook('three');
          store.rollbackToSavepoint(tx, first);
          expect(await bookCount(), 0);
        });
        expect(await bookCount(), 0);
      });
    });

    test('an upgraded lock is shared again after the rollback', () {
      return run(() async {
        await addAuthors(1);
        final ready = Gate();
        final release = Gate();
        final holder = inTx((tx) async {
          await store.findById(authors, 1, lock: LockMode.pessimisticRead);
          final savepoint = store.createSavepoint(tx);
          await store.update(authors, Author(id: 1, name: 'x'));
          store.rollbackToSavepoint(tx, savepoint);
          ready.open();
          await release.wait;
        });
        await ready.wait;
        // Still shared by the holder: another reader gets in at once.
        await inTx(
          (_) => store.findById(
            authors,
            1,
            lock: LockMode.pessimisticRead,
            lockTimeout: Duration.zero,
          ),
        );
        release.open();
        await holder;
        expect(await authorName(1), 'a1');
      });
    });
  });

  group('transactions', () {
    test('a read-only transaction refuses writes and locking reads', () {
      return run(() async {
        final [author, ...] = await addAuthors(1);
        await inTx(readOnly: true, (_) async {
          expect(await authorName(1), 'a1');
          expect(await store.count(authors), 1);
          Future<void> refused(Future<Object?> Function() write, String what) =>
              expectLater(
                write(),
                throwsA(
                  isA<InvalidDataAccessResourceUsageException>().having(
                    (e) => e.message,
                    'message',
                    'cannot execute $what in a read-only transaction',
                  ),
                ),
              );
          await refused(
            () => store.insert(authors, Author(name: 'n')),
            'insert',
          );
          await refused(
            () => store.update(authors, Author(id: author.id, name: 'n')),
            'update',
          );
          await refused(() => store.deleteById(authors, 1), 'delete');
          await refused(() => store.deleteWhere(authors), 'delete');
          await refused(
            () => store.find(authors, lock: LockMode.pessimisticRead),
            'select',
          );
        });
        expect(await authorName(1), 'a1');
      });
    });

    test('generated ids are never reused after a rollback', () {
      return run(() async {
        late int rolledBackId;
        await inTx((_) async {
          rolledBackId = (await addBook('gone')).id!;
        }, rollback: true);
        final next = await addBook('next');
        expect(rolledBackId, 1);
        expect(next.id, 2);
      });
    });

    test('children go with their root: insert, update and delete', () {
      return run(() async {
        PurchaseOrder order(String customer, List<String> skus) =>
            PurchaseOrder(
              customer: customer,
              lines: [for (final sku in skus) OrderLine(sku: sku, quantity: 1)],
              notes: {'n': OrderNote(text: customer)},
            );
        List<String> skus(PurchaseOrder o) => [for (final l in o.lines) l.sku];

        await inTx((_) async {
          await store.insert(orders, order('rolled back', ['x']));
          expect(await store.count(orders), 1);
        }, rollback: true);
        expect(await store.count(orders), 0);

        final saved = await store.insert(orders, order('kept', ['a', 'b']));
        await inTx((_) async {
          await store.update(
            orders,
            PurchaseOrder(
              id: saved.id,
              customer: 'changed',
              lines: [OrderLine(sku: 'z', quantity: 9)],
            ),
          );
          final seen = (await store.findById(orders, saved.id!))!;
          expect(skus(seen), ['z']);
          expect(seen.notes, isEmpty);
        }, rollback: true);
        var found = (await store.findById(orders, saved.id!))!;
        expect(found.customer, 'kept');
        expect(skus(found), ['a', 'b']);
        expect(found.notes['n']!.text, 'kept');

        await inTx((_) async {
          await store.deleteById(orders, saved.id!);
          expect(await store.count(orders), 0);
        }, rollback: true);
        found = (await store.findById(orders, saved.id!))!;
        expect(skus(found), ['a', 'b']);

        await inTx((_) async {
          await store.update(
            orders,
            PurchaseOrder(
              id: saved.id,
              customer: 'committed',
              lines: [OrderLine(sku: 'c', quantity: 2)],
            ),
          );
        });
        found = (await store.findById(orders, saved.id!))!;
        expect(found.customer, 'committed');
        expect(skus(found), ['c']);
      });
    });

    test('an operation on an ended transaction fails', () {
      return run(() async {
        await addAuthors(1);
        // Inside: the transaction ended, its resource still bound.
        await inTx((tx) async {
          await store.rollback(tx);
          await expectLater(
            store.count(authors),
            throwsA(isA<IllegalTransactionStateException>()),
          );
          await expectLater(
            store.commit(tx),
            throwsA(isA<IllegalTransactionStateException>()),
          );
          await expectLater(
            store.rollback(tx),
            throwsA(isA<IllegalTransactionStateException>()),
          );
        });
        // Work started in the transaction and not awaited.
        final go = Gate();
        late Future<Object?> stray;
        await inTx((_) async {
          stray = settle(() async {
            await go.wait;
            return await store.insert(authors, Author(name: 'stray'));
          }());
        });
        go.open();
        expect(await stray, isA<IllegalTransactionStateException>());
        expect(store.size(authors), 1);
      });
    });

    test('a rollback-only transaction is not committed', () {
      return run(() async {
        final tx = store.begin()..setRollbackOnly();
        await expectLater(
          store.commit(tx),
          throwsA(isA<IllegalTransactionStateException>()),
        );
        expect(tx.isActive, isTrue);
        await store.rollback(tx);
        expect(tx.state, InMemoryTransactionState.rolledBack);
      });
    });

    test('isolation: read committed (and the default) only', () {
      return run(() async {
        for (final level in [
          Isolation.readUncommitted,
          Isolation.repeatableRead,
          Isolation.serializable,
        ]) {
          expect(
            () => store.begin(isolation: level),
            throwsA(isA<InvalidIsolationLevelException>()),
            reason: level.name,
          );
        }
        for (final level in [Isolation.defaultLevel, Isolation.readCommitted]) {
          final tx = store.begin(isolation: level);
          expect(tx.isolation, level);
          await store.rollback(tx);
        }
      });
    });

    test('an exception in a transaction leaves the committed rows alone', () {
      return run(() async {
        final book = await addBook('t');
        final result = await settle(
          inTx<void>((_) async {
            await store.update(books, retitled(book, 'changed'));
            await store.insert(accounts, const Account(iban: 'X', owner: 'o'));
            throw StateError('boom');
          }),
        );
        expect(result, isA<StateError>());
        expect(await bookTitle(book.id!), 't');
        expect(store.size(accounts), 0);
        // Its locks are gone too.
        await store.update(books, retitled(book, 'later'));
        expect(app.context, isNotNull);
      });
    });
  });

  group('references and unique keys', () {
    test('a reference holds the row it points to: a delete of it waits', () {
      return run(() async {
        final [writer, ...] = await addAuthors(1);
        final inserted = Gate();
        final release = Gate();
        final holder = inTx((_) async {
          await store.insert(
            books,
            Book(title: 'b', year: 1, author: author(writer.id!)),
          );
          inserted.open();
          await release.wait;
        });
        await inserted.wait;
        final deleter = settle(
          inTx((_) => store.deleteById(authors, writer.id!)),
        );
        await waiting(1);
        // The reference is committed: the delete sees it and is refused.
        release.open();
        await holder;
        expect(await deleter, isA<DataIntegrityViolationException>());
        expect(await authorName(writer.id!), 'a1');
        expect(store.waitingCount, 0);
      });
    });

    test('...and goes through when the reference is rolled back', () {
      return run(() async {
        final [writer, ...] = await addAuthors(1);
        final inserted = Gate();
        final release = Gate();
        final holder = settle(
          inTx<void>((_) async {
            await store.insert(
              books,
              Book(title: 'b', year: 1, author: author(writer.id!)),
            );
            inserted.open();
            await release.wait;
          }, rollback: true),
        );
        await inserted.wait;
        final deleter = settle(
          inTx((_) => store.deleteById(authors, writer.id!)),
        );
        await waiting(1);
        release.open();
        await holder;
        expect(await deleter, isTrue);
        expect(await store.count(authors), 0);
      });
    });

    test('a reference waits for the delete of its target, then fails', () {
      return run(() async {
        final [writer, ...] = await addAuthors(1);
        final deleted = Gate();
        final release = Gate();
        // The author is deleted but not committed: a book that references
        // it still finds it (read committed) and waits for the delete.
        final deleting = inTx((_) async {
          await store.deleteById(authors, writer.id!);
          deleted.open();
          await release.wait;
        });
        await deleted.wait;
        final inserting = settle(
          inTx<Book>(
            (_) => store.insert(
              books,
              Book(title: 'b', year: 1, author: author(writer.id!)),
            ),
          ),
        );
        await waiting(1);
        release.open();
        await deleting;
        // It read the row again after the delete: it is gone.
        expect(await inserting, isA<DataIntegrityViolationException>());
        expect(await bookCount(), 0);
      });
    });

    test('equal unique values: the second inserter waits, then fails', () {
      return run(() async {
        final inserted = Gate();
        final release = Gate();
        final first = inTx((_) async {
          await store.insert(authors, Author(name: 'a', isni: '0001'));
          inserted.open();
          await release.wait;
        });
        await inserted.wait;
        final second = settle(
          inTx((_) => store.insert(authors, Author(name: 'b', isni: '0001'))),
        );
        await waiting(1);
        release.open();
        await first;
        expect(await second, isA<DuplicateKeyException>());
        expect(await store.count(authors), 1);
      });
    });

    test('...and succeeds when the first one is rolled back', () {
      return run(() async {
        final inserted = Gate();
        final release = Gate();
        final first = inTx((_) async {
          await store.insert(authors, Author(name: 'a', isni: '0001'));
          inserted.open();
          await release.wait;
        }, rollback: true);
        await inserted.wait;
        final second = settle(
          inTx((_) => store.insert(authors, Author(name: 'b', isni: '0001'))),
        );
        await waiting(1);
        release.open();
        await first;
        expect(await second, isA<Author>());
        expect(await store.count(authors), 1);
      });
    });

    test('a failed statement undoes its writes, the transaction goes on', () {
      return run(() async {
        await inTx((_) async {
          await store.insert(authors, Author(name: 'a', isni: '0001'));
          await expectLater(
            store.insert(authors, Author(name: 'b', isni: '0001')),
            throwsA(isA<DuplicateKeyException>()),
          );
          // The transaction goes on, with what the first statement wrote.
          await store.insert(authors, Author(name: 'c', isni: '0002'));
          expect(await store.count(authors), 2);
        });
        expect(await store.count(authors), 2);
      });
    });

    test('a delete that fails midway undoes the cascades it made', () {
      return run(() async {
        final [writer, ...] = await addAuthors(1);
        await store.insert(
          books,
          Book(title: 'b', year: 1, author: author(writer.id!)),
        );
        // The author has a book (noAction): nothing changes.
        await expectLater(
          inTx((_) => store.deleteById(authors, writer.id!)),
          throwsA(isA<DataIntegrityViolationException>()),
        );
        expect(await store.count(authors), 1);
        expect(await bookCount(), 1);
      });
    });
  });
}
