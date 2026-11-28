import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_interceptor.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_synchronization_manager.dart';

/// Keeps a `@Retryable` method from being retried when its call runs
/// inside a transaction it did not open: a failure there has marked that
/// transaction rollback-only (and what the attempt wrote stays in it), so
/// a new attempt would write twice and the commit would end in an
/// `UnexpectedRollbackException`. The failure goes to the caller at once.
///
/// A method whose own `@Transactional` starts a transaction of its own
/// (`Propagation.requiresNew`), runs in a savepoint (`nested`) or outside
/// any (`notSupported`) is retried: each attempt is on its own. A debug
/// build logs, once per method, that it was not retried and what to do:
/// put `@Retryable` on the method that opens the transaction, or use
/// `requiresNew`.
///
/// The data starter registers it as the bean `joinedTransactionRetryVeto`
/// with `spring.resilience.enabled: true`.
///
/// Spring (Java) has no such rule: the retry runs, and the outer
/// transaction fails at its commit.
final class JoinedTransactionRetryVeto implements MethodRetryVeto {
  /// The veto.
  const JoinedTransactionRetryVeto();

  static const Set<Propagation> _onItsOwn = {
    Propagation.requiresNew,
    Propagation.nested,
    Propagation.notSupported,
  };

  @override
  String? vetoRetry(MethodInvocation invocation) {
    final running = TransactionSynchronizationManager.currentTransaction;
    if (running == null) {
      return null;
    }
    final own = TransactionAnnotationPointcut.transactionalOf(
      invocation.signature,
    );
    if (own != null && _onItsOwn.contains(own.propagation)) {
      return null;
    }
    final which = switch (running.name) {
      null => 'a transaction',
      final name => "the transaction '$name'",
    };
    return 'it runs inside $which, which it did '
        'not open, and its failure has marked that transaction '
        'rollback-only; put @Retryable on the method that opens the '
        'transaction, or give this one '
        '@Transactional(propagation: Propagation.requiresNew)';
  }
}
