// @Retryable around @Transactional, end to end through the generated
// proxies of app/resilience_app.dart: each attempt is a new transaction;
// a call inside a transaction it did not open is not retried; one with a
// transaction of its own is; a TransactionSystemException never is.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/resilience/app/resilience_app.spring.dart';
import '../transaction/support/recording_transaction_manager.dart';
import 'app/resilience_app.dart';

Future<void> _withApp(
  Future<void> Function(
    Bookings bookings,
    Agency agency,
    RecordingTransactionManager manager,
  )
  body,
) => const ApplicationContextRunner()
    .withUserConfiguration($application)
    .withAutoConfiguration(springBootResilienceAutoConfiguration)
    .withAutoConfiguration(springBootStarterDataAutoConfiguration)
    .withAutoConfiguration(springBootStarterDataResilienceAutoConfiguration)
    .runAsync((context) async {
      if (context.startupFailure case final failure?) {
        throw StateError('The application did not start: $failure');
      }
      await body(
        context.getBean<Bookings>(),
        context.getBean<Agency>(),
        context.getBean<RecordingTransactionManager>(),
      );
    });

void main() {
  test('the retry is outside the transaction: a new one per attempt', () {
    return _withApp((bookings, _, manager) async {
      expect(await bookings.book(), 3);
      expect(bookings.transactions, [1, 2, 3]);
      expect(manager.calls, [
        'begin 1',
        'rollback 1',
        'begin 2',
        'rollback 2',
        'begin 3',
        'commit 3',
      ]);
    });
  });

  test('a call inside a transaction it did not open is not retried', () {
    return _withApp((bookings, agency, manager) async {
      await expectLater(agency.joined(), throwsA(isA<TimeoutException>()));
      expect(bookings.transactions, [1]);
      expect(manager.calls, ['begin 1', 'rollback 1']);
    });
  });

  test('one with a transaction of its own (requiresNew) is retried', () {
    return _withApp((bookings, agency, manager) async {
      expect(await agency.separate(), 3);
      expect(bookings.transactions, [2, 3]);
      expect(manager.calls.last, 'commit 1');
    });
  });

  test('a TransactionSystemException is never retried', () {
    return _withApp((bookings, _, _) async {
      await expectLater(
        bookings.unknownOutcome(),
        throwsA(isA<TransactionSystemException>()),
      );
      expect(bookings.transactions, [null]);
    });
  });

  test('the orders: the retry advisor outside the transaction advisor', () {
    return _withApp((bookings, _, _) async {
      final advisors = (bookings as Advised).aopAdvisors;
      expect(
        [for (final a in advisors) (a as DefaultPointcutAdvisor).order],
        [AdvisorOrder.retry, AdvisorOrder.transaction],
      );
    });
  });
}
