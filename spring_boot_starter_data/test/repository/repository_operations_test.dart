// RepositoryOperations and SimpleRepository, without generated code: the
// operations come from a RepositoryFactory over the hand-written entity
// descriptions of ../mapping/support.dart, and the derived queries are the
// PartTrees the build writes, written here by hand. Each group runs on the
// in-memory store and on SQLite (an in-memory database).
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../mapping/support.dart';
import '../schema/support.dart' show memorySource;

// ------------------------------------------------------------ the trees

PartTree tree(
  String name,
  List<Part> parts, {
  SubjectKind kind = SubjectKind.find,
  int? max,
  bool distinct = false,
  Sort sort = Sort.unsorted,
}) => PartTree(
  name,
  [if (parts.isNotEmpty) OrPart(parts)],
  subject: Subject(kind, maxResults: max, distinct: distinct),
  sort: sort,
);

final PartTree byTitle = tree('findByTitle', const [Part('title')]);
final PartTree byTitleIgnoreCase = tree('findByTitleIgnoreCase', const [
  Part('title', PartType.simpleProperty, true),
]);
final PartTree byTitleContaining = tree('findByTitleContaining', const [
  Part('title', PartType.containing),
]);
const PartTree byTitleOrYearAfter = PartTree('findByTitleOrYearGreaterThan', [
  OrPart([Part('title')]),
  OrPart([Part('year', PartType.greaterThan)]),
]);
final PartTree byYearAfter = tree('findByYearGreaterThan', const [
  Part('year', PartType.greaterThan),
]);
final PartTree byYearBetween = tree('findByYearBetween', const [
  Part('year', PartType.between),
]);
final PartTree everything = tree('findAllBy', const []);
final PartTree newestTwo = tree(
  'findTop2ByOrderByYearDesc',
  const [],
  max: 2,
  sort: const Sort([SortOrder.desc('year')]),
);
final PartTree oldestThree = tree(
  'findTop3ByOrderByYear',
  const [],
  max: 3,
  sort: const Sort([SortOrder.asc('year')]),
);
final PartTree firstAfter = tree(
  'findFirstByYearGreaterThanOrderByYear',
  const [Part('year', PartType.greaterThan)],
  max: 1,
  sort: const Sort([SortOrder.asc('year')]),
);
final PartTree countAfter = tree(
  'countByYearGreaterThan',
  const [Part('year', PartType.greaterThan)],
  kind: SubjectKind.count,
);
final PartTree existsAfter = tree(
  'existsByYearGreaterThan',
  const [Part('year', PartType.greaterThan)],
  kind: SubjectKind.exists,
);
final PartTree deleteAfter = tree(
  'deleteByYearGreaterThan',
  const [Part('year', PartType.greaterThan)],
  kind: SubjectKind.delete,
);
// Every book has available == false: the tree's order is all ties.
final PartTree tiedFirst = tree(
  'findByYearGreaterThanOrderByAvailable',
  const [Part('year', PartType.greaterThan)],
  sort: const Sort([SortOrder.asc('available')]),
);

const byYear = Sort([SortOrder.asc('year')]);
const newestFirst = Sort([SortOrder.desc('year')]);

List<String> titles(Iterable<Book> books) => [for (final b in books) b.title];

/// Dune 1965, Dune Messiah 1969, Neuromancer 1984, Snow Crash 1992,
/// Cryptonomicon 1999: ids 1 to 5.
Future<List<Book>> seed(SimpleRepository<Book, int> repository) =>
    repository.saveAll([
      Book(title: 'Dune', year: 1965),
      Book(title: 'Dune Messiah', year: 1969),
      Book(title: 'Neuromancer', year: 1984),
      Book(title: 'Snow Crash', year: 1992),
      Book(title: 'Cryptonomicon', year: 1999),
    ]);

// ---------------------------------------------------------- the fixtures

