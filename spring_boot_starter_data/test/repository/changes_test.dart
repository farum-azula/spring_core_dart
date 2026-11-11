import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../mapping/support.dart';
import 'support/plain_store.dart';

// The changes of rows: the in-memory store reports them once committed,
// the operations give them as a stream (changes) or keep a query's result
// up to date (watch).
const _byGenre = PartTree('changesByGenre', [
  OrPart([Part('genre')]),
]);
const _all = PartTree('changesBy', []);
const _watchByGenre = PartTree(
  'watchByGenreOrderByTitle',
  [
    OrPart([Part('genre')]),
  ],
  sort: Sort([SortOrder.asc('title')]),
);
const _expensive = PartTree('changesByPriceGreaterThan', [
  OrPart([Part('price', PartType.greaterThan)]),
]);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late EntityConverter converter;
  late InMemoryDataStore memory;
  late RelationalMappingContext context;
  late PersistentEntity<Book> entity;
  late RepositoryOperations<Book, int> books;

  RepositoryOperations<Book, int> on(DataStore store) => RepositoryFactory(
    mappingContext: context,
    converter: converter,
    stores: [store],
  ).operations<Book, int>('Books', annotations: [UseStore(store.name)]);

  setUpAll(() => SpringLog.level = SpringLogLevel.off);
  setUp(() {
    converter = EntityConverter();
    memory = InMemoryDataStore(converter: converter);
    context = testContext();
    entity = context.getRequiredPersistentEntity<Book>();
    books = on(memory);
  });

  Book book(String title, Genre genre, {double price = 0}) =>
      Book(title: title, genre: genre, price: price);

  group('CriteriaMatcher', () {
    CriteriaMatcher<Book> matcher(PartTree tree, List<Object?> arguments) =>
        CriteriaMatcher<Book>(
          entity,
          Criteria(tree.predicate, arguments),
          converter: converter,
        );

    test('tests an instance and a row', () {
      final science = matcher(_byGenre, [Genre.science]);
      expect(science.matches(book('Dune', Genre.science)), isTrue);
      expect(science.matches(book('Emma', Genre.fiction)), isFalse);
      expect(science.matchesRow({'genre': 'science'}), isTrue);
      expect(science.matchesRow({'genre': 'fiction'}), isFalse);
      expect(science.matchesRow({'genre': null}), isFalse);
    });

    test('alternatives, comparisons and no condition at all', () {
      final either = matcher(
        const PartTree('x', [
          OrPart([Part('title', PartType.startingWith, true)]),
          OrPart([
            Part('price', PartType.between),
            Part('year', PartType.isNull),
          ]),
        ]),
        ['du', 5, 10],
      );
      expect(either.matches(book('Dune', Genre.science)), isTrue);
      expect(either.matches(book('Emma', Genre.fiction, price: 7)), isTrue);
      expect(either.matches(book('Emma', Genre.fiction, price: 11)), isFalse);
      expect(
        either.matches(book('Emma', Genre.fiction, price: 7)..year = 1815),
        isFalse,
      );
      expect(matcher(_all, const []).matches(book('Any', Genre.fiction)), true);
    });

    test('a property that is no column is refused when it is made', () {
      expect(
        () => matcher(
          const PartTree('x', [
            OrPart([Part('nope')]),
          ]),
          [1],
        ),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
    });

    test('a change concerns the criteria by its row or its previous row; '
        'one without rows always does', () {
      final science = matcher(_byGenre, [Genre.science]);
      final dune = book('Dune', Genre.science);
      final emma = book('Emma', Genre.fiction);
      expect(
        science.concerns(RowChange(RowChangeKind.insert, row: dune)),
        isTrue,
      );
      expect(
        science.concerns(RowChange(RowChangeKind.insert, row: emma)),
        isFalse,
      );
      expect(
        science.concerns(
          RowChange(RowChangeKind.update, row: emma, previous: dune),
        ),
        isTrue,
      );
      expect(
        science.concerns(RowChange(RowChangeKind.delete, previous: emma)),
        isFalse,
      );
      expect(
        science.concerns(const RowChange(RowChangeKind.delete, id: 1)),
        isTrue,
      );
    });

    test('compareValues and sameValue', () {
      expect(CriteriaMatcher.compareValues(1, 2.5), isNegative);
      expect(CriteriaMatcher.compareValues('b', 'a'), isPositive);
      expect(CriteriaMatcher.compareValues(1, 'a'), isNull);
      expect(CriteriaMatcher.sameValue(1, 1.0), isTrue);
      expect(CriteriaMatcher.sameValue(null, null), isTrue);
      expect(CriteriaMatcher.sameValue(null, 1), isFalse);
      expect(CriteriaMatcher.sameValue([1, 2], [1, 2]), isTrue);
    });
  });

  group('the in-memory store', () {
    test('an insert, an update and a delete are seen, with the rows before '
        'and after', () async {
      final seen = <RowChange<Book>>[];
      final subscription = memory.changes<Book>(entity).listen(seen.add);
      final saved = await books.save(book('Dune', Genre.science));
      await books.save(saved..title = 'Dune Messiah');
      await books.deleteById(saved.id!);
      await _settle();
      expect(seen.map((c) => c.kind), [
        RowChangeKind.insert,
        RowChangeKind.update,
        RowChangeKind.delete,
      ]);
      expect(seen.map((c) => c.id), [saved.id, saved.id, saved.id]);
      expect(seen[0].row!.title, 'Dune');
      expect(seen[0].previous, isNull);
      expect(seen[1].row!.title, 'Dune Messiah');
      expect(seen[1].previous!.title, 'Dune');
      expect(seen[2].row, isNull);
      expect(seen[2].previous!.title, 'Dune Messiah');
      expect('${seen[2]}', 'RowChange(delete ${saved.id})');
      await subscription.cancel();
    });

    test('nothing before the stream is listened to, nothing after it is '
        'cancelled', () async {
      final stream = memory.changes<Book>(entity);
      await books.save(book('Early', Genre.fiction));
      expect(memory.changeListenerCount, 0);
      final seen = <RowChange<Book>>[];
      final subscription = stream.listen(seen.add);
      expect(memory.changeListenerCount, 1);
      await books.save(book('Dune', Genre.science));
      await _settle();
      await subscription.cancel();
      expect(memory.changeListenerCount, 0);
      await books.save(book('Late', Genre.fiction));
      await _settle();
      expect(seen.map((c) => c.row!.title), ['Dune']);
    });

    test('the criteria are applied by the store: a row that matches after '
        'or matched before', () async {
      final criteria = Criteria(_byGenre.predicate, [Genre.science]);
      expect(memory.filtersChanges<Book>(entity, criteria), isTrue);
      final seen = <RowChange<Book>>[];
      final subscription = memory
          .changes<Book>(entity, criteria: criteria)
          .listen(seen.add);
      await books.save(book('Emma', Genre.fiction));
      final dune = await books.save(book('Dune', Genre.science));
      // It leaves the set: reported, with its new row.
      final moved = await books.save(dune..genre = Genre.fiction);
      // Now it never matched: not reported.
      await books.save(moved..title = 'Dune 2');
      await books.deleteAll();
      await _settle();
      expect(seen.map((c) => (c.kind, c.row?.title)), [
        (RowChangeKind.insert, 'Dune'),
        (RowChangeKind.update, 'Dune'),
      ]);
      expect(seen[1].row!.genre, Genre.fiction);
      await subscription.cancel();
    });

    test('a criteria on a property that is no column is refused', () {
      expect(
        () => memory.changes<Book>(
          entity,
          criteria: Criteria(
            const [
              OrPart([Part('nope')]),
            ],
            [1],
          ),
        ),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
    });

    test('the writes of a transaction are reported when it commits, a row '
        'written twice once', () async {
      final seen = <RowChange<Book>>[];
      final subscription = memory.changes<Book>(entity).listen(seen.add);
      await TransactionTemplate(memory.transactionManager).execute((_) async {
        final dune = await books.save(book('Dune', Genre.science));
        await books.save(dune..title = 'Dune Messiah');
        await books.save(book('Emma', Genre.fiction));
        final gone = await books.save(book('Gone', Genre.fiction));
        await books.deleteById(gone.id!);
        await _settle();
        expect(seen, isEmpty);
      });
      await _settle();
      expect(seen.map((c) => (c.kind, c.row?.title)), [
        (RowChangeKind.insert, 'Dune Messiah'),
        (RowChangeKind.insert, 'Emma'),
      ]);
      await subscription.cancel();
    });

    test('a transaction that rolls back reports nothing', () async {
      final kept = await books.save(book('Kept', Genre.fiction));
      final seen = <RowChange<Book>>[];
      final subscription = memory.changes<Book>(entity).listen(seen.add);
      await expectLater(
        TransactionTemplate(memory.transactionManager).execute((_) async {
          await books.save(book('Dune', Genre.science));
          await books.save(kept..title = 'Changed');
          await books.deleteById(kept.id!);
          throw StateError('no');
        }),
        throwsStateError,
      );
      await _settle();
      expect(seen, isEmpty);
      expect((await books.findById(kept.id!))!.title, 'Kept');
      await subscription.cancel();
    });

    test('a write that fails reports nothing', () async {
      final seen = <RowChange<Book>>[];
      final subscription = memory.changes<Book>(entity).listen(seen.add);
      await expectLater(
        memory
            .insert<Book>(entity, Book(id: 1, title: 'A'))
            .then(
              (_) => memory.insert<Book>(entity, Book(id: 1, title: 'B')),
            ),
        throwsA(isA<DuplicateKeyException>()),
      );
      await _settle();
      expect(seen.map((c) => c.row!.title), ['A']);
      await subscription.cancel();
    });

    test('each listener has its own stream, of its own entity', () async {
      final authors = context.getRequiredPersistentEntity<Author>();
      final bookChanges = <RowChange<Book>>[];
      final authorChanges = <RowChange<Author>>[];
      final a = memory.changes<Book>(entity).listen(bookChanges.add);
      final b = memory.changes<Author>(authors).listen(authorChanges.add);
      final c = memory.changes<Book>(entity).listen(bookChanges.add);
      expect(memory.changeListenerCount, 3);
      await memory.insert<Author>(authors, Author(name: 'Herbert'));
      await books.save(book('Dune', Genre.science));
      await _settle();
      expect(authorChanges.single.row!.name, 'Herbert');
      expect(bookChanges, hasLength(2));
      await Future.wait([a.cancel(), b.cancel(), c.cancel()]);
      expect(memory.changeListenerCount, 0);
    });
  });

  group('operations.changes', () {
    test('the changes that concern the tree, filtered by the store', () async {
      final seen = <RowChange<Book>>[];
      final subscription = books
          .changes(_byGenre, [Genre.science])
          .listen(seen.add);
      await books.save(book('Emma', Genre.fiction));
      await books.save(book('Dune', Genre.science));
      await _settle();
      expect(seen.single.row!.title, 'Dune');
      await subscription.cancel();
      expect(memory.changeListenerCount, 0);
    });

    test('a tree without conditions reports everything', () async {
      final seen = <RowChange<Book>>[];
      final subscription = books.changes(_all, const []).listen(seen.add);
      await books.save(book('Emma', Genre.fiction));
      await books.save(book('Dune', Genre.science));
      await _settle();
      expect(seen, hasLength(2));
      await subscription.cancel();
    });

    test('what the store does not filter is filtered here', () async {
      final feed = UnfilteredChangeStore(memory);
      final viaFeed = on(feed);
      final seen = <RowChange<Book>>[];
      final subscription = viaFeed.changes(_expensive, [10]).listen(seen.add);
      await viaFeed.save(book('Cheap', Genre.fiction, price: 5));
      final dear = await viaFeed.save(book('Dear', Genre.fiction, price: 50));
      await viaFeed.save(dear..price = 1);
      await viaFeed.save(dear..title = 'Sale');
      await _settle();
      // The store was asked with the criteria, and said it did not apply
      // them.
      expect(feed.asked.single, isNotNull);
      expect(seen.map((c) => (c.kind, c.row?.title, c.row?.price)), [
        (RowChangeKind.insert, 'Dear', 50.0),
        (RowChangeKind.update, 'Dear', 1.0),
      ]);
      await subscription.cancel();
      expect(memory.changeListenerCount, 0);
    });

    test('the stream opens when it is listened to; a misuse is its '
        'error', () async {
      final stream = books.changes(_byGenre, const []);
      expect(memory.changeListenerCount, 0);
      await expectLater(
        stream,
        emitsInOrder([
          emitsError(isA<InvalidDataAccessApiUsageException>()),
          emitsDone,
        ]),
      );
    });

    test('a store that reports no changes is refused', () {
      final plain = on(PlainStore(memory));
      for (final call in <void Function()>[
        () => plain.changes(_byGenre, [Genre.science]),
        () => plain.watch(_watchByGenre, [Genre.science]),
      ]) {
        expect(
          call,
          throwsA(
            isA<InvalidDataAccessApiUsageException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('needs a store that reports the changes'),
                contains('the rest store is none'),
              ),
            ),
          ),
        );
      }
    });
  });

  group('operations.watch', () {
    test('the result when it is listened to, and again after every change '
        'that concerns it', () async {
      await books.save(book('Dune', Genre.science));
      final lists = <List<String>>[];
      final subscription = books
          .watch(_watchByGenre, [Genre.science])
          .listen((rows) => lists.add([for (final b in rows) b.title]));
      await _settle();
      expect(lists, [
        ['Dune'],
      ]);
      await books.save(book('Emma', Genre.fiction));
      await _settle();
      expect(lists, hasLength(1));
      final cosmos = await books.save(book('Cosmos', Genre.science));
      await _settle();
      await books.save(cosmos..genre = Genre.fiction);
      await _settle();
      expect(lists, [
        ['Dune'],
        ['Cosmos', 'Dune'],
        ['Dune'],
      ]);
      await subscription.cancel();
    });

    test('a Sort and a Pageable are those of the query', () async {
      await books.saveAll([
        book('A', Genre.science, price: 1),
        book('B', Genre.science, price: 3),
        book('C', Genre.science, price: 2),
      ]);
      final first = await books
          .watch(
            _all,
            const [],
            pageable: PageRequest.of(0, 2, Sort.by(['price']).descending()),
          )
          .first;
      expect(first, isA<List<Book>>());
      expect(first.map((b) => b.title), ['B', 'C']);
      final sorted = await books
          .watch(_all, const [], sort: Sort.by(['price']))
          .first;
      expect(sorted.map((b) => b.title), ['A', 'C', 'B']);
      expect(memory.changeListenerCount, 0);
    });

    test('queries never overlap: the changes during a query are answered by '
        'exactly one more', () async {
      final slow = _GatedStore(memory);
      final viaSlow = on(slow);
      final lists = <int>[];
      final subscription = viaSlow
          .watch(_all, const [])
          .listen((rows) => lists.add(rows.length));
      await _settle();
      // The first query is held: three changes commit meanwhile.
      expect(slow.running, 1);
      await memory.insert<Book>(entity, book('A', Genre.fiction));
      await memory.insert<Book>(entity, book('B', Genre.fiction));
      await memory.insert<Book>(entity, book('C', Genre.fiction));
      await _settle();
      expect(slow.finds, 1);
      expect(lists, isEmpty);
      slow.release();
      await _settle();
      // One more query for the three, and it is held too.
      expect(slow.finds, 2);
      expect(slow.maxRunning, 1);
      slow.release();
      await _settle();
      await _settle();
      expect(slow.finds, 2);
      expect(lists, [0, 3]);
      // A change with no query running: one query.
      await memory.insert<Book>(entity, book('D', Genre.fiction));
      await _settle();
      slow.release();
      await _settle();
      expect(slow.finds, 3);
      expect(lists, [0, 3, 4]);
      expect(slow.maxRunning, 1);
      await subscription.cancel();
    });

    test('cancelling releases the subscription of the store, also during a '
        'query', () async {
      final slow = _GatedStore(memory);
      final lists = <List<Book>>[];
      final subscription = on(slow).watch(_all, const []).listen(lists.add);
      await _settle();
      expect(memory.changeListenerCount, 1);
      await subscription.cancel();
      expect(memory.changeListenerCount, 0);
      slow.release();
      await memory.insert<Book>(entity, book('A', Genre.fiction));
      await _settle();
      expect(lists, isEmpty);
      expect(slow.finds, 1);
    });

    test('an error of a query is forwarded and does not end the '
        'stream', () async {
      final slow = _GatedStore(memory)..gated = false;
      final events = <Object>[];
      var done = false;
      final subscription = on(slow)
          .watch(_all, const [])
          .listen(
            (rows) => events.add(rows.length),
            onError: (Object error) => events.add(error),
            onDone: () => done = true,
          );
      await _settle();
      slow.failure = StateError('broken');
      await memory.insert<Book>(entity, book('A', Genre.fiction));
      await _settle();
      slow.failure = null;
      await memory.insert<Book>(entity, book('B', Genre.fiction));
      await _settle();
      expect(events, [0, isA<InvalidDataAccessApiUsageException>(), 2]);
      expect(done, isFalse);
      await subscription.cancel();
    });

    test("an error of the store's changes is forwarded too", () async {
      final broken = _BrokenFeed(memory);
      final events = <Object>[];
      final subscription = on(broken)
          .watch(_all, const [])
          .listen(
            (rows) => events.add(rows.length),
            onError: (Object error) => events.add(error),
          );
      await _settle();
      broken.feed.addError(const FormatException('bad frame'));
      await _settle();
      broken.feed.add(const RowChange<Book>(RowChangeKind.delete, id: 1));
      await _settle();
      expect(events, [0, isA<InvalidDataAccessApiUsageException>(), 0]);
      await subscription.cancel();
      expect(broken.feed.hasListener, isFalse);
    });

    test('a paused subscription queries nothing and catches up with one '
        'query', () async {
      final slow = _GatedStore(memory)..gated = false;
      final lists = <int>[];
      final subscription = on(slow)
          .watch(_all, const [])
          .listen((rows) => lists.add(rows.length));
      await _settle();
      subscription.pause();
      await memory.insert<Book>(entity, book('A', Genre.fiction));
      await memory.insert<Book>(entity, book('B', Genre.fiction));
      await _settle();
      expect(slow.finds, 1);
      subscription.resume();
      await _settle();
      await _settle();
      expect(lists.last, 2);
      expect(slow.finds, lessThanOrEqualTo(3));
      await subscription.cancel();
    });
  });
}

