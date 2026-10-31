/// The root of the errors of data access: every store (in memory, SQLite,
/// PostgreSQL, Redis, Supabase) translates its driver's errors into this one
/// hierarchy, so a caller catches the same exceptions whatever the store.
///
/// A message never holds the values of a statement: the SQL (with `?` or
/// `:name`), the SQL state, the vendor code and the cause are kept, the
/// parameters are not.
///
/// Spring (Java): `org.springframework.dao.DataAccessException`.
abstract class DataAccessException implements Exception {
  /// An error described by [message], caused by [cause] when there is one.
  DataAccessException(this.message, {this.cause, this.sql});

  /// What went wrong.
  final String message;

  /// The driver's error behind this one, if any.
  final Object? cause;

  /// The statement that failed, with its placeholders and without its
  /// values; null when no statement was involved.
  final String? sql;

  @override
  String toString() {
    final out = StringBuffer('$runtimeType: $message');
    if (sql case final sql?) {
      out.write(' [$sql]');
    }
    if (cause case final cause?) {
      out.write('; caused by $cause');
    }
    return out.toString();
  }
}

/// An error that may not happen again when the operation is retried
/// unchanged: a lock that could not be had, a deadlock, a serialization
/// failure, a timeout.
///
/// Spring (Java): `org.springframework.dao.TransientDataAccessException`.
abstract class TransientDataAccessException extends DataAccessException {
  /// A transient error described by [message].
  TransientDataAccessException(super.message, {super.cause, super.sql});
}

/// An error that happens again when the operation is retried unchanged: a
/// broken constraint, wrong SQL, a missing row.
///
/// Spring (Java): `org.springframework.dao.NonTransientDataAccessException`.
abstract class NonTransientDataAccessException extends DataAccessException {
  /// A lasting error described by [message].
  NonTransientDataAccessException(super.message, {super.cause, super.sql});
}

/// A write broke an integrity constraint (not null, foreign key, check).
///
/// Spring (Java): `org.springframework.dao.DataIntegrityViolationException`.
class DataIntegrityViolationException extends NonTransientDataAccessException {
  /// A broken constraint described by [message].
  DataIntegrityViolationException(
    super.message, {
    super.cause,
    super.sql,
    this.constraint,
  });

  /// The name of the broken constraint, when the store gives it.
  final String? constraint;
}

/// An insert or update would duplicate a unique key (a primary key or a
/// unique index). The web starter answers it with 409.
///
/// Spring (Java): `org.springframework.dao.DuplicateKeyException`.
class DuplicateKeyException extends DataIntegrityViolationException {
  /// A duplicate key described by [message].
  DuplicateKeyException(
    super.message, {
    super.cause,
    super.sql,
    super.constraint,
  });
}

/// A query returned a number of results other than the one expected.
///
/// Spring (Java):
/// `org.springframework.dao.IncorrectResultSizeDataAccessException`.
class IncorrectResultSizeDataAccessException
    extends NonTransientDataAccessException {
  /// [actualSize] results where [expectedSize] were expected.
  IncorrectResultSizeDataAccessException(
    this.expectedSize,
    this.actualSize, {
    String? message,
    super.cause,
    super.sql,
  }) : super(
         message ??
             'Incorrect result size: expected $expectedSize, '
                 'actual $actualSize',
       );

  /// The number of results expected.
  final int expectedSize;

  /// The number of results found.
  final int actualSize;
}

/// A query expected one result and found none. The web starter answers it
/// with 404.
///
/// Spring (Java): `org.springframework.dao.EmptyResultDataAccessException`.
class EmptyResultDataAccessException
    extends IncorrectResultSizeDataAccessException {
  /// No result where [expectedSize] were expected.
  EmptyResultDataAccessException(
    int expectedSize, {
    String? message,
    super.cause,
    super.sql,
  }) : super(
         expectedSize,
         0,
         message:
             message ??
             'Incorrect result size: expected $expectedSize, actual 0',
       );
}

