import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/fake_jdbc.dart';
import 'support/people.dart';

enum Color { red, green }

void main() {
  late FakeJdbcDriver driver;
  late PooledDataSource ds;
  late JdbcTemplate jdbc;

  setUpAll(() => SpringLog.level = SpringLogLevel.off);
  setUp(() {
    driver = FakeJdbcDriver();
    ds = fakePool(driver);
    jdbc = JdbcTemplate(ds);
  });

  FakeJdbcConnection conn() => driver.connections.single;

  void answer(List<String> columns, List<List<Object?>> rows) {
    driver.onConnect = (c) =>
        c.onQuery = (sql, parameters) => JdbcResult(columns, rows);
  }

  group('query', () {
    test('maps each row; parameters in order, through the dialect', () async {
      answer(
        ['id', 'title'],
        [
          [1, 'Dune'],
          [2, 'Emma'],
        ],
      );
      final titles = await jdbc.query<String>(
        'select id, title from books where year > ? and ok = ?',
        [2000, true],
        (row) => row.string('title'),
      );
      expect(titles, ['Dune', 'Emma']);
      expect(conn().statements.single, startsWith('select id'));
      // true became 1 through FakeDialect.toDatabase.
      expect(conn().parameters.single, [2000, 1]);
      expect(ds.activeCount, 0);
    });

    test('enums are bound as their name, dates through the dialect', () async {
      await jdbc.query('q', [Color.green, DateTime.utc(2024)], (r) => r);
      expect(conn().parameters.single, [
        'green',
        '2024-01-01T00:00:00.000Z',
      ]);
    });

    test('a result extractor sees the whole result (one to many)', () async {
      answer(
        ['parent', 'child'],
        [
          ['a', 1],
          ['a', 2],
          ['b', 3],
        ],
      );
      final grouped = await jdbc.queryWithExtractor<Map<String, List<int>>>(
        'join',
        const [],
        (result) {
          final out = <String, List<int>>{};
          for (final row in result.rows) {
            (out[row.string('parent')] ??= []).add(row.int_('child'));
          }
          return out;
        },
      );
      expect(grouped, {
        'a': [1, 2],
        'b': [3],
      });
    });

    test('a connection is given back when the mapper throws', () async {
      answer(
        ['x'],
        [
          [1],
        ],
      );
      await expectLater(
        jdbc.query<int>('q', const [], (_) => throw StateError('mine')),
        throwsStateError,
      );
      expect(ds.activeCount, 0);
    });
  });

  group('queryForObject', () {
    test('one row with a mapper', () async {
      answer(
        ['n'],
        [
          [5],
        ],
      );
      expect(
        await jdbc.queryForObject<int>('q', const [], (r) => r.int_('n') * 2),
        10,
      );
    });

    test('scalar form: a single column read as T', () async {
      answer(
        ['count'],
        [
          [3],
        ],
      );
      expect(await jdbc.queryForObject<int>('select count(*)'), 3);
    });

    test('scalar form widens and converts through the dialect', () async {
      answer(
        ['v'],
        [
          [3],
        ],
      );
      expect(await jdbc.queryForObject<double>('q'), 3.0);
      answer(
        ['v'],
        [
          [1],
        ],
      );
      final fresh = JdbcTemplate(fakePool(driver));
      expect(await fresh.queryForObject<bool>('q'), isTrue);
    });

    test('scalar form reads an enum by name when its type is known', () async {
      answer(
        ['c'],
        [
          ['closed'],
        ],
      );
      final known = JdbcTemplate(ds, introspector: peopleIntrospector());
      expect(await known.queryForObject<Status>('q'), Status.closed);
      await expectLater(
        jdbc.queryForObject<Color>('q'),
        throwsA(isA<MappingException>()),
      );
    });

    test('no row: EmptyResultDataAccessException with the SQL', () async {
      await expectLater(
        jdbc.queryForObject<int>('select none'),
        throwsA(
          isA<EmptyResultDataAccessException>()
              .having((e) => e.expectedSize, 'expected', 1)
              .having((e) => e.sql, 'sql', 'select none'),
        ),
      );
    });

    test('many rows: IncorrectResultSizeDataAccessException', () async {
      answer(
        ['x'],
        [
          [1],
          [2],
          [3],
        ],
      );
      await expectLater(
        jdbc.queryForObject<int>('select many'),
        throwsA(
          isA<IncorrectResultSizeDataAccessException>()
              .having((e) => e.actualSize, 'actual', 3)
              .having(
                (e) => e is EmptyResultDataAccessException,
                'empty',
                false,
              ),
        ),
      );
    });

    test(
      'scalar of two columns: IncorrectResultSetColumnCountException',
      () async {
        answer(
          ['a', 'b'],
          [
            [1, 2],
          ],
        );
        await expectLater(
          jdbc.queryForObject<int>('q'),
          throwsA(
            isA<IncorrectResultSetColumnCountException>().having(
              (e) => e.actual,
              'actual',
              2,
            ),
          ),
        );
      },
    );

    test('a null scalar needs a nullable type', () async {
      answer(
        ['x'],
        [
          [null],
        ],
      );
      await expectLater(
        jdbc.queryForObject<int>('q'),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
      expect(await jdbc.queryForObject<int?>('q'), isNull);
    });
  });

  group('lists and maps', () {
    test('queryForList reads the single column', () async {
      answer(
        ['id'],
        [
          [1],
          [2],
        ],
      );
      expect(await jdbc.queryForList<int>('q'), [1, 2]);
    });

    test('queryForMap and queryForMaps', () async {
      answer(
        ['id', 'title'],
        [
          [1, 'Dune'],
        ],
      );
      expect(await jdbc.queryForMap('q'), {'id': 1, 'title': 'Dune'});
      expect(await jdbc.queryForMaps('q'), [
        {'id': 1, 'title': 'Dune'},
      ]);
    });

    test('queryForMap of many rows fails', () async {
      answer(
        ['id'],
        [
          [1],
          [2],
        ],
      );
      await expectLater(
        jdbc.queryForMap('q'),
        throwsA(isA<IncorrectResultSizeDataAccessException>()),
      );
    });
  });

  group('stream', () {
    test('rows one by one; the connection is held until the end', () async {
      answer(
        ['n'],
        [
          [1],
          [2],
          [3],
        ],
      );
      final seen = <int>[];
      await for (final n in jdbc.queryForStream<int>(
        'q',
        const [],
        (r) => r.int_('n'),
      )) {
        seen.add(n);
        expect(ds.activeCount, 1);
      }
      expect(seen, [1, 2, 3]);
      expect(ds.activeCount, 0);
    });

    test('cancelling releases the connection', () async {
      answer(
        ['n'],
        [
          [1],
          [2],
          [3],
        ],
      );
      final first = await jdbc
          .queryForStream<int>('q', const [], (r) => r.int_('n'))
          .first;
      expect(first, 1);
      expect(ds.activeCount, 0);
    });

    test(
      "inside a transaction it uses the transaction's connection",
      () async {
        answer(
          ['n'],
          [
            [1],
          ],
        );
        final manager = DataSourceTransactionManager(ds);
        await TransactionTemplate(manager).execute((_) async {
          await jdbc.update('before');
          await jdbc
              .queryForStream<int>('q', const [], (r) => r.int_('n'))
              .drain<void>();
          await jdbc.update('after');
        });
        expect(driver.connections, hasLength(1));
        expect(conn().statements, ['before', 'q', 'after']);
      },
    );

    test('a SQL error is translated', () async {
      driver.onConnect = (c) => c.failOn = (_) => badGrammar;
      await expectLater(
        jdbc.queryForStream<int>('bad', const [], (r) => 1).toList(),
        throwsA(isA<BadSqlGrammarException>()),
      );
      expect(ds.activeCount, 0);
    });
  });

  group('changes', () {
    test('update returns the affected rows', () async {
      expect(await jdbc.update('update t set a = ?', [1]), 1);
    });

    test('updateReturningKey returns the generated key', () async {
      expect(
        await jdbc.updateReturningKey('insert into t values (?)', [1]),
        42,
      );
    });

    test('updateWithKeyHolder fills the holder', () async {
      final holder = KeyHolder();
      expect(await jdbc.updateWithKeyHolder('insert', const [], holder), 1);
      expect(holder.keyAs<int>(), 42);
      expect(
        () => holder.keyAs<String>(),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
    });

    test('batchUpdate converts every list', () async {
      final counts = await jdbc.batchUpdate('insert into tags values (?, ?)', [
        [1, true],
        [2, false],
      ]);
      expect(counts, [1, 1]);
      expect(conn().calls.single, startsWith('batch insert into tags'));
    });

    test('execute runs DDL', () async {
      await jdbc.execute('create table t (id int)');
      expect(conn().calls, ['execute create table t (id int)']);
    });

    test(
      'executeWithConnection gives the connection and gives it back',
      () async {
        final value = await jdbc.executeWithConnection((c) async {
          await c.execute('pragma x');
          return 7;
        });
        expect(value, 7);
        expect(ds.activeCount, 0);
      },
    );
  });

  group('errors', () {
    test('the dialect translates, with the SQL and never the values', () async {
      driver.onConnect = (c) => c.failOn = (_) => duplicateKey;
      await expectLater(
        jdbc.update('insert into users(email) values (?)', ['secret@x.org']),
        throwsA(
          isA<DuplicateKeyException>()
              .having(
                (e) => e.sql,
                'sql',
                'insert into users(email) values (?)',
              )
              .having(
                (e) => e.toString(),
                'text',
                isNot(contains('secret@x.org')),
              )
              .having((e) => e.cause, 'cause', duplicateKey),
        ),
      );
      expect(ds.activeCount, 0);
    });

    test('bad grammar and an unknown error', () async {
      driver.onConnect = (c) => c.failOn = (_) => badGrammar;
      await expectLater(
        jdbc.query('selct', const [], (r) => r),
        throwsA(isA<BadSqlGrammarException>()),
      );
      final other = FakeJdbcDriver()
        ..onConnect = (c) => c.failOn = (_) => const SqlError('weird');
      await expectLater(
        JdbcTemplate(fakePool(other)).execute('x'),
        throwsA(isA<UncategorizedSqlException>()),
      );
    });

    test('a lost connection is dropped from the pool', () async {
      driver.onConnect = (c) => c.failOn = (_) {
        c.breakNow();
        return const SqlError('gone', connectionLost: true);
      };
      await expectLater(
        jdbc.update('x'),
        throwsA(isA<DataAccessResourceFailureException>()),
      );
      expect(ds.totalCount, 0);
    });

    test(
      'a pool that cannot give a connection: CannotGetJdbcConnection',
      () async {
        driver.connectError = const SqlError('refused');
        await expectLater(
          jdbc.update('x'),
          throwsA(isA<CannotGetJdbcConnectionException>()),
        );
      },
    );
  });

  group('rowMapperFor', () {
    test('picks by type', () async {
      answer(
        ['x'],
        [
          [4],
        ],
      );
      expect(await jdbc.query<int>('q', const [], jdbc.rowMapperFor<int>()), [
        4,
      ]);
      expect(
        await jdbc.query<Map<String, Object?>>(
          'q',
          const [],
          jdbc.rowMapperFor<Map<String, Object?>>(),
        ),
        [
          {'x': 4},
        ],
      );
      expect(
        () => jdbc.rowMapperFor<Duration>(),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
    });
  });
}
