@Tags(['postgres'])
library;

// Locks and concurrent transactions of the JDBC store on PostgreSQL, through
// the repositories of the SQL test application: `@Lock` (FOR UPDATE, FOR
// SHARE, NOWAIT, SKIP LOCKED, the lock timeout), the version column, and the
// isolation levels. Two transactions, each on a connection of its own, are
// held open side by side with completers.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../repository/jdbc/support.dart';
import 'support.dart';

void main() => group('PostgreSQL', () {
  usePostgresServer();
  _tests();
}, skip: postgresServerSkip);

Future<void> _run(Future<void> Function(Jdbc jdbc) body) =>
    withJdbc(postgres: true, connections: 4, (j) async {
      await j.sqlStocks.saveAll([
        Stock(sku: 'a', quantity: 5),
        Stock(sku: 'b', quantity: 1),
        Stock(sku: 'c', quantity: 9),
      ]);
      await body(j);
    });

// Locks the row of the stock 'a' for update.
Future<void> _lockA(Jdbc j) async {
  await j.sqlStocks.findBySku('a');
}

// Two transactions side by side: [first] runs and, once it calls `hold`,
// [second] runs with `first` still open; `first` ends when [second] is done.
Future<(Object?, Object?)> _sideBySide(
  Jdbc j,
  Future<void> Function() first,
  Future<void> Function() second, {
  TransactionDefinition definition = TransactionDefinition.defaults,
}) async {
  final holding = Completer<void>();
  final release = Completer<void>();
  final a = j
      .transaction(definition)
      .execute((_) async {
        await first();
        holding.complete();
        await release.future;
      })
      .then<Object?>((_) => null, onError: (Object e) => e);
  await holding.future;
  final b = await j
      .transaction(definition)
      .execute((_) => second())
      .then<Object?>((_) => null, onError: (Object e) => e);
  release.complete();
  return (await a, b);
}

