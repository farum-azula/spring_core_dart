import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/fake_jdbc.dart';
import 'support/people.dart';

void main() {
  SubstitutedSql sub(String sql, Map<String, Object?> values) =>
      NamedParameterUtils.substitute(
        NamedParameterUtils.parse(sql),
        MapSqlParameterSource(values),
      );

  group('parsing', () {
    test('names become ?, in order', () {
      final out = sub('select * from t where a = :a and b = :b', {
        'a': 1,
        'b': 2,
      });
      expect(out.sql, 'select * from t where a = ? and b = ?');
      expect(out.values, [1, 2]);
      expect(out.names, ['a', 'b']);
    });

    test('a repeated name is bound each time', () {
      final out = sub(':x + :x', {'x': 5});
      expect(out.sql, '? + ?');
      expect(out.values, [5, 5]);
    });

    test('quoted text is left alone', () {
      final out = sub(
        "select ':no', \":no\", `:no`, 'it''s :no', :yes",
        {'yes': 1},
      );
      expect(out.sql, "select ':no', \":no\", `:no`, 'it''s :no', ?");
      expect(out.values, [1]);
    });

    test('a :: cast is not a parameter', () {
      final out = sub('select :v::int, a::text from t', {'v': 3});
      expect(out.sql, 'select ?::int, a::text from t');
    });

    test('comments are left alone', () {
      final out = sub(
        'select 1 -- :no\n, :a /* :no */ , 2',
        {'a': 1},
      );
      expect(out.sql, 'select 1 -- :no\n, ? /* :no */ , 2');
      expect(out.values, [1]);
    });

    test('dollar-quoted text is left alone', () {
      final out = sub(r'select $$ :no $$, :a', {'a': 1});
      expect(out.sql, r'select $$ :no $$, ?');
    });

    test('a lone colon, a colon before a space or digit, stays text', () {
      final out = sub('select a[1:2], b : c, :a', {'a': 1});
      expect(out.sql, 'select a[1:2], b : c, ?');
    });

    test('names with dots, underscores and the :{name} form', () {
      final out = sub('where a = :user.name and b = :{odd name} and c = :a_1', {
        'user.name': 1,
        'odd name': 2,
        'a_1': 3,
      });
      expect(out.sql, 'where a = ? and b = ? and c = ?');
      expect(out.values, [1, 2, 3]);
    });

    test('a trailing dot is not part of the name', () {
      final out = sub('select :a.', {'a': 1});
      expect(out.sql, 'select ?.');
    });

    test('an unterminated quote runs to the end', () {
      final out = sub("select :a, 'open :b", {'a': 1});
      expect(out.sql, "select ?, 'open :b");
    });

    test('parse reports the names', () {
      expect(NamedParameterUtils.parse(':a :b :a').names, ['a', 'b', 'a']);
    });
  });

  group('substitution', () {
    test('a list expands to ?, ?, ?', () {
      final out = sub('where id in (:ids) and x = :x', {
        'ids': [1, 2, 3],
        'x': 0,
      });
      expect(out.sql, 'where id in (?, ?, ?) and x = ?');
      expect(out.values, [1, 2, 3, 0]);
      expect(out.names, ['ids', 'ids', 'ids', 'x']);
    });

    test('a set expands too; a string and bytes do not', () {
      expect(
        sub('in (:s)', {
          's': {1, 2},
        }).sql,
        'in (?, ?)',
      );
      expect(sub(':s', {'s': 'abc'}).sql, '?');
    });

    test('a list of lists expands to tuples', () {
      final out = sub('where (a, b) in (:pairs)', {
        'pairs': [
          [1, 'x'],
          [2, 'y'],
        ],
      });
      expect(out.sql, 'where (a, b) in ((?, ?), (?, ?))');
      expect(out.values, [1, 'x', 2, 'y']);
    });

    test('an empty list is refused with a clear message', () {
      expect(
        () => sub('where id in (:ids)', {'ids': <int>[]}),
        throwsA(
          isA<InvalidDataAccessApiUsageException>().having(
            (e) => e.message,
            'message',
            allOf(contains("'ids'"), contains('empty')),
          ),
        ),
      );
    });

    test('a null value is a value', () {
      final out = sub('set a = :a', {'a': null});
      expect(out.values, [null]);
    });

    test('a missing value names the parameter and keeps the SQL', () {
      expect(
        () => sub('select :a, :b', {'a': 1}),
        throwsA(
          isA<InvalidDataAccessApiUsageException>()
              .having(
                (e) => e.message,
                'message',
                "No value supplied for the SQL parameter 'b'",
              )
              .having((e) => e.sql, 'sql', 'select :a, :b'),
        ),
      );
    });

    test('mixing ? and names is refused; ? alone says what to do', () {
      expect(
        () => sub('select ?, :a', {'a': 1}),
        throwsA(
          isA<InvalidDataAccessApiUsageException>().having(
            (e) => e.message,
            'message',
            contains('Cannot mix'),
          ),
        ),
      );
      expect(
        () => sub('select ?', {}),
        throwsA(
          isA<InvalidDataAccessApiUsageException>().having(
            (e) => e.message,
            'message',
            contains('positional'),
          ),
        ),
      );
    });

    test('a ? inside a literal is fine', () {
      expect(sub("select '?', :a", {'a': 1}).sql, "select '?', ?");
    });
  });

  group('sources', () {
    test('a bean: properties by name, also snake case', () {
      final person = Person(firstName: 'Ada', lastName: 'Lovelace', age: 36);
      final source = BeanPropertySqlParameterSource(
        person,
        introspector: peopleIntrospector(),
      );
      expect(source.hasValue('firstName'), isTrue);
      expect(source.getValue('age'), 36);
      expect(source.hasValue('last_name'), isTrue);
      expect(source.getValue('last_name'), 'Lovelace');
      expect(source.hasValue('nope'), isFalse);
    });

    test('a class that is not introspected is refused', () {
      expect(
        () => BeanPropertySqlParameterSource(
          Object(),
          introspector: peopleIntrospector(),
        ),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
    });

    test('SqlParameterSource.of takes sources, maps and beans', () {
      final map = MapSqlParameterSource({'a': 1});
      expect(SqlParameterSource.of(map), same(map));
      expect(SqlParameterSource.of({'a': 1}).getValue('a'), 1);
      expect(
        SqlParameterSource.of(
          Person(firstName: 'A', lastName: 'B'),
          introspector: peopleIntrospector(),
        ).getValue('firstName'),
        'A',
      );
    });
  });

  group('NamedParameterJdbcTemplate', () {
    late FakeJdbcDriver driver;
    late PooledDataSource ds;
    late NamedParameterJdbcTemplate named;

    setUpAll(() => SpringLog.level = SpringLogLevel.off);
    setUp(() {
      driver = FakeJdbcDriver();
      ds = fakePool(driver);
      named = NamedParameterJdbcTemplate(
        JdbcTemplate(ds, introspector: peopleIntrospector()),
      );
    });

    test('query with a map and a list', () async {
      driver.onConnect = (c) => c.onQuery = (_, _) => JdbcResult(
        ['n'],
        [
          [1],
          [2],
        ],
      );
      final out = await named.query<int>(
        'select n from t where id in (:ids) and ok = :ok',
        {
          'ids': [7, 8],
          'ok': true,
        },
        (r) => r.int_('n'),
      );
      expect(out, [1, 2]);
      final c = driver.connections.single;
      expect(
        c.statements.single,
        'select n from t where id in (?, ?) and ok = ?',
      );
      expect(c.parameters.single, [7, 8, 1]);
    });

    test('update with a bean', () async {
      final n = await named.update(
        'update people set age = :age where first_name = :firstName',
        Person(firstName: 'Ada', lastName: 'L', age: 40),
      );
      expect(n, 1);
      expect(driver.connections.single.parameters.single, [40, 'Ada']);
    });

    test('queryForObject scalar, queryForList, queryForMap', () async {
      driver.onConnect = (c) => c.onQuery = (_, _) => JdbcResult(
        ['n'],
        [
          [9],
        ],
      );
      expect(await named.queryForObject<int>('select :a', {'a': 1}), 9);
      expect(await named.queryForList<int>('select :a', {'a': 1}), [9]);
      expect(await named.queryForMap('select :a', {'a': 1}), {'n': 9});
    });

    test('batchUpdate prepares each map', () async {
      final counts = await named.batchUpdate('insert into t values (:a, :b)', [
        {'a': 1, 'b': 2},
        {'a': 3, 'b': 4},
      ]);
      expect(counts, [1, 1]);
      expect(named.jdbc.dataSource, ds);
    });

    test('a missing parameter fails before any connection is taken', () async {
      await expectLater(
        named.update('update t set a = :a', <String, Object?>{}),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
      expect(driver.connections, isEmpty);
    });

    test('an empty list fails before any connection is taken', () async {
      await expectLater(
        named.query('select * from t where id in (:ids)', {
          'ids': <int>[],
        }, (r) => r),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
      expect(driver.connections, isEmpty);
    });

    test('the same statement is parsed once', () async {
      for (var i = 0; i < 3; i++) {
        await named.update('update t set a = :a', {'a': i});
      }
      expect(
        driver.connections.single.statements,
        everyElement('update t set a = ?'),
      );
    });

    test('updateReturningKey and key holder', () async {
      expect(await named.updateReturningKey('insert :a', {'a': 1}), 42);
      final holder = KeyHolder();
      await named.updateWithKeyHolder('insert :a', {'a': 1}, holder);
      expect(holder.key, 42);
    });
  });
}
