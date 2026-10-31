import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/fake_jdbc.dart';

void main() {
  late FakeJdbcDriver driver;

  setUpAll(() => SpringLog.level = SpringLogLevel.off);
  setUp(() => driver = FakeJdbcDriver());

  Matcher cannotGet([String? text]) => throwsA(
    isA<CannotGetJdbcConnectionException>().having(
      (e) => e.message,
      'message',
      contains(text ?? ''),
    ),
  );

  test('opens on demand and reuses released connections', () async {
    final pool = fakePool(driver);
    final a = await pool.getConnection();
    await pool.releaseConnection(a);
    final b = await pool.getConnection();
    expect(b, same(a));
    expect(driver.connections, hasLength(1));
    expect(pool.activeCount, 1);
    await pool.releaseConnection(b);
    expect(pool.idleCount, 1);
    expect(pool.totalCount, 1);
  });

  test(
    'never more than max-size connections; the next one waits, FIFO',
    () async {
      final pool = fakePool(driver, pool: const PoolSettings(maxSize: 2));
      final a = await pool.getConnection();
      final b = await pool.getConnection();
      final order = <String>[];
      final first = pool.getConnection().then((c) {
        order.add('first');
        return c;
      });
      final second = pool.getConnection().then((c) {
        order.add('second');
        return c;
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(pool.waitingCount, 2);
      expect(order, isEmpty);

      await pool.releaseConnection(a);
      final got1 = await first;
      expect(got1, same(a));
      expect(order, ['first']);
      await pool.releaseConnection(b);
      final got2 = await second;
      expect(got2, same(b));
      expect(order, ['first', 'second']);
      expect(driver.connections, hasLength(2));
    },
  );

  test('a wait past connection-timeout is a CannotGetJdbcConnection', () async {
    final pool = fakePool(
      driver,
      pool: const PoolSettings(
        maxSize: 1,
        connectionTimeout: Duration(milliseconds: 30),
      ),
    );
    await pool.getConnection();
    final watch = Stopwatch()..start();
    await expectLater(pool.getConnection(), cannotGet('timed out after 30 ms'));
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(25));
    expect(pool.waitingCount, 0);
  });

  test('a timed out waiter is not served later', () async {
    final pool = fakePool(
      driver,
      pool: const PoolSettings(
        maxSize: 1,
        connectionTimeout: Duration(milliseconds: 20),
      ),
    );
    final a = await pool.getConnection();
    await expectLater(pool.getConnection(), cannotGet());
    await pool.releaseConnection(a);
    expect(pool.idleCount, 1);
    expect(pool.activeCount, 0);
  });

  test('a broken connection is dropped and its place reused', () async {
    final pool = fakePool(driver, pool: const PoolSettings(maxSize: 1));
    final a = await pool.getConnection();
    final waiting = pool.getConnection();
    await Future<void>.delayed(const Duration(milliseconds: 2));
    (a as FakeJdbcConnection).breakNow();
    await pool.releaseConnection(a);
    final b = await waiting;
    expect(b, isNot(same(a)));
    expect(driver.connections, hasLength(2));
    expect(pool.totalCount, 1);
  });

  test('a broken idle connection is dropped at the next take', () async {
    final pool = fakePool(driver);
    final a = await pool.getConnection();
    await pool.releaseConnection(a);
    (a as FakeJdbcConnection).breakNow();
    final b = await pool.getConnection();
    expect(b, isNot(same(a)));
    expect(pool.totalCount, 1);
  });

  test('validation: an invalid idle connection is replaced', () async {
    final pool = fakePool(driver);
    final a = await pool.getConnection();
    await pool.releaseConnection(a);
    (a as FakeJdbcConnection).valid = false;
    final b = await pool.getConnection();
    expect(b, isNot(same(a)));
    expect(a.calls, contains('isValid'));
    expect(a.isClosed, isTrue);
  });

  test('validation off: no isValid', () async {
    final pool = fakePool(driver, pool: const PoolSettings(validation: false));
    final a = await pool.getConnection();
    await pool.releaseConnection(a);
    final b = await pool.getConnection();
    expect(b, same(a));
    expect((a as FakeJdbcConnection).calls, isNot(contains('isValid')));
  });

  test('a fresh connection is not validated', () async {
    final pool = fakePool(driver);
    final a = await pool.getConnection();
    expect((a as FakeJdbcConnection).calls, isEmpty);
  });

  test(
    'a connect error is a CannotGetJdbcConnection without leaking a slot',
    () async {
      final pool = fakePool(driver, pool: const PoolSettings(maxSize: 1));
      driver.connectError = const SqlError('refused', connectionLost: true);
      await expectLater(pool.getConnection(), cannotGet('refused'));
      expect(pool.totalCount, 0);
      driver.connectError = null;
      expect(await pool.getConnection(), isNotNull);
    },
  );

  test('a slow connect is bounded by the connection timeout', () async {
    final pool = fakePool(
      driver,
      pool: const PoolSettings(connectionTimeout: Duration(milliseconds: 20)),
    );
    final gate = Completer<void>();
    driver.connectGate = gate.future;
    await expectLater(pool.getConnection(), cannotGet('timed out'));
    expect(pool.totalCount, 0);
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    // The late connection was closed, not leaked.
    expect(driver.connections.single.isClosed, isTrue);
  });

  test('max-lifetime: an old connection is closed when released', () async {
    final pool = fakePool(
      driver,
      pool: const PoolSettings(maxLifetime: Duration(milliseconds: 10)),
    );
    final a = await pool.getConnection();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pool.releaseConnection(a);
    expect(a.isClosed, isTrue);
    expect(pool.totalCount, 0);
  });

  test('idle-timeout: idle connections above min-idle are closed', () async {
    final pool = fakePool(
      driver,
      pool: const PoolSettings(idleTimeout: Duration(milliseconds: 10)),
    );
    final a = await pool.getConnection();
    final b = await pool.getConnection();
    await pool.releaseConnection(a);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pool.releaseConnection(b);
    expect(a.isClosed, isTrue);
    expect(pool.idleCount, 1);
  });

  test('min-idle opens connections when the pool starts', () async {
    final pool = fakePool(driver, pool: const PoolSettings(minIdle: 2));
    await pool.start();
    expect(driver.connections, hasLength(2));
    expect(pool.idleCount, 2);
  });

  test(
    'close: closes idle connections, fails waiters, refuses new ones',
    () async {
      final pool = fakePool(driver, pool: const PoolSettings(maxSize: 1));
      final a = await pool.getConnection();
      final waiting = pool.getConnection();
      final failed = expectLater(waiting, cannotGet('closed'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await pool.close();
      await failed;
      await pool.releaseConnection(a);
      expect(a.isClosed, isTrue);
      await expectLater(pool.getConnection(), cannotGet('closed'));
      await pool.close();
    },
  );

  test('releasing twice or a foreign connection does nothing', () async {
    final pool = fakePool(driver);
    final a = await pool.getConnection();
    await pool.releaseConnection(a);
    await pool.releaseConnection(a);
    expect(pool.idleCount, 1);
    await pool.releaseConnection(FakeJdbcConnection(99));
    expect(pool.idleCount, 1);
  });

  test(
    'logs start and stop at info with the URL without its password',
    () async {
      SpringLog.level = SpringLogLevel.info;
      addTearDown(() => SpringLog.level = SpringLogLevel.off);
      final hold = SpringLog.hold();
      final pool = fakePool(driver);
      await (await pool.getConnection()).close();
      await pool.close();
      final records = hold.release();
      final text = records.map((r) => r.message).join('\n');
      expect(text, contains('shop - Starting...'));
      expect(text, contains('shop - Shutdown completed'));
      expect(text, contains('fake://admin@db:5432/shop'));
      expect(text, isNot(contains('hunter2')));
      expect(
        records.map((r) => r.loggerName).toSet(),
        {'spring.jdbc.datasource.PooledDataSource'},
      );
      expect(
        records.every((r) => r.level == SpringLogLevel.info),
        isTrue,
      );
    },
  );

  test('driver data source opens and closes each time', () async {
    final source = DriverDataSource(
      name: 'plain',
      driver: driver,
      settings: secretSettings,
    );
    final a = await source.getConnection();
    await source.releaseConnection(a);
    expect(a.isClosed, isTrue);
    driver.connectError = const SqlError('down');
    await expectLater(source.getConnection(), cannotGet('down'));
  });
}
