import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/fake_jdbc.dart';

void main() {
  late FakeJdbcDriver driver;
  late PooledDataSource ds;

  setUpAll(() => SpringLog.handler = (_) {});

  setUp(() {
    driver = FakeJdbcDriver();
    ds = fakePool(driver);
    SpringLog.level = SpringLogLevel.info;
    SpringLog.resetLevels();
  });

  tearDown(() {
    SpringLog.level = SpringLogLevel.info;
    SpringLog.resetLevels();
  });

  Future<List<SpringLogRecord>> capture(Future<void> Function() body) async {
    final records = <SpringLogRecord>[];
    final stop = SpringLog.listen(records.add);
    try {
      await body();
    } finally {
      stop();
    }
    return records
        .where((r) => !r.loggerName.contains('PooledDataSource'))
        .toList();
  }

  String text(List<SpringLogRecord> records) =>
      records.map((r) => r.message).join('\n');

  test('nothing is logged at the default level', () async {
    final jdbc = JdbcTemplate(ds);
    final records = await capture(() => jdbc.update('delete from t'));
    expect(records, isEmpty);
  });

  test(
    'debug: the SQL, the rows, the time, the data source; never values',
    () async {
      SpringLog.setLevel('spring.jdbc.core.JdbcTemplate', SpringLogLevel.debug);
      final jdbc = JdbcTemplate(ds);
      final records = await capture(
        () => jdbc.update('update users set email = ? where id = ?', [
          'a@b.org',
          7,
        ]),
      );
      expect(records, hasLength(1));
      final record = records.single;
      expect(record.loggerName, 'spring.jdbc.core.JdbcTemplate');
      expect(record.level, SpringLogLevel.debug);
      expect(
        record.message,
        matches(
          r'^\[shop\] update users set email = \? where id = \?  '
          r'\(1 row, \d+ ms\)$',
        ),
      );
      expect(record.message, isNot(contains('a@b.org')));
    },
  );

  test('query rows are counted', () async {
    SpringLog.setLevel('spring.jdbc.core.JdbcTemplate', SpringLogLevel.debug);
    driver.onConnect = (c) => c.onQuery = (_, _) => JdbcResult(
      ['x'],
      [
        [1],
        [2],
      ],
    );
    final jdbc = JdbcTemplate(ds);
    final records = await capture(() => jdbc.queryForList<int>('select x'));
    expect(text(records), contains('(2 rows,'));
  });

  test('trace: the values, ?1 names, types, masked by name', () async {
    SpringLog.setLevel(
      'spring.jdbc.core.StatementCreatorUtils',
      SpringLogLevel.trace,
    );
    final jdbc = JdbcTemplate(ds);
    final records = await capture(
      () => jdbc.update('insert into t values (?, ?)', [42, 'text']),
    );
    expect(records.map((r) => r.loggerName).toSet(), {
      'spring.jdbc.core.StatementCreatorUtils',
    });
    expect(text(records), contains('?1 = 42 (int)'));
    expect(text(records), contains('?2 = "text" (String)'));
  });

  test('trace: a secret-looking name is masked, others are not', () async {
    SpringLog.setLevel(
      'spring.jdbc.core.StatementCreatorUtils',
      SpringLogLevel.trace,
    );
    final named = NamedParameterJdbcTemplate(JdbcTemplate(ds));
    final records = await capture(
      () => named.update(
        'update users set password = :password, api_key = :apiKey, '
        'name = :name where id = :id',
        {
          'password': 'hunter2',
          'apiKey': 'k-123',
          'name': 'Ada',
          'id': 7,
        },
      ),
    );
    final all = text(records);
    expect(all, contains('password = ******'));
    expect(all, contains('apiKey = ******'));
    expect(all, contains('name = "Ada" (String)'));
    expect(all, contains('id = 7 (int)'));
    expect(all, isNot(contains('hunter2')));
    expect(all, isNot(contains('k-123')));
  });

  test('the password of the connection is never in any log or error', () async {
    SpringLog.level = SpringLogLevel.trace;
    final all = <SpringLogRecord>[];
    final stop = SpringLog.listen(all.add);
    final jdbc = JdbcTemplate(ds);
    await jdbc.update('x');
    driver.connectError = const SqlError('refused', connectionLost: true);
    final failing = JdbcTemplate(fakePool(driver, name: 'down'));
    Object? error;
    try {
      await failing.update('x');
    } on Object catch (e) {
      error = e;
    }
    await ds.close();
    stop();
    expect(error, isA<CannotGetJdbcConnectionException>());
    expect('$error', isNot(contains('hunter2')));
    expect(all.map((r) => r.message).join('\n'), isNot(contains('hunter2')));
    expect('$ds', isNot(contains('hunter2')));
  });

  test('the transaction number and name show in the line', () async {
    SpringLog.setLevel('spring.jdbc.core.JdbcTemplate', SpringLogLevel.debug);
    final jdbc = JdbcTemplate(ds);
    final template = TransactionTemplate(
      DataSourceTransactionManager(ds),
      const TransactionDefinition(name: 'checkout'),
    );
    final records = await capture(
      () => template.execute((_) => jdbc.update('update t set a = 1')),
    );
    expect(text(records), matches(RegExp(r'\[shop tx#\d+ checkout\] update')));
  });

  test('the request id of SpringLog.withFields ends the line', () async {
    SpringLog.setLevel('spring.jdbc.core.JdbcTemplate', SpringLogLevel.debug);
    final jdbc = JdbcTemplate(ds);
    final records = await capture(
      () => SpringLog.withFields({'request': '7f3a'}, () => jdbc.update('u')),
    );
    expect(records.single.message, endsWith(' {request=7f3a}'));
    expect(records.single.fields['request'], '7f3a');
  });

  test('slow statements warn past the threshold, with the SQL', () async {
    driver.onConnect = (c) => c.gate = Future<void>.delayed(
      const Duration(milliseconds: 30),
    );
    final jdbc = JdbcTemplate(
      ds,
      logSettings: const JdbcLogSettings(
        slowQueryThreshold: Duration(milliseconds: 10),
      ),
    );
    final records = await capture(
      () => SpringLog.withFields(
        {'request': 'r1'},
        () => jdbc.queryForList<int>('select slow from t where a = ?', [
          'secret-value',
        ]),
      ),
    );
    final warning = records.singleWhere(
      (r) => r.level == SpringLogLevel.warning,
    );
    expect(
      warning.message,
      matches(
        r'^\[shop\] slow statement, \d+ ms: select slow from t where a = \?',
      ),
    );
    expect(warning.message, endsWith('{request=r1}'));
    expect(warning.message, isNot(contains('secret-value')));
  });

  test('fast statements do not warn', () async {
    final jdbc = JdbcTemplate(
      ds,
      logSettings: const JdbcLogSettings(
        slowQueryThreshold: Duration(seconds: 5),
      ),
    );
    final records = await capture(() => jdbc.update('x'));
    expect(records, isEmpty);
  });

  test('show-sql logs at info; show-parameters shows the values at info, '
      'masked by name', () async {
    final jdbc = JdbcTemplate(
      ds,
      logSettings: const JdbcLogSettings(showSql: true, showParameters: true),
    );
    final records = await capture(
      () => jdbc.update('update t set a = ?', [5]),
    );
    expect(records.every((r) => r.level == SpringLogLevel.info), isTrue);
    expect(text(records), contains('update t set a = ?'));
    expect(text(records), contains('?1 = 5 (int)'));
  });

  test('format-sql puts the main clauses on their own lines', () async {
    SpringLog.setLevel('spring.jdbc.core.JdbcTemplate', SpringLogLevel.debug);
    final jdbc = JdbcTemplate(
      ds,
      logSettings: const JdbcLogSettings(formatSql: true),
    );
    final records = await capture(
      () => jdbc.queryForList<int>(
        'select a from t where b = ? order by a',
      ),
    );
    expect(
      text(records),
      contains('\n  select a\n  from t\n  where b = ?\n  order by a'),
    );
  });

  test('failed statements are logged without values', () async {
    SpringLog.setLevel('spring.jdbc.core.JdbcTemplate', SpringLogLevel.debug);
    driver.onConnect = (c) => c.failOn = (_) => duplicateKey;
    final jdbc = JdbcTemplate(ds);
    final records = await capture(() async {
      try {
        await jdbc.update('insert into t values (?)', ['pw']);
      } on DataAccessException {
        // Expected.
      }
    });
    expect(text(records), contains('failed after'));
    expect(text(records), isNot(contains('pw')));
  });

  test(
    'the transaction manager logs begin, commit, rollback at debug',
    () async {
      SpringLog.setLevel(
        'spring.jdbc.datasource.DataSourceTransactionManager',
        SpringLogLevel.debug,
      );
      final template = TransactionTemplate(DataSourceTransactionManager(ds));
      final records = await capture(() async {
        await template.execute((_) {});
        try {
          await template.execute((_) => throw StateError('x'));
        } on StateError {
          // Expected.
        }
      });
      final names = records.map((r) => r.loggerName).toSet();
      expect(
        names,
        contains('spring.jdbc.datasource.DataSourceTransactionManager'),
      );
      final all = text(records);
      expect(all, contains('Acquired Connection'));
      expect(all, contains('Began JDBC transaction'));
      expect(all, contains('Committing JDBC transaction'));
      expect(all, contains('Rolling back JDBC transaction'));
      expect(all, contains('Releasing JDBC Connection'));
      expect(all, isNot(contains('hunter2')));
    },
  );
}