// A store whose finds wait until the test releases them, one at a time.
class _GatedStore extends PlainStore implements ChangeStreamDataStore {
  _GatedStore(super.inner)
    : super(capabilities: const DataStoreCapabilities(changes: true));

  bool gated = true;
  Object? failure;
  int finds = 0;
  int running = 0;
  int maxRunning = 0;
  final _gates = <Completer<void>>[];

  /// Lets the oldest waiting find go on.
  void release() => _gates.removeAt(0).complete();

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
  }) async {
    finds++;
    running++;
    maxRunning = running > maxRunning ? running : maxRunning;
    try {
      if (failure case final failure?) {
        Error.throwWithStackTrace(failure, StackTrace.current);
      }
      // Reads at once, answers when released.
      final rows = await inner.find(entity, criteria: criteria, sort: sort);
      if (gated) {
        final gate = Completer<void>();
        _gates.add(gate);
        await gate.future;
      }
      return rows;
    } finally {
      running--;
    }
  }

  @override
  Stream<RowChange<T>> changes<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => inner.changes<T>(entity, criteria: criteria);

  @override
  bool filtersChanges<T extends Object>(
    PersistentEntity<T> entity,
    Criteria criteria,
  ) => true;
}

// A store whose changes the test sends itself.
class _BrokenFeed extends PlainStore implements ChangeStreamDataStore {
  _BrokenFeed(super.inner)
    : super(capabilities: const DataStoreCapabilities(changes: true));

  final feed = StreamController<RowChange<Book>>();

  @override
  Stream<RowChange<T>> changes<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => feed.stream.cast<RowChange<T>>();

  @override
  bool filtersChanges<T extends Object>(
    PersistentEntity<T> entity,
    Criteria criteria,
  ) => true;
}
