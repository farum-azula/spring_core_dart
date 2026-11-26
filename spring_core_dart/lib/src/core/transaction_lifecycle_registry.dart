/// What code that keeps state learns of the running transaction, without
/// depending on the package that runs transactions: which one runs now,
/// and how it goes on and ends.
///
/// The data starter registers a bean of it; a starter that holds writes
/// until a commit (the Flutter signals starter) takes it as an optional
/// bean. Nothing else needs it.
///
/// ```dart
/// final registry = context.findBean<TransactionLifecycleRegistry>();
/// if (registry?.transactionKey case final key?) {
///   registry!.registerListener(MyListener(key));
/// }
/// ```
///
/// Spring (Java): `TransactionSynchronizationManager.registerSynchronization`
/// with a `TransactionSynchronization` (spring-tx). The data starter's
/// `TransactionSynchronizationManager` is that API; this one is the part
/// of it other packages need.
abstract interface class TransactionLifecycleRegistry {
  /// The transaction that runs for the current code, compared by
  /// identity; `null` outside one.
  Object? get transactionKey;

  /// Tells [listener] how the current transaction goes on and ends. Fails
  /// outside a transaction.
  void registerListener(TransactionLifecycleListener listener);
}

/// How a transaction goes on and ends, for
/// [TransactionLifecycleRegistry.registerListener].
///
/// Spring (Java): `TransactionSynchronization`'s `savepoint`,
/// `savepointRollback`, `afterCommit` and `afterCompletion`.
abstract interface class TransactionLifecycleListener {
  /// A savepoint was made (a nested block starts).
  void savepoint(Object savepoint);

  /// The transaction went back to [savepoint] and goes on.
  void savepointRollback(Object savepoint);

  /// The transaction was committed.
  void afterCommit();

  /// The transaction ended without a commit: it was rolled back, or its
  /// end is unknown (the commit or the rollback failed, so what it wrote
  /// may or may not be in the store). Spring's `afterCompletion` with
  /// `STATUS_ROLLED_BACK` or `STATUS_UNKNOWN`.
  void afterRollbackOrUnknown();
}
