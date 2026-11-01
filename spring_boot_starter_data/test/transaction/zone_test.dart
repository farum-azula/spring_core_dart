// What is particular to Dart: one thread, many interleaved tasks. The
// transaction lives in a zone: it follows await, microtasks and timers, is
// never seen by a concurrent block, and ended work cannot use it.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/recording_transaction_manager.dart';

void main() {
  late RecordingTransactionManager manager;
  late TransactionTemplate template;

  setUp(() {
    manager = RecordingTransactionManager();
    template = TransactionTemplate(manager);
  });

  test('the transaction follows awaits, microtasks and timers', () async {
    final seen = <String, int?>{};
    await template.execute((_) async {
      seen['start'] = manager.currentId;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      seen['after timer'] = manager.currentId;
      await Future<void>.value();
      seen['after future'] = manager.currentId;
      scheduleMicrotask(() => seen['microtask'] = manager.currentId);
      await Future<void>.microtask(() {});
      final completer = Completer<void>();
      Timer(const Duration(milliseconds: 1), () {
        seen['timer'] = manager.currentId;
        completer.complete();
      });
      await completer.future;
      await for (final _ in Stream<int>.fromIterable([1, 2])) {
        seen['stream'] = manager.currentId;
      }
      seen['then'] = await Future<void>.delayed(
        Duration.zero,
      ).then((_) => manager.currentId);
    });
    expect(seen.values.toSet(), {1});
    expect(seen.keys, hasLength(7));
    expect(manager.calls, ['begin 1', 'commit 1']);
    // Outside the block there is no transaction.
    expect(TransactionSynchronizationManager.hasScope, isFalse);
  });

  test('two concurrent blocks never see each other', () async {
    final gate1 = Completer<void>();
    final gate2 = Completer<void>();
    final seen = <String>[];

    Future<void> block(
      String name,
      Completer<void> mine,
      Completer<void> other,
    ) {
      return template.execute((_) async {
        final id = manager.currentId;
        seen.add('$name starts in $id');
        // Hand the turn to the other block, then wait for it to be at
        // the same point.
        other.complete();
        await mine.future;
        await Future<void>.delayed(Duration.zero);
        seen.add('$name still in ${manager.currentId} (was $id)');
        expect(manager.currentId, id);
      });
    }

    await Future.wait([block('a', gate1, gate2), block('b', gate2, gate1)]);
    expect(seen.where((s) => s.contains('starts')), hasLength(2));
    expect(seen, contains('a starts in 1'));
    expect(seen, contains('b starts in 2'));
    expect(seen, contains('a still in 1 (was 1)'));
    expect(seen, contains('b still in 2 (was 2)'));
    expect(
      manager.calls,
      unorderedEquals([
        'begin 1',
        'begin 2',
        'commit 1',
        'commit 2',
      ]),
    );
  });

  test('concurrent blocks end independently', () async {
    final slow = Completer<void>();
    final order = <String>[];
    final first = template.execute((_) async {
      await slow.future;
      order.add('first done');
      throw StateError('first fails');
    });
    final second = template.execute((_) async {
      order.add('second done');
    });
    await second;
    slow.complete();
    await expectLater(first, throwsStateError);
    expect(order, ['second done', 'first done']);
    expect(manager.calls, ['begin 1', 'begin 2', 'commit 2', 'rollback 1']);
  });

  test('Future.wait inside one transaction shares it', () async {
    final ids = <int?>[];
    await template.execute((_) async {
      Future<void> part() => template.execute((_) async {
        await Future<void>.delayed(Duration.zero);
        ids.add(manager.currentId);
      });
      await Future.wait([part(), part(), part()]);
    });
    expect(ids, [1, 1, 1]);
    expect(manager.calls, ['begin 1', 'commit 1']);
  });

  test('a failing part of Future.wait marks the shared transaction', () async {
    await expectLater(
      template.execute((_) async {
        Future<void> part(bool fail) => template.execute((_) async {
          await Future<void>.delayed(Duration.zero);
          if (fail) {
            throw StateError('part');
          }
        });
        try {
          await Future.wait([part(false), part(true)]);
        } on StateError {
          // Swallowed: the outer wants to commit.
        }
      }),
      throwsA(isA<UnexpectedRollbackException>()),
    );
    expect(manager.calls, ['begin 1', 'rollbackOnly 1', 'rollback 1']);
  });

  test('work started without await and run after the end fails', () async {
    final late = Completer<void>();
    final result = Completer<Object?>();
    await template.execute((_) {
      unawaited(
        late.future.then((_) {
          try {
            result.complete(manager.current);
          } on Object catch (error) {
            result.complete(error);
          }
        }),
      );
    });
    // The transaction has ended; the forgotten work now runs.
    late.complete();
    expect(await result.future, isA<IllegalTransactionStateException>());
  });

  test(
    'the forgotten work fails also after the end of a nested block',
    () async {
      final late = Completer<void>();
      final result = Completer<Object?>();
      await template.execute((_) async {
        await template.execute((_) {
          unawaited(
            late.future.then((_) {
              try {
                result.complete(manager.current);
              } on Object catch (error) {
                result.complete(error);
              }
            }),
          );
        });
        // The outer is still running here.
        expect(manager.currentId, 1);
      });
      late.complete();
      expect(await result.future, isA<IllegalTransactionStateException>());
    },
  );

  test('forgotten work finishing within the block still sees it', () async {
    final done = Completer<int?>();
    await template.execute((_) async {
      unawaited(
        Future<void>.delayed(Duration.zero).then(
          (_) => done.complete(manager.currentId),
        ),
      );
      await done.future;
    });
    expect(await done.future, 1);
  });

  test('getTransaction outside a scope fails clearly', () async {
    await expectLater(
      manager.getTransaction(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('outside a transaction scope'), contains('Template')),
        ),
      ),
    );
    expect(manager.events, isEmpty);
  });

  test('a scope without a begun transaction has none', () async {
    await TransactionSynchronizationManager.runInScope(() {
      expect(TransactionSynchronizationManager.hasScope, isTrue);
      expect(TransactionSynchronizationManager.currentTransaction, isNull);
      expect(manager.currentId, isNull);
    });
  });

  group('timeout', () {
    test('checkDeadline passes before and throws after the timeout', () async {
      await TransactionTemplate(
        manager,
        const TransactionDefinition(timeout: Duration(milliseconds: 30)),
      ).execute((_) async {
        final info = TransactionSynchronizationManager.currentTransaction!;
        expect(info.timeout, const Duration(milliseconds: 30));
        info.checkDeadline();
        expect(info.timeLeft, isNotNull);
        // A real wait, with margin: the clock is the transaction's own.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(info.timeLeft, Duration.zero);
        expect(
          info.checkDeadline,
          throwsA(isA<TransactionTimedOutException>()),
        );
      });
    });

    test('without a timeout there is no deadline', () async {
      await template.execute((_) async {
        final info = TransactionSynchronizationManager.currentTransaction!;
        expect(info.timeLeft, isNull);
        info.checkDeadline();
      });
    });

    test('a joined block keeps the outer timeout', () async {
      await TransactionTemplate(
        manager,
        const TransactionDefinition(timeout: Duration(minutes: 5)),
      ).execute((_) async {
        await TransactionTemplate(
          manager,
          const TransactionDefinition(timeout: Duration(milliseconds: 1)),
        ).execute((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          TransactionSynchronizationManager.currentTransaction!.checkDeadline();
        });
      });
    });
  });
}
