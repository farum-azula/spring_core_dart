// What the tests of the rate limiter's SQL store share: the same checks
// on every database.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

/// The checks every database must pass: [newSource] gives a pool over the
/// same empty database each time it is called in one test.
void rateLimitStoreContract(
  Future<DataSource> Function() newSource, {
  required String ddlFile,
}) {
  const five = RateLimit(5, Duration(hours: 1));

  Future<JdbcRateLimitStore> newStore({
    bool createTable = true,
    String table = 'rate_limit',
  }) async => JdbcRateLimitStore(
    await newSource(),
    createTable: createTable,
    table: table,
  );

  test('a burst of the capacity, then a refusal with retry-after', () async {
    final store = await newStore();
    for (var left = 4; left >= 0; left--) {
      final decision = await store.tryAcquire('k', five);
      expect(decision.allowed, isTrue);
      expect(decision.remaining, left);
      expect(decision.retryAfter, Duration.zero);
    }
    final refused = await store.tryAcquire('k', five);
    expect(refused.allowed, isFalse);
    expect(refused.remaining, 0);
    // One token every twelve minutes, less the moment that passed.
    expect(refused.retryAfter.inSeconds, inInclusiveRange(700, 720));
    // Another key has its own bucket.
    expect((await store.tryAcquire('other', five)).remaining, 4);
  });

  test('the bucket is filled again by the clock of the database', () async {
    final store = await newStore();
    const fast = RateLimit(20, Duration(seconds: 1), burst: 2);
    expect((await store.tryAcquire('k', fast)).allowed, isTrue);
    expect((await store.tryAcquire('k', fast)).allowed, isTrue);
    final refused = await store.tryAcquire('k', fast);
    expect(refused.allowed, isFalse);
    expect(refused.retryAfter.inMilliseconds, inInclusiveRange(1, 50));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Never more than the burst, however long the pause.
    expect((await store.tryAcquire('k', fast)).remaining, 1);
    expect((await store.tryAcquire('k', fast)).allowed, isTrue);
    expect((await store.tryAcquire('k', fast)).allowed, isFalse);
  });

  test('several permits at once, and more than the bucket holds', () async {
    final store = await newStore();
    expect((await store.tryAcquire('k', five, permits: 3)).remaining, 2);
    final refused = await store.tryAcquire('k', five, permits: 3);
    expect(refused.allowed, isFalse);
    expect(refused.remaining, 2);
    expect((await store.tryAcquire('k', five, permits: 2)).remaining, 0);
    final never = await store.tryAcquire('new', five, permits: 6);
    expect(never.allowed, isFalse);
    expect(never.remaining, 5);
  });

  test('100 acquisitions at once never pass the limit', () async {
    final store = await newStore();
    const ten = RateLimit(10, Duration(hours: 1));
    final decisions = await Future.wait([
      for (var i = 0; i < 100; i++) store.tryAcquire('k', ten),
    ]);
    expect(decisions.where((d) => d.allowed), hasLength(10));
    expect(
      decisions.where((d) => d.allowed).map((d) => d.remaining).toSet(),
      {for (var i = 0; i < 10; i++) i},
    );
  });

  test('two servers on one database share the limit', () async {
    final first = await newStore();
    final second = await newStore();
    // The table is there before both count at once.
    await first.tryAcquire('warm-up', five);
    const ten = RateLimit(10, Duration(hours: 1));
    final decisions = await Future.wait([
      for (var i = 0; i < 100; i++)
        (i.isEven ? first : second).tryAcquire('k', ten),
    ]);
    expect(decisions.where((d) => d.allowed), hasLength(10));
  });

  test('the rows of full buckets are purged', () async {
    final store = await newStore();
    const fast = RateLimit(100, Duration(seconds: 1), burst: 1);
    await store.tryAcquire('short', fast);
    await store.tryAcquire('long', five);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await store.purge(), 1);
    expect(await store.purge(), 0);
    // The purged key starts with a full bucket, as it would have anyway.
    expect((await store.tryAcquire('short', fast)).allowed, isTrue);
    expect((await store.tryAcquire('long', five)).remaining, 3);
  });

  test('without the table the store fails, until the shipped SQL made '
      'it', () async {
    final source = await newSource();
    final store = JdbcRateLimitStore(source);
    await expectLater(store.tryAcquire('k', five), throwsA(anything));
    final connection = await source.getConnection();
    try {
      await connection.execute(ddlFile);
    } finally {
      await source.releaseConnection(connection);
    }
    expect((await store.tryAcquire('k', five)).remaining, 4);
    // What the file holds is what the store would create.
    String squeezed(String sql) => sql
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    expect(
      squeezed(ddlFile),
      squeezed(
        store.statements.createTable('rate_limit').map((s) => '$s;').join('\n'),
      ),
    );
  });

  test('a table of another name', () async {
    final store = await newStore(table: 'limits_of_the_api');
    expect((await store.tryAcquire('k', five)).remaining, 4);
    expect((await store.tryAcquire('k', five)).remaining, 3);
  });
}
