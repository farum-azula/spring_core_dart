import 'dart:async';

import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_exceptions.dart';

/// Where the current transaction lives: in a [Zone], so it follows `await`
/// and is never shared by two concurrent requests.
///
/// Spring keeps the current transaction in thread-locals; Dart has one
/// thread and many interleaved tasks, so here each `TransactionTemplate`
/// call (and each `@Transactional` method) runs its body in a new zone
/// holding a new scope ([runInScope]). Resources (a store's transaction, a
/// connection) are bound into the current scope and found from the scopes
/// it is nested in:
///
/// - joining (`required` within a transaction): nothing is bound, the
///   outer transaction's resources are found through the parent scopes;
/// - setting aside (`requiresNew`, `notSupported`): the new scope is
///   [isolate]d for the manager's resource key, so the outer transaction
///   of that store is not seen from it (the transactions of other stores
///   still are, as Spring suspends only the manager's own resource); when
///   the body ends, the code after it runs in the outer zone again, where
///   it is. That is Spring's suspend and resume, done by the structure of
///   the code;
/// - ending: the resources of a finished transaction are replaced by a
///   marker, so work started inside it without being awaited, and still
///   running after it, fails ([IllegalTransactionStateException]) instead
///   of silently running outside the transaction.
///
/// Stores and managers use it; applications rarely need it.
///
/// Spring (Java): `org.springframework.transaction.support.
/// TransactionSynchronizationManager`.
abstract final class TransactionSynchronizationManager {
  static final Object _zoneKey = Object();

  static TransactionScope? get _current =>
      Zone.current[_zoneKey] as TransactionScope?;

  static TransactionScope get _required =>
      _current ??
      (throw StateError(
        'No transaction scope: run the code in a TransactionTemplate, a '
        '@Transactional method, or '
        'TransactionSynchronizationManager.runInScope',
      ));

  /// Runs [body] in a new zone with a new scope nested in the current one
  /// (or a first one), and returns its result.
  static Future<R> runInScope<R>(FutureOr<R> Function() body) => runZoned(
    () => Future.sync(body),
    zoneValues: {_zoneKey: TransactionScope._(_current)},
  );

  /// Whether the code runs in a scope ([runInScope]).
  static bool get hasScope => _current != null;

  /// Hides, from the current scope and the scopes nested in it, the
  /// resource bound to [key] in the enclosing scopes and the transaction
  /// started for [key] there; without [key], every resource and
  /// transaction. A transaction started here for [key] is then independent
  /// of the outer one, which goes on when the current zone's body ends.
  /// Call before binding [key] or starting its transaction in the scope.
  static void isolate([Object? key]) {
    final scope = _required;
    if (key == null) {
      if (scope._resources.isNotEmpty || scope._transactions.isNotEmpty) {
        throw StateError('isolate() after binding resources in the scope');
      }
      scope._isolatedAll = true;
      return;
    }
    if (scope._resources.containsKey(key) ||
        scope._transactions.containsKey(key)) {
      throw StateError('isolate($key) after binding it in the scope');
    }
    scope._isolatedKeys.add(key);
  }

  /// Whether [key] (or, without it, everything) is isolated in the current
  /// scope ([isolate]).
  static bool isIsolated([Object? key]) {
    final scope = _current;
    if (scope == null) {
      return false;
    }
    return scope._isolatedAll ||
        (key != null && scope._isolatedKeys.contains(key));
  }

  // ------------------------------------------------------------ resources

  /// The resource bound to [key] in the current scope or the scopes it can
  /// see, or null.
  ///
  /// Throws an [IllegalTransactionStateException] when the resource
  /// belonged to a transaction that has ended (work started in it and not
  /// awaited).
  static Object? getResource(Object key) {
    for (var scope = _current; scope != null; scope = scope.parent) {
      final value = scope._resources[key];
      if (value is _Ended) {
        throw IllegalTransactionStateException(
          'The transaction ${value.name ?? ''} this work was started in has '
          'already ended: await the work inside the transaction',
        );
      }
      if (value != null) {
        return value;
      }
      if (scope._hides(key)) {
        return null;
      }
    }
    return null;
  }

  /// Whether a resource is bound to [key] and visible ([getResource]).
  static bool hasResource(Object key) => getResource(key) != null;

  /// Binds [value] to [key] in the current scope. Throws a [StateError]
  /// when something is already bound to [key] in it.
  static void bindResource(Object key, Object value) {
    final scope = _required;
    final old = scope._resources[key];
    if (old != null && old is! _Ended) {
      throw StateError('A resource is already bound to $key in this scope');
    }
    scope._resources[key] = value;
  }

  /// Unbinds the resource of [key] from the current scope, leaving the
  /// marker of an ended transaction (see the class comment); returns the
  /// resource. Throws a [StateError] when none is bound there.
  static Object unbindResource(Object key) {
    final scope = _required;
    final value = scope._resources[key];
    if (value == null || value is _Ended) {
      throw StateError('No resource bound to $key in this scope');
    }
    scope._resources[key] = _Ended(scope._transactions[key]?.name);
    return value;
  }

  // ---------------------------------------------------------- transaction

  /// Records that a transaction defined by [definition] starts in the
  /// current scope for the resource [key] (the store or database; by
  /// default one shared key); called by the transaction manager when it
  /// begins one.
  static void initTransaction(TransactionDefinition definition, {Object? key}) {
    final scope = _required;
    final k = key ?? _defaultKey;
    if (scope._transactions.containsKey(k)) {
      throw StateError('A transaction already started in this scope');
    }
    final timeout = definition.timeout;
    if (timeout != null && timeout <= Duration.zero) {
      throw InvalidTimeoutException('Invalid transaction timeout: $timeout');
    }
    scope._transactions[k] = TransactionInfo._(definition);
  }

