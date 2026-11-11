import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';

const _log = SpringLog('spring.data.ratelimit');

/// The SQL of the rate limiter's table for one kind of database: the
/// extension point of [JdbcRateLimitStore].
///
/// The store asks its statements in order ([supports]); the first that
/// knows the data source's dialect is used. The application's beans come
/// first, then the built-in ones ([PostgresRateLimitStatements],
/// [SqliteRateLimitStatements]).
///
/// [acquire] is one statement that does everything: it fills the bucket
/// of the key for the time that passed on the database's clock, takes
/// the permits when they are there, writes the bucket and returns
/// `allowed` and `tokens`. The database makes it atomic: two servers on
/// one database never both get the last permit. It names its values
/// `:key`, `:capacity`, `:refill` (permits a second) and `:permits`.
///
/// ```dart
/// // The same for a database the starter has no statements for.
/// @Component()
/// class H2RateLimitStatements implements RateLimitStatements {
///   @override
///   bool supports(SqlDialect dialect) => dialect.name == 'h2';
///   ...
/// }
/// ```
abstract interface class RateLimitStatements {
  /// Whether these are the statements of [dialect].
  bool supports(SqlDialect dialect);

  /// The statements that create [table] and its index when they are not
  /// there.
  List<String> createTable(String table);

  /// The one statement of an acquisition, with `:key`, `:capacity`,
  /// `:refill` and `:permits`; it returns one row, `allowed` and
  /// `tokens` (what is left).
  String acquire(String table);

  /// Deletes the buckets of [table] that are full again (a key without a
  /// row has a full bucket).
  String purge(String table);
}

// The upsert both built-in databases run; they differ in the clock, the
// names of min and max, and the cast of a value.
String _upsert(
  String table, {
  required String now,
  required String least,
  required String greatest,
  required String Function(String name) number,
}) {
  final capacity = number(':capacity');
  final refill = number(':refill');
  final permits = number(':permits');
  final filled =
      '$least($capacity, b.tokens + '
      '$greatest(0, excluded.updated_at - b.updated_at) * $refill)';
  return '''
insert into $table as b (key, tokens, allowed, updated_at, expires_at)
values (
  :key,
  case when $permits <= $capacity then $capacity - $permits else $capacity end,
  $permits <= $capacity,
  $now,
  $now + $capacity / $refill
)
on conflict (key) do update set
  tokens = case when $filled >= $permits
    then $filled - $permits
    else $filled end,
  allowed = $filled >= $permits,
  updated_at = $greatest(b.updated_at, excluded.updated_at),
  expires_at = excluded.expires_at
returning allowed, tokens''';
}

/// The rate limiter's SQL for PostgreSQL: an `unlogged` table (a bucket
/// lost in a crash is a full bucket, and nothing is written to the WAL)
/// and one `insert ... on conflict do update ... returning`, on the
/// server's `clock_timestamp()`.
///
/// ```sql
/// create unlogged table if not exists rate_limit (
///   key text primary key,
///   tokens double precision not null,
///   allowed boolean not null,
///   updated_at double precision not null,
///   expires_at double precision not null
/// );
/// create index if not exists rate_limit_expires_at
///   on rate_limit (expires_at);
/// ```
///
/// The times are seconds since 1970. The file
/// `package:spring_boot_starter_data/sql/rate_limit/postgresql.sql` holds
/// the same, to copy into the application's migrations.
final class PostgresRateLimitStatements implements RateLimitStatements {
  /// The statements.
  const PostgresRateLimitStatements();

  static const _now = 'extract(epoch from clock_timestamp())::double precision';

  @override
  bool supports(SqlDialect dialect) => dialect.name == 'postgresql';

  @override
  List<String> createTable(String table) => [
    '''
create unlogged table if not exists $table (
  key text primary key,
  tokens double precision not null,
  allowed boolean not null,
  updated_at double precision not null,
  expires_at double precision not null
)''',
    '''
create index if not exists ${_indexName(table)}
  on $table (expires_at)''',
  ];

  @override
  String acquire(String table) => _upsert(
    table,
    now: _now,
    least: 'least',
    greatest: 'greatest',
    number: (name) => 'cast($name as double precision)',
  );

  @override
  String purge(String table) => 'delete from $table where expires_at < $_now';
}

