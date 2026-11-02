// Any object may be thrown in Dart; the tests throw strings and plain
// objects on purpose.
// ignore_for_file: only_throw_errors
// A small application whose beans have @Transactional methods: the
// generator writes the proxies (transaction_app.spring.dart, from
// `dart run build_runner build`), the tests start it with the starter's
// auto-configuration and call the beans.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import '../support/recording_transaction_manager.dart';
import 'transaction_app.spring.dart';

/// Thrown when there is no stock; the order is still booked.
class OutOfStock implements Exception {}

/// A kind of [OutOfStock]: matched through its supertype.
class SoldOut extends OutOfStock {}

/// A failure that rolls back although [OutOfStock] does not.
class Counterfeit extends OutOfStock {}

/// The transaction managers: the main one, and one for the archive.
@Configuration()
class Managers {
  @Bean()
  @Primary()
  RecordingTransactionManager transactionManager() =>
      RecordingTransactionManager();

  @Bean()
  @Qualifier('archive')
  RecordingTransactionManager archiveTransactionManager() =>
      RecordingTransactionManager();
}

/// Method-level annotations.
@Service()
class Shop {
  Shop(this.manager, @Qualifier('archive') this.archive);

  final RecordingTransactionManager manager;
  final RecordingTransactionManager archive;

  /// The id of the transaction the method runs in.
  @Transactional()
  Future<int?> transactionId() async => manager.currentId;

  /// Without the annotation: no transaction.
  Future<int?> plain() async => manager.currentId;

  /// Fails with [error]: it rolls back.
  @Transactional()
  Future<void> fail(Object error) async => throw error;

  /// Fails with [error] after a delay.
  @Transactional()
  Future<void> failLater(Object error) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    throw error;
  }

  /// [OutOfStock] and its subtypes commit.
  @Transactional(noRollbackFor: [OutOfStock])
  Future<void> failOutOfStock(Object error) async => throw error;

  /// [OutOfStock] commits, but [Counterfeit] rolls back.
  @Transactional(noRollbackFor: [OutOfStock], rollbackFor: [Counterfeit])
  Future<void> failWithRules(Object error) async => throw error;

  /// The closest entry decides: [OutOfStock] and [SoldOut] roll back,
  /// [Counterfeit] (closer to itself than [OutOfStock]) commits.
  @Transactional(rollbackFor: [OutOfStock], noRollbackFor: [Counterfeit])
  Future<void> failClosest(Object error) async => throw error;

  /// The archive's transaction manager.
  @Transactional(transactionManager: 'archive')
  Future<int?> archived() async => archive.currentId;

  /// By bean name.
  @Transactional(transactionManager: 'archiveTransactionManager')
  Future<int?> archivedByName() async => archive.currentId;

  /// Its own transaction.
  @Transactional(propagation: Propagation.requiresNew)
  Future<int?> fresh() async => manager.currentId;

  /// Needs a running one.
  @Transactional(propagation: Propagation.mandatory)
  Future<int?> mandatory() async => manager.currentId;

  /// The settings of the transaction.
  @Transactional(
    readOnly: true,
    isolation: Isolation.serializable,
    timeout: Duration(seconds: 5),
  )
  Future<String> settings() async {
    final info = TransactionSynchronizationManager.currentTransaction!;
    return '${info.name} readOnly=${info.readOnly} '
        '${info.isolation.name} ${info.timeout?.inSeconds}';
  }

  /// Calls another bean's transactional method: it joins.
  @Transactional()
  Future<List<int?>> callsLedger(Ledger ledger) async => [
    manager.currentId,
    await ledger.a(),
    await ledger.fresh(),
    manager.currentId,
  ];

  /// A call through `this` is not proxied: no transaction of its own.
  Future<int?> callsItself() => transactionId();

  /// Forgets a task that uses the transaction after it ended; the result
  /// of the task is in the returned completer.
  @Transactional()
  Future<Completer<Object?>> forgets() async {
    final result = Completer<Object?>();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 5)).then((_) {
        try {
          result.complete(manager.current);
        } on Object catch (error) {
          result.complete(error);
        }
      }),
    );
    return result;
  }
}

/// A class-level annotation: every public method.
@Service()
@Transactional()
class Ledger {
  Ledger(this.manager);

  final RecordingTransactionManager manager;

  Future<int?> a() async => manager.currentId;

  Future<int?> b() async => manager.currentId;

  /// Its own annotation wins over the class's.
  @Transactional(propagation: Propagation.requiresNew)
  Future<int?> fresh() async => manager.currentId;

  /// Its own annotation wins: no transaction without one running.
  @Transactional(propagation: Propagation.supports)
  Future<int?> supports() async => manager.currentId;
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