Future<RepositoryOperations<Book, int>> operationsOn(
  String store, {
  AuditingHandler? Function(EntityConverter converter)? auditing,
  List<QueryMethod> queries = const [],
}) async {
  final mapping = testContext();
  final converter = EntityConverter();
  final handler = auditing?.call(converter);
  if (store == 'memory') {
    return RepositoryFactory(
      mappingContext: mapping,
      converter: converter,
      auditing: handler,
    ).operations<Book, int>('BookRepository');
  }
  SpringLog.setLevel('spring.data.jdbc.schema', SpringLogLevel.warning);
  final db = await memorySource();
  await SchemaCreator(db).create([
    mapping.getRequiredPersistentEntity<Author>(),
    mapping.getRequiredPersistentEntity<Book>(),
  ]);
  return RepositoryFactory(
    mappingContext: mapping,
    converter: converter,
    auditing: handler,
    jdbcDataSources: {RepositoryFactory.primaryDataSource: db},
    environment: StandardEnvironment(systemEnvironment: const {}),
  ).operations<Book, int>(
    'BookRepository',
    annotations: const [UseStore('jdbc')],
    queries: queries,
  );
}

// A store that fails every call with [error].
final class _FailingStore implements DataStore {
  _FailingStore(this.error);

  final Object error;

  @override
  String get name => 'failing';

  Future<R> _fail<R>() => Future<R>.error(error);

  @override
  Future<T> insert<T extends Object>(PersistentEntity<T> entity, T instance) =>
      _fail();

  @override
  Future<T> update<T extends Object>(
    PersistentEntity<T> entity,
    T instance, {
    Object? expectedVersion,
  }) => _fail();

  @override
  Future<bool> deleteById<T extends Object>(
    PersistentEntity<T> entity,
    Object id, {
    Object? expectedVersion,
  }) => _fail();

  @override
  Future<T?> findById<T extends Object>(
    PersistentEntity<T> entity,
    Object id, {
    LockMode? lock,
    Duration? lockTimeout,
    bool skipLocked = false,
  }) => _fail();

  @override
  Future<List<T>> findAllById<T extends Object>(
    PersistentEntity<T> entity,
    Iterable<Object> ids,
  ) => _fail();

  @override
  Future<List<T>> find<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
    Sort sort = Sort.unsorted,
    int? offset,
    int? limit,
    bool distinct = false,
    LockMode? lock,
    Duration? lockTimeout,
    bool skipLocked = false,
  }) => _fail();

  @override
  Future<int> count<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => _fail();

  @override
  Future<bool> exists<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => _fail();

  @override
  Future<int> deleteWhere<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => _fail();

  @override
  Future<List<T>> deleteWhereAndReturn<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => _fail();
}

RepositoryOperations<Book, int> operationsOver(DataStore store) =>
    RepositoryFactory(
      mappingContext: testContext(),
      converter: EntityConverter(),
      stores: [store],
    ).operations<Book, int>(
      'BookRepository',
      annotations: [UseStore(store.name)],
    );

