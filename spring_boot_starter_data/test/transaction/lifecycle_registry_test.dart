// What other starters learn of the running transaction through core's
// TransactionLifecycleRegistry: which one runs, and how it ends. A
// transaction that was not committed (rolled back, or its end unknown
// because the commit failed) is told as such, under that name.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/recording_transaction_manager.dart';

final class _Listener implements TransactionLifecycleListener {
  final events = <String>[];

  @override
  void savepoint(Object savepoint) => events.add('savepoint');

  @override
  void savepointRollback(Object savepoint) => events.add('savepointRollback');

  @override
  void afterCommit() => events.add('afterCommit');

  @override
  void afterRollbackOrUnknown() => events.add('afterRollbackOrUnknown');
}

void main() {
  const TransactionLifecycleRegistry registry =
      DataTransactionLifecycleRegistry();
  late RecordingTransactionManager manager;
  late _Listener listener;

  setUp(() {
    manager = RecordingTransactionManager();
    listener = _Listener();
  });

  test('no transaction: no key', () {
    expect(registry.transactionKey, isNull);
  });

  test('a commit is told as one', () async {
    await TransactionTemplate(manager).execute((_) async {
      expect(registry.transactionKey, isNotNull);
      registry.registerListener(listener);
    });
    expect(listener.events, ['afterCommit']);
  });

  test('a rollback is told as no commit', () async {
    await expectLater(
      TransactionTemplate(manager).execute<void>((_) async {
        registry.registerListener(listener);
        throw StateError('no');
      }),
      throwsStateError,
    );
    expect(listener.events, ['afterRollbackOrUnknown']);
  });

  test('a failed commit, whose end is unknown, is told as no commit', () async {
    manager.failCommit = 'disk full';
    await expectLater(
      TransactionTemplate(manager).execute((_) async {
        registry.registerListener(listener);
      }),
      throwsA(isA<TransactionSystemException>()),
    );
    expect(listener.events, ['afterRollbackOrUnknown']);
  });
}