/// An update changed no row where one was expected: `save` of an entity
/// with an id (and no `@Version`) whose row does not exist.
///
/// Spring (Java):
/// `org.springframework.dao.IncorrectUpdateSemanticsDataAccessException`.
class IncorrectUpdateSemanticsDataAccessException
    extends InvalidDataAccessResourceUsageException {
  /// An update without effect described by [message].
  IncorrectUpdateSemanticsDataAccessException(
    super.message, {
    super.cause,
    super.sql,
  });
}

/// A resource was used wrongly: wrong SQL, an update without effect.
///
/// Spring (Java):
/// `org.springframework.dao.InvalidDataAccessResourceUsageException`.
class InvalidDataAccessResourceUsageException
    extends NonTransientDataAccessException {
  /// A wrong use described by [message].
  InvalidDataAccessResourceUsageException(
    super.message, {
    super.cause,
    super.sql,
  });
}

/// The SQL of a statement is wrong (a syntax error, an unknown table or
/// column).
///
/// Spring (Java): `org.springframework.jdbc.BadSqlGrammarException`.
class BadSqlGrammarException extends InvalidDataAccessResourceUsageException {
  /// Wrong SQL described by [message].
  BadSqlGrammarException(super.message, {super.cause, super.sql});
}

/// A data access API was used wrongly (a method called where it cannot
/// work, a wrong argument).
///
/// Spring (Java):
/// `org.springframework.dao.InvalidDataAccessApiUsageException`.
class InvalidDataAccessApiUsageException
    extends NonTransientDataAccessException {
  /// A wrong use described by [message].
  InvalidDataAccessApiUsageException(super.message, {super.cause, super.sql});
}

/// The store cannot be reached, or the connection was lost.
///
/// Spring (Java):
/// `org.springframework.dao.DataAccessResourceFailureException`.
class DataAccessResourceFailureException
    extends NonTransientDataAccessException {
  /// A failure of the store described by [message].
  DataAccessResourceFailureException(super.message, {super.cause, super.sql});
}

/// A save or delete found the row changed or gone since it was loaded: its
/// `@Version` no longer matches. Worth a retry on fresh data
/// (`@Retryable`); the web starter answers it with 409.
///
/// Spring (Java):
/// `org.springframework.dao.OptimisticLockingFailureException`.
class OptimisticLockingFailureException extends TransientDataAccessException {
  /// A version conflict described by [message].
  OptimisticLockingFailureException(super.message, {super.cause, super.sql});
}

/// A pessimistic lock (`@Lock`, `select ... for update`) failed.
///
/// Spring (Java):
/// `org.springframework.dao.PessimisticLockingFailureException`.
class PessimisticLockingFailureException extends TransientDataAccessException {
  /// A lock failure described by [message].
  PessimisticLockingFailureException(super.message, {super.cause, super.sql});
}

/// A lock could not be had in time (`nowait`, a lock timeout).
///
/// Spring (Java): `org.springframework.dao.CannotAcquireLockException`.
class CannotAcquireLockException extends PessimisticLockingFailureException {
  /// A lock not had, described by [message].
  CannotAcquireLockException(super.message, {super.cause, super.sql});
}

/// The store chose this transaction as the loser of a deadlock and rolled
/// it back.
///
/// Spring (Java):
/// `org.springframework.dao.DeadlockLoserDataAccessException`.
class DeadlockLoserDataAccessException
    extends PessimisticLockingFailureException {
  /// A lost deadlock described by [message].
  DeadlockLoserDataAccessException(super.message, {super.cause, super.sql});
}

/// A serializable transaction conflicted with another and was rolled back.
///
/// Spring (Java):
/// `org.springframework.dao.CannotSerializeTransactionException`.
class CannotSerializeTransactionException
    extends PessimisticLockingFailureException {
  /// A serialization conflict described by [message].
  CannotSerializeTransactionException(super.message, {super.cause, super.sql});
}

/// A statement ran past its timeout and was cancelled.
///
/// Spring (Java): `org.springframework.dao.QueryTimeoutException`.
class QueryTimeoutException extends TransientDataAccessException {
  /// A timeout described by [message].
  QueryTimeoutException(super.message, {super.cause, super.sql});
}