/// The rate limiter's SQL for SQLite: the same single statement
/// (`insert ... on conflict do update ... returning`, SQLite 3.35 or
/// later), on the database's clock. SQLite runs one writer at a time, so
/// the statement is atomic across the connections of a file.
///
/// ```sql
/// create table if not exists rate_limit (
///   key text primary key,
///   tokens real not null,
///   allowed integer not null,
///   updated_at real not null,
///   expires_at real not null
/// ) without rowid;
/// create index if not exists rate_limit_expires_at
///   on rate_limit (expires_at);
/// ```
///
/// The file `package:spring_boot_starter_data/sql/rate_limit/sqlite.sql`
/// holds the same.
final class SqliteRateLimitStatements implements RateLimitStatements {
  /// The statements.
  const SqliteRateLimitStatements();

  // Seconds since 1970 with milliseconds, on every version of SQLite.
  static const _now = "((julianday('now') - 2440587.5) * 86400.0)";

  @override
  bool supports(SqlDialect dialect) => dialect.name == 'sqlite';

  @override
  List<String> createTable(String table) => [
    '''
create table if not exists $table (
  key text primary key,
  tokens real not null,
  allowed integer not null,
  updated_at real not null,
  expires_at real not null
) without rowid''',
    '''
create index if not exists ${_indexName(table)}
  on $table (expires_at)''',
  ];

  @override
  String acquire(String table) => _upsert(
    table,
    now: _now,
    least: 'min',
    greatest: 'max',
    number: (name) => 'cast($name as real)',
  );

  @override
  String purge(String table) => 'delete from $table where expires_at < $_now';
}

String _indexName(String table) => '${table.replaceAll('.', '_')}_expires_at';

/// The buckets of the rate limiter in a table of the application's
/// database: the [RateLimitStore] of an application with a primary
/// `DataSource` (`spring.web.rate-limit.store: jdbc`). Every server on
/// that database shares the limits, and they outlive a restart.
///
/// An acquisition is one statement ([RateLimitStatements.acquire]) on a
/// connection of its own, outside any transaction of the request: a
/// rolled-back order has still been counted. The arithmetic runs in the
/// database, on its clock.
///
/// The table is [table] (`spring.data.jdbc.rate-limit.table`, default
/// `rate_limit`). With [createTable] the store creates it before its
/// first statement (`spring.data.jdbc.rate-limit.create-table`; by
/// default when `spring.data.jdbc.schema` is `create` or `create-drop`);
/// else it must exist: copy
/// `package:spring_boot_starter_data/sql/rate_limit/<database>.sql` into
/// the migrations. Rows of buckets that are full again are deleted at
/// most every [purgeInterval].
///
/// ```dart
/// final store = JdbcRateLimitStore(dataSource, createTable: true);
/// final decision = await store.tryAcquire('login:ip:203.0.113.7', limit);
/// ```
///
/// Spring (Java): Bucket4j's `PostgreSQLadvisoryLockBasedProxyManager`
/// and Spring Cloud Gateway's `RedisRateLimiter` (a Lua script) keep
/// shared buckets the same way: one atomic step in the store.
final class JdbcRateLimitStore implements VerifiableRateLimitStore {
  /// A store over [dataSource]; [statements] come before the built-in
  /// ones. Throws an [ArgumentError] when [table] is no table name and a
  /// [StateError] when no statements know the database.
  JdbcRateLimitStore(
    this.dataSource, {
    this.table = 'rate_limit',
    this.createTable = false,
    this.purgeInterval = const Duration(minutes: 1),
    List<RateLimitStatements> statements = const [],
  }) : statements = _statementsOf(dataSource, statements) {
    if (!_tableName.hasMatch(table)) {
      throw ArgumentError.value(
        table,
        'table',
        'The rate limit table is a name, or schema.name',
      );
    }
    final (sql, names) = _positional(this.statements.acquire(table));
    _acquire = sql;
    _parameters = names;
  }