  static final Object _defaultKey = Object();

  /// The transaction of [key] (a store, see [initTransaction]) visible from
  /// the current scope, or null.
  static TransactionInfo? currentTransactionFor(Object key) {
    for (var scope = _current; scope != null; scope = scope.parent) {
      if (scope._transactions[key] case final info?) {
        return info.isCompleted ? null : info;
      }
      if (scope._hides(key)) {
        return null;
      }
    }
    return null;
  }

  /// The innermost transaction visible from the current scope, of any
  /// store, or null.
  static TransactionInfo? get currentTransaction {
    final hidden = <Object>{};
    for (var scope = _current; scope != null; scope = scope.parent) {
      for (final MapEntry(:key, :value) in [
        ...scope._transactions.entries,
      ].reversed) {
        if (!hidden.contains(key)) {
          return value.isCompleted ? null : value;
        }
      }
      if (scope._isolatedAll) {
        return null;
      }
      hidden.addAll(scope._isolatedKeys);
    }
    return null;
  }

  /// Whether a transaction is running for the current code.
  static bool get isActualTransactionActive => currentTransaction != null;

  /// The current transaction's name, or null.
  static String? get currentTransactionName => currentTransaction?.name;

  /// Whether the current transaction only reads.
  static bool get isCurrentTransactionReadOnly =>
      currentTransaction?.readOnly ?? false;

  /// The current transaction's isolation level, or null.
  static Isolation? get currentTransactionIsolationLevel =>
      currentTransaction?.isolation;

  /// Registers [synchronization] with the current transaction. Throws an
  /// [IllegalTransactionStateException] without one.
  static void registerSynchronization(
    TransactionSynchronization synchronization,
  ) {
    final info =
        currentTransaction ??
        (throw IllegalTransactionStateException(
          'No transaction to register a synchronization with',
        ));
    info._synchronizations.add(synchronization);
  }

  /// Marks a transaction as ended: its [TransactionInfo] reports
  /// [TransactionInfo.isCompleted] and is no longer current. Without
  /// [transaction], it is the one started in the current scope. Called by
  /// the transaction manager.
  static void completeTransaction([TransactionInfo? transaction]) {
    if (transaction != null) {
      transaction._completed = true;
      return;
    }
    final started = _required._transactions.values;
    if (started.length != 1) {
      throw StateError(
        started.isEmpty
            ? 'No transaction started in this scope'
            : 'Several transactions started in this scope: name the one',
      );
    }
    started.single._completed = true;
  }
}

/// One scope of [TransactionSynchronizationManager]: the resources bound in
/// it and the transaction started in it.
final class TransactionScope {
  TransactionScope._(this.parent);

  /// The scope this one is nested in.
  final TransactionScope? parent;

  bool _isolatedAll = false;
  final _isolatedKeys = <Object>{};
  final _resources = <Object, Object>{};
  final _transactions = <Object, TransactionInfo>{};

  bool _hides(Object key) => _isolatedAll || _isolatedKeys.contains(key);
}

/// What is known of a running transaction: its settings, its deadline, its
/// synchronizations.
final class TransactionInfo {
  TransactionInfo._(TransactionDefinition definition)
    : name = definition.name,
      readOnly = definition.readOnly,
      isolation = definition.isolation,
      timeout = definition.timeout,
      _clock = Stopwatch()..start();

  /// The name in logs.
  final String? name;

  /// Whether it only reads.
  final bool readOnly;

  /// Its isolation level.
  final Isolation isolation;

  /// Its timeout, from its start; null for none.
  final Duration? timeout;

  final Stopwatch _clock;
  final _synchronizations = <TransactionSynchronization>[];
  bool _completed = false;

  /// Whether it has ended.
  bool get isCompleted => _completed;

  /// The synchronizations registered with it, in order.
  List<TransactionSynchronization> get synchronizations =>
      List.unmodifiable(_synchronizations);

  /// The time left before its timeout; null without one, never negative.
  Duration? get timeLeft {
    final timeout = this.timeout;
    if (timeout == null) {
      return null;
    }
    final left = timeout - _clock.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// Throws a [TransactionTimedOutException] when its timeout has passed;
  /// stores call it before each statement.
  void checkDeadline() {
    if (timeLeft == Duration.zero) {
      throw TransactionTimedOutException(
        'Transaction ${name ?? ''} timed out after '
        '${timeout!.inMilliseconds} ms',
      );
    }
  }
}

/// Callbacks around the end of a transaction: work to do just before the
/// commit (flush a buffer), or after it (send an event only once the data
/// is committed).
///
/// Spring (Java): `org.springframework.transaction.support.
/// TransactionSynchronization`.
abstract class TransactionSynchronization {
  /// Before the commit, in order of registration; an exception here rolls
  /// the transaction back.
  FutureOr<void> beforeCommit({required bool readOnly}) {}

  /// Before the commit or the rollback.
  FutureOr<void> beforeCompletion() {}

  /// After a successful commit.
  FutureOr<void> afterCommit() {}

  /// After the commit or the rollback, with how it ended; an exception
  /// here is logged, not thrown.
  FutureOr<void> afterCompletion(TransactionCompletion status) {}
}

/// How a transaction ended, for [TransactionSynchronization.afterCompletion].
enum TransactionCompletion {
  /// Committed.
  committed,

  /// Rolled back.
  rolledBack,

  /// Unknown (the commit or rollback itself failed).
  unknown,
}

final class _Ended {
  const _Ended(this.name);
  final String? name;
}
