@Tags(['postgres'])
library;

// Database functions (@Procedure) and the session hooks of the JDBC store on
// PostgreSQL: the call with named notation, its rows as the method's result,
// the transaction it runs in, the permission error, and a setting a
// JdbcSessionHook makes for a transaction and for the work outside one.
import 'dart:typed_data';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../mapping/support.dart';
import 'support.dart';

const _named = ProcedureMethod(
  'named',
  Procedure('authors_named'),
  parameters: ['prefix'],
  element: ClassType<Author>(),
);
const _count = ProcedureMethod(
  'count',
  Procedure('author_count'),
  shape: QueryShape.single,
  element: ClassType<int>(),
);
const _rename = ProcedureMethod(
  'rename',
  Procedure('rename_author'),
  parameters: ['authorId', 'newName'],
);
const _among = ProcedureMethod(
  'among',
  Procedure('authors_in'),
  parameters: ['names'],
  shape: QueryShape.stream,
  element: ClassType<Author>(),
);
const _byIds = ProcedureMethod(
  'byIds',
  Procedure('authors_by_ids'),
  parameters: ['ids'],
  element: ClassType<Author>(),
);
const _byteCount = ProcedureMethod(
  'byteCount',
  Procedure('byte_count'),
  parameters: ['data'],
  shape: QueryShape.single,
  element: ClassType<int>(),
);
const _forbidden = ProcedureMethod('forbidden', Procedure('forbidden'));
const _whoami = ProcedureMethod(
  'whoami',
  Procedure('whoami'),
  shape: QueryShape.single,
  element: ClassType<String>(nullable: true),
);

const _schema = [
  'create table authors (id serial primary key, name text not null)',
  r'''
create function authors_named(prefix text) returns setof authors
language sql stable as $$
  select * from authors where name like prefix || '%' order by id
$$''',
  r'''
create function author_count() returns bigint
language sql stable as $$ select count(*) from authors $$''',
  r'''
create function rename_author(author_id int, new_name text) returns void
language sql as $$ update authors set name = new_name where id = author_id $$''',
  r'''
create function authors_in(names text[]) returns setof authors
language sql stable as $$
  select * from authors where name = any(names) order by id
$$''',
  r'''
create function authors_by_ids(ids bigint[]) returns setof authors
language sql stable as $$
  select * from authors where id = any(ids) order by id
$$''',
  r'''
create function byte_count(data bytea) returns int
language sql immutable as $$ select length(data) $$''',
  r'''
create function forbidden() returns void language plpgsql as $$
begin
  raise exception 'permission denied for table secrets'
    using errcode = '42501';
end $$''',
  r'''
create function whoami() returns text
language sql stable as $$ select current_setting('app.actor', true) $$''',
];

// Says who the statements run as: for the transaction, or for the session
// of one unit of work.
class _UserHook extends JdbcSessionHook {
  String user = 'alice';

  @override
  Future<void> afterBegin(ConnectionHolder transaction) async {
    await transaction.connection.query(
      "select set_config('app.actor', ?, true)",
      ['$user in a transaction'],
    );
  }

  @override
  Future<void> beforeWork(
    DataSource dataSource,
    JdbcConnection connection,
  ) async {
    await connection.query("select set_config('app.actor', ?, false)", [user]);
  }

  @override
  Future<void> afterWork(
    DataSource dataSource,
    JdbcConnection connection,
  ) => connection.execute('reset app.actor');
}

void main() => group('PostgreSQL', () {
  usePostgresServer();
  _tests();
}, skip: postgresServerSkip);

