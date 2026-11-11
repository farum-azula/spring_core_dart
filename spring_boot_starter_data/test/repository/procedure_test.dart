import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../jdbc/support/fake_jdbc.dart';
import '../mapping/support.dart';
import 'support/plain_store.dart';

// @Procedure methods: the generated class gives a ProcedureMethod for each and
// calls operations.procedure / procedureStream; the store calls the database
// function and the rows are read as the rows of a @Query are. With a store of
// the test (any FunctionDataStore) and with the JDBC store over a fake driver
// and PostgreSQL's dialect.
const _bookRow = <String, Object?>{
  'id': 7,
  'title': 'Dune',
  'year': 1965,
  'genre': 'science',
  'price': 9,
  'available': 1,
  'version': 2,
};

const _total = ProcedureMethod(
  'totalOf',
  Procedure('books_total'),
  parameters: ['authorId', 'sinceYear'],
  shape: QueryShape.single,
  element: ClassType<int>(),
);
const _maybeTotal = ProcedureMethod(
  'maybeTotal',
  Procedure('books_total'),
  shape: QueryShape.single,
  element: ClassType<int>(nullable: true),
);
const _byGenre = ProcedureMethod(
  'byGenre',
  Procedure('books_of'),
  parameters: ['genre'],
  element: ClassType<Book>(),
);
const _oneBook = ProcedureMethod(
  'best',
  Procedure('best_book'),
  shape: QueryShape.single,
  element: ClassType<Book>(nullable: true),
);
const _titles = ProcedureMethod(
  'titles',
  Procedure('titles'),
  shape: QueryShape.set,
  element: ClassType<String>(),
);
const _authors = ProcedureMethod(
  'authors',
  Procedure('public.authors_of'),
  parameters: ['titles'],
  element: ClassType<Author>(),
);
const _archive = ProcedureMethod(
  'archive',
  Procedure('archive_books'),
  parameters: ['olderThan'],
);
const _streamed = ProcedureMethod(
  'streamed',
  Procedure('books_of'),
  parameters: ['genre'],
  shape: QueryShape.stream,
  element: ClassType<Book>(),
);
const _rows = ProcedureMethod(
  'raw',
  Procedure('raw'),
  element: MapType<String, Object?>(ClassType<String>(), DynamicType()),
);
const List<ProcedureMethod> _all = [
  _total,
  _maybeTotal,
  _byGenre,
  _oneBook,
  _titles,
  _authors,
  _archive,
  _streamed,
  _rows,
];