void main() {
  for (final store in ['memory', 'sqlite']) {
    group(store, () {
      late RepositoryOperations<Book, int> operations;
      late SimpleRepository<Book, int> repository;
      late TransactionTemplate transaction;

      setUp(() async {
        operations = await operationsOn(store);
        repository = SimpleRepository(operations);
        transaction = TransactionTemplate(operations.transactionManager!);
      });

      test('the operations know their store and entity', () {
        expect(operations.typeName, 'BookRepository');
        expect(operations.entity.type, Book);
        expect(operations.store.name, store == 'memory' ? 'memory' : 'jdbc');
        expect(repository, isA<ListCrudRepository<Book, int>>());
        expect(repository, isA<ListPagingAndSortingRepository<Book, int>>());
      });

      group('CRUD', () {
        test('save inserts a new entity and updates a stored one', () async {
          final saved = await repository.save(Book(title: 'Dune', year: 1965));
          expect((saved.id, saved.version), (1, 1));

          saved.title = 'Dune!';
          final updated = await repository.save(saved);
          expect((updated.id, updated.version), (1, 2));
          expect((await repository.findById(1))!.title, 'Dune!');
          expect(await repository.count(), 1);
        });

        test('an update with a stale version loses', () async {
          await seed(repository);
          final a = (await repository.findById(1))!;
          final b = (await repository.findById(1))!;
          await repository.save(a..title = 'first');
          await expectLater(
            repository.save(b..title = 'second'),
            throwsA(isA<OptimisticLockingFailureException>()),
          );
          expect((await repository.findById(1))!.title, 'first');
        });

        test(
          'saveAll saves in turn and returns a List of the entity',
          () async {
            final saved = await seed(repository);
            expect(saved, isA<List<Book>>());
            expect([for (final b in saved) b.id], [1, 2, 3, 4, 5]);
          },
        );

        test('saveAll is atomic', () async {
          await expectLater(
            repository.saveAll([
              Book(title: 'New', year: 2000),
              // A version without a row: an update that matches nothing.
              Book(title: 'Ghost', year: 2001, id: 99, version: 5),
            ]),
            throwsA(isA<OptimisticLockingFailureException>()),
          );
          expect(await repository.count(), 0);
        });

        test('finders return typed results', () async {
          await seed(repository);
          expect((await repository.findById(2))!.title, 'Dune Messiah');
          expect(await repository.findById(99), isNull);
          expect(await repository.existsById(3), isTrue);
          expect(await repository.existsById(99), isFalse);
          final all = await repository.findAll();
          expect(all, isA<List<Book>>());
          expect(all, hasLength(5));
          final some = await repository.findAllById([1, 3, 99]);
          expect(some, isA<List<Book>>());
          expect(titles(some), ['Dune', 'Neuromancer']);
          expect(await repository.count(), 5);
        });

        test('findAllSorted and findAllPaged', () async {
          await seed(repository);
          final sorted = await repository.findAllSorted(newestFirst);
          expect(sorted, isA<List<Book>>());
          expect(titles(sorted), [
            'Cryptonomicon',
            'Snow Crash',
            'Neuromancer',
            'Dune Messiah',
            'Dune',
          ]);

          final page = await repository.findAllPaged(
            PageRequest.of(1, 2, byYear),
          );
          expect(page, isA<Page<Book>>());
          expect(titles(page.content), ['Neuromancer', 'Snow Crash']);
          expect((page.totalElements, page.totalPages), (5, 3));
          expect((page.number, page.size), (1, 2));

          final unpaged = await repository.findAllPaged(
            const Pageable.unpaged(newestFirst),
          );
          expect(unpaged.content.first.title, 'Cryptonomicon');
          expect(unpaged.totalElements, 5);
        });

        test('deleteById and deleteAllById', () async {
          await seed(repository);
          await repository.deleteById(1);
          await repository.deleteById(99);
          expect(await repository.count(), 4);
          await repository.deleteAllById([2, 3, 99]);
          expect(titles(await repository.findAll()), [
            'Snow Crash',
            'Cryptonomicon',
          ]);
        });

        test('delete checks the version and needs an id', () async {
          final saved = await seed(repository);
          final stale = (await repository.findById(1))!;
          await repository.save(saved.first..title = 'changed');
          await expectLater(
            repository.delete(stale),
            throwsA(isA<OptimisticLockingFailureException>()),
          );
          await repository.delete(saved.first);
          expect(await repository.existsById(1), isFalse);
          await expectLater(
            repository.delete(Book(title: 'Unsaved', year: 2000)),
            throwsA(
              isA<InvalidDataAccessApiUsageException>().having(
                (e) => e.message,
                'message',
                contains('its id is null'),
              ),
            ),
          );
        });

        test('deleteAllOf and deleteAll', () async {
          final saved = await seed(repository);
          await repository.deleteAllOf(saved.take(2));
          expect(await repository.count(), 3);
          await repository.deleteAll();
          expect(await repository.count(), 0);
        });
      });

      group('transactions', () {
        test('a write joins the transaction of the caller', () async {
          await expectLater(
            transaction.execute((_) async {
              await seed(repository);
              expect(await repository.count(), 5);
              throw StateError('boom');
            }),
            throwsStateError,
          );
          expect(await repository.count(), 0);

          await transaction.execute((_) => seed(repository));
          expect(await repository.count(), 5);
        });

        test('a derived delete joins it too', () async {
          await seed(repository);
          await expectLater(
            transaction.execute((_) async {
              expect(await operations.deleteBy(deleteAfter, [1980]), 3);
              throw StateError('boom');
            }),
            throwsStateError,
          );
          expect(await repository.count(), 5);
        });

        test('a lock needs a transaction of the store', () async {
          await seed(repository);
          const lock = Lock(LockMode.pessimisticWrite);
          await expectLater(
            operations.findById(1, lock: lock),
            throwsA(isA<IllegalTransactionStateException>()),
          );
          await expectLater(
            operations.list(byTitle, ['Dune'], lock: lock),
            throwsA(isA<IllegalTransactionStateException>()),
          );
          await transaction.execute((_) async {
            expect((await operations.findById(1, lock: lock))!.title, 'Dune');
            expect(
              titles(await operations.list(byTitle, ['Dune'], lock: lock)),
              ['Dune'],
            );
            expect(
              (await operations.one(byTitle, ['Dune'], lock: lock))!.title,
              'Dune',
            );
          });
        });
      });

      group('derived queries', () {
        setUp(() => seed(repository));

        test('list returns a List of the entity', () async {
          final found = await operations.list(byTitle, ['Dune']);
          expect(found, isA<List<Book>>());
          expect(titles(found), ['Dune']);
          expect(await operations.list(byTitle, ['Nope']), isEmpty);
          expect(await operations.list(everything, []), hasLength(5));
        });

        test('the parts take the arguments in order', () async {
          expect(
            titles(await operations.list(byTitleOrYearAfter, ['Dune', 1990])),
            ['Dune', 'Snow Crash', 'Cryptonomicon'],
          );
          expect(
            titles(await operations.list(byYearBetween, [1966, 1990])),
            ['Dune Messiah', 'Neuromancer'],
          );
        });

        test('IgnoreCase and Containing', () async {
          expect(
            titles(await operations.list(byTitleIgnoreCase, ['dUNE'])),
            ['Dune'],
          );
          expect(
            titles(await operations.list(byTitleContaining, ['Dune'])),
            ['Dune', 'Dune Messiah'],
          );
        });

        test("the name's order comes first, then the sort given", () async {
          expect(
            titles(await operations.list(newestTwo, [])),
            ['Cryptonomicon', 'Snow Crash'],
          );
          // The tree orders by `available`: all ties, so the Sort decides.
          expect(
            titles(
              await operations.list(tiedFirst, [1980], sort: newestFirst),
            ),
            ['Cryptonomicon', 'Snow Crash', 'Neuromancer'],
          );
          // Without a Sort, the sort of the Pageable.
          expect(
            titles(
              await operations.list(
                tiedFirst,
                [1980],
                pageable: const Pageable.unpaged(newestFirst),
              ),
            ),
            ['Cryptonomicon', 'Snow Crash', 'Neuromancer'],
          );
        });

        test('a Pageable cuts the list to its window', () async {
          expect(
            titles(
              await operations.list(
                byYearAfter,
                [1900],
                pageable: PageRequest.of(1, 2, byYear),
              ),
            ),
            ['Neuromancer', 'Snow Crash'],
          );
        });

        test('First and Top limit the pages of a Pageable', () async {
          Future<List<String>> window(int page) async => titles(
            await operations.list(
              oldestThree,
              [],
              pageable: PageRequest.of(page, 2),
            ),
          );
          expect(await window(0), ['Dune', 'Dune Messiah']);
          expect(await window(1), ['Neuromancer']);
          expect(await window(2), isEmpty);
        });

        test('set returns a Set of the entity', () async {
          final found = await operations.set(byYearAfter, [1980]);
          expect(found, isA<Set<Book>>());
          expect(titles(found), ['Neuromancer', 'Snow Crash', 'Cryptonomicon']);
        });

        test('one is the only result, or null', () async {
          expect((await operations.one(byTitle, ['Dune']))!.year, 1965);
          expect(await operations.one(byTitle, ['Nope']), isNull);
        });

        test('more than one result is an error unless First or Top', () async {
          await expectLater(
            operations.one(byYearAfter, [1980]),
            throwsA(
              isA<IncorrectResultSizeDataAccessException>()
                  .having((e) => e.actualSize, 'actual size', 3)
                  .having(
                    (e) => e.message,
                    'message',
                    contains('BookRepository.findByYearGreaterThan: 3 results'),
                  ),
            ),
          );
          await expectLater(
            operations.single(byYearAfter, [1980]),
            throwsA(isA<IncorrectResultSizeDataAccessException>()),
          );
          expect(
            (await operations.one(firstAfter, [1980]))!.title,
            'Neuromancer',
          );
          expect(
            (await operations.single(firstAfter, [1980])).title,
            'Neuromancer',
          );
        });

        test(
          'single without a result is an EmptyResultDataAccessException',
          () async {
            expect((await operations.single(byTitle, ['Dune'])).year, 1965);
            await expectLater(
              operations.single(byTitle, ['Nope']),
              throwsA(
                isA<EmptyResultDataAccessException>().having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains('BookRepository.findByTitle: no result'),
                    contains('non-null Book'),
                  ),
                ),
              ),
            );
          },
        );

        test('stream is typed and reads when it is listened to', () async {
          final books = operations.stream(byYearAfter, [1980], sort: byYear);
          expect(books, isA<Stream<Book>>());
          // Not read yet: a book saved now is in the result.
          await repository.save(Book(title: 'Late', year: 2005));
          expect(titles(await books.toList()), [
            'Neuromancer',
            'Snow Crash',
            'Cryptonomicon',
            'Late',
          ]);
        });

        test('page counts the matches and cuts the window', () async {
          final page = await operations.page(
            byYearAfter,
            [1900],
            PageRequest.of(0, 2, byYear),
          );
          expect(page, isA<Page<Book>>());
          expect(titles(page.content), ['Dune', 'Dune Messiah']);
          expect((page.totalElements, page.totalPages), (5, 3));
          expect(page.hasNext, isTrue);

          final matches = await operations.page(
            byYearAfter,
            [1980],
            PageRequest.of(1, 2, byYear),
          );
          expect(titles(matches.content), ['Cryptonomicon']);
          expect(matches.totalElements, 3);
          expect(matches.hasNext, isFalse);
        });

        test('page: Unpaged gives everything, Top caps the total', () async {
          final all = await operations.page(
            byYearAfter,
            [1980],
            const Pageable.unpaged(byYear),
          );
          expect(all.content, hasLength(3));
          expect(all.totalElements, 3);

          final capped = await operations.page(
            oldestThree,
            [],
            PageRequest.of(0, 2),
          );
          expect(capped.content, hasLength(2));
          expect(capped.totalElements, 3);
          final rest = await operations.page(
            oldestThree,
            [],
            PageRequest.of(1, 2),
          );
          expect(titles(rest.content), ['Neuromancer']);
          expect(rest.totalElements, 3);
        });

        test('slice knows whether a next window follows', () async {
          final first = await operations.slice(
            byYearAfter,
            [1900],
            PageRequest.of(0, 2, byYear),
          );
          expect(first, isA<Slice<Book>>());
          expect(titles(first.content), ['Dune', 'Dune Messiah']);
          expect(first.hasNext, isTrue);

          final last = await operations.slice(
            byYearAfter,
            [1900],
            PageRequest.of(2, 2, byYear),
          );
          expect(titles(last.content), ['Cryptonomicon']);
          expect(last.hasNext, isFalse);

          final whole = await operations.slice(
            byYearAfter,
            [1900],
            PageRequest.of(0, 5, byYear),
          );
          expect(whole.content, hasLength(5));
          expect(whole.hasNext, isFalse);

          final unpaged = await operations.slice(
            byYearAfter,
            [1900],
            const Pageable.unpaged(),
          );
          expect(unpaged.content, hasLength(5));
          expect(unpaged.hasNext, isFalse);
        });

        test('slice stops at the limit of Top', () async {
          final slice = await operations.slice(
            oldestThree,
            [],
            PageRequest.of(1, 3),
          );
          expect(slice.content, isEmpty);
          expect(slice.hasNext, isFalse);
          final two = await operations.slice(
            oldestThree,
            [],
            PageRequest.of(1, 2),
          );
          expect(titles(two.content), ['Neuromancer']);
          expect(two.hasNext, isFalse);
        });

        test('countBy and existsBy', () async {
          expect(await operations.countBy(countAfter, [1980]), 3);
          expect(await operations.countBy(countAfter, [2100]), 0);
          expect(await operations.existsBy(existsAfter, [1980]), isTrue);
          expect(await operations.existsBy(existsAfter, [2100]), isFalse);
        });

        test(
          'deleteBy returns how many, deleteByReturning the entities',
          () async {
            expect(await operations.deleteBy(deleteAfter, [1990]), 2);
            expect(await repository.count(), 3);

            final removed = await operations.deleteByReturning(deleteAfter, [
              1980,
            ]);
            expect(removed, isA<List<Book>>());
            expect(titles(removed), ['Neuromancer']);
            expect(titles(await repository.findAll()), [
              'Dune',
              'Dune Messiah',
            ]);
            expect(await operations.deleteBy(deleteAfter, [2100]), 0);
          },
        );

        test('arguments that do not fit the tree are a misuse', () async {
          await expectLater(
            operations.list(byTitle, []),
            throwsA(
              isA<InvalidDataAccessApiUsageException>().having(
                (e) => e.cause,
                'cause',
                isA<ArgumentError>(),
              ),
            ),
          );
        });

        test('a property the entity does not have is a misuse', () async {
          await expectLater(
            operations.list(tree('findByNope', const [Part('nope')]), [1]),
            throwsA(isA<InvalidDataAccessApiUsageException>()),
          );
        });
      });

      test('auditing fills the audit properties on save', () async {
        final audited = await operationsOn(
          store,
          auditing: (converter) => AuditingHandler(converter: converter),
        );
        final books = SimpleRepository(audited);
        final saved = await books.save(Book(title: 'Dune', year: 1965));
        expect(saved.createdAt, isNotNull);
        expect(saved.modifiedAt, isNotNull);
        final created = saved.createdAt;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final updated = await books.save(saved..title = 'Dune!');
        expect(updated.createdAt, created);
        expect(updated.modifiedAt!.isAfter(created!), isTrue);
      });
    });
  }

  group('@Query on SQLite', () {
    const minYear = QueryMethod(
      'minYear',
      Query('select * from books where year >= :year order by year'),
      parameters: ['year'],
      element: ClassType<Book>(),
    );
    const total = QueryMethod(
      'total',
      Query('select count(*) from books'),
      shape: QueryShape.single,
      element: ClassType<int>(),
    );
    const streamAll = QueryMethod(
      'streamAll',
      Query('select * from books order by year'),
      shape: QueryShape.stream,
      element: ClassType<Book>(),
    );
    const bump = QueryMethod(
      'bump',
      Query('update books set year = year + 1 where year > :year'),
      parameters: ['year'],
      change: QueryChange.rows,
    );
    const unlisted = QueryMethod(
      'unlisted',
      Query('select 1'),
      shape: QueryShape.single,
      element: ClassType<int>(),
    );

    late RepositoryOperations<Book, int> operations;
    late SimpleRepository<Book, int> repository;

    setUp(() async {
      operations = await operationsOn(
        'sqlite',
        queries: [minYear, total, streamAll, bump],
      );
      repository = SimpleRepository(operations);
      await seed(repository);
    });

    test('query returns what the method returns', () async {
      final books = await operations.query<List<Book>>(minYear, [1990]);
      expect(books, isA<List<Book>>());
      expect(titles(books), ['Snow Crash', 'Cryptonomicon']);
      expect(await operations.query<int>(total, const []), 5);
    });

    test('queryStream is typed and reads the rows', () async {
      final stream = operations.queryStream<Book>(streamAll, const []);
      expect(stream, isA<Stream<Book>>());
      expect(titles(await stream.toList()), [
        'Dune',
        'Dune Messiah',
        'Neuromancer',
        'Snow Crash',
        'Cryptonomicon',
      ]);
    });

    test('a @Modifying query runs in the transaction of the caller', () async {
      final transaction = TransactionTemplate(operations.transactionManager!);
      await expectLater(
        transaction.execute((_) async {
          expect(await operations.query<int>(bump, [1980]), 3);
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(
        titles(await operations.query<List<Book>>(minYear, [1999])),
        ['Cryptonomicon'],
      );
      expect(await operations.query<int>(bump, [1980]), 3);
      expect(
        titles(await operations.query<List<Book>>(minYear, [2000])),
        ['Cryptonomicon'],
      );
    });

    test('a method asked for the wrong way, or not given, is a misuse', () {
      expect(
        () => operations.query<List<Book>>(streamAll, const []),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('call queryStream'),
          ),
        ),
      );
      expect(
        () => operations.queryStream<Book>(minYear, [1990]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('call query'),
          ),
        ),
      );
      expect(
        () => operations.query<int>(unlisted, const []),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('was not given as a query'),
          ),
        ),
      );
    });

    test('a failing query is translated', () async {
      const method = QueryMethod(
        'broken',
        Query('select count(*) from nowhere'),
        shape: QueryShape.single,
        element: ClassType<int>(),
      );
      final broken = await operationsOn('sqlite', queries: [method]);
      await expectLater(
        broken.query<int>(method, const []),
        throwsA(isA<DataAccessException>()),
      );
    });
  });

  group('errors of the store', () {
    test('a DataAccessException reaches the caller unchanged', () async {
      final error = DuplicateKeyException('duplicate');
      final operations = operationsOver(_FailingStore(error));
      await expectLater(
        operations.findAll(),
        throwsA(same(error)),
      );
      await expectLater(
        operations.save(Book(title: 'Dune', year: 1965)),
        throwsA(same(error)),
      );
    });

    test('a TransactionException reaches the caller unchanged', () async {
      final error = IllegalTransactionStateException('no transaction');
      final operations = operationsOver(_FailingStore(error));
      await expectLater(
        operations.list(byTitle, ['Dune']),
        throwsA(same(error)),
      );
    });

    test('a misuse is an InvalidDataAccessApiUsageException', () async {
      final error = StateError('bad state');
      final operations = operationsOver(_FailingStore(error));
      await expectLater(
        operations.count(),
        throwsA(
          isA<InvalidDataAccessApiUsageException>()
              .having((e) => e.cause, 'cause', same(error))
              .having(
                (e) => e.message,
                'message',
                startsWith('BookRepository failed:'),
              ),
        ),
      );
    });

    test('any other error is a DataAccessResourceFailureException', () async {
      final error = Exception('connection lost');
      final operations = operationsOver(_FailingStore(error));
      for (final call in <Future<Object?> Function()>[
        operations.findAll,
        () => operations.findById(1),
        () => operations.existsById(1),
        () => operations.one(byTitle, ['Dune']),
        () => operations.page(byTitle, ['Dune'], PageRequest.of(0, 2)),
        () => operations.countBy(countAfter, [1]),
        () => operations.deleteBy(deleteAfter, [1]),
        () => operations.stream(byTitle, ['Dune']).toList(),
      ]) {
        await expectLater(
          call(),
          throwsA(
            isA<DataAccessResourceFailureException>().having(
              (e) => e.cause,
              'cause',
              same(error),
            ),
          ),
        );
      }
    });
  });

  group('logging', () {
    late List<SpringLogRecord> records;
    late void Function() stop;
    late RepositoryOperations<Book, int> operations;

    setUpAll(() => SpringLog.handler = (_) {});

    setUp(() async {
      operations = await operationsOn('memory');
      SpringLog.level = SpringLogLevel.info;
      SpringLog.resetLevels();
      records = [];
      stop = SpringLog.listen(records.add);
    });

    tearDown(() {
      stop();
      SpringLog.level = SpringLogLevel.info;
      SpringLog.resetLevels();
    });

    List<String> messages([SpringLogLevel? level]) => [
      for (final record in records)
        if (record.loggerName == 'spring.data.repository.BookRepository' &&
            (level == null || record.level == level))
          record.message,
    ];

    test('nothing is logged at the default level', () async {
      await operations.findById(1);
      expect(messages(), isEmpty);
    });

    test('debug names the method alone', () async {
      SpringLog.setLevel(
        'spring.data.repository.BookRepository',
        SpringLogLevel.debug,
      );
      await operations.findById(1);
      await operations.list(byTitle, ['Dune']);
      await operations.countBy(countAfter, [1980]);
      expect(messages(SpringLogLevel.debug), [
        'BookRepository.findById',
        'BookRepository.findByTitle',
        'BookRepository.countByYearGreaterThan',
      ]);
      expect(messages(SpringLogLevel.trace), isEmpty);
    });

    test('trace adds the arguments, named, a secret masked', () async {
      SpringLog.setLevel(
        'spring.data.repository.BookRepository',
        SpringLogLevel.trace,
      );
      await operations.findById(7);
      await operations.list(
        byYearBetween,
        [1960, 1970],
        sort: byYear,
        pageable: PageRequest.of(0, 2),
      );
      // A property whose name looks secret: the value is masked, and the
      // store refuses the property after the line is written.
      await expectLater(
        operations.list(tree('findByToken', const [Part('token')]), ['s3cret']),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
      final trace = messages(SpringLogLevel.trace);
      expect(trace[0], 'BookRepository.findById(id: 7)');
      expect(
        trace[1],
        allOf(
          startsWith(
            'BookRepository.findByYearBetween(year: 1960, year: 1970, ',
          ),
          contains('sort: year: asc'),
          contains('pageable: Page request [number: 0, size: 2'),
        ),
      );
      expect(trace[2], 'BookRepository.findByToken(token: ******)');
      expect(trace.join(), isNot(contains('s3cret')));
    });
  });
}
