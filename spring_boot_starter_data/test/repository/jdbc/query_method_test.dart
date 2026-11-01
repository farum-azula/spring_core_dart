// What the run time does with the QueryMethod the build writes for a @Query:
// the expressions the build compiled (and those it leaves to the SpEL
// interpreter), the entity placeholders (the mapping names the table and the
// columns), and the descriptor itself.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../../mapping/support.dart' as mapped;
import '../../schema/support.dart' show memorySource;
import 'support.dart';

// The columns of this strategy have a prefix: `title` is stored in `c_title`
// (a `@Column` still wins).
class _PrefixNaming extends NamingStrategy {
  const _PrefixNaming();

  @override
  String columnName(String propertyName, Column? column) =>
      column?.value ?? 'c_${snakeCase(propertyName)}';
}

void main() {
  setUpAll(() => SpringLog.handler = (_) {});

  group('the descriptor', () {
    test('binds all the parameters but the Pageable and the Sort', () {
      const method = QueryMethod(
        'find',
        Query('select 1'),
        parameters: ['year', 'sort', 'title', 'page'],
        sort: 1,
        pageable: 3,
        element: ClassType<int>(),
      );
      expect(method.boundParameters, {'year': 0, 'title': 2});
      expect(method.shape, QueryShape.list);
    });

    test('a method reads or changes', () {
      expect(
        () => QueryMethod('find', const Query('select 1')),
        throwsA(isA<AssertionError>()),
      );
      const change = QueryMethod(
        'change',
        Query('delete from books'),
        change: QueryChange.any,
      );
      expect(change.element, isNull);
    });
  });

  group('the context of a compiled expression', () {
    test('has the bean factory and the environment', () async {
      await withJdbc(properties: const ['books.cutoff=1990'], (jdbc) async {
        final context = QueryExpressionContext(
          entityName: '"books"',
          methodName: 'find',
          beanFactory: jdbc.context.getBean<BeanFactory>(),
          environment: jdbc.context.getBean<Environment>(),
        );
        expect((context.bean('years') as Years).cutoff, 1990);
        expect(context.environment!.getProperty('books.cutoff'), '1990');
      });
    });

    test('answers what is missing with a clear error or the default', () {
      const context = QueryExpressionContext(
        entityName: '"books"',
        methodName: 'find',
      );
      expect(
        () => context.bean('years'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('no BeanFactory to look up the bean @years'),
          ),
        ),
      );
      expect(context.environment, isNull);
    });
  });

  group('compiled expressions', () {
    Future<void> run(
      Future<void> Function(Jdbc jdbc) body, {
      List<String> properties = const ['books.cutoff=1990'],
    }) => withJdbc(properties: properties, (jdbc) async {
      await seedBooks(jdbc.sqlAuthors, jdbc.sqlBooks);
      await body(jdbc);
    });

    RepositoryOperations<Book, int> operationsFor(
      Jdbc jdbc,
      List<QueryMethod> queries,
    ) => jdbc.factory.operations<Book, int>(
      'CompiledRepository',
      annotations: const [UseStore('jdbc')],
      queries: queries,
    );

    test(
      'a compiled expression runs, and its text is never parsed',
      () => run((jdbc) async {
        final calls = <List<Object?>>[];
        final method = QueryMethod(
          'since',
          // Not SpEL at all: the interpreter would refuse it.
          const Query(
            'select * from books where year >= :#{this (} order by id',
          ),
          parameters: const ['year'],
          element: const ClassType<Book>(),
          expressions: [
            (arguments, context) {
              calls.add(arguments);
              return arguments.first;
            },
          ],
        );
        final operations = operationsFor(jdbc, [method]);
        expect(
          ids(await operations.query<List<Book>>(method, [1992])),
          [4, 5, 6, 7, 8],
        );
        expect(calls, [
          [1992],
        ]);
        // At each call.
        await operations.query<List<Book>>(method, [2001]);
        expect(calls, hasLength(2));
      }),
    );

    test(
      'the context gives the beans, the environment, the table and the method',
      () => run((jdbc) async {
        QueryExpressionContext? seen;
        final method = QueryMethod(
          'sinceCutoff',
          const Query('select * from books where year >= :#{@years.cutoff}'),
          element: const ClassType<Book>(),
          expressions: [
            (arguments, context) {
              seen = context;
              return (context.bean('years') as Years).cutoff;
            },
          ],
        );
        final operations = operationsFor(jdbc, [method]);
        final compiled = ids(await operations.query<List<Book>>(method, []));
        // The same as the interpreter gives.
        expect(compiled, ids(await jdbc.sqlBooks.sinceCutoff()));
        expect(compiled, [4, 5, 6, 7, 8]);
        expect(seen!.entityName, '"books"');
        expect(seen!.methodName, 'sinceCutoff');
        expect(seen!.environment!.getProperty('books.cutoff'), '1990');
      }),
    );

    test(
      'an expression left null is interpreted, among compiled ones',
      () => run((jdbc) async {
        final method = QueryMethod(
          'between',
          const Query(
            'select * from books where year >= :#{@years.cutoff} '
            'and year < :#{#year} order by id',
          ),
          parameters: const ['year'],
          element: const ClassType<Book>(),
          expressions: [(arguments, context) => 1990, null],
        );
        final operations = operationsFor(jdbc, [method]);
        expect(ids(await operations.query<List<Book>>(method, [2000])), [4, 5]);
      }),
    );

    test(
      'the expressions of the count query follow those of the SQL',
      () => run((jdbc) async {
        final order = <String>[];
        final method = QueryMethod(
          'page',
          const Query(
            'select * from books where year > :#{#year} order by id',
            countQuery: 'select count(*) from books where year > :#{#year}',
          ),
          parameters: const ['year', 'pageable'],
          pageable: 1,
          shape: QueryShape.page,
          element: const ClassType<Book>(),
          expressions: [
            (arguments, context) {
              order.add('sql');
              return arguments.first;
            },
            (arguments, context) {
              order.add('count');
              return arguments.first;
            },
          ],
        );
        final operations = operationsFor(jdbc, [method]);
        final page = await operations.query<Page<Book>>(method, [
          1984,
          PageRequest.of(0, 2),
        ]);
        expect(ids(page.content), [4, 5]);
        expect(page.totalElements, 5);
        expect(order, ['sql', 'count']);
      }),
    );

    test(
      'a failing expression is reported with its text',
      () => run((jdbc) async {
        final method = QueryMethod(
          'broken',
          const Query('select * from books where year = :#{boom}'),
          element: const ClassType<Book>(),
          expressions: [(arguments, context) => throw StateError('no')],
        );
        final operations = operationsFor(jdbc, [method]);
        await expectLater(
          operations.query<List<Book>>(method, []),
          throwsA(
            isA<InvalidDataAccessApiUsageException>().having(
              (e) => e.message,
              'message',
              allOf(contains(':#{boom} failed'), contains('no')),
            ),
          ),
        );
      }),
    );

    test(
      'a compiled expression is not checked as SpEL, an interpreted one is',
      () => run((jdbc) async {
        const text = 'select * from books where year = :#{1 +}';
        final compiled = QueryMethod(
          'compiled',
          const Query(text),
          element: const ClassType<Book>(),
          expressions: [(arguments, context) => 1965],
        );
        final operations = operationsFor(jdbc, [compiled]);
        expect(ids(await operations.query<List<Book>>(compiled, [])), [1]);
        expect(
          () => operationsFor(jdbc, [
            const QueryMethod(
              'interpreted',
              Query(text),
              element: ClassType<Book>(),
            ),
          ]),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('the expression :#{1 +} is invalid'),
            ),
          ),
        );
      }),
    );
  });

  group('entity placeholders follow the mapping', () {
    test('the naming strategy and @Column name the columns', () async {
      final mapping = mapped.testContext(naming: const _PrefixNaming());
      final db = await memorySource();
      await SchemaCreator(db).create([
        mapping.getRequiredPersistentEntity<mapped.Author>(),
        mapping.getRequiredPersistentEntity<mapped.Book>(),
      ]);
      const method = QueryMethod(
        'titles',
        Query(
          'select {Book.title} from {Book} where {Book.year} >= :year '
          'and {Book.author} is null order by {Book.year}',
        ),
        parameters: ['year'],
        element: ClassType<String>(),
        entities: {'Book': mapped.Book},
      );
      final operations =
          RepositoryFactory(
            mappingContext: mapping,
            converter: EntityConverter(),
            jdbcDataSources: {RepositoryFactory.primaryDataSource: db},
          ).operations<mapped.Book, int>(
            'TitlesRepository',
            annotations: const [UseStore('jdbc')],
            queries: [method],
          );
      await operations.saveAll([
        mapped.Book(title: 'Dune', year: 1965),
        mapped.Book(title: 'Emma', year: 1815),
        mapped.Book(title: 'Neuromancer', year: 1984),
      ]);

      final statements = <String>[];
      SpringLog.setLevel('spring.jdbc.core.JdbcTemplate', SpringLogLevel.debug);
      final stop = SpringLog.listen((record) {
        if (record.loggerName == 'spring.jdbc.core.JdbcTemplate') {
          statements.add(record.message);
        }
      });
      try {
        expect(await operations.query<List<String>>(method, [1900]), [
          'Dune',
          'Neuromancer',
        ]);
      } finally {
        stop();
        SpringLog.resetLevels();
      }
      // The table by @Table, the columns by the strategy, `author` by its
      // @Column('writer_id').
      expect(
        statements.single,
        contains(
          'select "c_title" from "books" where "c_year" >= ? '
          'and "writer_id" is null order by "c_year"',
        ),
      );
    });
  });
}