void _tests() {
  late PooledDataSource ds;
  late JdbcDataStore store;
  late RepositoryOperations<Author, int> authors;

  setUp(() async {
    ds = await newPostgresSource();
    final converter = EntityConverter();
    store = JdbcDataStore(dataSource: ds, converter: converter);
    for (final statement in _schema) {
      await store.jdbc.execute(statement);
    }
    authors =
        RepositoryFactory(
          mappingContext: testContext(),
          converter: converter,
          stores: [store],
        ).operations<Author, int>(
          'Authors',
          annotations: const [UseStore('jdbc')],
          functions: const [
            _named,
            _count,
            _rename,
            _among,
            _byIds,
            _byteCount,
            _forbidden,
            _whoami,
          ],
        );
    await authors.saveAll([
      Author(name: 'Herbert'),
      Author(name: 'Heinlein'),
      Author(name: 'Austen'),
    ]);
  });

  test('the store has functions', () {
    expect(store.capabilities.functions, isTrue);
  });

  test(
    'a function that returns rows of the table gives the entities',
    () async {
      final found = await authors.procedure<List<Author>>(_named, ['He']);
      expect(found, isA<List<Author>>());
      expect(found.map((a) => a.name), ['Herbert', 'Heinlein']);
      expect(found.first.id, isNotNull);
    },
  );

  test('a scalar function gives its value', () async {
    expect(await authors.procedure<int>(_count, const []), 3);
  });

  test(
    'the arguments go by name, in snake case; nothing is returned',
    () async {
      final herbert = (await authors.procedure<List<Author>>(_named, [
        'Her',
      ])).single;
      await authors.procedure<void>(_rename, [herbert.id, 'Frank Herbert']);
      expect((await authors.findById(herbert.id!))!.name, 'Frank Herbert');
    },
  );

  test('a list is one array argument; a Stream gives the rows', () async {
    final found = await authors.procedureStream<Author>(_among, [
      ['Austen', 'Herbert', 'Nobody'],
    ]).toList();
    expect(found.map((a) => a.name), ['Herbert', 'Austen']);
  });

  test('a List<int> is an integer array argument, also empty or with a '
      'null; a Uint8List is bytes', () async {
    final all = await authors.findAll();
    final ids = <int>[all[2].id!, all[0].id!];
    final found = await authors.procedure<List<Author>>(_byIds, [ids]);
    expect(found.map((a) => a.name), ['Herbert', 'Austen']);
    expect(await authors.procedure<List<Author>>(_byIds, [<int>[]]), isEmpty);
    expect(
      (await authors.procedure<List<Author>>(_byIds, [
        <int?>[null, all[1].id],
      ])).map((a) => a.name),
      ['Heinlein'],
    );

    expect(
      await authors.procedure<int>(_byteCount, [
        Uint8List.fromList([1, 2, 3]),
      ]),
      3,
    );
    expect(await authors.procedure<int>(_byteCount, [Uint8List(0)]), 0);
  });

  test('the call runs in the transaction of the caller', () async {
    final herbert = (await authors.procedure<List<Author>>(_named, [
      'Her',
    ])).single;
    await expectLater(
      TransactionTemplate(store.transactionManager).execute((_) async {
        await authors.procedure<void>(_rename, [herbert.id, 'Changed']);
        expect(
          (await authors.procedure<List<Author>>(_named, [
            'Changed',
          ])).single.id,
          herbert.id,
        );
        throw StateError('undo');
      }),
      throwsStateError,
    );
    expect((await authors.findById(herbert.id!))!.name, 'Herbert');
  });

  test('insufficient privilege is a '
      'PermissionDeniedDataAccessException', () async {
    await expectLater(
      authors.procedure<void>(_forbidden, const []),
      throwsA(
        isA<PermissionDeniedDataAccessException>()
            .having((e) => e.message, 'message', contains('permission denied'))
            .having((e) => e.sql, 'sql', 'select * from "forbidden"()'),
      ),
    );
  });

  test('a function that does not exist is wrong SQL', () async {
    await expectLater(
      store.callFunction('no_such_function', {'a': 1}),
      throwsA(isA<BadSqlGrammarException>()),
    );
  });

  test('a session hook sets who a transaction runs as, and who the work '
      'outside one runs as; nothing stays on the pooled connection', () async {
    final hook = _UserHook();
    ds.sessionHooks.add(hook);
    expect(await authors.procedure<String?>(_whoami, const []), 'alice');
    await TransactionTemplate(store.transactionManager).execute((_) async {
      expect(
        await authors.procedure<String?>(_whoami, const []),
        'alice in a transaction',
      );
    });
    hook.user = 'bob';
    expect(await authors.procedure<String?>(_whoami, const []), 'bob');
    // The pool has one connection: without the hook, the same one.
    ds.sessionHooks.clear();
    expect(
      await authors.procedure<String?>(_whoami, const []),
      anyOf(isNull, ''),
    );
  });
}
