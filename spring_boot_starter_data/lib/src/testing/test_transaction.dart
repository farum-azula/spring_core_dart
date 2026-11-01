import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/repository/repository_factory.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_synchronization_manager.dart';

const _log = SpringLog('spring.data.test.TestTransaction');

const _definition = TransactionDefinition(name: 'test');

/// Runs a test in a transaction of every `PlatformTransactionManager` its
/// repositories write through, and rolls them back afterwards (or commits
/// them, with `rollback: false`): what a `@DataTest` class does around each
/// test.
///
/// The managers are those of the application (the primary one and the ones
/// of `@UseDataSource` names) and those the repository factory made for the
/// stores of the repositories: the in-memory store, the primary database
/// and each named one. A manager binds its transaction to its store or
/// database, so all the transactions are open at the same time, side by side
/// in one scope; a repository on any of them joins its own.
///
/// The transactions begin first, then run, in this order, the [before]
/// steps (the `@BeforeEach` methods), [body] (the test) and the [after]
/// steps (the `@AfterEach` methods), all inside the scope: the repositories
/// and the `@Transactional` methods they call join the transactions, so
/// nothing a test writes outlives it. A step that fails stops the ones
/// after it of its kind: when a [before] step fails, [body] is skipped, and
/// the [after] steps run anyway (as `tearDown` does after a failing
/// `setUp`).
///
/// The first error is thrown once everything has run; later ones are
/// logged. A test that failed is rolled back even with `rollback: false`,
/// so a failure leaves nothing behind for the tests after it. A
/// transaction that was marked rollback-only by a participant fails a
/// committing test with an `UnexpectedRollbackException`, as in Spring; the
/// transactions of the other managers are rolled back then, as they are
/// when committing one fails.
///
/// ```dart
/// final app = springBootTest(springApplication);
///
/// test('saves a book', () => runInTestTransaction(app.context, () async {
///   await app.getBean<BookRepository>().save(Book(title: 'Dune'));
/// })); // rolled back
/// ```
///
/// Spring (Java): `TransactionalTestExecutionListener`, which starts the
/// transaction before `@BeforeEach` and ends it after `@AfterEach`; Spring
/// uses the one transaction manager the test names (or the only one).
/// The steps run in the scope's zone, so a `package:test` `setUp` or
/// `tearDown` cannot be part of it: the generated code calls the lifecycle
/// methods from here instead.
///
/// ```dart
/// final app = springBootTest(springApplication);
///
/// test('saves a book', () => runInTestTransaction(app.context, () async {
///   await app.getBean<BookRepository>().save(Book(title: 'Dune'));
/// })); // rolled back
/// ```
///
/// Spring (Java): `TransactionalTestExecutionListener`, which starts the
/// transaction before `@BeforeEach` and ends it after `@AfterEach`.
Future<void> runInTestTransaction(
  BeanFactory beans,
  FutureOr<void> Function() body, {
  bool rollback = true,
  List<FutureOr<void> Function()> before = const [],
  List<FutureOr<void> Function()> after = const [],
}) {
  final managers = _managersOf(beans);
  return TransactionSynchronizationManager.runInScope<void>(() async {
    final begun = <(PlatformTransactionManager, TransactionStatus)>[];
    Object? failure;
    StackTrace? trace;
    void failed(Object error, StackTrace stackTrace) {
      if (failure == null) {
        failure = error;
        trace = stackTrace;
      } else {
        _log.warning(
          'Another failure in the test after the first one',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    // Ends the transactions that are left, the last begun first.
    Future<void> end({required bool rollback}) async {
      var commit = !rollback;
      while (begun.isNotEmpty) {
        final (manager, status) = begun.removeLast();
        try {
          if (commit) {
            await manager.commit(status);
          } else {
            await manager.rollback(status);
          }
        } on Object catch (error, stackTrace) {
          failed(error, stackTrace);
          // What was not committed must not be left open or half done.
          commit = false;
        }
      }
    }

    try {
      for (final manager in managers) {
        begun.add((manager, await manager.getTransaction(_definition)));
      }
    } on Object catch (error, stackTrace) {
      failed(error, stackTrace);
      await end(rollback: true);
      Error.throwWithStackTrace(failure!, trace!);
    }
    var prepared = true;
    for (final step in before) {
      try {
        await step();
      } on Object catch (error, stackTrace) {
        failed(error, stackTrace);
        prepared = false;
        break;
      }
    }
    if (prepared) {
      try {
        await body();
      } on Object catch (error, stackTrace) {
        failed(error, stackTrace);
      }
    }
    for (final step in after) {
      try {
        await step();
      } on Object catch (error, stackTrace) {
        failed(error, stackTrace);
      }
    }
    await end(rollback: rollback || failure != null);
    if (failure case final error?) {
      Error.throwWithStackTrace(error, trace!);
    }
  });
}

// The managers the repositories of [beans] write through, one for each
// store or database (two managers of a store share its transaction).
List<PlatformTransactionManager> _managersOf(BeanFactory beans) {
  final all = Set<PlatformTransactionManager>.identity();
  if (beans case final ListableBeanFactory listable) {
    all.addAll(listable.getSortedBeans<PlatformTransactionManager>());
  }
  if (beans.findBean<RepositoryFactory>() case final factory?) {
    all.addAll(factory.transactionManagers);
  }
  if (all.isEmpty) {
    // Fails the way a missing bean does.
    all.add(beans.getBean<PlatformTransactionManager>());
  }
  final keys = Set<Object>.identity();
  return [
    for (final manager in all)
      if (keys.add(switch (manager) {
        final TransactionManagerHooks hooks => hooks.resourceKey,
        _ => manager,
      }))
        manager,
  ];
}
