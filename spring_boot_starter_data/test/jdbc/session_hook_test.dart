import 'dart:async';

import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/fake_jdbc.dart';

// JdbcSessionHook: what runs on a connection right after its transaction
// began, and around the work of a pooled connection outside a transaction.
// The fake connections record every call, the hooks' statements among them.
class _Hook extends JdbcSessionHook {
  _Hook(this.name, this.log);

  final String name;
  final List<String> log;

  Object? failBegin;
  Object? failBefore;
  Object? failAfter;

  @override
  Future<void> afterBegin(ConnectionHolder transaction) async {
    log.add('$name afterBegin');
    if (failBegin case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    await transaction.connection.execute(
      'set local $name${transaction.readOnly ? ' ro' : ''}',
    );
  }

  @override
  Future<void> beforeWork(
    DataSource dataSource,
    JdbcConnection connection,
  ) async {
    log.add('$name beforeWork');
    if (failBefore case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    await connection.execute('set $name');
  }

  @override
  Future<void> afterWork(
    DataSource dataSource,
    JdbcConnection connection,
  ) async {
    log.add('$name afterWork');
    if (failAfter case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    await connection.execute('reset $name');
  }
}

void main() {
  late FakeJdbcDriver driver;
  late PooledDataSource ds;
  late TransactionTemplate template;
  late JdbcTemplate jdbc;
  late List<String> log;
  late _Hook role;
  late _Hook tenant;

  void build({SqlDialect? dialect}) {
    driver = FakeJdbcDriver(dialect: dialect);
    ds = fakePool(driver);
    template = TransactionTemplate(DataSourceTransactionManager(ds));
    jdbc = JdbcTemplate(ds);
    log = [];
    role = _Hook('role', log);
    tenant = _Hook('tenant', log);
    ds.sessionHooks.addAll([role, tenant]);
  }

  setUpAll(() => SpringLog.level = SpringLogLevel.off);
  setUp(build);

  // What connection [n] was asked, without the pool's own checks (isValid
  // on a borrowed connection, a second close of a dropped one).
  List<String> callsOf(int n) {
    final calls = <String>[];
    for (final call in driver.connections[n - 1].calls) {
      if (call == 'isValid' || (call == 'close' && calls.lastOrNull == call)) {
        continue;
      }
      calls.add(call);
    }
    return calls;
  }

  group('a transaction', () {
    test('the hooks run once, in order, after begin and before the first '
        'statement, on its connection', () async {
      await template.execute((_) async {
        await jdbc.update('insert 1');
        await jdbc.update('insert 2');
      });
      expect(driver.connections, hasLength(1));
      expect(callsOf(1), [
        'begin',
        'execute set local role',
        'execute set local tenant',
        'update insert 1',
        'update insert 2',
        'commit',
      ]);
      // Nothing of the work outside a transaction.
      expect(log, ['role afterBegin', 'tenant afterBegin']);
    });

    test('once for each transaction, with what the transaction is', () async {
      await template.execute((_) => jdbc.update('a'));
      await TransactionTemplate(
        DataSourceTransactionManager(ds),
        const TransactionDefinition(readOnly: true),
      ).execute((_) => jdbc.query('b', const [], (row) => row));
      expect(log, [
        'role afterBegin',
        'tenant afterBegin',
        'role afterBegin',
        'tenant afterBegin',
      ]);
      expect(callsOf(1).where((call) => call.startsWith('execute')), [
        'execute set local role',
        'execute set local tenant',
        'execute set local role ro',
        'execute set local tenant ro',
      ]);
    });

    test('a joined transaction does not run them again; a new one on '
        'another connection does', () async {
      await template.execute((_) async {
        await template.execute((_) => jdbc.update('joined'));
        await TransactionTemplate(
          DataSourceTransactionManager(ds),
          const TransactionDefinition(propagation: Propagation.requiresNew),
        ).execute((_) => jdbc.update('own'));
      });
      expect(log.where((l) => l == 'role afterBegin'), hasLength(2));
      expect(callsOf(2), [
        'begin',
        'execute set local role',
        'execute set local tenant',
        'update own',
        'commit',
      ]);
    });

    test('every manager of the data source runs them: the repository '
        "store's too", () async {
      final store = JdbcDataStore(dataSource: ds, converter: EntityConverter());
      await TransactionTemplate(
        store.transactionManager,
      ).execute((_) => jdbc.update('a'));
      expect(log, ['role afterBegin', 'tenant afterBegin']);
    });

    test('a hook that fails fails the transaction before its body, and the '
        'connection is closed and released', () async {
      tenant.failBegin = StateError('no user');
      var ran = false;
      await expectLater(
        template.execute((_) async => ran = true),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'no user'),
        ),
      );
      expect(ran, isFalse);
      expect(callsOf(1), ['begin', 'execute set local role', 'close']);
      expect(ds.activeCount, 0);
      expect(ds.idleCount, 0);
      // The next transaction gets a new connection, prepared.
      tenant.failBegin = null;
      await template.execute((_) => jdbc.update('a'));
      expect(callsOf(2), [
        'begin',
        'execute set local role',
        'execute set local tenant',
        'update a',
        'commit',
      ]);
    });

    test('an error of the database in a hook is a '
        'CannotCreateTransactionException', () async {
      driver.onConnect = (connection) => connection.failOn = (sql) =>
          sql == 'set local role'
          ? const SqlError('permission denied to set role', sqlState: '42501')
          : null;
      await expectLater(
        template.execute((_) => jdbc.update('a')),
        throwsA(
          isA<CannotCreateTransactionException>().having(
            (e) => e.message,
            'message',
            contains('permission denied to set role'),
          ),
        ),
      );
      expect(log, ['role afterBegin']);
      expect(callsOf(1).last, 'close');
      expect(ds.activeCount, 0);
    });

    test('a transaction begun again on its connection is prepared '
        'again', () async {
      build(dialect: FakeDialect(lockStrategy: LockStrategy.databaseLock));
      await template.execute((_) async {
        await DataSourceUtils.requireWriteLock(ds);
        await jdbc.update('a');
      });
      expect(callsOf(1), [
        'begin',
        'execute set local role',
        'execute set local tenant',
        'rollback',
        'begin lockForWrite',
        'execute set local role',
        'execute set local tenant',
        'update a',
        'commit',
      ]);
    });
  });

  group('work outside a transaction', () {
    test('each call of the template is prepared before its statement and '
        'cleaned, in reverse order, before the pool has the connection '
        'back', () async {
      await jdbc.update('a');
      expect(callsOf(1), [
        'execute set role',
        'execute set tenant',
        'update a',
        'execute reset tenant',
        'execute reset role',
      ]);
      expect(log, [
        'role beforeWork',
        'tenant beforeWork',
        'tenant afterWork',
        'role afterWork',
      ]);
      expect(ds.activeCount, 0);
      expect(ds.idleCount, 1);
      // The next unit of work, on the same pooled connection.
      await jdbc.query('b', const [], (row) => row);
      expect(driver.connections, hasLength(1));
      expect(callsOf(1).skip(5), [
        'execute set role',
        'execute set tenant',
        'query b',
        'execute reset tenant',
        'execute reset role',
      ]);
    });

    test('a stream is one unit of work: until it ends, or is '
        'cancelled', () async {
      driver.onConnect = (connection) =>
          connection.onQuery = (_, _) => JdbcResult(
            ['x'],
            [
              [1],
              [2],
            ],
          );
      expect(
        await jdbc.queryForStream('s', const [], (row) => row['x']).toList(),
        [1, 2],
      );
      expect(callsOf(1), [
        'execute set role',
        'execute set tenant',
        'stream s',
        'stream done',
        'execute reset tenant',
        'execute reset role',
      ]);
      log.clear();
      await jdbc.queryForStream('s', const [], (row) => row['x']).first;
      await Future<void>.delayed(Duration.zero);
      expect(log, [
        'role beforeWork',
        'tenant beforeWork',
        'tenant afterWork',
        'role afterWork',
      ]);
      expect(ds.activeCount, 0);
    });

    test('executeWithConnection and the named template and the client go '
        'the same way', () async {
      await jdbc.executeWithConnection((connection) => connection.execute('x'));
      await NamedParameterJdbcTemplate(jdbc).update('y :a', {'a': 1});
      await JdbcClient.fromTemplate(jdbc).sql('z').update();
      expect(callsOf(1), [
        'execute set role',
        'execute set tenant',
        'execute x',
        'execute reset tenant',
        'execute reset role',
        'execute set role',
        'execute set tenant',
        'update y ? [1]',
        'execute reset tenant',
        'execute reset role',
        'execute set role',
        'execute set tenant',
        'update z',
        'execute reset tenant',
        'execute reset role',
      ]);
    });

    test('the work fails as before, and the connection is still '
        'cleaned', () async {
      driver.onConnect = (connection) =>
          connection.failOn = (sql) => sql == 'bad' ? badGrammar : null;
      await expectLater(
        jdbc.update('bad'),
        throwsA(isA<BadSqlGrammarException>()),
      );
      expect(callsOf(1), [
        'execute set role',
        'execute set tenant',
        'update bad',
        'execute reset tenant',
        'execute reset role',
      ]);
      expect(ds.idleCount, 1);
    });

    test('a hook that fails before the work fails it: no statement runs, '
        'the connection is closed and released', () async {
      tenant.failBefore = StateError('no user');
      await expectLater(jdbc.update('a'), throwsStateError);
      expect(callsOf(1), ['execute set role', 'close']);
      expect(log, ['role beforeWork', 'tenant beforeWork']);
      expect(ds.activeCount, 0);
      expect(ds.idleCount, 0);
      await expectLater(
        jdbc.queryForStream('s', const [], (row) => row).toList(),
        throwsStateError,
      );
      expect(callsOf(2), ['execute set role', 'close']);
      expect(ds.activeCount, 0);
    });

    test('an error of the database in a hook is translated', () async {
      driver.onConnect = (connection) =>
          connection.failOn = (sql) => sql == 'set role' ? badGrammar : null;
      await expectLater(
        jdbc.update('a'),
        throwsA(isA<BadSqlGrammarException>()),
      );
      expect(callsOf(1), ['execute set role', 'close']);
      expect(ds.activeCount, 0);
    });

    test('a hook that fails after the work: the result stands, and the '
        'connection is closed instead of going back with its state', () async {
      tenant.failAfter = StateError('cannot reset');
      expect(await jdbc.update('a'), 1);
      expect(callsOf(1), [
        'execute set role',
        'execute set tenant',
        'update a',
        'close',
      ]);
      // The hooks after the failed one have no connection to clean.
      expect(log.last, 'tenant afterWork');
      expect(ds.activeCount, 0);
      expect(ds.idleCount, 0);
      tenant.failAfter = null;
      await jdbc.update('b');
      expect(driver.connections, hasLength(2));
      expect(ds.idleCount, 1);
    });

    test('a connection that broke during the work is not cleaned', () async {
      await jdbc.executeWithConnection((connection) async {
        (connection as FakeJdbcConnection).breakNow();
      });
      expect(log, ['role beforeWork', 'tenant beforeWork']);
      expect(ds.activeCount, 0);
      expect(ds.idleCount, 0);
    });

    test('without hooks nothing changes', () async {
      ds.sessionHooks.clear();
      await jdbc.update('a');
      await template.execute((_) => jdbc.update('b'));
      expect(callsOf(1), ['update a', 'begin', 'update b', 'commit']);
    });
  });

  group('the beans', () {
    test('every JdbcSessionHook bean reaches every DataSource bean, in '
        '@Order', () async {
      final beans = BeanModule('hooks', [
        BeanDefinition<DataSource>(
          name: 'dataSource',
          types: const [DataSource],
          source: 'test#dataSource',
          create: (_) => fakePool(driver),
        ),
        BeanDefinition<JdbcSessionHook>(
          name: 'tenantHook',
          types: const [JdbcSessionHook],
          source: 'test#tenantHook',
          order: 2,
          create: (_) => tenant,
        ),
        BeanDefinition<JdbcSessionHook>(
          name: 'roleHook',
          types: const [JdbcSessionHook],
          source: 'test#roleHook',
          order: 1,
          create: (_) => role,
        ),
      ]);
      await const ApplicationContextRunner()
          .withUserConfiguration(beans)
          .withAutoConfiguration(springBootStarterDataAutoConfiguration)
          .withPropertyValues(['spring.sql.init.mode=never'])
          .runAsync<void>((context) async {
            if (context.startupFailure case final failure?) {
              throw StateError('The application did not start: $failure');
            }
            final dataSource = context.getBean<DataSource>();
            expect(dataSource.sessionHooks, [role, tenant]);
            log.clear();
            await context.getBean<JdbcTemplate>().update('a');
            expect(log, [
              'role beforeWork',
              'tenant beforeWork',
              'tenant afterWork',
              'role afterWork',
            ]);
            log.clear();
            await context.getBean<TransactionTemplate>().execute(
              (_) => context.getBean<JdbcTemplate>().update('b'),
            );
            expect(log, ['role afterBegin', 'tenant afterBegin']);
          });
    });
  });
}
