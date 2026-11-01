@Tags(['postgres'])
library;

// The propagation x isolation matrix with races, on PostgreSQL: every outer
// x inner propagation with what commits and what rolls back, the rollback
// rules, read-only transactions, the isolation levels against the anomalies
// (two transactions driven step by step), locks (FOR UPDATE, FOR SHARE,
// NOWAIT, SKIP LOCKED, lock timeout), `@Version`, and timeouts. Every
// scenario gives a normalized outcome (scenarios.dart) that must be the one
// expected (expectations.dart); the differential test compares the same
// outcomes with Spring's. Needs SPRING_TEST_POSTGRES_URL.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../postgres/support.dart';
import 'env.dart';
import 'expectations.dart';
import 'scenarios.dart';

void main() => group('transaction matrix', _tests, skip: postgresSkip);

void _tests() {
  late Env env;
  final done = Completer<void>();
  final scenarios = allScenarios();

  setUpAll(() async {
    final started = Completer<void>();
    unawaited(
      withEnv((e) async {
        env = e;
        started.complete();
        await done.future;
      }).catchError((Object error, StackTrace stack) {
        if (!started.isCompleted) {
          started.completeError(error, stack);
        }
      }),
    );
    await started.future;
  });

  tearDownAll(() {
    if (!done.isCompleted) {
      done.complete();
    }
  });

  for (final scenario in scenarios) {
    test(
      scenario.id,
      () async {
        final outcome = await runScenario(env, scenario);
        expect(outcome, expectedOutcome(scenario.id));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  test('every scenario has a distinct id', () {
    final ids = [for (final s in scenarios) s.id];
    expect(ids.toSet(), hasLength(ids.length));
  });

  group("the exceptions are Spring's", () {
    // What retry code catches: one root for a version conflict, a lock, a
    // deadlock and a serialization failure.
    test('the concurrency failures share their roots', () {
      final lock = CannotAcquireLockException('x');
      final deadlock = DeadlockLoserDataAccessException('x');
      final serialization = CannotSerializeTransactionException('x');
      for (final failure in [lock, deadlock, serialization]) {
        expect(failure, isA<PessimisticLockingFailureException>());
        expect(failure, isA<ConcurrencyFailureException>());
        expect(failure, isA<TransientDataAccessException>());
      }
      expect(
        OptimisticLockingFailureException('x'),
        isA<ConcurrencyFailureException>(),
      );
      expect(
        QueryTimeoutException('x'),
        isNot(isA<ConcurrencyFailureException>()),
      );
    });
  });
}
