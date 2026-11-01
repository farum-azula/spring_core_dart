// How the outcomes of the Spring reference and of the starter are compared,
// and where they deliberately differ. Used by the differential test and by
// the PostgreSQL suite (which asserts the starter's side of each difference).

/// Exception classes of Spring's side written as the starter names the same
/// condition, with the reason. Both name the same SQLSTATE: Spring 7's
/// `JdbcTemplate` translates by the SQL state alone
/// (`SQLExceptionSubclassTranslator`), the starter by the finer classes of
/// Spring's PostgreSQL error-code table
/// (`org/springframework/jdbc/support/sql-error-codes.xml`, the table
/// Spring's `JdbcTemplate` used up to 6): all of them are the same
/// supertypes (`ConcurrencyFailureException`,
/// `PessimisticLockingFailureException`) for the code that retries.
const equivalentKinds = <String, String>{
  'CannotAcquireLockException[40001]':
      'CannotSerializeTransactionException[40001]',
  'PessimisticLockingFailureException[40P01]':
      'DeadlockLoserDataAccessException[40P01]',
  'UncategorizedSQLException[55P03]': 'CannotAcquireLockException[55P03]',
  // Spring does not classify a write in a read-only transaction.
  'UncategorizedSQLException[25006]':
      'InvalidDataAccessResourceUsageException[25006]',
};

/// [value] (a value of an outcome) with Spring's exception classes
/// replaced by the starter's ([equivalentKinds]).
Object? normalizeSpring(Object? value) => switch (value) {
  final String text when text.startsWith('!') =>
    '!${equivalentKinds[text.substring(1)] ?? text.substring(1)}',
  final List<Object?> list => [for (final item in list) normalizeSpring(item)],
  final Map<String, Object?> map => {
    for (final entry in map.entries) entry.key: normalizeSpring(entry.value),
  },
  _ => value,
};

/// A deliberate difference between the starter and Spring.
final class KnownDifference {
  const KnownDifference(this.reason, {required this.starter});

  final String reason;

  /// The starter's outcome (Spring's is in `expectedOutcomes`).
  final Map<String, Object?> starter;
}

/// The scenarios where the starter differs from Spring on purpose.
const knownDifferences = <String, KnownDifference>{
  'rules/checked-exception': KnownDifference(
    'Dart has no checked exceptions: every exception rolls back unless '
    'noRollbackFor lists it (Spring commits after a checked one)',
    starter: {'outer': 'Checked', 'rows': <String>[]},
  ),
  'rules/noRollbackFor-closer-than-rollbackFor': KnownDifference(
    'when an exception matches both rollbackFor and noRollbackFor, '
    'rollbackFor wins (Spring: the entry closest to the exception class '
    'wins); Dart cannot rank two types without reflection',
    starter: {'outer': 'Hard', 'rows': <String>[]},
  ),
  'lock/outside-a-transaction': KnownDifference(
    'a @Lock query outside a transaction never runs unlocked: it fails '
    '(Spring runs it in autocommit, so the lock is gone at once)',
    starter: {'result': '!IllegalTransactionStateException'},
  ),
};
