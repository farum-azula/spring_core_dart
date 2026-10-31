import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

// Repositories as the generator describes them, written by hand to make the
// mistakes generated code could not compile: the factory refuses them at
// startup, with every reason.
ProxyMethod method(
  String name, {
  List<BeanParameter> parameters = const [],
  TypeInfo<Object?> returnType = const DynamicType(),
  bool isFuture = true,
  bool isVoid = false,
  List<Object> annotations = const [],
}) => ProxyMethod(
  name,
  parameters: parameters,
  returnType: returnType,
  isFuture: isFuture,
  isVoid: isVoid,
  annotations: annotations,
  call: (target, arguments) => null,
);

BeanParameter parameter(String name, TypeInfo<Object?> type) =>
    BeanParameter(name, type: type, isRequired: true);

const book = ClassType<Book>();
const bookList = ListType<Book>(book);
const integer = ClassType<int>();
const bookPage = GenericType<Page<Book>>([book]);

/// A class nothing describes.
class Unknown {}

int wrongMapper(int x) => x;

Object? goodMapper(JdbcRow row) => row.values.first;

Object? goodExtractor(JdbcResult result) => result.rows.length;

InterfaceMetadata<Object> repository(
  List<ProxyMethod> methods, {
  List<Object> annotations = const [UseStore('jdbc')],
  String name = 'BrokenRepository',
}) => InterfaceMetadata<Object>(
  typeName: name,
  methods: methods,
  annotations: annotations,
  supertypeArguments: {
    'DataRepository': [book, integer],
  },
);

ProxyMethod query(
  String sql, {
  List<BeanParameter>? parameters,
  TypeInfo<Object?> returnType = bookList,
  Query? annotation,
  List<Object> more = const [],
  bool isVoid = false,
  bool isFuture = true,
}) => method(
  'find',
  parameters: parameters ?? [parameter('year', integer)],
  returnType: returnType,
  isVoid: isVoid,
  isFuture: isFuture,
  annotations: [annotation ?? Query(sql), ...more],
);

