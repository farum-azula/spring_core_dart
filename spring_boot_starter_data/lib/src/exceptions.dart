import 'package:spring_boot_dart/spring_boot_dart.dart' show LogFormatUtils;

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

/// An argument VALUE the caller gave cannot be used by the database: a text
/// with a NUL character, a list longer than a statement binds, a `LIKE`
/// pattern the database rejects.
///
/// It is the caller's input (often from a request), not a mistake of the
/// developer, which is what the other
/// [InvalidDataAccessApiUsageException]s signal. The message and the SQL
/// never contain the value. The web glue answers it with a 400 and the
/// fixed detail `Invalid request value`.
///
/// Spring (Java): none; Spring's drivers fail with a `PSQLException`
/// that becomes a `DataIntegrityViolationException` or
/// `InvalidDataAccessApiUsageException`.
class InvalidDataArgumentException extends InvalidDataAccessApiUsageException {
  /// A refused argument value described by [message] (without the value).
  InvalidDataArgumentException(super.message, {super.cause, super.sql});
}

/// A sort asked for a property the entity does not have (or, for a `@Query`,
/// a name that is no column or property).
///
/// Often the property comes from a request (`?sort=title,desc`): the
/// message writes the name with [LogFormatUtils.formatValue] (quoted, line
/// breaks and control characters replaced, cut when long), so it cannot
/// forge a log line; [propertyName] keeps the name as it was given. The web
/// glue answers it with a 400 and a fixed detail.
///
/// Spring (Java): `org.springframework.data.mapping.PropertyReferenceException`
/// (Spring's repositories translate it to
/// `InvalidDataAccessApiUsageException`).
class PropertyReferenceException extends InvalidDataAccessApiUsageException {
  /// A refused sort [propertyName] of [typeName]; [hint] says what is
  /// accepted.
  PropertyReferenceException(
    this.propertyName,
    this.typeName, {
    String? hint,
    super.cause,
  }) : super(
         'No property ${LogFormatUtils.formatValue(propertyName)} found for '
         'type $typeName${hint == null ? '' : ': $hint'}',
       );

  /// The name that was refused, as it was given (never log it as it is).
  final String propertyName;

  /// The type that was searched for it (an entity's class name, or the
  /// repository method of a `@Query`).
  final String typeName;
}

/// A request for a page or a sort that cannot be served: a negative page, a
/// size below one, an offset past what a database counts, a direction that
/// is neither `asc` nor `desc`.
///
/// An [ArgumentError], as Spring's `IllegalArgumentException` of
/// `PageRequest.of`, raised where the request is built, before any store
/// is reached; the web glue answers it with a 400 and a fixed detail.
/// [toString] writes the invalid value escaped (it may come from a request),
/// [invalidValue] has it as it was given.
///
/// Spring (Java): `IllegalArgumentException`.
class InvalidPagingRequestException extends ArgumentError {
  /// The invalid [value] of [name], and what is wrong with it.
  InvalidPagingRequestException(
    super.value,
    String super.name,
    String super.message,
  ) : super.value();

  @override
  String toString() =>
      'InvalidPagingRequestException: $message ($name: '
      '${LogFormatUtils.formatValue(invalidValue)})';
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

/// The root of the failures of concurrent access that may succeed when
/// tried again: a version conflict ([OptimisticLockingFailureException]), a
/// lock, a deadlock or a serialization failure
/// ([PessimisticLockingFailureException]). Retry code catches this type.
///
/// Spring (Java): `org.springframework.dao.ConcurrencyFailureException`.
class ConcurrencyFailureException extends TransientDataAccessException {
  /// A concurrency failure described by [message].
  ConcurrencyFailureException(super.message, {super.cause, super.sql});
}

/// A save or delete found the row changed or gone since it was loaded: its
/// `@Version` no longer matches. Worth a retry on fresh data
/// (`@Retryable`); the web starter answers it with 409.
///
/// Spring (Java):
/// `org.springframework.dao.OptimisticLockingFailureException`.
class OptimisticLockingFailureException extends ConcurrencyFailureException {
  /// A version conflict described by [message].
  OptimisticLockingFailureException(super.message, {super.cause, super.sql});
}

/// A pessimistic lock (`@Lock`, `select ... for update`) failed.
///
/// Spring (Java):
/// `org.springframework.dao.PessimisticLockingFailureException`.
class PessimisticLockingFailureException extends ConcurrencyFailureException {
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