void main() {
  late EntityConverter converter;

  setUpAll(() => SpringLog.level = SpringLogLevel.off);
  setUp(() => converter = EntityConverter());

  Matcher invalid(List<String> reasons) => throwsA(
    isA<StateError>().having(
      (e) => e.message,
      'message',
      allOf([
        startsWith('Invalid repository Books:'),
        for (final reason in reasons) contains(reason),
      ]),
    ),
  );

  group('with a FunctionDataStore', () {
    late FunctionStore store;
    late RepositoryOperations<Book, int> books;

    RepositoryOperations<Book, int> create(
      DataStore store, {
      List<ProcedureMethod> functions = _all,
    }) =>
        RepositoryFactory(
          mappingContext: testContext(),
          converter: converter,
          stores: [store],
        ).operations<Book, int>(
          'Books',
          annotations: [UseStore(store.name)],
          functions: functions,
        );

    setUp(() {
      store = FunctionStore(InMemoryDataStore(converter: converter));
      books = create(store);
    });

    test('the arguments are the parameters in snake case, with the values '
        'given', () async {
      store.onCall = (_, _) => [
        {'books_total': 3},
      ];
      expect(await books.procedure<int>(_total, [12, 1960]), 3);
      expect(store.calls.single.$1, 'books_total');
      expect(store.calls.single.$2, {'author_id': 12, 'since_year': 1960});
    });

    test('a scalar is read from the single column; several columns are '
        'refused', () async {
      store.onCall = (_, _) => [
        {'a': 1, 'b': 2},
      ];
      await expectLater(
        books.procedure<int>(_total, [1, 2]),
        throwsA(isA<IncorrectResultSetColumnCountException>()),
      );
    });

    test('one value: none is null for a nullable type, else an '
        'EmptyResultDataAccessException; several are refused', () async {
      expect(await books.procedure<int?>(_maybeTotal, const []), isNull);
      await expectLater(
        books.procedure<int>(_total, [1, 2]),
        throwsA(
          isA<EmptyResultDataAccessException>().having(
            (e) => e.message,
            'message',
            contains('Books.totalOf'),
          ),
        ),
      );
      store.onCall = (_, _) => [
        {'n': 1},
        {'n': 2},
      ];
      await expectLater(
        books.procedure<int?>(_maybeTotal, const []),
        throwsA(isA<IncorrectResultSizeDataAccessException>()),
      );
    });

    test('rows of the entity are read by the entity converter, as a typed '
        'List', () async {
      store.onCall = (_, _) => [
        _bookRow,
        {..._bookRow, 'id': 8, 'title': 'Emma', 'genre': 'fiction'},
      ];
      final found = await books.procedure<List<Book>>(_byGenre, [
        Genre.science,
      ]);
      expect(found, isA<List<Book>>());
      expect(found.map((b) => b.title), ['Dune', 'Emma']);
      expect(found.first.id, 7);
      expect(found.first.genre, Genre.science);
      expect(found.first.price, 9.0);
      expect(found.first.available, isTrue);
      expect(found.first.version, 2);
      // The value reaches the store as the method got it.
      expect(store.calls.single.$2, {'genre': Genre.science});
    });

    test('one entity, or null', () async {
      expect(await books.procedure<Book?>(_oneBook, const []), isNull);
      store.onCall = (_, _) => [_bookRow];
      expect((await books.procedure<Book?>(_oneBook, const []))!.title, 'Dune');
    });

    test('a Set of a simple type', () async {
      store.onCall = (_, _) => [
        {'title': 'Dune'},
        {'title': 'Emma'},
        {'title': 'Dune'},
      ];
      final titles = await books.procedure<Set<String>>(_titles, const []);
      expect(titles, isA<Set<String>>());
      expect(titles, {'Dune', 'Emma'});
    });

    test('a described class is built from the columns by name', () async {
      store.onCall = (_, _) => [
        {'id': 1, 'name': 'Herbert', 'extra': true},
      ];
      final authors = await books.procedure<List<Author>>(_authors, [
        ['Dune'],
      ]);
      expect(authors, isA<List<Author>>());
      expect(authors.single.name, 'Herbert');
      expect(store.calls.single.$1, 'public.authors_of');
      expect(store.calls.single.$2, {
        'titles': ['Dune'],
      });
    });

    test('rows as maps', () async {
      store.onCall = (_, _) => [
        {'a': 1, 'b': 'x'},
      ];
      expect(
        await books.procedure<List<Map<String, Object?>>>(_rows, const []),
        [
          {'a': 1, 'b': 'x'},
        ],
      );
    });

    test('a method that returns nothing ignores what the function '
        'returns', () async {
      store.onCall = (_, _) => [
        {'archive_books': null},
      ];
      await books.procedure<void>(_archive, [1900]);
      expect(store.calls.single.$1, 'archive_books');
      expect(store.calls.single.$2, {'older_than': 1900});
    });

    test('a Stream calls the function when it is listened to', () async {
      store.onCall = (_, _) => [_bookRow];
      final stream = books.procedureStream<Book>(_streamed, [Genre.science]);
      expect(stream, isA<Stream<Book>>());
      expect(store.calls, isEmpty);
      expect((await stream.toList()).single.title, 'Dune');
      expect(store.calls, hasLength(1));
    });

    test('a method asked for the wrong way, or not given, is a misuse', () {
      expect(
        () => books.procedure<Object?>(_streamed, [Genre.science]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('procedureStream'),
          ),
        ),
      );
      expect(
        () => books.procedureStream<Book>(_byGenre, [Genre.science]),
        throwsA(isA<StateError>()),
      );
      expect(
        () => books.procedure<int>(
          const ProcedureMethod('other', Procedure('other')),
          const [],
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('was not given as a function'),
          ),
        ),
      );
    });

    test('the wrong number of arguments is a misuse', () async {
      await expectLater(
        books.procedure<int>(_total, [1]),
        throwsA(
          isA<InvalidDataAccessApiUsageException>().having(
            (e) => e.message,
            'message',
            contains('1 argument(s) for 2 parameter(s)'),
          ),
        ),
      );
    });

    test('what the store fails with is a DataAccessException', () async {
      store.onCall = (_, _) =>
          throw PermissionDeniedDataAccessException('permission denied');
      await expectLater(
        books.procedure<int>(_total, [1, 2]),
        throwsA(isA<PermissionDeniedDataAccessException>()),
      );
      await expectLater(
        books.procedureStream<Book>(_streamed, [Genre.science]).toList(),
        throwsA(isA<PermissionDeniedDataAccessException>()),
      );
      store.onCall = (_, _) => throw const FormatException('not json');
      await expectLater(
        books.procedure<int>(_total, [1, 2]),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
      await expectLater(
        books.procedureStream<Book>(_streamed, [Genre.science]).toList(),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
    });

    test('the naming strategy of the mapping names the arguments', () async {
      final shouting =
          RepositoryFactory(
            mappingContext: testContext(naming: const _Shouting()),
            converter: converter,
            stores: [store],
          ).operations<Book, int>(
            'Books',
            annotations: const [UseStore('functions')],
            functions: const [_total],
          );
      store.onCall = (_, _) => [
        {'n': 1},
      ];
      await shouting.procedure<int>(_total, [1, 2]);
      expect(store.calls.single.$2.keys, ['AUTHOR_ID', 'SINCE_YEAR']);
    });

    group('problems of the repository', () {
      test('a store without functions', () {
        expect(
          () => create(PlainStore(store.inner)),
          invalid([
            'Books.totalOf: @Procedure needs a store with database functions',
            'the rest store is none',
            'Books.archive: @Procedure',
          ]),
        );
      });

      test('a store that says it has functions but is no '
          'FunctionDataStore', () {
        expect(
          () => create(
            PlainStore(
              store.inner,
              capabilities: const DataStoreCapabilities(functions: true),
            ),
            functions: const [_total],
          ),
          invalid(['Books.totalOf', 'is no FunctionDataStore']),
        );
      });

      test('a Page or a Slice, and a class that is not described', () {
        expect(
          () => create(
            store,
            functions: const [
              ProcedureMethod(
                'paged',
                Procedure('books_of'),
                shape: QueryShape.page,
                element: ClassType<Book>(),
              ),
              ProcedureMethod(
                'odd',
                Procedure('odd'),
                element: ClassType<Uri>(),
              ),
            ],
          ),
          invalid([
            'Books.paged: @Procedure cannot return a page',
            'Books.odd: Uri cannot be built from rows',
          ]),
        );
      });
    });
  });

  group('the JDBC store', () {
    late FakeJdbcDriver driver;
    late PooledDataSource ds;
    late JdbcDataStore store;
    late RepositoryOperations<Book, int> books;

    void build(SqlDialect dialect) {
      driver = FakeJdbcDriver(dialect: dialect);
      ds = fakePool(driver);
      store = JdbcDataStore(dataSource: ds, converter: converter);
      books =
          RepositoryFactory(
            mappingContext: testContext(),
            converter: converter,
            stores: [store],
          ).operations<Book, int>(
            'Books',
            annotations: const [UseStore('jdbc')],
            functions: _all,
          );
    }

    test('PostgreSQL: select * from the function with named notation, the '
        'values bound', () async {
      build(const PostgresDialect());
      driver.onConnect = (connection) =>
          connection.onQuery = (_, _) => JdbcResult(
            ['books_total'],
            [
              [5],
            ],
          );
      expect(await books.procedure<int>(_total, [12, 1960]), 5);
      final connection = driver.connections.single;
      expect(connection.statements, [
        'select * from "books_total"("author_id" => ?, "since_year" => ?)',
      ]);
      expect(connection.parameters.single, [12, 1960]);
    });

    test('a schema is quoted apart, a list is one array argument, no '
        'argument is an empty list', () async {
      build(const PostgresDialect());
      await books.procedure<List<Author>>(_authors, [
        ['Dune', 'Emma'],
      ]);
      await books.procedure<Set<String>>(_titles, const []);
      final connection = driver.connections.single;
      expect(connection.statements, [
        'select * from "public"."authors_of"("titles" => ?)',
        'select * from "titles"()',
      ]);
      expect(connection.parameters.first, [
        ['Dune', 'Emma'],
      ]);
    });

    test('a name cannot leave its quotes', () {
      expect(
        const PostgresDialect().functionCall('f"(); drop table x; --', [
          'a" => 1); --',
        ]),
        'select * from "f""(); drop table x; --"("a"" => 1); --" => ?)',
      );
    });

    test('rows of the entity go through the dialect and the store', () async {
      build(const PostgresDialect());
      driver.onConnect = (connection) =>
          connection.onQuery = (_, _) => JdbcResult(
            ['id', 'title', 'price', 'available', 'version', 'genre'],
            [
              // A numeric comes as text from PostgreSQL.
              [7, 'Dune', '9.50', true, 2, 'science'],
            ],
          );
      final found = await books.procedure<List<Book>>(_byGenre, [
        Genre.science,
      ]);
      expect(found.single.price, 9.5);
      expect(found.single.genre, Genre.science);
      // The enum is bound as its name, as a column value is.
      expect(driver.connections.single.parameters.single, ['science']);
    });

    test(
      'the call runs on the connection of the running transaction',
      () async {
        build(const PostgresDialect());
        await TransactionTemplate(store.transactionManager).execute((_) async {
          await books.procedure<void>(_archive, [1900]);
          await books.procedure<void>(_archive, [1950]);
        });
        expect(driver.connections, hasLength(1));
        expect(driver.connections.single.calls, [
          'begin',
          'query select * from "archive_books"("older_than" => ?) [1900]',
          'query select * from "archive_books"("older_than" => ?) [1950]',
          'commit',
        ]);
      },
    );

    test(
      'an error of the database is translated, with the statement',
      () async {
        build(const PostgresDialect());
        driver.onConnect = (connection) => connection.failOn = (_) =>
            const SqlError('permission denied for function', sqlState: '42501');
        await expectLater(
          books.procedure<void>(_archive, [1900]),
          throwsA(
            isA<PermissionDeniedDataAccessException>().having(
              (e) => e.sql,
              'sql',
              'select * from "archive_books"("older_than" => ?)',
            ),
          ),
        );
      },
    );

    test('a dialect without functions: the repository is refused, and a '
        'call of the store too', () async {
      expect(
        () => build(const SqliteDialect()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Books.totalOf: @Procedure needs a store with database'),
              contains('the jdbc store is none'),
            ),
          ),
        ),
      );
      await expectLater(
        store.callFunction('f', const {}),
        throwsA(isA<InvalidDataAccessResourceUsageException>()),
      );
      expect(const SqliteDialect().supportsFunctions, isFalse);
      expect(
        () => const SqliteDialect().functionCall('f', const []),
        throwsUnsupportedError,
      );
    });
  });
}

// Names in upper snake case.
final class _Shouting extends NamingStrategy {
  const _Shouting();

  @override
  String snakeCase(String name) => super.snakeCase(name).toUpperCase();
}
