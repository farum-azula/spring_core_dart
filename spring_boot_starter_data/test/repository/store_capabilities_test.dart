import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../jdbc/support/fake_jdbc.dart';
import '../mapping/support.dart';
import 'support/plain_store.dart';

// What a repository uses and its store lacks is found when the repository
// is created: the generated class says what its methods need
// (StoreRequirement), the store what it has (DataStoreCapabilities).
void main() {
  late EntityConverter converter;
  late InMemoryDataStore memory;

  setUp(() {
    converter = EntityConverter();
    memory = InMemoryDataStore(converter: converter);
  });

  RepositoryFactory factory({
    List<DataStore> stores = const [],
    Map<String, DataSource> jdbcDataSources = const {},
  }) => RepositoryFactory(
    mappingContext: testContext(),
    converter: converter,
    stores: [memory, ...stores],
    jdbcDataSources: jdbcDataSources,
  );

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

  group('DataStoreCapabilities', () {
    test('nothing unless said', () {
      const none = DataStoreCapabilities();
      for (final capability in DataStoreCapability.values) {
        expect(none.supports(capability), isFalse, reason: capability.name);
      }
      expect('$none', 'DataStoreCapabilities(none)');
    });

    test('supports answers by capability; equal by content', () {
      const some = DataStoreCapabilities(locks: true, changes: true);
      expect(some.supports(DataStoreCapability.locks), isTrue);
      expect(some.supports(DataStoreCapability.changes), isTrue);
      expect(some.supports(DataStoreCapability.transactions), isFalse);
      expect(some.supports(DataStoreCapability.queries), isFalse);
      expect(some.supports(DataStoreCapability.functions), isFalse);
      // The instances are not canonical: built at run time.
      final locks = [true].single;
      expect(some, DataStoreCapabilities(locks: locks, changes: true));
      expect(
        some.hashCode,
        DataStoreCapabilities(locks: locks, changes: true).hashCode,
      );
      expect(some, isNot(const DataStoreCapabilities(locks: true)));
      expect('$some', 'DataStoreCapabilities(locks, changes)');
    });

    test('the memory store: transactions, locks, changes', () {
      expect(
        memory.capabilities,
        const DataStoreCapabilities(
          transactions: true,
          locks: true,
          changes: true,
        ),
      );
      expect(memory, isA<TransactionalDataStore>());
      expect(memory, isA<ChangeStreamDataStore>());
      expect(memory, isNot(isA<FunctionDataStore>()));
    });

    test('the JDBC store: transactions, locks, queries; functions by the '
        'dialect', () {
      JdbcDataStore store(SqlDialect dialect) => JdbcDataStore(
        dataSource: fakePool(FakeJdbcDriver(dialect: dialect)),
        converter: converter,
      );
      expect(
        store(FakeDialect()).capabilities,
        const DataStoreCapabilities(
          transactions: true,
          locks: true,
          queries: true,
        ),
      );
      expect(
        store(const SqliteDialect()).capabilities.functions,
        isFalse,
      );
      expect(
        store(const PostgresDialect()).capabilities,
        const DataStoreCapabilities(
          transactions: true,
          locks: true,
          queries: true,
          functions: true,
        ),
      );
    });
  });

  group('a store that lacks what the repository uses', () {
    late PlainStore rest;
    const onRest = [UseStore('rest')];

    setUp(() => rest = PlainStore(memory));

    test('nothing needed: the repository is created, without a transaction '
        'manager', () async {
      final repositories = factory(stores: [rest]);
      final books = repositories.operations<Book, int>(
        'Books',
        annotations: onRest,
      );
      expect(books.store, same(rest));
      expect(books.transactionManager, isNull);
      expect(repositories.transactionManagers, isEmpty);
      final saved = await books.save(Book(title: 'Dune'));
      expect(await books.findById(saved.id!), isNotNull);
    });

    test('@Lock without locks: the method, the store and the fix', () {
      expect(
        () => factory(stores: [rest]).operations<Book, int>(
          'Books',
          annotations: onRest,
          requirements: const [
            StoreRequirement('findByTitle', DataStoreCapability.locks),
          ],
        ),
        invalid([
          'Books.findByTitle: @Lock needs a store with row locks',
          'the rest store is none',
          "@UseStore('jdbc')",
          'remove @Lock',
        ]),
      );
    });

    test('a read with a lock is refused at the call too: it never runs '
        'unlocked', () async {
      final books = factory(
        stores: [rest],
      ).operations<Book, int>('Books', annotations: onRest);
      const lock = Lock(LockMode.pessimisticWrite);
      const tree = PartTree('findByTitle', [
        OrPart([Part('title')]),
      ]);
      final refused = throwsA(
        isA<InvalidDataAccessApiUsageException>().having(
          (e) => e.message,
          'message',
          contains('@Lock needs a store with row locks'),
        ),
      );
      await expectLater(books.findById(1, lock: lock), refused);
      await expectLater(books.list(tree, ['Dune'], lock: lock), refused);
      await expectLater(books.one(tree, ['Dune'], lock: lock), refused);
      await expectLater(
        books.stream(tree, ['Dune'], lock: lock).toList(),
        refused,
      );
      await expectLater(
        books.page(tree, ['Dune'], PageRequest.of(0, 2), lock: lock),
        refused,
      );
      // Without a lock the same reads run.
      expect(await books.list(tree, ['Dune']), isEmpty);
    });

    test('@Transactional on a method without transactions', () {
      expect(
        () => factory(stores: [rest]).operations<Book, int>(
          'Books',
          annotations: onRest,
          requirements: const [
            StoreRequirement('moveAll', DataStoreCapability.transactions),
          ],
        ),
        invalid([
          'Books.moveAll: @Transactional needs a store with transactions',
          'the rest store is none',
          '@Procedure',
        ]),
      );
    });

    test('@Transactional on the interface is among its annotations', () {
      expect(
        () => factory(stores: [rest]).operations<Book, int>(
          'Books',
          annotations: const [UseStore('rest'), Transactional()],
        ),
        invalid([
          '  - Books: @Transactional needs a store with transactions',
          'the rest store is none',
        ]),
      );
    });

    test('@Query without queries', () {
      expect(
        () => factory(stores: [rest]).operations<Book, int>(
          'Books',
          annotations: onRest,
          queries: const [
            QueryMethod(
              'search',
              Query('select * from books'),
              element: ClassType<Book>(),
            ),
          ],
        ),
        invalid([
          'Books.search: @Query needs a SQL store',
          'the rest store is none',
          'spring.datasource.url',
        ]),
      );
    });

    test('a store that says it runs SQL but is not the JDBC store', () {
      final liar = PlainStore(
        memory,
        capabilities: const DataStoreCapabilities(queries: true),
      );
      expect(
        () => factory(stores: [liar]).operations<Book, int>(
          'Books',
          annotations: onRest,
          queries: const [
            QueryMethod(
              'search',
              Query('select * from books'),
              element: ClassType<Book>(),
            ),
          ],
        ),
        invalid(['Books.search: @Query runs on the JDBC store']),
      );
    });

    test('a stream of changes without changes; usedBy names the reason', () {
      expect(
        () => factory(stores: [rest]).operations<Book, int>(
          'Books',
          annotations: onRest,
          requirements: const [
            StoreRequirement('watchByTitle', DataStoreCapability.changes),
            StoreRequirement(
              'changesByTitle',
              DataStoreCapability.changes,
              usedBy: 'Stream<RowChange<Book>>',
            ),
          ],
        ),
        invalid([
          'Books.watchByTitle: a stream of changes needs a store that',
          'Books.changesByTitle: Stream<RowChange<Book>> needs',
        ]),
      );
    });

    test('every problem is reported together, each once', () {
      Object? thrown;
      try {
        factory(stores: [rest]).operations<Book, int>(
          'Books',
          annotations: const [UseStore('rest'), Transactional()],
          requirements: const [
            StoreRequirement('findByTitle', DataStoreCapability.locks),
            StoreRequirement('findByTitle', DataStoreCapability.locks),
            StoreRequirement('watchByTitle', DataStoreCapability.changes),
          ],
          queries: const [
            QueryMethod(
              'search',
              Query('select * from books'),
              element: ClassType<Book>(),
            ),
          ],
        );
      } on StateError catch (error) {
        thrown = error;
      }
      final message = (thrown! as StateError).message;
      expect('  - '.allMatches(message), hasLength(4));
      expect(message, contains('Books: @Transactional'));
      expect(message, contains('Books.findByTitle: @Lock'));
      expect(message, contains('Books.watchByTitle: a stream of changes'));
      expect(message, contains('Books.search: @Query'));
    });
  });

  group('a store that has what the repository uses', () {
    test('the memory store meets locks, transactions and changes', () {
      final books = factory().operations<Book, int>(
        'Books',
        annotations: const [Transactional()],
        requirements: const [
          StoreRequirement('findByTitle', DataStoreCapability.locks),
          StoreRequirement('moveAll', DataStoreCapability.transactions),
          StoreRequirement('watchByTitle', DataStoreCapability.changes),
        ],
      );
      expect(books.transactionManager, same(memory.transactionManager));
    });

    test('the memory store has no functions and no SQL', () {
      expect(
        () => factory().operations<Book, int>(
          'Books',
          functions: const [ProcedureMethod('total', Procedure('total'))],
        ),
        invalid([
          'Books.total: @Procedure needs a store with database functions',
          'the memory store is none',
        ]),
      );
    });

    test("the manager of a TransactionalDataStore is the repository's, and "
        "among the factory's", () {
      final ds = fakePool(FakeJdbcDriver());
      final repositories = factory(
        jdbcDataSources: {RepositoryFactory.primaryDataSource: ds},
      );
      final books = repositories.operations<Book, int>(
        'Books',
        annotations: const [UseStore('jdbc')],
        requirements: const [
          StoreRequirement('findByTitle', DataStoreCapability.locks),
        ],
      );
      final store = books.store as JdbcDataStore;
      expect(books.transactionManager, same(store.transactionManager));
      expect(repositories.transactionManagers, [store.transactionManager]);
    });

    test("@UseStore('supabase') still names no store", () {
      expect(
        () => factory().operations<Book, int>(
          'Books',
          annotations: const [UseStore('supabase')],
        ),
        invalid(["@UseStore('supabase') names no store", 'not available']),
      );
    });
  });

  test('StoreRequirement: equality and text', () {
    const lock = StoreRequirement('findByTitle', DataStoreCapability.locks);
    final name = ['findByTitle'].single;
    expect(lock, StoreRequirement(name, DataStoreCapability.locks));
    expect(
      lock.hashCode,
      StoreRequirement(name, DataStoreCapability.locks).hashCode,
    );
    expect('$lock', 'StoreRequirement(findByTitle: locks)');
    expect(
      '${const StoreRequirement.ofInterface(DataStoreCapability.changes)}',
      'StoreRequirement(the interface: changes)',
    );
    expect(lock.problemWith('Books', memory), isNull);
  });
}
