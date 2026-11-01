import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/fake_jdbc.dart';

void main() {
  late FakeJdbcDriver driver;
  late PooledDataSource ds;
  late DataSourceTransactionManager manager;
  late TransactionTemplate template;
  late JdbcTemplate jdbc;

  void build({
    PoolSettings pool = const PoolSettings(),
    SqlDialect? dialect,
  }) {
    driver = FakeJdbcDriver(dialect: dialect);
    ds = fakePool(driver, pool: pool);
    manager = DataSourceTransactionManager(ds);
    template = TransactionTemplate(manager);
    jdbc = JdbcTemplate(ds);
  }

  setUpAll(() => SpringLog.level = SpringLogLevel.off);
  setUp(build);

  List<String> callsOf(int n) => driver.connections[n - 1].calls;

  group('connections', () {
    test('inside a transaction every call uses the same connection, across '
        'awaits', () async {
      await template.execute((_) async {
        await jdbc.update('insert 1');
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await jdbc.update('insert 2');
        await Future.wait([jdbc.update('insert 3'), jdbc.update('insert 4')]);
      });
      expect(driver.connections, hasLength(1));
      expect(callsOf(1), [
        'begin',
        'update insert 1',
        'update insert 2',
        'update insert 3',
        'update insert 4',
        'commit',
      ]);
    });

    test('outside a transaction each call takes a connection and gives it '
        'back', () async {
      await jdbc.update('a');
      expect(ds.activeCount, 0);
      expect(ds.idleCount, 1);
      await Future.wait([jdbc.update('b'), jdbc.update('c')]);
      expect(driver.connections, hasLength(2));
      expect(ds.activeCount, 0);
    });

    test(
      'the connection goes back to the pool after the transaction',
      () async {
        await template.execute((_) => jdbc.update('x'));
        expect(ds.activeCount, 0);
        expect(ds.idleCount, 1);
        await jdbc.update('y');
        expect(driver.connections, hasLength(1));
      },
    );

    test('a transaction of another data source is not used', () async {
      final other = fakePool(FakeJdbcDriver(), name: 'other');
      final otherJdbc = JdbcTemplate(other);
      await template.execute((_) async {
        await jdbc.update('mine');
        await otherJdbc.update('theirs');
      });
      expect(callsOf(1), ['begin', 'update mine', 'commit']);
      expect(other.driver, isNot(same(driver)));
      expect(other.activeCount, 0);
    });

    test('notSupported suspends: a different connection', () async {
      await template.execute((_) async {
        await jdbc.update('in tx');
        await TransactionTemplate(
          manager,
          const TransactionDefinition(propagation: Propagation.notSupported),
        ).execute((_) => jdbc.update('outside'));
      });
      expect(driver.connections, hasLength(2));
      expect(callsOf(1), ['begin', 'update in tx', 'commit']);
      expect(callsOf(2), ['update outside']);
    });
  });

  group('the manager', () {
    test('commit and rollback', () async {
      await template.execute((_) => jdbc.update('ok'));
      await expectLater(
        template.execute((_) async {
          await jdbc.update('bad');
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(callsOf(1), [
        'begin',
        'update ok',
        'commit',
        'isValid',
        'begin',
        'update bad',
        'rollback',
      ]);
    });

    test('isolation and read-only reach begin', () async {
      await TransactionTemplate(
        manager,
        const TransactionDefinition(
          isolation: Isolation.serializable,
          readOnly: true,
        ),
      ).execute((_) => jdbc.update('x'));
      expect(callsOf(1).first, 'begin serializable readOnly');
    });

    test(
      'a level the dialect lacks is refused before taking a connection',
      () async {
        await expectLater(
          TransactionTemplate(
            manager,
            const TransactionDefinition(isolation: Isolation.repeatableRead),
          ).execute((_) => jdbc.update('x')),
          throwsA(isA<InvalidIsolationLevelException>()),
        );
        expect(driver.connections, isEmpty);
        expect(ds.activeCount, 0);
      },
    );

    test('required joins the running transaction', () async {
      await template.execute((_) async {
        await template.execute((_) => jdbc.update('inner'));
        await jdbc.update('outer');
      });
      expect(driver.connections, hasLength(1));
      expect(callsOf(1), [
        'begin',
        'update inner',
        'update outer',
        'commit',
      ]);
    });

    test(
      'requiresNew takes a second connection, committed on its own',
      () async {
        final requiresNew = TransactionTemplate(
          manager,
          const TransactionDefinition(propagation: Propagation.requiresNew),
        );
        await expectLater(
          template.execute((_) async {
            await jdbc.update('outer');
            await requiresNew.execute((_) => jdbc.update('inner'));
            throw StateError('outer fails');
          }),
          throwsStateError,
        );
        expect(driver.connections, hasLength(2));
        expect(callsOf(1), ['begin', 'update outer', 'rollback']);
        expect(callsOf(2), ['begin', 'update inner', 'commit']);
        expect(ds.activeCount, 0);
      },
    );

    test('nested uses savepoints named SAVEPOINT_1, SAVEPOINT_2', () async {
      final nested = TransactionTemplate(
        manager,
        const TransactionDefinition(propagation: Propagation.nested),
      );
      await template.execute((_) async {
        await nested.execute((_) => jdbc.update('n1'));
        await expectLater(
          nested.execute((_) async {
            await jdbc.update('n2');
            throw StateError('inner');
          }),
          throwsStateError,
        );
      });
      expect(callsOf(1), [
        'begin',
        'savepoint SAVEPOINT_1',
        'update n1',
        'release SAVEPOINT_1',
        'savepoint SAVEPOINT_2',
        'update n2',
        'rollbackTo SAVEPOINT_2',
        'release SAVEPOINT_2',
        'commit',
      ]);
    });

    test(
      'a participant that fails marks the transaction rollback-only',
      () async {
        await expectLater(
          template.execute((_) async {
            await expectLater(
              template.execute((_) => throw StateError('inner')),
              throwsStateError,
            );
            await jdbc.update('after');
          }),
          throwsA(isA<UnexpectedRollbackException>()),
        );
        expect(callsOf(1), ['begin', 'update after', 'rollback']);
      },
    );

    test('setRollbackOnly rolls back', () async {
      await template.execute((status) async {
        await jdbc.update('x');
        status.setRollbackOnly();
      });
      expect(callsOf(1), ['begin', 'update x', 'rollback']);
    });

    test(
      'a failing commit is translated, and its connection is closed',
      () async {
        driver.onConnect = (c) => c.failCommit = const SqlError('disk full');
        // The translated DataAccessException itself, as Spring's
        // JdbcTransactionManager throws it (not a TransactionSystemException).
        await expectLater(
          template.execute((_) => jdbc.update('x')),
          throwsA(isA<UncategorizedSqlException>()),
        );
        expect(driver.connections.single.isClosed, isTrue);
        expect(ds.totalCount, 0);
        driver.onConnect = null;
        await jdbc.update('again');
        expect(driver.connections, hasLength(2));
      },
    );

    test(
      'a serialization failure at commit is a '
      'CannotSerializeTransactionException, not wrapped',
      () async {
        build(dialect: const PostgresDialect());
        driver.onConnect = (c) => c.failCommit = const SqlError(
          'could not serialize access',
          sqlState: '40001',
        );
        await expectLater(
          template.execute((_) => jdbc.update('x')),
          throwsA(isA<CannotSerializeTransactionException>()),
        );
        expect(driver.connections.single.isClosed, isTrue);
      },
    );

    test(
      'a connection that cannot be had is a CannotCreateTransaction',
      () async {
        driver.connectError = const SqlError('down', connectionLost: true);
        await expectLater(
          template.execute((_) => jdbc.update('x')),
          throwsA(isA<CannotCreateTransactionException>()),
        );
        expect(ds.totalCount, 0);
      },
    );

    test(
      'SQL errors inside become DataAccessExceptions and roll back',
      () async {
        driver.onConnect = (c) => c.failOn = (sql) => duplicateKey;
        await expectLater(
          template.execute((_) => jdbc.update('insert dup')),
          throwsA(isA<DuplicateKeyException>()),
        );
        expect(callsOf(1), ['begin', 'update insert dup', 'rollback']);
      },
    );
  });

  group('pool exhaustion', () {
    test(
      'nested requiresNew past max-size waits, then fails; never hangs',
      () async {
        build(
          pool: const PoolSettings(
            maxSize: 2,
            connectionTimeout: Duration(milliseconds: 50),
          ),
        );
        final requiresNew = TransactionTemplate(
          manager,
          const TransactionDefinition(propagation: Propagation.requiresNew),
        );
        Future<void> nest(int depth) => requiresNew.execute((_) async {
          await jdbc.update('level $depth');
          if (depth < 4) {
            await nest(depth + 1);
          }
        });
        await expectLater(
          nest(1).timeout(const Duration(seconds: 5)),
          throwsA(
            anyOf(
              isA<CannotCreateTransactionException>(),
              isA<CannotGetJdbcConnectionException>(),
            ),
          ),
        );
        expect(ds.activeCount, 0);
        expect(ds.waitingCount, 0);
        expect(driver.connections, hasLength(2));
      },
    );

    test('a template call inside a transaction never needs a second '
        'connection', () async {
      build(pool: const PoolSettings(maxSize: 1));
      await template.execute((_) async {
        for (var i = 0; i < 5; i++) {
          await jdbc.update('u$i');
        }
      });
      expect(driver.connections, hasLength(1));
    });
  });

  group('timeouts', () {
    test('the transaction time left bounds each statement', () async {
      final timed = TransactionTemplate(
        manager,
        const TransactionDefinition(timeout: Duration(seconds: 10)),
      );
      await timed.execute((_) async {
        await jdbc.update('a');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await jdbc.update('b');
      });
      final timeouts = driver.connections.single.timeouts;
      expect(timeouts.whereType<Duration>(), hasLength(2));
      expect(
        timeouts[0]!.compareTo(const Duration(seconds: 10)),
        lessThanOrEqualTo(0),
      );
      expect(timeouts[1]!.compareTo(timeouts[0]!), isNegative);
      // Reset before the connection goes back to the pool.
      expect(timeouts.last, isNull);
    });

    test('a spent deadline stops the next statement', () async {
      final timed = TransactionTemplate(
        manager,
        const TransactionDefinition(timeout: Duration(milliseconds: 30)),
      );
      await expectLater(
        timed.execute((_) async {
          await jdbc.update('a');
          await Future<void>.delayed(const Duration(milliseconds: 60));
          await jdbc.update('never');
        }),
        throwsA(isA<TransactionTimedOutException>()),
      );
      final connection = driver.connections.single;
      expect(connection.statements, ['a']);
      expect(connection.calls.last, 'rollback');
    });

    test('a timed-out transaction can only roll back, even when the error '
        'was caught (Spring marks it rollback-only)', () async {
      final timed = TransactionTemplate(
        manager,
        const TransactionDefinition(timeout: Duration(milliseconds: 30)),
      );
      await expectLater(
        timed.execute((_) async {
          await jdbc.update('a');
          await Future<void>.delayed(const Duration(milliseconds: 60));
          try {
            await jdbc.update('never');
          } on TransactionTimedOutException {
            // Caught: the commit still must not happen.
          }
        }),
        throwsA(isA<UnexpectedRollbackException>()),
      );
      final connection = driver.connections.single;
      expect(connection.statements, ['a']);
      expect(connection.calls.last, 'rollback');
    });

    test('query-timeout of the template applies without a transaction and is '
        'reset', () async {
      final bounded = JdbcTemplate(
        ds,
        queryTimeout: const Duration(seconds: 3),
      );
      await bounded.update('x');
      expect(driver.connections.single.timeouts, [
        const Duration(seconds: 3),
        null,
      ]);
    });

    test('the shorter of the query timeout and the time left wins', () async {
      final bounded = JdbcTemplate(
        ds,
        queryTimeout: const Duration(milliseconds: 100),
      );
      await TransactionTemplate(
        manager,
        const TransactionDefinition(timeout: Duration(seconds: 50)),
      ).execute((_) => bounded.update('x'));
      expect(
        driver.connections.single.timeouts.first,
        const Duration(milliseconds: 100),
      );
    });
  });

  group('@Lock: the write lock of the database', () {
    FakeDialect sqliteLike({String? statement}) => FakeDialect(
      lockStrategy: LockStrategy.databaseLock,
      writeLockStatement: statement,
    );

    test('first statement: the transaction begins again for writing', () async {
      build(dialect: sqliteLike());
      await template.execute((_) async {
        await DataSourceUtils.requireWriteLock(ds);
        await jdbc.query('select', const [], (r) => r);
      });
      expect(callsOf(1), [
        'begin',
        'rollback',
        'begin lockForWrite',
        'query select',
        'commit',
      ]);
    });

    test('keeps the isolation of the transaction', () async {
      build(dialect: sqliteLike());
      await TransactionTemplate(
        manager,
        const TransactionDefinition(isolation: Isolation.serializable),
      ).execute((_) => DataSourceUtils.requireWriteLock(ds));
      expect(callsOf(1)[2], 'begin serializable lockForWrite');
    });

    test('asked twice, it happens once', () async {
      build(dialect: sqliteLike());
      await template.execute((_) async {
        await DataSourceUtils.requireWriteLock(ds);
        await DataSourceUtils.requireWriteLock(ds);
      });
      expect(callsOf(1).where((c) => c.startsWith('begin')), hasLength(2));
    });

    test(
      "after a statement: the dialect's write-lock statement runs",
      () async {
        build(dialect: sqliteLike(statement: 'lock it'));
        await template.execute((_) async {
          await jdbc.update('write');
          await DataSourceUtils.requireWriteLock(ds);
        });
        expect(callsOf(1), [
          'begin',
          'update write',
          'execute lock it',
          'commit',
        ]);
      },
    );

    test(
      'after a statement without such a statement: a clear failure',
      () async {
        build(dialect: sqliteLike());
        await expectLater(
          template.execute((_) async {
            await jdbc.update('write');
            await DataSourceUtils.requireWriteLock(ds);
          }),
          throwsA(
            isA<IllegalTransactionStateException>().having(
              (e) => e.message,
              'message',
              contains('must be the first statement'),
            ),
          ),
        );
      },
    );

    test('after a savepoint it cannot begin again', () async {
      build(dialect: sqliteLike(statement: 'lock it'));
      await template.execute((_) async {
        await TransactionTemplate(
          manager,
          const TransactionDefinition(propagation: Propagation.nested),
        ).execute((_) => DataSourceUtils.requireWriteLock(ds));
      });
      expect(callsOf(1), contains('execute lock it'));
    });

    test('outside a transaction: IllegalTransactionStateException', () async {
      build(dialect: sqliteLike());
      await expectLater(
        DataSourceUtils.requireWriteLock(ds),
        throwsA(isA<IllegalTransactionStateException>()),
      );
    });

    test('read-only transaction: refused', () async {
      build(dialect: sqliteLike());
      await expectLater(
        TransactionTemplate(
          manager,
          const TransactionDefinition(readOnly: true),
        ).execute((_) => DataSourceUtils.requireWriteLock(ds)),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
    });

    test('a database with row locks does nothing', () async {
      await template.execute((_) => DataSourceUtils.requireWriteLock(ds));
      await DataSourceUtils.requireWriteLock(ds);
      expect(callsOf(1), ['begin', 'commit']);
    });
  });
}
