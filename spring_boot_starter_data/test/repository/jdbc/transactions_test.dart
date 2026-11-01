import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

// Repositories on SQLite inside the transactions of a service: a
// TransactionTemplate over the DataSourceTransactionManager of the data
// source, which is what `@Transactional` runs.
void main() {
  late Jdbc jdbc;

  Future<void> run(
    FutureOr<void> Function() body, {
    String? file,
    int connections = 1,
  }) => withJdbc(file: file, connections: connections, (j) async {
    jdbc = j;
    await body();
  });

  Future<void> runFile(
    FutureOr<void> Function() body, {
    int connections = 3,
  }) async {
    final temp = newTemp();
    addTearDown(() => deleteTemp(temp));
    await run(file: '${temp.path}/tx.db', connections: connections, body);
  }

  setUpAll(() => SpringLog.handler = (_) {});

  Future<int> total() async =>
      await jdbc.sqlBooks.count() +
      await jdbc.sqlOrders.count() +
      await jdbc.sqlAccounts.count().then((n) => n);

  group('several repository writes in one transaction', () {
    test(
      'commit together',
      () => run(() async {
        await jdbc.transaction().execute((_) async {
          await jdbc.sqlBooks.save(Book(title: 'a', year: 1));
          await jdbc.sqlOrders.save(
            PurchaseOrder(
              customer: 'ada',
              lines: [OrderLine(sku: 's', quantity: 1)],
            ),
          );
          await jdbc.sqlAccounts.save(
            const Account(iban: 'DE01', owner: 'Ada'),
          );
          // Visible inside.
          expect(await total(), 3);
        });
        expect(await total(), 3);
        expect(
          (await jdbc.sqlOrders.findAll()).single.lines.single.sku,
          's',
        );
      }),
    );

    test(
      'roll back together',
      () => run(() async {
        await expectLater(
          jdbc.transaction().execute((_) async {
            await jdbc.sqlBooks.save(Book(title: 'a', year: 1));
            await jdbc.sqlOrders.save(
              PurchaseOrder(
                customer: 'ada',
                lines: [OrderLine(sku: 's', quantity: 1)],
              ),
            );
            await jdbc.sqlAccounts.save(
              const Account(iban: 'DE01', owner: 'Ada'),
            );
            throw StateError('stop');
          }),
          throwsStateError,
        );
        expect(await total(), 0);
        expect(
          await jdbc.jdbc.queryForObject<int>(
            'select count(*) from order_lines',
          ),
          0,
        );
      }),
    );

    test(
      'the writes join the transaction: one connection, one begin',
      () => run(() async {
        final holders = <int>{};
        await jdbc.transaction().execute((_) async {
          await jdbc.sqlBooks.save(Book(title: 'a', year: 1));
          holders.add(DataSourceUtils.currentHolder(jdbc.dataSource)!.id);
          await jdbc.sqlBooks.save(Book(title: 'b', year: 2));
          holders.add(DataSourceUtils.currentHolder(jdbc.dataSource)!.id);
          await jdbc.sqlBooks.findAll();
          holders.add(DataSourceUtils.currentHolder(jdbc.dataSource)!.id);
        });
        expect(holders, hasLength(1));
        expect(jdbc.dataSource.activeCount, 0);
      }),
    );

    test(
      'a failed write in a joined transaction makes it rollback-only',
      () => run(() async {
        await jdbc.sqlBooks.save(Book(title: 'old', year: 1));
        final stale = (await jdbc.sqlBooks.findById(1))!;
        await jdbc.sqlBooks.save((await jdbc.sqlBooks.findById(1))!);
        await expectLater(
          jdbc.transaction().execute((_) async {
            await jdbc.sqlBooks.save(Book(title: 'new', year: 2));
            try {
              await jdbc.sqlBooks.save(stale..title = 'stale');
            } on OptimisticLockingFailureException {
              // Swallowed: the transaction is spoiled all the same.
            }
          }),
          throwsA(isA<UnexpectedRollbackException>()),
        );
        expect(await jdbc.sqlBooks.count(), 1);
      }),
    );

    test(
      'a transaction on the memory store is another transaction',
      () => run(() async {
        await expectLater(
          jdbc.transaction().execute((_) async {
            await jdbc.sqlBooks.save(Book(title: 'sql', year: 1));
            await jdbc.memoryBooks.save(Book(title: 'memory', year: 1));
            throw StateError('stop');
          }),
          throwsStateError,
        );
        // The SQL write is undone; the memory store has its own
        // transactions, which this one did not cover.
        expect(await jdbc.sqlBooks.count(), 0);
        expect(await jdbc.memoryBooks.count(), 1);
      }),
    );
  });

  group('requiresNew and nested', () {
    test(
      'requiresNew takes a second connection and commits on its own',
      () => runFile(() async {
        final outer = <int>[];
        await expectLater(
          jdbc.transaction().execute((_) async {
            // A read: the outer transaction holds no write lock.
            expect(await jdbc.sqlBooks.count(), 0);
            outer.add(DataSourceUtils.currentHolder(jdbc.dataSource)!.id);
            await jdbc
                .transaction(
                  const TransactionDefinition(
                    propagation: Propagation.requiresNew,
                  ),
                )
                .execute((_) async {
                  outer.add(
                    DataSourceUtils.currentHolder(jdbc.dataSource)!.id,
                  );
                  await jdbc.sqlBooks.save(Book(title: 'inner', year: 1));
                });
            outer.add(DataSourceUtils.currentHolder(jdbc.dataSource)!.id);
            throw StateError('the outer one fails');
          }),
          throwsStateError,
        );
        expect(outer[0], isNot(outer[1]));
        expect(outer[0], outer[2]);
        // The inner transaction stayed committed.
        expect(await jdbc.sqlBooks.count(), 1);
        expect(jdbc.dataSource.activeCount, 0);
      }),
    );

    test(
      'nested rolls back to its savepoint only',
      () => run(() async {
        await jdbc.transaction().execute((_) async {
          await jdbc.sqlBooks.save(Book(title: 'outer', year: 1));
          await expectLater(
            jdbc
                .transaction(
                  const TransactionDefinition(propagation: Propagation.nested),
                )
                .execute((_) async {
                  await jdbc.sqlBooks.save(Book(title: 'inner', year: 2));
                  throw StateError('inner fails');
                }),
            throwsStateError,
          );
        });
        expect(
          [for (final b in await jdbc.sqlBooks.findAll()) b.title],
          [
            'outer',
          ],
        );
      }),
    );
  });

  group('optimistic locking between two transactions', () {
    test(
      'a stale instance loses in the next transaction',
      () => runFile(() async {
        final books = jdbc.sqlBooks;
        await books.save(Book(title: 'shared', year: 1));
        final mine = (await books.findById(1))!;
        final yours = (await books.findById(1))!;
        await jdbc.transaction().execute((_) => books.save(mine..title = 'A'));
        await expectLater(
          jdbc.transaction().execute((_) => books.save(yours..title = 'B')),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
        expect((await books.findById(1))!.title, 'A');
        expect((await books.findById(1))!.version, 2);
      }),
    );

    test(
      'two transactions reading before writing: one wins, the other fails',
      () => runFile(() async {
        final books = jdbc.sqlBooks;
        await books.save(Book(title: 'shared', year: 1));
        final bothRead = [Completer<void>(), Completer<void>()];
        final firstWrote = Completer<void>();
        Future<void> writer(int index, String title) =>
            jdbc.transaction().execute((_) async {
              final book = (await books.findById(1))!;
              bothRead[index].complete();
              await Future.wait(bothRead.map((c) => c.future));
              if (index == 1) {
                await firstWrote.future;
              }
              await books.save(book..title = title);
              if (index == 0) {
                firstWrote.complete();
              }
            });
        final results = await Future.wait([
          outcome(writer(0, 'first')),
          outcome(writer(1, 'second')),
        ]);
        expect(results[0], isNull);
        // SQLite (WAL) refuses a writer whose snapshot is stale: the lost
        // update is stopped by the database as a lock failure (retry the
        // transaction) before the version check could see it. On a
        // database with row locks and read committed it is the version
        // check that stops it (see the stale instance test).
        expect(results[1], isA<CannotAcquireLockException>());
        expect((await books.findById(1))!.title, 'first');
      }),
    );
  });
}
