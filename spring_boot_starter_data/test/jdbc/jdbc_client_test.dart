import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/fake_jdbc.dart';
import 'support/people.dart';

void main() {
  late FakeJdbcDriver driver;
  late PooledDataSource ds;
  late JdbcClient client;

  setUpAll(() => SpringLog.level = SpringLogLevel.off);
  setUp(() {
    driver = FakeJdbcDriver();
    ds = fakePool(driver);
    client = JdbcClient.fromTemplate(
      JdbcTemplate(ds, introspector: peopleIntrospector()),
    );
  });

  FakeJdbcConnection conn() => driver.connections.single;

  void answer(List<String> columns, List<List<Object?>> rows) {
    driver.onConnect = (c) => c.onQuery = (_, _) => JdbcResult(columns, rows);
  }

  test('named parameters, optional, single', () async {
    answer(
      ['first_name', 'last_name'],
      [
        ['Ada', 'Lovelace'],
      ],
    );
    final person = await client
        .sql('select * from people where id = :id')
        .param('id', 42)
        .query<Person>()
        .optional();
    expect(person!.firstName, 'Ada');
    expect(person.lastName, 'Lovelace');
    expect(conn().statements.single, 'select * from people where id = ?');
    expect(conn().parameters.single, [42]);
  });

  test('positional parameters', () async {
    answer(
      ['c'],
      [
        [3],
      ],
    );
    final count = await client
        .sql('select count(*) c from t where a = ? and b = ?')
        .param(1)
        .param('x')
        .query<int>()
        .single();
    expect(count, 3);
    expect(conn().parameters.single, [1, 'x']);
  });

  test('params: a list is positional, a map named', () async {
    await client.sql('update t set a = ?, b = ?').params([1, 2]).update();
    await client.sql('update t set a = :a').params({'a': 5}).update();
    expect(conn().parameters, [
      [1, 2],
      [5],
    ]);
  });

  test('paramSource: a bean, with param overriding it', () async {
    await client
        .sql('update people set first = :firstName, age = :age')
        .paramSource(Person(firstName: 'Ada', lastName: 'L', age: 1))
        .param('age', 2)
        .update();
    expect(conn().parameters.single, ['Ada', 2]);
  });

  test('a named parameter set to null is a null parameter', () async {
    await client.sql('update t set a = :a').param('a', null).update();
    expect(conn().parameters.single, [null]);
  });

  test('mixing positional and named fails', () async {
    await expectLater(
      client.sql('update t set a = :a, b = ?').param('a', 1).param(2).update(),
      throwsA(isA<InvalidDataAccessApiUsageException>()),
    );
  });

  test('a name without a value fails; no params and ? runs as is', () async {
    await expectLater(
      client.sql('select :a').query<int>().list(),
      throwsA(isA<InvalidDataAccessApiUsageException>()),
    );
    await client.sql('select 1').query<int>().list();
    expect(conn().statements, ['select 1']);
  });

  test('list, set, optional, single sizes', () async {
    answer(
      ['n'],
      [
        [1],
        [1],
        [2],
      ],
    );
    expect(await client.sql('q').query<int>().list(), [1, 1, 2]);
    expect(await client.sql('q').query<int>().set(), {1, 2});
    await expectLater(
      client.sql('q').query<int>().single(),
      throwsA(isA<IncorrectResultSizeDataAccessException>()),
    );
    await expectLater(
      client.sql('q').query<int>().optional(),
      throwsA(isA<IncorrectResultSizeDataAccessException>()),
    );
    answer(['n'], []);
    final empty = JdbcClient.fromTemplate(JdbcTemplate(fakePool(driver)));
    expect(await empty.sql('q').query<int>().optional(), isNull);
    await expectLater(
      empty.sql('q').query<int>().single(),
      throwsA(isA<EmptyResultDataAccessException>()),
    );
  });

  test('query with a mapper, as maps, stream and extractor', () async {
    answer(
      ['n'],
      [
        [1],
        [2],
      ],
    );
    expect(
      await client.sql('q').query<String>((r) => 'n${r.int_('n')}').list(),
      ['n1', 'n2'],
    );
    expect(await client.sql('q').query<Object?>().list(), [
      {'n': 1},
      {'n': 2},
    ]);
    expect(
      await client.sql('q').query<int>().stream().toList(),
      [1, 2],
    );
    expect(
      await client.sql('q').query<int>().extract((r) => r.rows.length),
      2,
    );
  });

  test('update with a key holder', () async {
    final holder = KeyHolder();
    expect(
      await client
          .sql('insert into t values (:a)')
          .param('a', 1)
          .update(holder),
      1,
    );
    expect(holder.keyAs<int>(), 42);
  });

  test('a class that is not introspected asks for a mapper', () {
    expect(
      () => client.sql('q').query<Duration>(),
      throwsA(isA<InvalidDataAccessApiUsageException>()),
    );
  });

  test('JdbcClient(dataSource) builds its own template', () async {
    final c = JdbcClient(ds);
    expect(c.template.dataSource, ds);
    await c.sql('update t set a = 1').update();
    expect(conn().statements, ['update t set a = 1']);
  });

  test('uses the transaction of the manager', () async {
    final manager = DataSourceTransactionManager(ds);
    await TransactionTemplate(manager).execute((_) async {
      await client.sql('update a set x = 1').update();
      await client.sql('update b set x = 1').update();
    });
    expect(driver.connections, hasLength(1));
    expect(conn().calls, [
      'begin',
      'update update a set x = 1',
      'update update b set x = 1',
      'commit',
    ]);
  });
}
