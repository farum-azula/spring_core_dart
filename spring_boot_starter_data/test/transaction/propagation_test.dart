// The propagation matrix: each of the seven propagations, called with and
// without an outer transaction, failing or not, the outer committing or
// rolling back. The expectations are Spring's.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/recording_transaction_manager.dart';

class _Boom implements Exception {}

// What one scenario shows.
class _Outcome {
  final events = <String>[];
  Object? outerError;
  Object? innerError;
  int? outerIdBefore;
  int? innerId;
  int? outerIdAfter;
}

Future<_Outcome> _run(
  Propagation propagation, {
  required bool outer,
  required bool innerFails,
  required bool outerFails,
}) async {
  final manager = RecordingTransactionManager();
  final out = _Outcome();
  final inner = TransactionTemplate(
    manager,
    TransactionDefinition(propagation: propagation),
  );
  Future<void> innerBlock() async {
    try {
      await inner.execute((_) {
        out.innerId = manager.currentId;
        if (innerFails) {
          throw _Boom();
        }
      });
    } on Object catch (error) {
      out.innerError = error;
    }
  }

  try {
    if (outer) {
      await TransactionTemplate(manager).execute((_) async {
        out.outerIdBefore = manager.currentId;
        await innerBlock();
        out.outerIdAfter = manager.currentId;
        if (outerFails) {
          throw StateError('outer');
        }
      });
    } else {
      await innerBlock();
    }
  } on Object catch (error) {
    out.outerError = error;
  }
  out.events.addAll(manager.calls);
  return out;
}

