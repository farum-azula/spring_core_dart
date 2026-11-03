// @Transactional end to end: the generated proxies of
// app/transaction_app.dart, started with the starter's auto-configuration.
import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/transaction/app/transaction_app.spring.dart';
import 'app/transaction_app.dart';
import 'support/recording_transaction_manager.dart';

Future<void> withApp(
  Future<void> Function(
    Shop shop,
    Ledger ledger,
    RecordingTransactionManager main,
    RecordingTransactionManager archive,
  )
  body,
) => const ApplicationContextRunner()
    .withUserConfiguration($application)
    .withAutoConfiguration(springBootStarterDataAutoConfiguration)
    .runAsync((context) async {
      if (context.startupFailure case final failure?) {
        throw StateError('The application did not start: $failure');
      }
      await body(
        context.getBean<Shop>(),
        context.getBean<Ledger>(),
        context.getBean<RecordingTransactionManager>(),
        context.getBean<RecordingTransactionManager>(qualifier: 'archive'),
      );
    });

void main() {
  test('the beans are proxied, the starter adds its beans', () async {
    await const ApplicationContextRunner()
        .withUserConfiguration($application)
        .withAutoConfiguration(springBootStarterDataAutoConfiguration)
        .runAsync((context) async {
          expect(context.startupFailure, isNull);
          expect(context.getBean<Shop>(), isA<Advised>());
          expect(context.getBean<Ledger>(), isA<Advised>());
          expect(context, hasSingleBean<TransactionInterceptor>());
          expect(context, hasSingleBean<TransactionValidator>());
          expect(context, hasBeanNamed('transactionAdvisor'));
          // The primary manager is the single candidate.
          expect(context, hasSingleBean<TransactionTemplate>());
          final advisor = context.getBean<DefaultPointcutAdvisor>();
          expect(advisor.order, Ordered.lowestPrecedence);
        });
  });

  test('a method runs in a transaction that commits', () async {
    await withApp((shop, _, main, archive) async {
      expect(await shop.transactionId(), 1);
      expect(main.calls, ['begin 1', 'commit 1']);
      expect(archive.calls, isEmpty);
    });
  });

  test('a method without the annotation runs without one', () async {
    await withApp((shop, _, main, _) async {
      expect(await shop.plain(), isNull);
      expect(main.calls, isEmpty);
    });
  });

  test('an error rolls back and is rethrown', () async {
    await withApp((shop, _, main, _) async {
      await expectLater(shop.fail(StateError('x')), throwsStateError);
      await expectLater(shop.fail('a string'), throwsA('a string'));
      await expectLater(
        shop.failLater(OutOfStock()),
        throwsA(isA<OutOfStock>()),
      );
      expect(main.calls, [
        'begin 1',
        'rollback 1',
        'begin 2',
        'rollback 2',
        'begin 3',
        'rollback 3',
      ]);
    });
  });

  group('rollback rules', () {
    test('noRollbackFor commits, and the error is thrown', () async {
      await withApp((shop, _, main, _) async {
        await expectLater(
          shop.failOutOfStock(OutOfStock()),
          throwsA(isA<OutOfStock>()),
        );
        expect(main.calls, ['begin 1', 'commit 1']);
      });
    });

    test('noRollbackFor matches subtypes (generated type tests)', () async {
      await withApp((shop, _, main, _) async {
        await expectLater(
          shop.failOutOfStock(SoldOut()),
          throwsA(isA<SoldOut>()),
        );
        expect(main.calls, ['begin 1', 'commit 1']);
      });
    });

    test('other errors still roll back', () async {
      await withApp((shop, _, main, _) async {
        await expectLater(
          shop.failOutOfStock(StateError('other')),
          throwsStateError,
        );
        expect(main.calls, ['begin 1', 'rollback 1']);
      });
    });

    test('rollbackFor wins over noRollbackFor, with subtypes', () async {
      await withApp((shop, _, main, _) async {
        await expectLater(
          shop.failWithRules(Counterfeit()),
          throwsA(isA<Counterfeit>()),
        );
        await expectLater(
          shop.failWithRules(SoldOut()),
          throwsA(isA<SoldOut>()),
        );
        expect(main.calls, [
          'begin 1',
          'rollback 1',
          'begin 2',
          'commit 2',
        ]);
      });
    });
  });

  group('the closest rule decides (generated type depths)', () {
    test(
      'noRollbackFor of a subtype beats rollbackFor of its supertype',
      () async {
        await withApp((shop, _, main, _) async {
          await expectLater(
            shop.failClosest(Counterfeit()),
            throwsA(isA<Counterfeit>()),
          );
          await expectLater(
            shop.failClosest(SoldOut()),
            throwsA(isA<SoldOut>()),
          );
          await expectLater(
            shop.failClosest(StateError('other')),
            throwsStateError,
          );
          expect(main.calls, [
            'begin 1',
            'commit 1',
            'begin 2',
            'rollback 2',
            'begin 3',
            'rollback 3',
          ]);
        });
      },
    );
  });

  group('transaction manager', () {
    test('by qualifier', () async {
      await withApp((shop, _, main, archive) async {
        expect(await shop.archived(), 1);
        expect(archive.calls, ['begin 1', 'commit 1']);
        expect(main.calls, isEmpty);
      });
    });

    test('by bean name', () async {
      await withApp((shop, _, main, archive) async {
        expect(await shop.archivedByName(), 1);
        expect(archive.calls, ['begin 1', 'commit 1']);
        expect(main.calls, isEmpty);
      });
    });
  });

  group('propagation and settings', () {
    test('a method called from a transactional bean joins it', () async {
      await withApp((shop, ledger, main, _) async {
        // [shop's tx, ledger.a joins, ledger.fresh new, shop's again]
        expect(await shop.callsLedger(ledger), [1, 1, 2, 1]);
        expect(main.calls, ['begin 1', 'begin 2', 'commit 2', 'commit 1']);
      });
    });

    test('the method annotation wins over the class annotation', () async {
      await withApp((_, ledger, main, _) async {
        expect(await ledger.supports(), isNull);
        expect(await ledger.fresh(), 1);
        expect(main.calls, ['begin 1', 'commit 1']);
      });
    });

    test('class-level annotation covers every public method', () async {
      await withApp((_, ledger, main, _) async {
        expect(await ledger.a(), 1);
        expect(await ledger.b(), 2);
        expect(main.calls, ['begin 1', 'commit 1', 'begin 2', 'commit 2']);
      });
    });

    test('mandatory fails without a transaction', () async {
      await withApp((shop, _, main, _) async {
        await expectLater(
          shop.mandatory(),
          throwsA(isA<IllegalTransactionStateException>()),
        );
        expect(main.calls, isEmpty);
      });
    });

    test('the definition carries the settings and the name', () async {
      await withApp((shop, _, _, _) async {
        expect(
          await shop.settings(),
          'Shop.settings readOnly=true serializable 5',
        );
      });
    });

    test('a call through this is not proxied', () async {
      await withApp((shop, _, main, _) async {
        // callsItself has no annotation, and calls transactionId() on this.
        expect(await shop.callsItself(), isNull);
        expect(main.calls, isEmpty);
      });
    });

    test('forgotten work using the transaction after it ended fails', () async {
      await withApp((shop, _, main, _) async {
        final later = await shop.forgets();
        expect(await later.future, isA<IllegalTransactionStateException>());
        expect(main.calls, ['begin 1', 'commit 1']);
      });
    });

    test('concurrent calls run in separate transactions', () async {
      await withApp((shop, _, main, _) async {
        final ids = await Future.wait([
          shop.transactionId(),
          shop.transactionId(),
        ]);
        expect(ids.toSet(), {1, 2});
      });
    });
  });

  test('the TransactionTemplate bean uses the primary manager', () async {
    await const ApplicationContextRunner()
        .withUserConfiguration($application)
        .withAutoConfiguration(springBootStarterDataAutoConfiguration)
        .runAsync((context) async {
          final template = context.getBean<TransactionTemplate>();
          final main = context.getBean<RecordingTransactionManager>();
          expect(template.manager, same(main));
          await template.execute((_) {});
          expect(main.calls, ['begin 1', 'commit 1']);
        });
  });
}