void main() {
  late Jdbc jdbc;

  Future<void> run(FutureOr<void> Function() body) => withJdbc((j) async {
    jdbc = j;
    await body();
  });

  RepositoryInvocationHandler create(InterfaceMetadata<Object> metadata) =>
      jdbc.factory.create(metadata) as RepositoryInvocationHandler;

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

  void expectInvalid(ProxyMethod method, List<String> reasons) =>
      expect(() => create(repository([method])), invalid(reasons));

  test(
    'a valid query is compiled',
    () => run(() async {
      final handler = create(
        repository([query('select * from books where year = :year')]),
      );
      expect(handler.store, isA<JdbcDataStore>());
      expect(handler.transactionManager, isA<DataSourceTransactionManager>());
    }),
  );

  test(
    'a named parameter that matches no parameter names the ones there are',
    () => run(() async {
      expectInvalid(
        query('select * from books where year = :yeer'),
        [':yeer matches no parameter', 'year'],
      );
      expectInvalid(
        query('select * from books where year = :book.year'),
        ['book.year', '#book.year'],
      );
      expectInvalid(
        query('select * from books where year = :year', parameters: []),
        [':year matches no parameter', 'none'],
      );
    }),
  );

  test(
    'a plain ? marker is refused',
    () => run(() async {
      expectInvalid(query('select * from books where year = ?'), ['? marker']);
    }),
  );

  test(
    'a Pageable or Sort is not a named parameter',
    () => run(() async {
      expectInvalid(
        query(
          'select * from books where year = :pageable',
          parameters: [
            parameter('pageable', const ClassType<Pageable>()),
          ],
        ),
        [':pageable matches no parameter'],
      );
    }),
  );

  test(
    '@Query on the memory store is refused',
    () => run(() async {
      expect(
        () => create(
          repository(
            [query('select * from books where year = :year')],
            annotations: const [UseStore('memory')],
          ),
        ),
        invalid(['BrokenRepository.find', '@Query needs a SQL store']),
      );
    }),
  );

  test(
    'a result that cannot be built is refused',
    () => run(() async {
      expectInvalid(
        query(
          'select * from books',
          parameters: [],
          returnType: const ListType<Unknown>(ClassType<Unknown>()),
        ),
        ['Unknown cannot be built from rows', '@Introspected'],
      );
      expectInvalid(
        query(
          'select * from books',
          parameters: [],
          returnType: const ListType<Object?>(DynamicType()),
        ),
        ['not known'],
      );
    }),
  );

  test(
    'a Page or Slice needs a Pageable',
    () => run(() async {
      expectInvalid(
        query(
          'select * from books where year = :year',
          returnType: bookPage,
        ),
        ['page needs a Pageable'],
      );
      expectInvalid(
        query(
          'select * from books where year = :year',
          returnType: const GenericType<Slice<Book>>([book]),
        ),
        ['slice needs a Pageable'],
      );
    }),
  );

  test(
    '@Modifying returns int, bool or nothing; nothing else changes data',
    () => run(() async {
      expectInvalid(
        query(
          'update books set year = 0 where year = :year',
          more: const [Modifying()],
        ),
        ['@Modifying returns the rows changed'],
      );
      expectInvalid(
        query(
          'select * from books where year = :year',
          returnType: const ClassType<String>(),
          more: const [Modifying()],
        ),
        ['@Modifying returns the rows changed'],
      );
      expectInvalid(
        query(
          'select * from books where year = :year',
          isVoid: true,
        ),
        ['a change needs @Modifying'],
      );
      expect(
        () => create(
          repository([
            query(
              'update books set year = 0 where year = :year',
              returnType: integer,
              more: const [Modifying()],
            ),
            query(
              'update books set year = 0 where year = :year',
              returnType: const DynamicType.forVoid(),
              isVoid: true,
              more: const [Modifying()],
            ),
          ]),
        ),
        returnsNormally,
      );
    }),
  );

  test(
    'rowMapper and resultSetExtractor: one, and a function of the right shape',
    () => run(() async {
      expectInvalid(
        query(
          '',
          annotation: const Query(
            'select 1',
            rowMapper: goodMapper,
            resultSetExtractor: goodExtractor,
          ),
          parameters: [],
        ),
        ['both rowMapper and resultSetExtractor'],
      );
      expectInvalid(
        query(
          '',
          annotation: const Query('select 1', rowMapper: wrongMapper),
          parameters: [],
        ),
        ['rowMapper is a', 'takes a JdbcRow'],
      );
      expectInvalid(
        query(
          '',
          annotation: const Query(
            'select 1',
            resultSetExtractor: goodMapper,
          ),
          parameters: [],
        ),
        ['resultSetExtractor is a', 'takes a JdbcResult'],
      );
      expectInvalid(
        query(
          '',
          annotation: const Query(
            'select 1',
            resultSetExtractor: goodExtractor,
          ),
          parameters: [parameter('page', const ClassType<PageRequest>())],
          returnType: bookPage,
        ),
        ['whole result', 'cannot be paged'],
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
        query(
          'select * from #{#tableName} where year = :year',
          parameters: [parameter('year', integer)],
        ),
        ['#{#tableName} is not allowed', ':#{#tableName}'],
      );
      expectInvalid(
        query('select * from books where year = :#{1 +}'),
        ['the expression :#{1 +} is invalid'],
      );
      expectInvalid(
        query('select * from books where year = :#{#year'),
        ['is not closed'],
      );
    }),
  );

  test(
    'an empty query, a synchronous method, @Lock and a stray countQuery',
    () => run(() async {
      expectInvalid(query('  '), ['@Query has no SQL']);
      expectInvalid(
        query(
          '',
          annotation: const Query('', name: 'books.byYear'),
        ),
        ['named queries'],
      );
      expectInvalid(
        query(
          'select * from books where year = :year',
          isFuture: false,
        ),
        ['asynchronous'],
      );
      expectInvalid(
        query(
          'select * from books where year = :year',
          more: const [Lock(LockMode.pessimisticWrite)],
        ),
        ['@Lock is for the derived find methods', 'for update'],
      );
      expectInvalid(
        query(
          '',
          annotation: const Query(
            'select * from books where year = :year',
            countQuery: 'select count(*) from books',
          ),
        ),
        ['countQuery is for a method that returns a Page'],
      );
    }),
  );

  test(
    'every problem of the repository is reported, not only the first',
    () => run(() async {
      expect(
        () => create(
          repository([
            query('select * from books where year = :yeer'),
            query('select * from books where year = ?'),
            query('select * from books where year = :year', isFuture: false),
          ]),
        ),
        invalid([':yeer matches no parameter', '? marker', 'asynchronous']),
      );
    }),
  );

  group('the store of a repository', () {
    RepositoryFactory factoryWith(
      Map<String, DataSource> sources, {
      String defaultStore = 'memory',
    }) => RepositoryFactory(
      mappingContext: jdbc.mapping,
      converter: jdbc.factory.converter,
      jdbcDataSources: sources,
      defaultStore: defaultStore,
    );

    DataStore storeOf(
      RepositoryFactory factory,
      List<Object> annotations,
    ) => (factory.create(
      repository(const [], annotations: annotations),
    ) as RepositoryInvocationHandler).store;

    test(
      '@UseStore(jdbc) is the primary data source; @UseDataSource names one',
      () => run(() async {
        final factory = factoryWith({
          RepositoryFactory.primaryDataSource: jdbc.dataSource,
          'reports': jdbc.dataSource,
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
          RepositoryFactory.primaryDataSource: jdbc.dataSource,
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
          RepositoryFactory.primaryDataSource: jdbc.dataSource,
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
        final a = create(repository(const []));
        final b = create(repository(const []));
        expect(a.store, same(b.store));
        expect(a.transactionManager, same(b.transactionManager));
        expect(
          (a.transactionManager! as DataSourceTransactionManager).dataSource,
          same(jdbc.dataSource),
        );
      }),
    );
  });
}