void _tests() {
  group('a locking read', () {
    test(
      'outside a transaction never runs unlocked',
      () => _run((j) async {
        await expectLater(
          j.sqlStocks.findBySku('a'),
          throwsA(isA<IllegalTransactionStateException>()),
        );
      }),
    );

    test(
      'in a transaction locks FOR UPDATE and reads',
      () => _run((j) async {
        await j.transaction().execute((_) async {
          expect((await j.sqlStocks.findBySku('a'))!.quantity, 5);
          expect(await j.sqlStocks.findByQuantityLessThan(10), hasLength(3));
          expect((await j.sqlStocks.findById(2))!.sku, 'b');
          // A write after the lock is the same transaction's.
          await j.sqlStocks.save(Stock(sku: 'd', quantity: 0));
        });
        expect(await j.sqlStocks.count(), 4);
      }),
    );

    test(
      'not in a read-only transaction',
      () => _run((j) async {
        await expectLater(
          j
              .transaction(const TransactionDefinition(readOnly: true))
              .execute((_) => j.sqlStocks.findBySku('a')),
          throwsA(
            anyOf(
              isA<InvalidDataAccessApiUsageException>(),
              isA<InvalidDataAccessResourceUsageException>(),
            ),
          ),
        );
      }),
    );

    test(
      'FOR UPDATE: a second writer waits for the first to end',
      () => _run((
        j,
      ) async {
        final order = <String>[];
        final holding = Completer<void>();
        final release = Completer<void>();
        final first = j.transaction().execute((_) async {
          await j.sqlStocks.findBySku('a');
          order.add('first holds');
          holding.complete();
          await release.future;
          order.add('first ends');
        });
        await holding.future;
        final second = j.transaction().execute((_) async {
          order.add('second asks');
          final stock = await j.sqlStocks.findBySku('a');
          order.add('second holds');
          return stock;
        });
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(order, ['first holds', 'second asks']);
        release.complete();
        await first;
        expect((await second)!.sku, 'a');
        expect(order, [
          'first holds',
          'second asks',
          'first ends',
          'second holds',
        ]);
      }),
    );

    test(
      'NOWAIT fails at once with a CannotAcquireLockException',
      () => _run((
        j,
      ) async {
        final (_, failure) = await _sideBySide(
          j,
          () => _lockA(j),
          () => j.store.find(
            j.entity<Stock>(),
            lock: LockMode.pessimisticWrite,
            lockTimeout: Duration.zero,
          ),
        );
        expect(failure, isA<CannotAcquireLockException>());
      }),
    );

    test(
      'a lock timeout bounds the wait',
      () => _run((j) async {
        final watch = Stopwatch()..start();
        final (_, failure) = await _sideBySide(
          j,
          () => _lockA(j),
          () => j.store.find(
            j.entity<Stock>(),
            lock: LockMode.pessimisticWrite,
            lockTimeout: const Duration(milliseconds: 300),
          ),
        );
        expect(failure, isA<CannotAcquireLockException>());
        expect(
          watch.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 250)),
        );
      }),
    );

    test(
      'SKIP LOCKED leaves out the rows another transaction holds',
      () => _run((j) async {
        List<String>? seen;
        final (_, failure) = await _sideBySide(
          j,
          () => _lockA(j),
          () async {
            final found = await j.store.find(
              j.entity<Stock>(),
              lock: LockMode.pessimisticWrite,
              skipLocked: true,
            );
            seen = [for (final stock in found) stock.sku];
          },
        );
        expect(failure, isNull);
        expect(seen, ['b', 'c']);
      }),
    );

    test(
      'SKIP LOCKED with a limit takes the next rows, as a work queue '
      'does',
      () => _run((j) async {
        List<String>? seen;
        await _sideBySide(
          j,
          () => _lockA(j),
          () async {
            final found = await j.store.find(
              j.entity<Stock>(),
              sort: Sort.by(['sku']),
              limit: 1,
              lock: LockMode.pessimisticWrite,
              skipLocked: true,
            );
            seen = [for (final stock in found) stock.sku];
          },
        );
        expect(seen, ['b']);
      }),
    );

    test(
      'FOR SHARE: readers share, a writer is refused',
      () => _run((j) async {
        Object? writer;
        final (_, reader) = await _sideBySide(
          j,
          () => j.store.find(
            j.entity<Stock>(),
            lock: LockMode.pessimisticRead,
          ),
          () async {
            // Another reader gets in.
            await j.store.find(
              j.entity<Stock>(),
              lock: LockMode.pessimisticRead,
              lockTimeout: Duration.zero,
            );
            // A writer does not.
            try {
              await j.store.find(
                j.entity<Stock>(),
                lock: LockMode.pessimisticWrite,
                lockTimeout: Duration.zero,
              );
            } on Object catch (error) {
              writer = error;
            }
          },
        );
        expect(reader, isNull);
        expect(writer, isA<CannotAcquireLockException>());
      }),
    );

    test(
      'a locked row is not changed by another transaction until the '
      'first ends',
      () => _run((j) async {
        final changed = Completer<void>();
        final holding = Completer<void>();
        final release = Completer<void>();
        final first = j.transaction().execute((_) async {
          await j.sqlStocks.findBySku('a');
          holding.complete();
          await release.future;
        });
        await holding.future;
        final second = j.sqlStocks.findOneBySku('a').then((stock) async {
          // A plain read does not wait: it sees the row as it is.
          expect(stock!.quantity, 5);
          stock.quantity = 6;
          await j.sqlStocks.save(stock);
          changed.complete();
        });
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(changed.isCompleted, isFalse, reason: 'the update waits');
        release.complete();
        await first;
        await second;
        expect((await j.sqlStocks.findOneBySku('a'))!.quantity, 6);
      }),
    );
  });

  group('the version column', () {
    test(
      'two transactions that read then write: one wins, the other fails '
      'with an OptimisticLockingFailureException',
      () => _run((j) async {
        final book = await j.sqlBooks.save(Book(title: 'Dune', year: 1965));
        final read = Completer<void>();
        final go = Completer<void>();
        Future<Object?> change(String title) => j
            .transaction()
            .execute((_) async {
              final copy = (await j.sqlBooks.findById(book.id!))!;
              if (!read.isCompleted) {
                read.complete();
                await go.future;
              }
              copy.title = title;
              await j.sqlBooks.save(copy);
            })
            .then<Object?>((_) => null, onError: (Object e) => e);
        final first = change('first');
        await read.future;
        final second = change('second');
        // The second read the row too, before the first writes.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        go.complete();
        final results = await Future.wait([first, second]);
        expect(
          results.whereType<OptimisticLockingFailureException>(),
          hasLength(1),
          reason: '$results',
        );
        expect(results.where((r) => r == null), hasLength(1));
        expect((await j.sqlBooks.findById(book.id!))!.version, 2);
      }),
    );
  });

  group('isolation levels', () {
    test(
      'repeatable read: a row changed by another transaction since the '
      'snapshot cannot be updated',
      () => _run((j) async {
        const repeatable = TransactionDefinition(
          isolation: Isolation.repeatableRead,
        );
        // A transaction updates a row another changed after its snapshot.
        final conflict = Completer<Object?>();
        await j
            .transaction(repeatable)
            .execute((_) async {
              final stock = (await j.sqlStocks.findOneBySku('a'))!;
              await j
                  .transaction(
                    const TransactionDefinition(
                      propagation: Propagation.requiresNew,
                    ),
                  )
                  .execute((_) async {
                    final again = (await j.sqlStocks.findOneBySku('a'))!;
                    await j.sqlStocks.save(again..quantity = 51);
                  });
              try {
                stock.quantity = 52;
                await j.sqlStocks.save(stock);
                conflict.complete(null);
              } on Object catch (error) {
                conflict.complete(error);
              }
            })
            .then<void>((_) {}, onError: (Object _) {});
        expect(
          await conflict.future,
          anyOf(
            isA<CannotSerializeTransactionException>(),
            isA<OptimisticLockingFailureException>(),
          ),
        );
      }),
    );
  });
}
