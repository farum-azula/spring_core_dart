import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import '../../jdbc/support/fake_jdbc.dart';

/// A dialect with row locks and a case sensitive `LIKE`, like PostgreSQL's,
/// for the tests that need what SQLite cannot give.
class RowLockDialect extends FakeDialect {
  RowLockDialect() : super();

  @override
  String get name => 'rowlocks';

  @override
  String lockClause(
    LockMode mode, {
    Duration? timeout,
    bool skipLocked = false,
  }) => [
    'FOR',
    if (mode == LockMode.pessimisticWrite) 'UPDATE' else 'SHARE',
    if (timeout == Duration.zero) 'NOWAIT',
    if (skipLocked) 'SKIP LOCKED',
  ].join(' ');

  @override
  String? lockTimeoutStatement(Duration timeout) =>
      "SET LOCAL lock_timeout = '${timeout.inMilliseconds}ms'";

  @override
  String limitOffset(int? limit, int? offset) => [
    if (limit != null) 'LIMIT $limit',
    if (offset != null) 'OFFSET $offset',
  ].join(' ');
}