void main() {
  group('without an outer transaction', () {
    for (final failing in [false, true]) {
      final how = failing ? 'fails' : 'succeeds';
      for (final propagation in [
        Propagation.required,
        Propagation.requiresNew,
        Propagation.nested,
      ]) {
        test('${propagation.name} $how: begins its own and ends it', () async {
          final out = await _run(
            propagation,
            outer: false,
            innerFails: failing,
            outerFails: false,
          );
          expect(out.innerId, 1);
          expect(out.events, [
            'begin 1',
            if (failing) 'rollback 1' else 'commit 1',
          ]);
          expect(out.innerError, failing ? isA<_Boom>() : isNull);
        });
      }
      for (final propagation in [
        Propagation.supports,
        Propagation.notSupported,
        Propagation.never,
      ]) {
        test('${propagation.name} $how: runs without a transaction', () async {
          final out = await _run(
            propagation,
            outer: false,
            innerFails: failing,
            outerFails: false,
          );
          expect(out.innerId, isNull);
          expect(out.events, isEmpty);
          expect(out.innerError, failing ? isA<_Boom>() : isNull);
        });
      }
    }

    test(
      'mandatory: IllegalTransactionStateException, nothing began',
      () async {
        final out = await _run(
          Propagation.mandatory,
          outer: false,
          innerFails: false,
          outerFails: false,
        );
        expect(out.innerError, isA<IllegalTransactionStateException>());
        expect(out.innerId, isNull);
        expect(out.events, isEmpty);
      },
    );
  });

  group('within an outer transaction', () {
    // The expectation per propagation: the id the inner runs in, and the
    // events for [innerFails] and [outerFails].
    for (final propagation in Propagation.values) {
      for (final innerFails in [false, true]) {
        for (final outerFails in [false, true]) {
          final title =
              '${propagation.name}, inner ${innerFails ? 'throws' : 'ok'}, '
              'outer ${outerFails ? 'rolls back' : 'commits'}';
          test(title, () async {
            final out = await _run(
              propagation,
              outer: true,
              innerFails: innerFails,
              outerFails: outerFails,
            );
            expect(out.outerIdBefore, 1);
            // The outer sees its own transaction again after the inner.
            expect(out.outerIdAfter, 1);

            final outerEnd = outerFails ? 'rollback 1' : 'commit 1';
            switch (propagation) {
              case Propagation.required:
              case Propagation.supports:
              case Propagation.mandatory:
                expect(out.innerId, 1);
                if (innerFails && !outerFails) {
                  // The inner marked the shared transaction; the outer
                  // learns that its commit did not happen.
                  expect(out.events, [
                    'begin 1',
                    'rollbackOnly 1',
                    'rollback 1',
                  ]);
                  expect(out.outerError, isA<UnexpectedRollbackException>());
                } else if (innerFails) {
                  expect(out.events, [
                    'begin 1',
                    'rollbackOnly 1',
                    'rollback 1',
                  ]);
                  expect(out.outerError, isA<StateError>());
                } else {
                  expect(out.events, ['begin 1', outerEnd]);
                }
              case Propagation.requiresNew:
                expect(out.innerId, 2);
                expect(out.events, [
                  'begin 1',
                  'begin 2',
                  if (innerFails) 'rollback 2' else 'commit 2',
                  outerEnd,
                ]);
                expect(out.outerError, outerFails ? isA<StateError>() : isNull);
              case Propagation.notSupported:
                expect(out.innerId, isNull);
                expect(out.events, ['begin 1', outerEnd]);
              case Propagation.never:
                expect(out.innerId, isNull);
                expect(out.innerError, isA<IllegalTransactionStateException>());
                expect(out.events, ['begin 1', outerEnd]);
                expect(out.outerError, outerFails ? isA<StateError>() : isNull);
              case Propagation.nested:
                expect(out.innerId, 1);
                expect(out.events, [
                  'begin 1',
                  'savepoint 1 #1',
                  if (innerFails) 'rollbackTo 1 #1',
                  'release 1 #1',
                  outerEnd,
                ]);
                expect(out.outerError, outerFails ? isA<StateError>() : isNull);
            }
            if (propagation != Propagation.never && innerFails) {
              expect(out.innerError, isA<_Boom>());
            }
          });
        }
      }
    }
  });

  group('details', () {
    test('a nested failure rolls back to its savepoint only', () async {
      final manager = RecordingTransactionManager();
      final nested = TransactionTemplate(
        manager,
        const TransactionDefinition(propagation: Propagation.nested),
      );
      await TransactionTemplate(manager).execute((status) async {
        await nested.execute((_) {});
        await expectLater(
          nested.execute((_) => throw _Boom()),
          throwsA(isA<_Boom>()),
        );
        await nested.execute((_) {});
        // The outer transaction is not marked.
        expect(status.isRollbackOnly, isFalse);
      });
      expect(manager.calls, [
        'begin 1',
        'savepoint 1 #1',
        'release 1 #1',
        'savepoint 1 #2',
        'rollbackTo 1 #2',
        'release 1 #2',
        'savepoint 1 #3',
        'release 1 #3',
        'commit 1',
      ]);
    });

    test('nested without savepoints within a transaction is refused', () async {
      final manager = RecordingTransactionManager(savepoints: false);
      final nested = TransactionTemplate(
        manager,
        const TransactionDefinition(propagation: Propagation.nested),
      );
      await expectLater(
        TransactionTemplate(manager).execute((_) => nested.execute((_) {})),
        throwsA(isA<NestedTransactionNotSupportedException>()),
      );
      // The refusal is an error of the outer block: it rolled back.
      expect(manager.calls, ['begin 1', 'rollback 1']);
    });

    test(
      'nested without savepoints and without a transaction begins one',
      () async {
        final manager = RecordingTransactionManager(savepoints: false);
        await TransactionTemplate(
          manager,
          const TransactionDefinition(propagation: Propagation.nested),
        ).execute((_) {});
        expect(manager.calls, ['begin 1', 'commit 1']);
      },
    );

    test('requiresNew commits although the outer rolls back', () async {
      final manager = RecordingTransactionManager();
      final isolated = TransactionTemplate(
        manager,
        const TransactionDefinition(propagation: Propagation.requiresNew),
      );
      await expectLater(
        TransactionTemplate(manager).execute((_) async {
          await isolated.execute((_) {});
          throw _Boom();
        }),
        throwsA(isA<_Boom>()),
      );
      expect(manager.calls, ['begin 1', 'begin 2', 'commit 2', 'rollback 1']);
    });

    test(
      "requiresNew sets aside only its own manager's transaction",
      () async {
        final manager = RecordingTransactionManager();
        final other = RecordingTransactionManager();
        final isolated = TransactionTemplate(
          manager,
          const TransactionDefinition(propagation: Propagation.requiresNew),
        );
        await TransactionTemplate(manager).execute((_) async {
          await TransactionTemplate(other).execute((_) async {
            final outerOwn = TransactionSynchronizationManager.getResource(
              manager,
            );
            final otherOwn = TransactionSynchronizationManager.getResource(
              other,
            );
            await isolated.execute((_) {
              // The manager's own outer transaction is set aside...
              expect(
                TransactionSynchronizationManager.getResource(manager),
                isNot(same(outerOwn)),
              );
              expect(manager.currentId, 2);
              // ...another store's transaction is still the current one for
              // that store, as Spring suspends only the manager's resource.
              expect(
                TransactionSynchronizationManager.getResource(other),
                same(otherOwn),
              );
              expect(
                TransactionSynchronizationManager.currentTransactionFor(other),
                isNotNull,
              );
            });
            expect(
              TransactionSynchronizationManager.getResource(manager),
              same(outerOwn),
            );
            expect(manager.currentId, 1);
          });
        });
        expect(manager.calls, ['begin 1', 'begin 2', 'commit 2', 'commit 1']);
      },
    );

    test("notSupported hides only its manager's transaction", () async {
      final manager = RecordingTransactionManager();
      final other = RecordingTransactionManager();
      await TransactionTemplate(manager).execute((_) async {
        await TransactionTemplate(other).execute((_) async {
          await TransactionTemplate(
            manager,
            const TransactionDefinition(
              propagation: Propagation.notSupported,
            ),
          ).execute((_) {
            expect(
              TransactionSynchronizationManager.currentTransactionFor(manager),
              isNull,
            );
            expect(
              TransactionSynchronizationManager.currentTransactionFor(other),
              isNotNull,
            );
          });
        });
      });
    });

    test('notSupported sets the transaction aside and resumes it', () async {
      final manager = RecordingTransactionManager();
      final aside = TransactionTemplate(
        manager,
        const TransactionDefinition(propagation: Propagation.notSupported),
      );
      await TransactionTemplate(
        manager,
        const TransactionDefinition(name: 'outer'),
      ).execute((_) async {
        await aside.execute((_) {
          expect(
            TransactionSynchronizationManager.isActualTransactionActive,
            isFalse,
          );
          expect(manager.currentId, isNull);
        });
        expect(
          TransactionSynchronizationManager.currentTransactionName,
          'outer',
        );
        expect(manager.currentId, 1);
      });
    });

    test('a failure in notSupported does not mark the outer', () async {
      final manager = RecordingTransactionManager();
      final aside = TransactionTemplate(
        manager,
        const TransactionDefinition(propagation: Propagation.notSupported),
      );
      await TransactionTemplate(manager).execute((_) async {
        await expectLater(
          aside.execute<void>((_) => throw _Boom()),
          throwsA(isA<_Boom>()),
        );
      });
      expect(manager.calls, ['begin 1', 'commit 1']);
    });

    test('settings apply to a new transaction only', () async {
      final manager = RecordingTransactionManager();
      await TransactionTemplate(
        manager,
        const TransactionDefinition(
          readOnly: true,
          isolation: Isolation.serializable,
          name: 'outer',
        ),
      ).execute((_) async {
        await TransactionTemplate(
          manager,
          const TransactionDefinition(name: 'inner'),
        ).execute((_) {
          // Joined: the outer transaction's settings.
          expect(
            TransactionSynchronizationManager.isCurrentTransactionReadOnly,
            isTrue,
          );
          expect(
            TransactionSynchronizationManager.currentTransactionIsolationLevel,
            Isolation.serializable,
          );
          expect(
            TransactionSynchronizationManager.currentTransactionName,
            'outer',
          );
        });
        await TransactionTemplate(
          manager,
          const TransactionDefinition(
            propagation: Propagation.requiresNew,
            name: 'fresh',
          ),
        ).execute((_) {
          expect(
            TransactionSynchronizationManager.isCurrentTransactionReadOnly,
            isFalse,
          );
          expect(
            TransactionSynchronizationManager.currentTransactionIsolationLevel,
            Isolation.defaultLevel,
          );
          expect(
            TransactionSynchronizationManager.currentTransactionName,
            'fresh',
          );
        });
      });
    });

    test('a zero timeout is refused', () async {
      final manager = RecordingTransactionManager();
      await expectLater(
        TransactionTemplate(
          manager,
          const TransactionDefinition(timeout: Duration.zero),
        ).execute((_) {}),
        throwsA(isA<InvalidTimeoutException>()),
      );
      expect(manager.calls, isEmpty);
    });
  });
}
