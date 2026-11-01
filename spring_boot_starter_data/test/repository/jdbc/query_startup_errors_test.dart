import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../../mapping/support.dart';
import '../../schema/support.dart' show memorySource;

// @Query methods as the generator describes them, written by hand to make
// the mistakes generated code could not make: the build has checked what
// does not depend on the run time (the parameters of the text, the shape of
// the result, the names of tables and columns; see the generator's tests),
// and the factory refuses what is left, with every reason.
const book = ClassType<Book>();
const integer = ClassType<int>();

/// A class nothing describes.
class Unknown {}

int plusOne(JdbcRow row) => 1;

QueryMethod query(
  String sql, {
  List<String> parameters = const ['year'],
  TypeInfo<Object?> element = book,
  QueryShape shape = QueryShape.list,
  Map<String, Type> entities = const {},
  List<QueryExpression?> expressions = const [],
}) => QueryMethod(
  'find',
  Query(sql),
  parameters: parameters,
  element: element,
  shape: shape,
  entities: entities,
  expressions: expressions,
);

void main() {
  late DataSource source;
  late RelationalMappingContext mapping;
  late RepositoryFactory factory;

  Future<void> run(
    FutureOr<void> Function() body, {
    Map<String, Object?> properties = const {},
  }) async {
    source = await memorySource();
    mapping = testContext();
    factory = RepositoryFactory(
      mappingContext: mapping,
      converter: EntityConverter(),
      jdbcDataSources: {RepositoryFactory.primaryDataSource: source},
      environment: StandardEnvironment(systemEnvironment: const {})
        ..propertySources.addFirst(MapPropertySource('test', properties)),
    );
    await body();
  }

  RepositoryOperations<Book, int> create(
    List<QueryMethod> queries, {
    List<Object> annotations = const [UseStore('jdbc')],
  }) => factory.operations<Book, int>(
    'BrokenRepository',
    annotations: annotations,
    queries: queries,
  );

  Matcher invalid(List<String> reasons) => throwsA(
    isA<StateError>().having(
      (e) => e.message,
      'message',
      allOf([
        startsWith('Invalid repository BrokenRepository:'),
        for (final reason in reasons) contains(reason),
      ]),
    ),
  );

  void expectInvalid(QueryMethod method, List<String> reasons) =>
      expect(() => create([method]), invalid(reasons));

  test(
    'a valid query is compiled',
    () => run(() async {
      final operations = create([
        query('select * from books where year = :year'),
      ]);
      expect(operations.store, isA<JdbcDataStore>());
      expect(
        operations.transactionManager,
        isA<DataSourceTransactionManager>(),
      );
    }),
  );

  test(
    'every kind of query is compiled: what the build checked is not checked',
    () => run(() async {
      // Written as the build writes them, without a second look at the SQL:
      // a plain ?, a :name that is no parameter are refused by the build,
      // and so nothing here repeats it.
      expect(
        () => create([
          query('select * from books where year = :year'),
          query(
            'update books set year = 0 where year = :year',
            shape: QueryShape.single,
          ),
          query('select count(*) from books', element: integer),
          query(
            'select 1',
            parameters: [],
            shape: QueryShape.single,
            element: integer,
          ),
          const QueryMethod(
            'change',
            Query('update books set year = 0 where year = :year'),
            parameters: ['year'],
            change: QueryChange.nothing,
          ),
        ]),
        returnsNormally,
      );
    }),
  );

  test(
    '@Query on the memory store is refused',
    () => run(() async {
      expect(
        () => create(
          [query('select * from books where year = :year')],
          annotations: const [UseStore('memory')],
        ),
        invalid(['BrokenRepository.find', '@Query needs a SQL store']),
      );
    }),
  );

  test(
    'a class that is not described cannot be built from rows',
    () => run(() async {
      expectInvalid(
        query(
          'select * from books',
          parameters: [],
          element: const ClassType<Unknown>(),
        ),
        ['Unknown cannot be built from rows', '@Introspected'],
      );
      // A row mapper needs no description.
      expect(
        () => create([
          const QueryMethod(
            'mapped',
            Query('select 1', rowMapper: plusOne),
            element: ClassType<Unknown>(),
          ),
        ]),
        returnsNormally,
      );
    }),
  );

  test(
    'placeholders and expressions are checked',
    () => run(() async {
      expectInvalid(
        query(
          r'select * from books limit ${no.such.property}',
          parameters: [],
        ),
        ['no.such.property'],
      );
      expectInvalid(
        query('select * from books where year = :#{1 +}'),
        ['the expression :#{1 +} is invalid'],
      );
    }),
  );

  // The build cannot read the text of a `${property}`: what it resolves to
  // is checked at the start, as the build checks any other text.
  test(
    'text from a placeholder: an expression that is not closed',
    () => run(
      properties: const {'where': 'year = :#{1 +'},
      () async {
        expectInvalid(
          query(r'select * from books where ${where}', parameters: []),
          ['an expression is not closed: :#{1 +'],
        );
      },
    ),
  );

  test(
    'text from a placeholder: an expression outside of a parameter',
    () => run(
      properties: const {'where': 'year = #{1 + 1}'},
      () async {
        expectInvalid(
          query(r'select * from books where ${where}', parameters: []),
          ['#{1 + 1} is not allowed in the SQL text', ':#{1 + 1}'],
        );
      },
    ),
  );

  test(
    'a Postgres literal holds no entity, expression or marker',
    () => run(
      properties: const {'text': r'$q$ {Nope} #{x} :#{ $q$'},
      () async {
        expect(
          () => create([
            query(
              r'select ${text}, $$ {Nope} :#{ $$ from books',
              parameters: [],
            ),
          ]),
          returnsNormally,
        );
        // Outside of the literal, the same text is wrong.
        expectInvalid(
          query('select * from {Nope}', parameters: []),
          ['{Nope} names an entity that is not described'],
        );
      },
    ),
  );

  test(
    'an entity placeholder names an entity the mapping describes',
    () => run(() async {
      expect(
        () => create([
          query(
            'select {Book.title} from {Book} where {Book.year} = :year',
            entities: const {'Book': Book},
          ),
        ]),
        returnsNormally,
      );
      expectInvalid(
        query('select * from {Book}'),
        ['{Book} names an entity that is not described'],
      );
      expectInvalid(
        query('select * from {Book}', entities: const {'Book': Unknown}),
        ['{Book} names an entity that is not described'],
      );
      expectInvalid(
        query(
          'select {Book.nope} from {Book}',
          entities: const {'Book': Book},
        ),
        ['{Book.nope}: Book has no column for nope'],
      );
    }),
  );

  test(
    'the compiled expressions are as many as the markers',
    () => run(() async {
      Object? one(List<Object?> arguments, QueryExpressionContext context) => 1;
      expect(
        () => create([
          query(
            'select * from books where year = :#{#year} or year = :#{1}',
            expressions: [one, null],
          ),
        ]),
        returnsNormally,
      );
      expectInvalid(
        query(
          'select * from books where year = :#{#year} or year = :#{1}',
          expressions: [one],
        ),
        ['1 compiled expression(s) for 2 `:#{...}` marker(s)'],
      );
      // None given: all are interpreted.
      expect(
        () => create([
          query('select * from books where year = :#{#year}'),
        ]),
        returnsNormally,
      );
    }),
  );

  test(
    'every problem of the repository is reported, not only the first',
    () => run(() async {
      expect(
        () => create([
          query(r'select * from books limit ${no.such}', parameters: []),
          query('select * from books where year = :#{1 +}'),
          query('select * from books', element: const ClassType<Unknown>()),
        ]),
        invalid(['no.such', ':#{1 +} is invalid', 'Unknown cannot be built']),
      );
    }),
  );

  group('the store of a repository', () {
    RepositoryFactory factoryWith(
      Map<String, DataSource> sources, {
      String defaultStore = 'memory',
    }) => RepositoryFactory(
      mappingContext: mapping,
      converter: factory.converter,
      jdbcDataSources: sources,
      defaultStore: defaultStore,
    );

    DataStore storeOf(RepositoryFactory factory, List<Object> annotations) =>
        factory
            .operations<Book, int>('BrokenRepository', annotations: annotations)
            .store;

    test(
      '@UseStore(jdbc) is the primary data source; @UseDataSource names one',
      () => run(() async {
        final factory = factoryWith({
          RepositoryFactory.primaryDataSource: source,
          'reports': source,
        });
        final primary = storeOf(factory, const [UseStore('jdbc')]);
        expect(primary, isA<JdbcDataStore>());
        expect(primary.name, 'jdbc');
        expect(storeOf(factory, const [UseStore('jdbc')]), same(primary));
        final reports = storeOf(factory, const [
          UseStore('jdbc'),
          UseDataSource('reports'),
        ]);
        expect(reports.name, 'jdbc:reports');
        expect(reports, isNot(same(primary)));
        // A data source name alone selects its SQL store.
        expect(
          storeOf(factory, const [UseDataSource('reports')]),
          same(reports),
        );
        // Memory is still what the annotation says.
        expect(
          storeOf(factory, const [UseStore('memory')]),
          isA<InMemoryDataStore>(),
        );
        expect(storeOf(factory, const []), isA<InMemoryDataStore>());
      }),
    );

    test(
      'the default store may be the SQL one',
      () => run(() async {
        final factory = factoryWith({
          RepositoryFactory.primaryDataSource: source,
        }, defaultStore: 'jdbc');
        expect(storeOf(factory, const []), isA<JdbcDataStore>());
        expect(
          storeOf(factory, const [UseStore('memory')]),
          isA<InMemoryDataStore>(),
        );
      }),
    );

    test(
      'a missing data source is a startup error naming the ones there are',
      () => run(() async {
        final empty = factoryWith(const {});
        expect(
          () => storeOf(empty, const [UseStore('jdbc')]),
          invalid(['primary data source', 'not configured']),
        );
        final factory = factoryWith({
          RepositoryFactory.primaryDataSource: source,
        });
        expect(
          () => storeOf(factory, const [
            UseStore('jdbc'),
            UseDataSource('nope'),
          ]),
          invalid(["@UseDataSource('nope') names no data source", 'default']),
        );
        expect(
          () => storeOf(factory, const [UseDataSource('nope')]),
          invalid(["@UseDataSource('nope')", 'none is configured', 'default']),
        );
      }),
    );

    test(
      'repositories on the same data source share one store and one manager',
      () => run(() async {
        final a = create(const []);
        final b = create(const []);
        expect(a.store, same(b.store));
        expect(a.transactionManager, same(b.transactionManager));
        expect(
          (a.transactionManager! as DataSourceTransactionManager).dataSource,
          same(source),
        );
      }),
    );
  });
}