  static final _tableName = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$',
  );

  static RateLimitStatements _statementsOf(
    DataSource dataSource,
    List<RateLimitStatements> statements,
  ) =>
      [
        ...statements,
        const PostgresRateLimitStatements(),
        const SqliteRateLimitStatements(),
      ].where((s) => s.supports(dataSource.dialect)).firstOrNull ??
      (throw StateError(
        'The rate limit store has no SQL for ${dataSource.dialect.name}: '
        'declare a RateLimitStatements bean, or set '
        'spring.web.rate-limit.store to another store',
      ));

  // `:name` to `?`, and the names in the order of the `?`.
  static (String, List<String>) _positional(String sql) {
    final names = <String>[];
    final text = sql.replaceAllMapped(
      RegExp(r'(?<!:):(key|capacity|refill|permits)\b'),
      (match) {
        names.add(match[1]!);
        return '?';
      },
    );
    return (text, names);
  }

  /// The database of the table.
  final DataSource dataSource;

  /// The table of the buckets.
  final String table;

  /// Whether the store creates the table when it is not there.
  final bool createTable;

  /// The least time between two deletions of the rows that are full
  /// again.
  final Duration purgeInterval;

  /// The SQL of the database.
  final RateLimitStatements statements;

  late final String _acquire;
  late final List<String> _parameters;
  Future<void>? _ready;
  final _sincePurge = Stopwatch()..start();

  Future<void> _prepare() async {
    if (!createTable) {
      return;
    }
    await _with((connection) async {
      for (final statement in statements.createTable(table)) {
        await connection.execute(statement);
      }
    });
    _log.debug(() => 'The rate limit table $table is there');
  }

  Future<T> _with<T>(Future<T> Function(JdbcConnection connection) work) async {
    final connection = await dataSource.getConnection();
    try {
      return await work(connection);
    } finally {
      await dataSource.releaseConnection(connection);
    }
  }

  /// Creates the table when [createTable] says so, then asks the database
  /// for it: a table that is not there is a
  /// [RateLimitStoreSetupException] with the migration to run. A database
  /// that gives no connection is thrown as it is.
  @override
  Future<void> verify() async {
    final connection = await dataSource.getConnection();
    try {
      if (createTable) {
        await (_ready ??= _prepare());
      }
      try {
        await connection.query('select 1 from $table where 1 = 0');
      } on Object catch (error) {
        throw RateLimitStoreSetupException(
          'The rate limit table $table cannot be read ($error). Create it '
          'with a migration (sql/rate_limit/postgresql.sql or '
          'sql/rate_limit/sqlite.sql of spring_boot_starter_data), set '
          'spring.data.jdbc.rate-limit.create-table=true for the store to '
          'create it, or name the table with '
          'spring.data.jdbc.rate-limit.table',
        );
      }
    } finally {
      await dataSource.releaseConnection(connection);
    }
  }

  @override
  Future<RateLimitDecision> tryAcquire(
    String key,
    RateLimit limit, {
    int permits = 1,
  }) async {
    try {
      await (_ready ??= _prepare());
    } on Object {
      // The next acquisition tries again.
      _ready = null;
      rethrow;
    }
    final refill = limit.refillPerSecond;
    final values = <String, Object>{
      'key': key,
      'capacity': limit.capacity.toDouble(),
      'refill': refill,
      'permits': permits.toDouble(),
    };
    final result = await _with<JdbcResult>(
      (connection) => connection.query(_acquire, [
        for (final name in _parameters) values[name],
      ]),
    );
    final row = result.rows.single;
    final allowed = switch (row['allowed']) {
      final bool value => value,
      final num value => value != 0,
      final other => throw StateError('allowed is $other'),
    };
    final tokens = (row['tokens']! as num).toDouble();
    _purgeSometimes();
    return RateLimitDecision(
      allowed: allowed,
      remaining: tokens.floor(),
      retryAfter: allowed
          ? Duration.zero
          : Duration(microseconds: ((permits - tokens) / refill * 1e6).ceil()),
    );
  }

  void _purgeSometimes() {
    if (_sincePurge.elapsed < purgeInterval) {
      return;
    }
    _sincePurge.reset();
    unawaited(
      purge().then<void>(
        (_) {},
        onError: (Object error) => _log.debug(
          () => 'The rate limit table was not purged: ${error.runtimeType}',
        ),
      ),
    );
  }

  /// Deletes the rows of buckets that are full again; returns how many.
  /// The store does it by itself every [purgeInterval].
  Future<int> purge() => _with(
    (connection) async =>
        (await connection.update(statements.purge(table))).affectedRows,
  );
}
