/// The root of the errors of transaction handling (not of the data access
/// inside a transaction, which are `DataAccessException`s).
///
/// Spring (Java): `org.springframework.transaction.TransactionException`.
abstract class TransactionException implements Exception {
  /// An error described by [message], caused by [cause] when there is one.
  TransactionException(this.message, {this.cause});

  /// What went wrong.
  final String message;

  /// The error behind this one, if any.
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : '; caused by $cause'}';
}

/// A transaction could not be started (no connection, the store refused).
///
/// Spring (Java):
/// `org.springframework.transaction.CannotCreateTransactionException`.
class CannotCreateTransactionException extends TransactionException {
  /// A transaction not started, described by [message].
  CannotCreateTransactionException(super.message, {super.cause});
}

/// A transaction was used in a state that does not allow it: `mandatory`
/// without a transaction, `never` within one, a `@Lock` query outside one,
/// work using a transaction that has already ended.
///
/// Spring (Java):
/// `org.springframework.transaction.IllegalTransactionStateException`.
class IllegalTransactionStateException extends TransactionException {
  /// A wrong state described by [message].
  IllegalTransactionStateException(super.message, {super.cause});
}

/// A commit was asked of a transaction that had to roll back instead,
/// because a part of it (an inner `required` method that failed) marked it
/// rollback-only: the caller learns that nothing was committed.
///
/// Spring (Java):
/// `org.springframework.transaction.UnexpectedRollbackException`.
class UnexpectedRollbackException extends TransactionException {
  /// An unexpected rollback described by [message].
  UnexpectedRollbackException(super.message, {super.cause});
}

/// The store failed to commit or roll back.
///
/// Spring (Java): `org.springframework.transaction.TransactionSystemException`.
class TransactionSystemException extends TransactionException {
  /// A failure described by [message].
  TransactionSystemException(
    super.message, {
    super.cause,
    this.applicationException,
  });

  /// The application's exception that was being handled (a rollback after
  /// it failed), when there is one: it is not lost.
  final Object? applicationException;
}

/// The transaction ran past its timeout.
///
/// Spring (Java):
/// `org.springframework.transaction.TransactionTimedOutException`.
class TransactionTimedOutException extends TransactionException {
  /// A timeout described by [message].
  TransactionTimedOutException(super.message, {super.cause});
}

/// A `nested` transaction was asked of a manager or store without
/// savepoints.
///
/// Spring (Java):
/// `org.springframework.transaction.NestedTransactionNotSupportedException`.
class NestedTransactionNotSupportedException
    extends CannotCreateTransactionException {
  /// An unsupported nesting described by [message].
  NestedTransactionNotSupportedException(super.message, {super.cause});
}

/// An isolation level the store does not offer was asked.
///
/// Spring (Java):
/// `org.springframework.transaction.InvalidIsolationLevelException`.
class InvalidIsolationLevelException extends TransactionException {
  /// An unsupported level described by [message].
  InvalidIsolationLevelException(super.message, {super.cause});
}

/// A negative or zero timeout was given.
///
/// Spring (Java): `org.springframework.transaction.InvalidTimeoutException`.
class InvalidTimeoutException extends TransactionException {
  /// A wrong timeout described by [message].
  InvalidTimeoutException(super.message, {super.cause});
}
