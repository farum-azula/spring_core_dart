import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../mapping/support.dart';

// What the build cannot know stays a startup check: the store and the data
// source of a repository, its entity, its @Query methods. The names of the
// derived queries, the CRUD signatures and the @Query methods themselves are
// checked by the build. The mistakes are made by hand, as the generated class
// could not make them.
QueryMethod query(String name, {String sql = 'select * from books'}) =>
    QueryMethod(name, Query(sql), element: const ClassType<Book>());

void main() {
  late RepositoryFactory factory;

  setUp(
    () => factory = RepositoryFactory(
      mappingContext: testContext(),
      converter: EntityConverter(),
    ),
  );

  RepositoryOperations<Book, int> operations({
    List<Object> annotations = const [],
    List<QueryMethod> queries = const [],
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

  test('a valid repository is created, on the memory store by default', () {
    final created = operations();
    expect(created.typeName, 'BrokenRepository');
    expect(created.entity.type, Book);
    expect(created.store.name, 'memory');
    expect(created.transactionManager, isA<InMemoryTransactionManager>());
  });

  test('@Query needs a SQL store', () {
    expect(
      () => operations(queries: [query('search')]),
      invalid(['BrokenRepository.search', '@Query', 'SQL store']),
    );
    expect(
      () => operations(queries: [query('search', sql: 'select 1')]),
      invalid(['@Query', 'spring.datasource.url']),
    );
  });

  test('an unknown store names the known ones', () {
    expect(
      () => operations(annotations: const [UseStore('cassandra')]),
      invalid(["@UseStore('cassandra')", 'memory']),
    );
    expect(
      () => operations(annotations: const [UseStore('jdbc')]),
      invalid(["@UseStore('jdbc')", 'not configured']),
    );
  });

  test('@UseDataSource needs a SQL store unless the store is memory', () {
    expect(
      () => operations(annotations: const [UseDataSource('reports')]),
      invalid(["@UseDataSource('reports')", 'SQL']),
    );
    expect(
      operations(
        annotations: const [UseStore('memory'), UseDataSource('reports')],
      ),
      isA<RepositoryOperations<Book, int>>(),
    );
  });

  test('store problems come with the query problems', () {
    expect(
      () => operations(
        queries: [query('search')],
        annotations: const [UseStore('cassandra')],
      ),
      invalid(['cassandra', 'BrokenRepository.search']),
    );
  });

  test('every problem is reported, not only the first', () {
    expect(
      () => operations(
        queries: [query('search'), query('lookup')],
        annotations: const [UseStore('cassandra')],
      ),
      invalid([
        'cassandra',
        'BrokenRepository.search',
        'BrokenRepository.lookup',
      ]),
    );
  });

  test('an entity that is not described is refused', () {
    expect(
      () => factory.operations<Uri, int>('BrokenRepository'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            startsWith('Invalid repository BrokenRepository:'),
            contains('Uri'),
          ),
        ),
      ),
    );
  });

  test('an entity without an @Id is refused', () {
    expect(
      () => factory.operations<Note, int>('BrokenRepository'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            startsWith('Invalid repository BrokenRepository:'),
            contains('no @Id'),
          ),
        ),
      ),
    );
  });

  test('the application fails to start with a broken repository', () async {
    final broken = BeanModule('broken', [
      BeanDefinition<RepositoryFactory>(
        name: 'repositoryFactory',
        create: (_) => factory,
      ),
      BeanDefinition<Object>(
        name: 'brokenRepository',
        create: (r) => r.dependency<RepositoryFactory>().operations<Book, int>(
          'BrokenRepository',
          queries: [query('search')],
        ),
      ),
    ]);
    await const ApplicationContextRunner()
        .withUserConfiguration(broken)
        .runAsync(
          (context) {
            expect(
              context.startupFailure,
              isA<BeanCreationException>().having(
                (e) => '$e',
                'message',
                contains('BrokenRepository.search'),
              ),
            );
          },
        );
  });
}
