import 'package:spring_boot_dart/spring_boot_dart.dart';

/// What a Cloudflare Worker is bound to (`wrangler.toml`): KV namespaces
/// and D1 databases, by the names of their bindings (the bean
/// `cloudflareBindings`, in a Worker only).
///
/// ```toml
/// [[kv_namespaces]]
/// binding = "SETTINGS"
/// id = "..."
///
/// [[d1_databases]]
/// binding = "DB"
/// database_name = "shop"
/// database_id = "..."
/// ```
///
/// ```dart
/// @Service()
/// class Settings {
///   Settings(this.bindings);
///   final CloudflareBindings bindings;
///
///   Future<String?> theme() => bindings.kv('SETTINGS').get('theme');
///
///   Future<List<Map<String, Object?>>> orders(String user) => bindings
///       .d1('DB')
///       .query('select id, total from orders where user = ?1', [user]);
/// }
/// ```
///
/// The bindings arrive with the Worker's first request: use them while a
/// request (or a scheduled event) is handled, not in a constructor.
abstract interface class CloudflareBindings {
  /// Whether the Worker has a binding named [binding].
  bool has(String binding);

  /// Whether the Worker's environment is there: the platform gives it
  /// with a request (or a scheduled run), so before the first one no
  /// binding can be told from a missing one.
  bool get loaded;

  /// The KV namespace bound as [binding]. Throws a [StateError] when the
  /// Worker has no such binding.
  KvNamespace kv(String binding);

  /// The D1 database bound as [binding]. Throws a [StateError] when the
  /// Worker has no such binding.
  D1Database d1(String binding);
}

/// A Workers KV namespace: text values by key, read everywhere, written
/// with a delay of up to a minute between locations (no counters in it).
abstract interface class KvNamespace {
  /// The value of [key], or `null`.
  Future<String?> get(String key);

  /// Stores [value] under [key]; with [expirationTtl] (at least a minute)
  /// it is gone after that long.
  Future<void> put(String key, String value, {Duration? expirationTtl});

  /// Removes [key].
  Future<void> delete(String key);

  /// The keys, those starting with [prefix] when given (the first
  /// thousand).
  Future<List<String>> keys({String? prefix});
}

/// A D1 database (SQLite). Parameters are positional: `?1`, `?2`.
abstract interface class D1Database {
  /// The rows of a statement that returns some, a map by column name.
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]);

  /// Runs a statement that returns none; gives how many rows it changed.
  Future<int> execute(String sql, [List<Object?> parameters = const []]);
}

/// The buckets of the rate limiter in a D1 database: the shared
/// [RateLimitStore] of a Cloudflare Worker
/// (`spring.edge.cloudflare.rate-limit.database`, the name of the
/// binding). Every instance of the Worker counts in the same table, so a
/// limit is one limit.
///
/// An acquisition is one statement (`insert ... on conflict do update ...
/// returning`), atomic in the database and on its clock: the statement of
/// the data starter's SQLite store. The table ([table], `rate_limit` by
/// default) is created before the first statement.
final class D1RateLimitStore implements VerifiableRateLimitStore {
  /// A store in the database [database] gives when it is first asked.
  D1RateLimitStore(
    this.database, {
    this.table = 'rate_limit',
    this.environmentLoaded,
  }) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(table)) {
      throw ArgumentError.value(table, 'table', 'Not the name of a table');
    }
  }

  /// Gives the database: the bindings exist only once a request arrived.
  final D1Database Function() database;

  /// The table of the buckets.
  final String table;

  /// Whether the Worker's environment is there (`CloudflareBindings.loaded`):
  /// [verify] asks nothing before it is. Not given: it is.
  final bool Function()? environmentLoaded;

  Future<void>? _created;

  // Seconds since 1970 with milliseconds.
  static const _now = "((julianday('now') - 2440587.5) * 86400.0)";

  Future<void> _create(D1Database db) async {
    await db.execute('''
create table if not exists $table (
  key text primary key,
  tokens real not null,
  allowed integer not null,
  updated_at real not null,
  expires_at real not null
) without rowid''');
    await db.execute(
      'create index if not exists ${table}_expires_at on $table (expires_at)',
    );
    // Buckets that are full again.
    await db.execute('delete from $table where expires_at < $_now');
  }

  /// Asks for the database and creates the table. A binding the Worker
  /// does not have is a [RateLimitStoreSetupException]; a database that
  /// does not answer is thrown as it is. Before the Worker's environment
  /// is there (a start without a request) nothing can be asked: the first
  /// acquisition then finds out.
  @override
  Future<void> verify() async {
    if (!(environmentLoaded?.call() ?? true)) {
      return;
    }
    final D1Database db;
    try {
      db = database();
    } on StateError catch (error) {
      throw RateLimitStoreSetupException(
        'The rate limiter has no D1 database (${error.message}). Declare '
        'the binding of spring.edge.cloudflare.rate-limit.database under '
        '[[d1_databases]] in wrangler.toml; the store creates its table '
        'itself',
      );
    }
    try {
      await (_created ??= _create(db));
    } on Object {
      _created = null;
      rethrow;
    }
  }

  @override
  Future<RateLimitDecision> tryAcquire(
    String key,
    RateLimit limit, {
    int permits = 1,
  }) async {
    final db = database();
    try {
      await (_created ??= _create(db));
    } on Object {
      _created = null;
      rethrow;
    }
    const capacity = 'cast(?2 as real)';
    const refill = 'cast(?3 as real)';
    const wanted = 'cast(?4 as real)';
    const filled =
        'min($capacity, b.tokens + '
        'max(0, excluded.updated_at - b.updated_at) * $refill)';
    final rows = await db.query(
      '''
insert into $table as b (key, tokens, allowed, updated_at, expires_at)
values (
  ?1,
  case when $wanted <= $capacity then $capacity - $wanted else $capacity end,
  $wanted <= $capacity,
  $_now,
  $_now + $capacity / $refill
)
on conflict (key) do update set
  tokens = case when $filled >= $wanted
    then $filled - $wanted
    else $filled end,
  allowed = $filled >= $wanted,
  updated_at = max(b.updated_at, excluded.updated_at),
  expires_at = excluded.expires_at
returning allowed, tokens''',
      [key, limit.capacity, limit.refillPerSecond, permits],
    );
    if (rows case [
      {'allowed': final Object? flag, 'tokens': final num tokens},
    ]) {
      final allowed = flag == true || flag == 1;
      return RateLimitDecision(
        allowed: allowed,
        remaining: tokens.floor(),
        retryAfter: allowed
            ? Duration.zero
            : Duration(
                microseconds:
                    ((permits - tokens) /
                            limit.refillPerSecond *
                            Duration.microsecondsPerSecond)
                        .ceil(),
              ),
      );
    }
    throw StateError('The rate limit statement did not answer: $rows');
  }
}
