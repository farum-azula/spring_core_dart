// Repositories and @Transactional services end to end, on the real
// in-memory store. Races are ordered with Completers; the only waits are the
// ones whose subject is a timeout.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('a service over repositories', () {
    test(
      'commits when the method returns',
      () => withApp((app) async {
        await app.warehouse.addItem('a');
        expect(await app.itemNames(), ['a']);
      }),
    );

    test(
      'rolls the writes back when the method throws',
      () => withApp((
        app,
      ) async {
        await expectLater(
          app.warehouse.addItem('a', Oops()),
          throwsA(isA<Oops>()),
        );
        expect(await app.itemNames(), isEmpty);
      }),
    );

    test(
      'noRollbackFor commits and throws; other errors roll back',
      () => withApp((app) async {
        await expectLater(
          app.warehouse.addItemTolerant('soft', Soft()),
          throwsA(isA<Soft>()),
        );
        expect(await app.itemNames(), ['soft']);
        await expectLater(
          app.warehouse.addItemTolerant('hard', Oops()),
          throwsA(isA<Oops>()),
        );
        expect(await app.itemNames(), ['soft']);
      }),
    );

    test(
      'requiresNew: the audit line outlives the outer rollback',
      () => withApp((app) async {
        await expectLater(
          app.warehouse.addWithAudit('x', fail: true),
          throwsA(isA<Oops>()),
        );
        expect(await app.itemNames(), isEmpty);
        expect(await app.auditTexts(), ['added x 1']);
      }),
    );

    test(
      'requiresNew: the outer goes on after it and commits',
      () => withApp((
        app,
      ) async {
        await app.warehouse.addWithAudit('x', fail: false);
        expect(await app.itemNames(), ['x 1', 'x 2']);
        expect(await app.auditTexts(), ['added x 1']);
      }),
    );

    test(
      'nested: a failed part rolls back alone',
      () => withApp((app) async {
        await app.warehouse.addWithNested(failNested: true);
        expect(await app.itemNames(), ['outer', 'outer after']);
        expect(await app.auditTexts(), isEmpty);
      }),
    );

    test(
      'nested: a part that succeeds is kept',
      () => withApp((app) async {
        await app.warehouse.addWithNested(failNested: false);
        expect(await app.itemNames(), ['outer', 'outer after']);
        expect(await app.auditTexts(), ['nested']);
      }),
    );

    test(
      'readOnly refuses writes and lets reads through',
      () => withApp((
        app,
      ) async {
        await expectLater(
          app.warehouse.writeReadOnly(),
          throwsA(isA<InvalidDataAccessResourceUsageException>()),
        );
        expect(await app.warehouse.countReadOnly(), 0);
        expect(await app.itemNames(), isEmpty);
      }),
    );

    test(
      'mandatory needs a transaction, never refuses one',
      () => withApp((
        app,
      ) async {
        await expectLater(
          app.auditor.mandatory('alone'),
          throwsA(isA<IllegalTransactionStateException>()),
        );
        await app.warehouse.callMandatory();
        expect(await app.auditTexts(), ['mandatory']);

        expect(await app.auditor.never(), 1);
        await expectLater(
          app.warehouse.callNever(),
          throwsA(isA<IllegalTransactionStateException>()),
        );
      }),
    );

    test(
      'an aggregate is rolled back with its children',
      () => withApp((
        app,
      ) async {
        await expectLater(
          app.warehouse.ship(fail: true),
          throwsA(isA<Oops>()),
        );
        expect(await app.shipments.count(), 0);
        final parcels = app.context
            .getBean<RelationalMappingContext>()
            .getRequiredPersistentEntity<Parcel>();
        expect(app.store.size(parcels), 0);

        await app.warehouse.ship(fail: false);
        final shipment = (await app.shipments.findAll()).single;
        expect([for (final p in shipment.parcels) p.label], ['a', 'b']);
      }),
    );

    test(
      'a TransactionTemplate joins the repositories too',
      () => withApp((
        app,
      ) async {
        final template = app.context.getBean<TransactionTemplate>();
        expect(template.manager, isA<InMemoryTransactionManager>());
        await template.execute((status) async {
          await app.items.save(Item(name: 'a'));
          await app.items.save(Item(name: 'b'));
          expect(await app.items.count(), 2);
          status.setRollbackOnly();
        });
        expect(await app.items.count(), 0);
      }),
    );
  });

  group('a repository on its own', () {
    test(
      'saveAll is atomic: a duplicate id undoes the ones before',
      () => withApp((app) async {
        await expectLater(
          app.labels.saveAll([
            const Label('a'),
            const Label('b'),
            const Label('a'),
          ]),
          throwsA(isA<DuplicateKeyException>()),
        );
        expect(await app.labels.count(), 0);

        await app.labels.saveAll([const Label('a'), const Label('b')]);
        expect(await app.labels.count(), 2);
      }),
    );

    test(
      'saveAll is atomic: a version conflict undoes the ones before',
      () => withApp((app) async {
        final first = await app.items.save(Item(name: 'a'));
        final stale = Item(
          name: 'stale',
          id: first.id,
          version: first.version,
        );
        first.name = 'a2';
        await app.items.save(first);

        await expectLater(
          app.items.saveAll([Item(name: 'new'), stale]),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
        expect(await app.itemNames(), ['a2']);
      }),
    );

    test(
      'deleteAll joins nothing and leaves the table empty',
      () => withApp((
        app,
      ) async {
        await app.items.saveAll([Item(name: 'a'), Item(name: 'b')]);
        await app.items.deleteAll();
        expect(await app.items.count(), 0);
      }),
    );

    test(
      'inside a failing transaction the writes of a repository roll '
      'back with it',
      () => withApp((app) async {
        await expectLater(
          app.warehouse.addItem('a', Oops()),
          throwsA(isA<Oops>()),
        );
        await app.items.save(Item(name: 'alone'));
        expect(await app.itemNames(), ['alone']);
      }),
    );
  });

  group('locks', () {
    Future<void> shelf(App app, String sku, int quantity) async {
      await app.stock.save(Stock(sku: sku, quantity: quantity));
    }

    test(
      'two sellers of the same row serialize: no oversell',
      () => withApp((
        app,
      ) async {
        await shelf(app, 'dune', 1);
        final locked = Completer<void>();
        final release = Completer<void>();
        app.gate.once = () async {
          locked.complete();
          await release.future;
        };
        final first = outcome(app.warehouse.sell('dune', 1));
        await locked.future;

        var secondDone = false;
        final second = outcome(app.warehouse.sell('dune', 1));
        unawaited(second.whenComplete(() => secondDone = true));
        await app.until(() => app.store.waitingCount == 1);
        expect(secondDone, isFalse);

        release.complete();
        expect(await first, 1);
        // The second waited, then saw the decremented row.
        expect(await second, isA<OutOfStock>());
        expect((await app.stock.findAll()).single.quantity, 0);
      }),
    );

    test(
      'the second seller sees the value the first one left',
      () => withApp((
        app,
      ) async {
        await shelf(app, 'dune', 2);
        final locked = Completer<void>();
        final release = Completer<void>();
        app.gate.once = () async {
          locked.complete();
          await release.future;
        };
        final first = outcome(app.warehouse.sell('dune', 1));
        await locked.future;
        final second = outcome(app.warehouse.sell('dune', 1));
        await app.until(() => app.store.waitingCount == 1);

        release.complete();
        expect(await first, 2);
        expect(await second, 1);
        expect((await app.stock.findAll()).single.quantity, 0);
      }),
    );

    test(
      'skipLocked: two workers of a queue take different jobs',
      () => withApp((app) async {
        await app.jobs.saveAll([
          Job(name: 'j1'),
          Job(name: 'j2'),
          Job(name: 'j3'),
        ]);
        final locked = Completer<void>();
        final release = Completer<void>();
        app.gate.once = () async {
          locked.complete();
          await release.future;
        };
        final first = app.warehouse.takeJob();
        await locked.future;

        // j1 is held: the second worker takes j2 without waiting.
        expect(await app.warehouse.takeJob(), 'j2');
        expect(app.store.waitingCount, 0);

        release.complete();
        expect(await first, 'j1');
        expect(await app.warehouse.takeJob(), 'j3');
        expect(await app.warehouse.takeJob(), isNull);
      }),
    );

    test(
      'a locking method outside a transaction fails, never unlocked',
      () => withApp((app) async {
        await shelf(app, 'dune', 1);
        await expectLater(
          app.stock.findBySku('dune'),
          throwsA(isA<IllegalTransactionStateException>()),
        );
      }),
    );

    test(
      'a transaction of another store is not enough',
      () => withApp((
        app,
      ) async {
        await shelf(app, 'dune', 1);
        await expectLater(
          app.warehouse.lockFromOtherStore('dune'),
          throwsA(isA<IllegalTransactionStateException>()),
        );
      }),
    );

    test(
      'the timeout of @Lock gives up with CannotAcquireLockException',
      () => withApp((app) async {
        await shelf(app, 'dune', 1);
        final locked = Completer<void>();
        final release = Completer<void>();
        app.gate.once = () async {
          locked.complete();
          await release.future;
        };
        final holder = outcome(app.warehouse.sell('dune', 1));
        await locked.future;

        // Here the timeout is the subject: 50 ms, from the annotation.
        await expectLater(
          app.warehouse.peekWithTimeout('dune'),
          throwsA(isA<CannotAcquireLockException>()),
        );
        release.complete();
        expect(await holder, 1);
      }),
    );

    test(
      "spring.data.memory.lock-timeout sets the stores' timeout",
      () => withApp(
        (app) async {
          expect(app.store.lockTimeout, const Duration(milliseconds: 250));
          expect(
            app.dataSources.storeFor('archive').lockTimeout,
            const Duration(milliseconds: 250),
          );
        },
        properties: const ['spring.data.memory.lock-timeout=250ms'],
      ),
    );

    test(
      'the lock timeout is 10 seconds by default',
      () => withApp((
        app,
      ) async {
        expect(app.store.lockTimeout, const Duration(seconds: 10));
      }),
    );

    test('a negative lock timeout stops the start', () async {
      await integrationRunner(const [
        'spring.data.memory.lock-timeout=-1s',
      ]).runAsync((context) async {
        expect(context.hasFailed, isTrue);
        expect('${context.startupFailure}', contains('lock-timeout'));
      });
    });
  });

  group('optimistic locking', () {
    test(
      'a lost update under two transactions fails for one',
      () => withApp((
        app,
      ) async {
        final item = await app.items.save(Item(name: 'start'));
        final readIt = Completer<void>();
        final release = Completer<void>();
        app.gate.once = () async {
          readIt.complete();
          await release.future;
        };
        // The first reads the item and stops; the second reads, writes and
        // commits; the first then writes a version that is gone.
        final first = outcome(app.warehouse.rename(item.id!, 'one'));
        await readIt.future;
        await app.warehouse.rename(item.id!, 'two');

        release.complete();
        expect(await first, isA<OptimisticLockingFailureException>());
        expect((await app.items.findAll()).single.name, 'two');
      }),
    );
  });

  group('the end of a transaction', () {
    test(
      'a repository call forgotten inside it fails when it runs later',
      () => withApp((app) async {
        final release = Completer<void>();
        final later = await app.warehouse.forgetsASave(release.future);
        release.complete();
        expect(await later.future, isA<IllegalTransactionStateException>());
        expect(await app.items.count(), 0);
      }),
    );
  });

  group('a data source of its own', () {
    test(
      'the manager is a bean of that name over the same store',
      () => withApp((app) async {
        final manager = app.context.getBean<PlatformTransactionManager>(
          qualifier: 'archive',
        );
        expect(manager, isA<InMemoryTransactionManager>());
        expect(
          (manager as InMemoryTransactionManager).store,
          same(app.dataSources.storeFor('archive')),
        );
        expect(manager.store.name, 'memory:archive');
        // The default manager is the memory store's.
        final main = app.context.getBean<PlatformTransactionManager>();
        expect((main as InMemoryTransactionManager).store, same(app.store));
        expect(
          app.context.getBean<TransactionTemplate>().manager,
          same(main),
        );
      }),
    );

    test(
      '@Transactional(transactionManager: x) commits and rolls back',
      () => withApp((app) async {
        await app.warehouse.archiveTitles(['a', 'b'], fail: false);
        expect(await app.archive.count(), 2);
        await expectLater(
          app.warehouse.archiveTitles(['c', 'd'], fail: true),
          throwsA(isA<Oops>()),
        );
        expect(await app.archive.count(), 2);
      }),
    );

    test(
      'the stores are independent: the default transaction does not '
      'cover the archive',
      () => withApp((app) async {
        await expectLater(
          app.warehouse.addItemAndArchive('x', fail: true),
          throwsA(isA<Oops>()),
        );
        expect(await app.itemNames(), isEmpty);
        // The archive repository ran its own transaction on its own store.
        expect(await app.archive.count(), 1);
      }),
    );
  });
}
