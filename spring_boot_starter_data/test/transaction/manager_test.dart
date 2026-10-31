// Any object may be thrown in Dart; the tests throw strings and plain
// objects on purpose.
// ignore_for_file: only_throw_errors
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/recording_transaction_manager.dart';

class _Boom implements Exception {}

void main() {
  late RecordingTransactionManager manager;
  late TransactionTemplate template;

  setUp(() {
    manager = RecordingTransactionManager();
    template = TransactionTemplate(manager);
  });

  group('synchronizations', () {
    test('commit: beforeCommit, beforeCompletion, commit, afterCommit, '
        'afterCompletion(committed)', () async {
      final log = <String>[];
      await template.execute((_) {
        TransactionSynchronizationManager.registerSynchronization(
          RecordingSynchronization(log, 'a'),
        );
        TransactionSynchronizationManager.registerSynchronization(
          RecordingSynchronization(log, 'b'),
        );
        log.add('body');
      });
      expect(log, [
        'body',
        'a beforeCommit readOnly=false',
        'b beforeCommit readOnly=false',
        'a beforeCompletion',
        'b beforeCompletion',
        'a afterCommit',
        'b afterCommit',
        'a afterCompletion committed',
        'b afterCompletion committed',
      ]);
    });

    test('rollback: beforeCompletion, afterCompletion(rolledBack)', () async {
      final log = <String>[];
      await expectLater(
        template.execute((_) {
          TransactionSynchronizationManager.registerSynchronization(
            RecordingSynchronization(log),
          );
          throw _Boom();
        }),
        throwsA(isA<_Boom>()),
      );
      expect(log, ['s beforeCompletion', 's afterCompletion rolledBack']);
    });

    test('readOnly reaches beforeCommit', () async {
      final log = <String>[];
      await TransactionTemplate(
        manager,
        const TransactionDefinition(readOnly: true),
      ).execute((_) {
        TransactionSynchronizationManager.registerSynchronization(
          RecordingSynchronization(log),
        );
      });
      expect(log.first, 's beforeCommit readOnly=true');
    });

    test('order with the store: before, doCommit, after', () async {
      final order = <String>[];
      await template.execute((_) {
        TransactionSynchronizationManager.registerSynchronization(
          _Hooked(
            before: () => order.add('beforeCommit (events ${manager.calls})'),
            after: () => order.add('afterCommit (events ${manager.calls})'),
          ),
        );
      });
      expect(order, [
        'beforeCommit (events [begin 1])',
        'afterCommit (events [begin 1, commit 1])',
      ]);
    });

    test('a failing beforeCommit rolls back and is thrown', () async {
      final log = <String>[];
      await expectLater(
        template.execute((_) {
          TransactionSynchronizationManager.registerSynchronization(
            _Hooked(before: () => throw _Boom()),
          );
          TransactionSynchronizationManager.registerSynchronization(
            RecordingSynchronization(log),
          );
        }),
        throwsA(isA<_Boom>()),
      );
      expect(manager.calls, ['begin 1', 'rollback 1']);
      expect(log, ['s beforeCompletion', 's afterCompletion rolledBack']);
    });

    test('a failing afterCompletion is logged, not thrown', () async {
      final records = <SpringLogRecord>[];
      final stop = SpringLog.listen(records.add);
      addTearDown(stop);
      final log = <String>[];
      await template.execute((_) {
        TransactionSynchronizationManager.registerSynchronization(
          _Hooked(afterDone: () => throw _Boom()),
        );
        TransactionSynchronizationManager.registerSynchronization(
          RecordingSynchronization(log),
        );
      });
      expect(log.last, 's afterCompletion committed');
      expect(
        records.where((r) => r.error is _Boom).map((r) => r.loggerName),
        ['spring.transaction.RecordingTransactionManager'],
      );
    });

    test('a failing commit gives afterCompletion(unknown)', () async {
      final log = <String>[];
      manager.failCommit = _Boom();
      await expectLater(
        template.execute((_) {
          TransactionSynchronizationManager.registerSynchronization(
            RecordingSynchronization(log),
          );
        }),
        throwsA(
          isA<TransactionSystemException>().having(
            (e) => e.cause,
            'cause',
            isA<_Boom>(),
          ),
        ),
      );
      expect(log.last, 's afterCompletion unknown');
      expect(manager.events.last, 'cleanup 1');
    });

    test('a transaction exception of the store is thrown as it is', () async {
      manager.failCommit = CannotCreateTransactionException('store down');
      await expectLater(
        template.execute((_) {}),
        throwsA(isA<CannotCreateTransactionException>()),
      );
    });

    test('a joined block has no synchronizations of its own', () async {
      final log = <String>[];
      await template.execute((_) async {
        TransactionSynchronizationManager.registerSynchronization(
          RecordingSynchronization(log),
        );
        await template.execute((_) {});
        log.add('inner done');
      });
      expect(log.indexOf('inner done'), 0);
      expect(log.last, 's afterCompletion committed');
    });

    test('registering without a transaction fails', () async {
      await TransactionTemplate(
        manager,
        const TransactionDefinition(propagation: Propagation.supports),
      ).execute((_) {
        expect(
          () => TransactionSynchronizationManager.registerSynchronization(
            RecordingSynchronization([]),
          ),
          throwsA(isA<IllegalTransactionStateException>()),
        );
      });
    });
  });

  group('status', () {
    test('what a block reports', () async {
      await template.execute((status) async {
        expect(status.isNewTransaction, isTrue);
        expect(status.hasTransaction, isTrue);
        expect(status.hasSavepoint, isFalse);
        expect(status.isCompleted, isFalse);
        await template.execute((inner) {
          expect(inner.isNewTransaction, isFalse);
          expect(inner.hasTransaction, isTrue);
        });
        await TransactionTemplate(
          manager,
          const TransactionDefinition(propagation: Propagation.nested),
        ).execute((nested) {
          expect(nested.hasSavepoint, isTrue);
          expect(nested.isNewTransaction, isFalse);
        });
        await TransactionTemplate(
          manager,
          const TransactionDefinition(propagation: Propagation.notSupported),
        ).execute((none) {
          expect(none.hasTransaction, isFalse);
        });
      });
    });

    test('a local rollback-only rolls back without an exception', () async {
      await template.execute((status) {
        status.setRollbackOnly();
        expect(status.isRollbackOnly, isTrue);
      });
      expect(manager.calls, ['begin 1', 'rollback 1']);
    });

    test(
      'a local rollback-only of a joined block marks the transaction',
      () async {
        await expectLater(
          template.execute((_) async {
            await template.execute((status) => status.setRollbackOnly());
          }),
          throwsA(isA<UnexpectedRollbackException>()),
        );
        expect(manager.calls, ['begin 1', 'rollbackOnly 1', 'rollback 1']);
      },
    );

    test(
      'a participant marking the transaction shows in isRollbackOnly',
      () async {
        await template
            .execute((status) async {
              await template.execute((inner) => inner.setRollbackOnly());
              expect(status.isRollbackOnly, isTrue);
              // The outer says it is done with it: no commit may follow.
            })
            .onError<UnexpectedRollbackException>((_, _) {});
      },
    );

    test(
      'a local rollback-only of a nested block rolls back to the savepoint',
      () async {
        await template.execute((_) async {
          await TransactionTemplate(
            manager,
            const TransactionDefinition(propagation: Propagation.nested),
          ).execute((status) => status.setRollbackOnly());
        });
        expect(manager.calls, [
          'begin 1',
          'savepoint 1 #1',
          'rollbackTo 1 #1',
          'release 1 #1',
          'commit 1',
        ]);
      },
    );

    test('commit and rollback of a completed status fail', () async {
      final status = await TransactionSynchronizationManager.runInScope(
        () => manager.getTransaction(),
      );
      // Not in the scope any more: the status of a block ended by hand.
      await TransactionSynchronizationManager.runInScope(() async {
        final own = await manager.getTransaction();
        await manager.commit(own);
        expect(own.isCompleted, isTrue);
        await expectLater(
          manager.commit(own),
          throwsA(isA<IllegalTransactionStateException>()),
        );
        await expectLater(
          manager.rollback(own),
          throwsA(isA<IllegalTransactionStateException>()),
        );
      });
      expect(status.isNewTransaction, isTrue);
    });

    test('a status of another manager is refused', () async {
      final other = RecordingTransactionManager();
      await TransactionSynchronizationManager.runInScope(() async {
        final status = await other.getTransaction();
        await expectLater(
          manager.commit(status),
          throwsA(isA<ArgumentError>()),
        );
        await other.rollback(status);
      });
    });

    test('savepoints through the status', () async {
      await template.execute((status) async {
        final savepoint = await status.createSavepoint();
        await status.rollbackToSavepoint(savepoint);
        await status.releaseSavepoint(savepoint);
      });
      expect(manager.calls, [
        'begin 1',
        'savepoint 1 #1',
        'rollbackTo 1 #1',
        'release 1 #1',
        'commit 1',
      ]);
    });

    test('a savepoint without a transaction fails', () async {
      await TransactionTemplate(
        manager,
        const TransactionDefinition(propagation: Propagation.supports),
      ).execute((status) async {
        await expectLater(
          status.createSavepoint(),
          throwsA(isA<IllegalTransactionStateException>()),
        );
      });
    });
  });

  group('failures', () {
    test('a failing rollback keeps the application exception', () async {
      manager.failRollback = StateError('store lost');
      Object? thrown;
      try {
        await template.execute((_) => throw _Boom());
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isA<TransactionSystemException>());
      final failure = thrown as TransactionSystemException;
      expect(failure.applicationException, isA<_Boom>());
      expect(
        failure.cause,
        isA<TransactionSystemException>().having(
          (e) => e.cause,
          'cause',
          isA<StateError>(),
        ),
      );
      // The transaction is cleaned up all the same.
      expect(manager.events.last, 'cleanup 1');
      expect(manager.current, isNull);
    });

    test(
      'rollback failure in the store is a TransactionSystemException',
      () async {
        manager.failRollback = StateError('x');
        await TransactionSynchronizationManager.runInScope(() async {
          final status = await manager.getTransaction();
          await expectLater(
            manager.rollback(status),
            throwsA(isA<TransactionSystemException>()),
          );
          expect(status.isCompleted, isTrue);
        });
      },
    );

    test('any thrown object rolls back and is rethrown', () async {
      await expectLater(template.execute((_) => throw 'text'), throwsA('text'));
      await expectLater(
        template.execute((_) => throw ArgumentError('e')),
        throwsA(isA<ArgumentError>()),
      );
      expect(manager.calls, ['begin 1', 'rollback 1', 'begin 2', 'rollback 2']);
    });

    test('the stack trace of the application error is kept', () async {
      StackTrace? thrownAt;
      try {
        await template.execute((_) async {
          await Future<void>.delayed(Duration.zero);
          throw _Boom();
        });
      } on _Boom catch (_, stackTrace) {
        thrownAt = stackTrace;
      }
      expect('$thrownAt', contains('manager_test.dart'));
    });

    test('a failing doBegin leaves nothing behind', () async {
      final failing = _FailingBegin();
      await expectLater(
        TransactionTemplate(failing).execute((_) {}),
        throwsA(isA<CannotCreateTransactionException>()),
      );
      expect(failing.events, isEmpty);
    });

    test('executeWithoutResult', () async {
      var ran = false;
      await template.executeWithoutResult((_) => ran = true);
      expect(ran, isTrue);
      expect(manager.calls, ['begin 1', 'commit 1']);
    });

    test('the result of the action is returned after the commit', () async {
      final result = await template.execute((_) async {
        await Future<void>.delayed(Duration.zero);
        return 42;
      });
      expect(result, 42);
      expect(manager.calls, ['begin 1', 'commit 1']);
    });
  });

  group('logging', () {
    test('Spring wording at debug, in spring.transaction.<Class>', () async {
      SpringLog.setLevel('spring.transaction', SpringLogLevel.debug);
      addTearDown(SpringLog.resetLevels);
      final records = <SpringLogRecord>[];
      final stop = SpringLog.listen(records.add);
      addTearDown(stop);
      final nested = TransactionTemplate(
        manager,
        const TransactionDefinition(
          propagation: Propagation.nested,
          name: 'n',
        ),
      );
      final isolated = TransactionTemplate(
        manager,
        const TransactionDefinition(
          propagation: Propagation.requiresNew,
          name: 'r',
        ),
      );
      await TransactionTemplate(
            manager,
            const TransactionDefinition(name: 'o'),
          )
          .execute((_) async {
            await template.execute((_) {});
            await nested.execute((_) {});
            await isolated.execute((_) {});
            await template
                .execute((status) => status.setRollbackOnly())
                .onError<UnexpectedRollbackException>((_, _) {});
          })
          .onError<UnexpectedRollbackException>((_, _) {});
      final messages = [
        for (final r in records)
          if (r.loggerName == 'spring.transaction.RecordingTransactionManager')
            r.message,
      ];
      expect(messages, containsAllInOrder(_expectedMessages));
    });
  });
}

final class _Hooked extends TransactionSynchronization {
  _Hooked({this.before, this.after, this.afterDone});

  final void Function()? before;
  final void Function()? after;
  final void Function()? afterDone;

  @override
  void beforeCommit({required bool readOnly}) => before?.call();

  @override
  void afterCommit() => after?.call();

  @override
  void afterCompletion(TransactionCompletion status) => afterDone?.call();
}

final class _FailingBegin extends RecordingTransactionManager {
  @override
  Future<void> doBegin(Object transaction, TransactionDefinition definition) =>
      throw CannotCreateTransactionException('no connection');
}

final List<String> _expectedMessages = [
  'Creating new transaction with name [o]: PROPAGATION_required',
  'Participating in existing transaction',
  'Creating nested transaction with name [n]',
  'Suspending current transaction, creating new transaction with name [r]',
  'Initiating transaction commit',
  'Resuming suspended transaction after completion of inner transaction',
  'Participating in existing transaction',
  'Setting transaction rollback-only',
  'Transactional code has requested rollback',
  [
    'Participating transaction failed - marking existing transaction as',
    'rollback-only',
  ].join(' '),
  'Initiating transaction rollback',
];
