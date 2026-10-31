import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../support/app.dart';

// The store's own behaviour, below the repositories: what a predicate
// means (SQL semantics), how results are sorted, what writes check.
Criteria where(
  PartType type,
  String property,
  List<Object?> arguments, {
  bool ignoreCase = false,
}) => Criteria([
  OrPart([
    Part([property], type, ignoreCase: ignoreCase),
  ]),
], arguments);

void main() {
  late Example app;
  late InMemoryDataStore store;
  late PersistentEntity<Book> entity;

  Future<void> run(Future<void> Function() body) =>
      withExample((example) async {
        app = example;
        store = InMemoryDataStore(converter: example.context.getBean());
        entity = example.entity<Book>();
        await body();
      });

  Future<Book> add(
    String title, {
    int year = 2000,
    String? subtitle,
    int? authorId,
    bool inStock = true,
  }) => store.insert(
    entity,
    Book(
      title: title,
      year: year,
      subtitle: subtitle,
      inStock: inStock,
      author: authorId == null ? null : author(authorId),
    ),
  );

  Future<List<String>> titles(Criteria criteria) async => [
    for (final b in await store.find(entity, criteria: criteria)) b.title,
  ];

  Future<List<String>> sorted(Sort sort) async => [
    for (final b in await store.find(entity, sort: sort)) b.title,
  ];

  group('nulls', () {
    Future<void> seed() async {
      await add('a', subtitle: 'x');
      await add('b', subtitle: 'y');
      await add('c');
    }

    test(
      'a comparison with null is false',
      () => run(() async {
        await seed();
        expect(await titles(where(PartType.lessThan, 'subtitle', ['z'])), [
          'a',
          'b',
        ]);
        expect(await titles(where(PartType.greaterThan, 'subtitle', ['a'])), [
          'a',
          'b',
        ]);
        expect(
          await titles(where(PartType.greaterThan, 'subtitle', [null])),
          isEmpty,
        );
        expect(await titles(where(PartType.between, 'subtitle', ['a', 'z'])), [
          'a',
          'b',
        ]);
        expect(
          await titles(where(PartType.between, 'subtitle', [null, 'z'])),
          isEmpty,
        );
      }),
    );

    test(
      'isNull and isNotNull',
      () => run(() async {
        await seed();
        expect(await titles(where(PartType.isNull, 'subtitle', [])), ['c']);
        expect(await titles(where(PartType.isNotNull, 'subtitle', [])), [
          'a',
          'b',
        ]);
      }),
    );

    test(
      'simple property with a null argument means isNull',
      () => run(() async {
        await seed();
        expect(
          await titles(where(PartType.simpleProperty, 'subtitle', [null])),
          ['c'],
        );
        expect(
          await titles(where(PartType.simpleProperty, 'subtitle', ['x'])),
          ['a'],
        );
        expect(
          await titles(
            where(PartType.negatingSimpleProperty, 'subtitle', [null]),
          ),
          ['a', 'b'],
        );
        // Not equal to x: the null row is not "different", it is unknown.
        expect(
          await titles(
            where(PartType.negatingSimpleProperty, 'subtitle', ['x']),
          ),
          ['b'],
        );
      }),
    );

    test(
      'negative string conditions leave nulls out',
      () => run(() async {
        await seed();
        expect(await titles(where(PartType.notLike, 'subtitle', ['x'])), ['b']);
        expect(await titles(where(PartType.notContaining, 'subtitle', ['x'])), [
          'b',
        ]);
        expect(
          await titles(
            where(PartType.notIn, 'subtitle', [
              ['x'],
            ]),
          ),
          ['b'],
        );
      }),
    );

    test(
      'in ignores null elements, not in with a null element is never true',
      () => run(() async {
        await seed();
        expect(
          await titles(
            where(PartType.in_, 'subtitle', [
              ['x', null],
            ]),
          ),
          ['a'],
        );
        expect(
          await titles(
            where(PartType.notIn, 'subtitle', [
              ['x', null],
            ]),
          ),
          isEmpty,
        );
        expect(await titles(where(PartType.notIn, 'subtitle', [<String>[]])), [
          'a',
          'b',
          'c',
        ]);
        expect(
          await titles(where(PartType.in_, 'subtitle', [<String>[]])),
          isEmpty,
        );
      }),
    );

    test(
      'in needs a collection',
      () => run(() async {
        await seed();
        await expectLater(
          store.find(entity, criteria: where(PartType.in_, 'subtitle', ['x'])),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      }),
    );
  });

  group('strings', () {
    test(
      'ignoreCase lower-cases both sides',
      () => run(() async {
        await add('Dune');
        await add('dune messiah');
        expect(
          await titles(
            where(PartType.simpleProperty, 'title', ['DUNE'], ignoreCase: true),
          ),
          ['Dune'],
        );
        expect(
          await titles(where(PartType.simpleProperty, 'title', ['DUNE'])),
          isEmpty,
        );
        expect(
          await titles(
            where(PartType.startingWith, 'title', ['DUNE'], ignoreCase: true),
          ),
          ['Dune', 'dune messiah'],
        );
        expect(
          await titles(
            where(PartType.like, 'title', ['D%E'], ignoreCase: true),
          ),
          ['Dune'],
        );
        expect(
          await titles(
            where(PartType.in_, 'title', [
              ['DUNE'],
            ], ignoreCase: true),
          ),
          ['Dune'],
        );
      }),
    );

    test(
      'like: % any text, _ one character, backslash escapes',
      () => run(() async {
        await add('a_b');
        await add('axb');
        await add('a.b');
        await add('100%');
        await add('a\nb');
        expect(await titles(where(PartType.like, 'title', ['a_b'])), [
          'a_b',
          'axb',
          'a.b',
          'a\nb',
        ]);
        expect(await titles(where(PartType.like, 'title', [r'a\_b'])), ['a_b']);
        expect(await titles(where(PartType.like, 'title', ['a%b'])), [
          'a_b',
          'axb',
          'a.b',
          'a\nb',
        ]);
        // A regular expression's dot is a dot here.
        expect(await titles(where(PartType.like, 'title', ['a.b'])), ['a.b']);
        expect(await titles(where(PartType.like, 'title', [r'100\%'])), [
          '100%',
        ]);
        expect(await titles(where(PartType.like, 'title', ['100'])), isEmpty);
      }),
    );

    test(
      'starting, ending and containing escape their argument',
      () => run(() async {
        await add('50% off');
        await add('50 off');
        await add('a_b');
        await add('axb');
        expect(await titles(where(PartType.startingWith, 'title', ['50%'])), [
          '50% off',
        ]);
        expect(await titles(where(PartType.endingWith, 'title', ['_b'])), [
          'a_b',
        ]);
        expect(await titles(where(PartType.containing, 'title', ['_'])), [
          'a_b',
        ]);
        expect(
          await titles(where(PartType.containing, 'title', [''])),
          hasLength(4),
        );
      }),
    );
  });

  group('values', () {
    test(
      'between is inclusive, numbers compare as numbers',
      () => run(() async {
        await add('a', year: 1);
        await add('b', year: 2);
        await add('c', year: 3);
        expect(await titles(where(PartType.between, 'year', [1, 3])), [
          'a',
          'b',
          'c',
        ]);
        expect(await titles(where(PartType.between, 'year', [3, 1])), isEmpty);
        expect(await titles(where(PartType.simpleProperty, 'year', [2.0])), [
          'b',
        ]);
        expect(await titles(where(PartType.lessThan, 'year', [2.5])), [
          'a',
          'b',
        ]);
      }),
    );

    test(
      'an aggregate reference matches by its id, given as either',
      () => run(() async {
        await add('a', authorId: 1);
        await add('b', authorId: 2);
        await add('c');
        expect(
          await titles(where(PartType.simpleProperty, 'author', [author(1)])),
          ['a'],
        );
        expect(await titles(where(PartType.simpleProperty, 'author', [1])), [
          'a',
        ]);
        expect(
          await titles(
            where(PartType.in_, 'author', [
              [author(1), 2],
            ]),
          ),
          ['a', 'b'],
        );
        expect(await titles(where(PartType.isNull, 'author', [])), ['c']);
      }),
    );

    test(
      'booleans',
      () => run(() async {
        await add('a');
        await add('b', inStock: false);
        expect(await titles(where(PartType.isTrue, 'inStock', [])), ['a']);
        expect(await titles(where(PartType.isFalse, 'inStock', [])), ['b']);
      }),
    );

    test(
      'or of ands',
      () => run(() async {
        await add('a', year: 1);
        await add('b', year: 2);
        await add('c', year: 3);
        final criteria = Criteria(
          [
            const OrPart([
              Part(['title'], PartType.simpleProperty),
              Part(['year'], PartType.simpleProperty),
            ]),
            const OrPart([
              Part(['year'], PartType.greaterThan),
            ]),
          ],
          ['a', 2, 2],
        );
        expect(await titles(criteria), ['c']);
      }),
    );

    test(
      'no part matches everything',
      () => run(() async {
        await add('a');
        await add('b');
        expect(
          await store.count(entity, criteria: Criteria(const [], const [])),
          2,
        );
        expect(await store.count(entity), 2);
        expect(await store.exists(entity), isTrue);
      }),
    );

    test('a wrong number of arguments is refused', () {
      expect(
        () => Criteria(
          const [
            OrPart([
              Part(['year'], PartType.between),
            ]),
          ],
          [1],
        ),
        throwsArgumentError,
      );
    });

    test(
      'an unknown property or a mapped collection is refused',
      () => run(() async {
        await add('a');
        await expectLater(
          store.find(entity, criteria: where(PartType.isNull, 'nope', [])),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
        final orders = app.entity<PurchaseOrder>();
        await expectLater(
          store.find(orders, criteria: where(PartType.isNull, 'lines', [])),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
        await expectLater(
          store.find(entity, sort: Sort.by(['nope'])),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      }),
    );
  });

  group('sorting', () {
    Future<void> seed() async {
      await add('b', subtitle: 'two', year: 2);
      await add('A', year: 1);
      await add('c', subtitle: 'one', year: 2);
      await add('B', subtitle: 'two', year: 1);
    }

    test(
      'by default null is the greatest: last ascending, first descending',
      () => run(() async {
        await seed();
        expect(await sorted(Sort.by(['subtitle'])), ['c', 'b', 'B', 'A']);
        expect(
          await sorted(Sort.byOrders([const SortOrder.desc('subtitle')])),
          [
            'A',
            'b',
            'B',
            'c',
          ],
        );
      }),
    );

    test(
      'null handling can be set',
      () => run(() async {
        await seed();
        expect(
          await sorted(
            Sort.byOrders([
              const SortOrder(
                'subtitle',
                nullHandling: NullHandling.nullsFirst,
              ),
            ]),
          ),
          ['A', 'c', 'b', 'B'],
        );
        expect(
          await sorted(
            Sort.byOrders([
              const SortOrder(
                'subtitle',
                direction: Direction.desc,
                nullHandling: NullHandling.nullsLast,
              ),
            ]),
          ),
          ['b', 'B', 'c', 'A'],
        );
      }),
    );

    test(
      'equal keys keep the order of insertion',
      () => run(() async {
        await seed();
        expect(await sorted(Sort.by(['year'])), ['A', 'B', 'b', 'c']);
        expect(await sorted(Sort.byOrders([const SortOrder.desc('year')])), [
          'b',
          'c',
          'A',
          'B',
        ]);
      }),
    );

    test(
      'several orders',
      () => run(() async {
        await seed();
        expect(
          await sorted(
            Sort.byOrders([
              const SortOrder.desc('year'),
              const SortOrder.asc('title'),
            ]),
          ),
          ['b', 'c', 'A', 'B'],
        );
        expect(
          await sorted(
            Sort.byOrders([
              const SortOrder.asc('year'),
              const SortOrder.desc('title'),
            ]),
          ),
          ['B', 'A', 'c', 'b'],
        );
      }),
    );

    test(
      'ignoreCase compares the lower-cased texts',
      () => run(() async {
        await seed();
        expect(await sorted(Sort.by(['title'])), ['A', 'B', 'b', 'c']);
        expect(
          await sorted(
            Sort.byOrders([const SortOrder('title', ignoreCase: true)]),
          ),
          ['A', 'b', 'B', 'c'],
        );
      }),
    );

    test(
      'offset and limit apply after sorting and distinct',
      () => run(() async {
        await seed();
        final sort = Sort.by(['title']);
        Future<List<String>> window({int? offset, int? limit}) async => [
          for (final b in await store.find(
            entity,
            sort: sort,
            offset: offset,
            limit: limit,
          ))
            b.title,
        ];
        expect(await window(offset: 1, limit: 2), ['B', 'b']);
        expect(await window(offset: 3), ['c']);
        expect(await window(offset: 9), isEmpty);
        expect(await window(limit: 0), isEmpty);
        expect(await window(limit: 99), hasLength(4));
        expect(await store.find(entity, distinct: true), hasLength(4));
      }),
    );
  });

  group('writes', () {
    test(
      'insert sets the generated id and the version, in the copy or not',
      () => run(() async {
        final book = Book(title: 'a', year: 1);
        final saved = await store.insert(entity, book);
        expect(saved.id, 1);
        expect(saved.version, 1);
        expect(store.size(entity), 1);
      }),
    );

    test(
      'a duplicate id fails and changes nothing',
      () => run(() async {
        await store.insert(entity, Book(title: 'a', year: 1, id: 7));
        await expectLater(
          store.insert(entity, Book(title: 'b', year: 1, id: 7)),
          throwsA(isA<DuplicateKeyException>()),
        );
        expect((await store.findById(entity, 7))!.title, 'a');
        expect(store.size(entity), 1);
      }),
    );

    test(
      "update checks the version, by default the instance's",
      () => run(() async {
        final saved = await add('a');
        saved.title = 'b';
        await expectLater(
          store.update(entity, saved, expectedVersion: 99),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
        expect((await store.findById(entity, saved.id!))!.title, 'a');
        final updated = await store.update(entity, saved);
        expect(updated.version, 2);
        // The old version is gone.
        saved
          ..version = 1
          ..title = 'c';
        await expectLater(
          store.update(entity, saved),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
      }),
    );

    test(
      "a failed write leaves the application's instance untouched",
      () => run(() async {
        await store.insert(entity, Book(title: 'a', year: 1, id: 7));
        final other = Book(title: 'b', year: 1, id: 7);
        await expectLater(
          store.insert(entity, other),
          throwsA(isA<DuplicateKeyException>()),
        );
        expect(other.version, isNull);
      }),
    );

    test(
      'update of an unknown id without a version',
      () => run(() async {
        final authors = app.entity<Author>();
        await expectLater(
          store.update(authors, Author(name: 'x', id: 3)),
          throwsA(isA<IncorrectUpdateSemanticsDataAccessException>()),
        );
        await expectLater(
          store.update(authors, Author(name: 'x')),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      }),
    );

    test(
      'deleteById with and without an expected version',
      () => run(() async {
        final saved = await add('a');
        await expectLater(
          store.deleteById(entity, saved.id!, expectedVersion: 5),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
        expect(
          await store.deleteById(entity, saved.id!, expectedVersion: 1),
          isTrue,
        );
        expect(await store.deleteById(entity, saved.id!), isFalse);
        await expectLater(
          store.deleteById(entity, saved.id!, expectedVersion: 1),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
      }),
    );

    test(
      'deleteWhere counts, deleteWhereAndReturn gives the aggregates',
      () => run(() async {
        await add('a', year: 1);
        await add('b', year: 2);
        await add('c', year: 3);
        final removed = await store.deleteWhereAndReturn(
          entity,
          criteria: where(PartType.lessThan, 'year', [3]),
        );
        expect([for (final b in removed) b.title], ['a', 'b']);
        expect(
          await store.deleteWhere(
            entity,
            criteria: where(PartType.greaterThan, 'year', [0]),
          ),
          1,
        );
        expect(await store.deleteWhere(entity), 0);
      }),
    );

    test(
      "findAllById lists in the table's order and skips unknown ids",
      () => run(() async {
        await add('a');
        await add('b');
        await add('c');
        final found = await store.findAllById(entity, [3, 1, 99]);
        expect([for (final b in found) b.title], ['a', 'c']);
      }),
    );

    test(
      'two concurrent updates of one version: one wins',
      () => run(() async {
        final saved = await add('a');
        final one = (await store.findById(entity, saved.id!))!..title = 'one';
        final two = (await store.findById(entity, saved.id!))!..title = 'two';
        final results = await Future.wait([
          store
              .update(entity, one)
              .then<Object>((_) => 'ok')
              .catchError((Object e) => e),
          store
              .update(entity, two)
              .then<Object>((_) => 'ok')
              .catchError((Object e) => e),
        ]);
        expect(results.first, 'ok');
        expect(results.last, isA<OptimisticLockingFailureException>());
      }),
    );

    test(
      'clear empties the tables and restarts the ids',
      () => run(() async {
        await add('a');
        store.clear();
        expect(store.size(entity), 0);
        expect((await add('b')).id, 1);
      }),
    );

    test(
      'children are stored per root, replaced on update',
      () => run(() async {
        final orders = app.entity<PurchaseOrder>();
        final saved = await store.insert(
          orders,
          PurchaseOrder(
            customer: 'x',
            lines: [OrderLine(sku: 'a', quantity: 1)],
          ),
        );
        saved.lines = [
          OrderLine(sku: 'b', quantity: 2),
          OrderLine(sku: 'c', quantity: 3),
        ];
        await store.update(orders, saved);
        final loaded = (await store.findById(orders, saved.id!))!;
        expect([for (final l in loaded.lines) l.sku], ['b', 'c']);
      }),
    );
  });

  group('logging', () {
    test(
      'debug says what happens, values only at trace',
      () => run(() async {
        const name = 'spring.data.memory.InMemoryDataStore';
        final records = <SpringLogRecord>[];
        final stop = SpringLog.listen(records.add);
        final handler = SpringLog.handler;
        SpringLog.handler = (_) {};
        addTearDown(() {
          stop();
          SpringLog.resetLevels();
          SpringLog.handler = handler;
        });
        SpringLog.setLevel(name, SpringLogLevel.debug);
        await add('secret-title');
        await store.find(
          entity,
          criteria: where(PartType.simpleProperty, 'title', ['secret-title']),
        );
        final debug = [
          for (final r in records)
            if (r.loggerName == name) r.message,
        ];
        expect(debug, isNotEmpty);
        expect(debug.join('\n'), isNot(contains('secret-title')));
        expect(debug.join('\n'), contains('books'));

        records.clear();
        SpringLog.setLevel(name, SpringLogLevel.trace);
        await add('another-secret');
        final trace = [
          for (final r in records)
            if (r.loggerName == name) r.message,
        ];
        expect(trace.join('\n'), contains('another-secret'));
      }),
    );
  });
}
