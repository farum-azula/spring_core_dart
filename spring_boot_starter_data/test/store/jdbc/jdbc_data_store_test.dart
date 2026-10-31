import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../../jdbc/support/fake_jdbc.dart';
import '../../repository/jdbc/support.dart';
import 'row_lock_dialect.dart';

// The JDBC store on SQLite: what its statements are, what its errors are,
// how it locks, and what it does with transactions.
void main() {
  late Jdbc jdbc;

  Future<void> run(
    FutureOr<void> Function() body, {
    String? file,
    int connections = 1,
    Map<String, String> driverProperties = const {},
  }) => withJdbc(
    file: file,
    connections: connections,
    driverProperties: driverProperties,
    (j) async {
      jdbc = j;
      await body();
    },
  );

  // The log records the body made, of the logger [name] (and its children).
  Future<List<SpringLogRecord>> logged(
    FutureOr<void> Function() body, {
    SpringLogLevel level = SpringLogLevel.debug,
  }) async {
    final records = <SpringLogRecord>[];
    SpringLog.setLevel('spring.jdbc.core', level);
    final stop = SpringLog.listen(records.add);
    try {
      await body();
    } finally {
      stop();
      SpringLog.resetLevels();
    }
    return records;
  }

  List<String> sqlOf(List<SpringLogRecord> records) => [
    for (final r in records)
      if (r.loggerName == 'spring.jdbc.core.JdbcTemplate') r.message,
  ];

  setUpAll(() => SpringLog.handler = (_) {});

  PurchaseOrder order(String customer) => PurchaseOrder(
    customer: customer,
    lines: [OrderLine(sku: '$customer-1', quantity: 1)],
    notes: {'a': OrderNote(text: 'n')},
    tags: {OrderTag(label: 't')},
  );

  group(
    'children: one select for each collection, never one for each root',
    () {
      test(
        'findAll, findAllById and a query read the children in bulk',
        () => run(() async {
          final orders = jdbc.sqlOrders;
          for (var i = 0; i < 12; i++) {
            await orders.save(order('c$i'));
          }
          late List<PurchaseOrder> all;
          var sql = sqlOf(
            await logged(() async => all = await orders.findAll()),
          );
          expect(all, hasLength(12));
          // The roots, then lines, notes and tags: four statements.
          expect(sql, hasLength(4));
          expect(sql[0], contains('from "orders"'));
          expect(sql[1], contains('from "order_lines"'));
          expect(sql[2], contains('from "order_notes"'));
          expect(sql[3], contains('from "order_tags"'));
          expect(
            sql[1],
            contains('"orders_id" in (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'),
          );
          sql = sqlOf(await logged(() => orders.findAllById([1, 5, 9])));
          expect(sql, hasLength(4));
          sql = sqlOf(await logged(() => orders.findByCustomer('c3')));
          expect(sql, hasLength(4));
          // No root, no child statement.
          sql = sqlOf(await logged(() => orders.findByCustomer('nobody')));
          expect(sql, hasLength(1));
        }),
      );

      test(
        'a save is: the root, then the children; an update replaces them',
        () => run(() async {
          final orders = jdbc.sqlOrders;
          final saved = await orders.save(order('ada'));
          final sql = sqlOf(
            await logged(() async {
              await orders.save(saved..customer = 'ada l.');
            }),
          );
          expect(sql[0], startsWith('[test tx#'));
          expect(sql[0], contains('update "orders" set'));
          expect(sql[1], contains('delete from "order_lines"'));
          expect(sql[2], contains('delete from "order_notes"'));
          expect(sql[3], contains('delete from "order_tags"'));
          expect(sql[4], contains('insert into "order_lines"'));
          expect(sql, hasLength(7));
        }),
      );

      test(
        'a failure while writing the children undoes the root too',
        () => run(() async {
          await jdbc.jdbc.execute('drop table order_tags');
          await expectLater(
            jdbc.sqlOrders.save(order('ada')),
            throwsA(isA<BadSqlGrammarException>()),
          );
          expect(await jdbc.sqlOrders.count(), 0);
          expect(
            await jdbc.jdbc.queryForObject<int>(
              'select count(*) from order_lines',
            ),
            0,
          );
        }),
      );

      test(
        'the store alone, without a repository, is atomic as well',
        () => run(() async {
          await jdbc.jdbc.execute('drop table order_tags');
          await expectLater(
            jdbc.store.insert(jdbc.entity<PurchaseOrder>(), order('ada')),
            throwsA(isA<BadSqlGrammarException>()),
          );
          expect(await jdbc.store.count(jdbc.entity<PurchaseOrder>()), 0);
        }),
      );

      test(
        'children with children are refused with a clear message',
        () => run(() async {
          await expectLater(
            jdbc.sqlCrates.save(
              Crate(
                name: 'c',
                jars: [Jar(label: 'j')],
              ),
            ),
            throwsA(
              isA<InvalidDataAccessApiUsageException>().having(
                (e) => e.message,
                'message',
                allOf(contains('Jar'), contains('one level of children')),
              ),
            ),
          );
        }),
      );
    },
  );

  group('many ids', () {
    test(
      'more ids than one statement takes: chunks, in the order of the table',
      () => run(() async {
        final notes = jdbc.sqlNotes;
        await notes.saveAll([for (var i = 0; i < 1200; i++) Note(text: '$i')]);
        final found = await notes.findAllById([
          for (var i = 1200; i > 0; i--) i,
        ]);
        expect(found, hasLength(1200));
        expect(
          [for (final n in found) n.id],
          [for (var i = 1; i <= 1200; i++) i],
        );
        final entity = jdbc.entity<Note>();
        final removed = await jdbc.store.deleteWhereAndReturn(entity);
        expect(removed, hasLength(1200));
        expect(await notes.count(), 0);
      }),
    );
  });

  group('errors and logs', () {
    test(
      'a duplicate key carries the SQL and the constraint, never the values',
      () => run(() async {
        await jdbc.sqlAccounts.save(
          const Account(iban: 'DE-SECRET-1', owner: 'Ada'),
        );
        Object? error;
        try {
          await jdbc.sqlAccounts.save(
            const Account(iban: 'DE-SECRET-1', owner: 'Bob'),
          );
        } on DuplicateKeyException catch (e) {
          error = e;
        }
        final duplicate = error! as DuplicateKeyException;
        expect(duplicate.sql, startsWith('insert into "accounts"'));
        expect(duplicate.constraint, contains('accounts.iban'));
        expect(duplicate.sql, isNot(contains('DE-SECRET-1')));
        expect(duplicate.toString(), isNot(contains('DE-SECRET-1')));
      }),
    );

    test(
      'wrong SQL is a BadSqlGrammarException with the statement',
      () => run(() async {
        await jdbc.jdbc.execute('drop table notes');
        Object? error;
        try {
          await jdbc.sqlNotes.findAll();
        } on BadSqlGrammarException catch (e) {
          error = e;
        }
        expect((error! as BadSqlGrammarException).sql, contains('"notes"'));
      }),
    );

    test(
      'debug logs the SQL, trace the values, and nothing at the default',
      () => run(() async {
        final quiet = await logged(
          () => jdbc.sqlBooks.findByTitle('Quiet'),
          level: SpringLogLevel.info,
        );
        expect(quiet, isEmpty);
        final debug = await logged(() => jdbc.sqlBooks.findByTitle('Loud'));
        expect(sqlOf(debug).single, contains('select "id", "title"'));
        expect(debug.map((r) => r.message).join(), isNot(contains('Loud')));
        final trace = await logged(
          () => jdbc.sqlBooks.findByTitle('Loud'),
          level: SpringLogLevel.trace,
        );
        expect(trace.map((r) => r.message).join('\n'), contains('Loud'));
      }),
    );
  });

  group('locks on SQLite', () {
    Future<void> seedStock() async {
      await jdbc.sqlStocks.saveAll([
        Stock(sku: 'a', quantity: 5),
        Stock(sku: 'b', quantity: 1),
      ]);
    }

    test(
      'a locking read outside a transaction never runs unlocked',
      () => run(() async {
        await seedStock();
        for (final call in [
          () => jdbc.sqlStocks.findBySku('a'),
          () => jdbc.sqlStocks.findByQuantityLessThan(10),
          () => jdbc.sqlStocks.findById(1),
        ]) {
          await expectLater(
            call(),
            throwsA(isA<IllegalTransactionStateException>()),
          );
        }
      }),
    );

    test(
      'as the first statement of a transaction it works, again and again',
      () => run(() async {
        await seedStock();
        await jdbc.transaction().execute((_) async {
          expect((await jdbc.sqlStocks.findBySku('a'))!.quantity, 5);
          expect(await jdbc.sqlStocks.findByQuantityLessThan(10), hasLength(2));
          expect((await jdbc.sqlStocks.findById(2))!.sku, 'b');
          // A write after the lock is the same transaction's.
          await jdbc.sqlStocks.save(Stock(sku: 'c', quantity: 0));
        });
        expect(await jdbc.sqlStocks.count(), 3);
      }),
    );

    test(
      'after a read it fails clearly: the transaction cannot become the writer',
      () => run(() async {
        await seedStock();
        await expectLater(
          jdbc.transaction().execute((_) async {
            await jdbc.sqlStocks.count();
            return await jdbc.sqlStocks.findBySku('a');
          }),
          throwsA(
            isA<IllegalTransactionStateException>().having(
              (e) => e.message,
              'message',
              allOf(contains('first statement'), contains('sqlite')),
            ),
          ),
        );
      }),
    );

    test(
      'not in a read-only transaction',
      () => run(() async {
        await seedStock();
        await expectLater(
          jdbc
              .transaction(const TransactionDefinition(readOnly: true))
              .execute((_) => jdbc.sqlStocks.findBySku('a')),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      }),
    );

    test(
      'a skip locked and a timeout are moot: the database lock is taken',
      () => run(() async {
        await seedStock();
        await jdbc.transaction().execute((_) async {
          final found = await jdbc.store.find(
            jdbc.entity<Stock>(),
            lock: LockMode.pessimisticWrite,
            lockTimeout: Duration.zero,
            skipLocked: true,
          );
          expect(found, hasLength(2));
        });
      }),
    );

    test(
      'a second writer waits for the first and then fails with a lock error',
      () async {
        final temp = newTemp();
        addTearDown(() => deleteTemp(temp));
        await run(
          file: '${temp.path}/lock.db',
          connections: 3,
          driverProperties: const {'busy-timeout': '150'},
          () async {
            await seedStock();
            final holding = Completer<void>();
            final release = Completer<void>();
            final first = jdbc.transaction().execute((_) async {
              await jdbc.sqlStocks.findBySku('a');
              holding.complete();
              await release.future;
            });
            await holding.future;
            await expectLater(
              jdbc
                  .transaction(
                    const TransactionDefinition(
                      propagation: Propagation.requiresNew,
                    ),
                  )
                  .execute((_) => jdbc.sqlStocks.findBySku('a')),
              throwsA(isA<CannotAcquireLockException>()),
            );
            release.complete();
            await first;
            // Free again.
            await jdbc.transaction().execute((_) async {
              expect(await jdbc.sqlStocks.findBySku('a'), isNotNull);
            });
          },
        );
      },
    );
  });

  group('row locks (a dialect that has them)', () {
    late FakeJdbcDriver driver;
    late JdbcDataStore store;
    late PersistentEntity<Stock> entity;

    Future<void> runFake(FutureOr<void> Function() body) => run(() async {
      driver = FakeJdbcDriver(dialect: RowLockDialect())
        ..onConnect = (c) => c.onQuery = (sql, _) => JdbcResult(
          ['id', 'sku', 'quantity'],
          [
            [1, 'a', 5],
          ],
        );
      store = JdbcDataStore(
        dataSource: fakePool(driver),
        converter: jdbc.factory.converter,
      );
      entity = jdbc.entity<Stock>();
      await body();
    });

    List<String> statements() => [
      for (final c in driver.connections) ...c.statements,
    ];

    test(
      'the lock clause, with the timeout statement before the select',
      () => runFake(() async {
        await TransactionTemplate(store.transactionManager).execute(
          (_) => store.findById(
            entity,
            1,
            lock: LockMode.pessimisticWrite,
            lockTimeout: const Duration(seconds: 2),
            skipLocked: true,
          ),
        );
        const select =
            'select "id", "sku", "quantity" from "stock" where "id" = ? ';
        expect(statements(), [
          "SET LOCAL lock_timeout = '2000ms'",
          '${select}FOR UPDATE SKIP LOCKED',
        ]);
      }),
    );

    test(
      'no wait is NOWAIT; a shared lock is FOR SHARE; find locks too',
      () => runFake(() async {
        await TransactionTemplate(store.transactionManager).execute((_) async {
          await store.findById(
            entity,
            1,
            lock: LockMode.pessimisticWrite,
            lockTimeout: Duration.zero,
          );
          await store.find(
            entity,
            criteria: Criteria(
              const [
                OrPart([
                  Part(['quantity'], PartType.lessThan),
                ]),
              ],
              [10],
            ),
            limit: 1,
            lock: LockMode.pessimisticRead,
          );
        });
        const select = 'select "id", "sku", "quantity" from "stock" where ';
        expect(statements(), [
          '$select"id" = ? FOR UPDATE NOWAIT',
          '$select("quantity" < ?) order by "id" ASC LIMIT 1 FOR SHARE',
        ]);
      }),
    );

    test(
      'outside a transaction nothing runs at all',
      () => runFake(() async {
        await expectLater(
          store.findById(entity, 1, lock: LockMode.pessimisticWrite),
          throwsA(isA<IllegalTransactionStateException>()),
        );
        await expectLater(
          store.find(entity, lock: LockMode.pessimisticRead),
          throwsA(isA<IllegalTransactionStateException>()),
        );
        expect(statements(), isEmpty);
      }),
    );
  });

  group('transactions', () {
    test(
      'a read-only transaction refuses writes, as the memory store does',
      () => run(() async {
        await expectLater(
          jdbc
              .transaction(const TransactionDefinition(readOnly: true))
              .execute((_) => jdbc.sqlNotes.save(Note(text: 'x'))),
          throwsA(isA<InvalidDataAccessResourceUsageException>()),
        );
        expect(await jdbc.sqlNotes.count(), 0);
      }),
    );

    test(
      'the repository and the store use the manager of the data source',
      () => run(() async {
        expect(jdbc.transactions.dataSource, same(jdbc.dataSource));
        expect(jdbc.store.dataSource, same(jdbc.dataSource));
        expect(jdbc.store.name, 'jdbc');
        expect(jdbc.store.toString(), contains('test'));
      }),
    );
  });
}
