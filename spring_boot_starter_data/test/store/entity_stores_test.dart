// The stores work through the entity descriptions the generator writes (here
// by hand, in ../mapping/support.dart): the same entities, in memory, in
// SQLite and, with SPRING_TEST_POSTGRES_URL set, in PostgreSQL, with mutable,
// immutable and mixed classes.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../mapping/support.dart';
import '../postgres/support.dart' show newPostgresSource, postgresSkip;
import '../schema/support.dart' show memorySource;

void main() {
  late RelationalMappingContext mapping;
  late PersistentEntity<Author> authors;
  late PersistentEntity<Book> books;
  late PersistentEntity<OrderLine> lines;
  late PersistentEntity<Reading> readings;
  late PersistentEntity<Gauge> gauges;

  setUp(() {
    mapping = testContext();
    authors = mapping.getRequiredPersistentEntity<Author>();
    books = mapping.getRequiredPersistentEntity<Book>();
    lines = mapping.getRequiredPersistentEntity<OrderLine>();
    readings = mapping.getRequiredPersistentEntity<Reading>();
    gauges = mapping.getRequiredPersistentEntity<Gauge>();
  });

  Future<DataStore> storeNamed(String name) async {
    final converter = EntityConverter();
    if (name == 'memory') {
      return InMemoryDataStore(converter: converter);
    }
    final db = name == 'postgres'
        ? await newPostgresSource()
        : await memorySource();
    await SchemaCreator(db).create([authors, books, lines, readings, gauges]);
    return JdbcDataStore(dataSource: db, converter: converter);
  }

  for (final name in ['memory', 'sqlite', 'postgres']) {
    group(
      name,
      skip: name == 'postgres' ? postgresSkip : null,
      tags: name == 'postgres' ? 'postgres' : null,
      () {
        late DataStore store;
        setUp(() async => store = await storeNamed(name));

        test('a mutable entity is changed in place and read back', () async {
          await store.insert(authors, Author(id: 1, name: 'Herbert'));
          final book = Book(
            title: 'Dune',
            year: 1965,
            genre: Genre.science,
            author: const AggregateReference<Author, int>(1),
            note: 'not stored',
          );
          final saved = await store.insert(books, book);
          expect(saved, same(book));
          expect((book.id, book.version), (1, 1));

          final found = (await store.findById(books, 1))!;
          expect(found, isNot(same(book)));
          expect(found.title, 'Dune');
          expect(found.genre, Genre.science);
          expect(found.author, const AggregateReference<Author, int>(1));
          expect(found.price, 0.0);
          expect(found.available, isFalse);
          expect(found.note, isNull);

          found.title = 'Dune Messiah';
          final updated = await store.update(books, found);
          expect(updated, same(found));
          expect(found.version, 2);
          expect((await store.findById(books, 1))!.title, 'Dune Messiah');
        });

        test('an immutable entity is copied with its id and version', () async {
          final original = makeReading(null, 'first', score: 1.5);
          final saved = await store.insert(readings, original);
          expect(saved, isNot(same(original)));
          expect((saved.id, saved.version, saved.score), (1, 1, 1.5));
          expect(original.id, isNull);

          final found = (await store.findById(readings, 1))!;
          expect((found.text, found.score, found.version), ('first', 1.5, 1));
          expect(found.kind, 'reading');

          final updated = await store.update(readings, found);
          expect(updated.version, 2);
        });

        test(
          'a mixed entity: the copy keeps what the constructor lacks',
          () async {
            final original = Gauge(null, 'g')
              ..level = 8
              ..label = 'north'
              ..scratch = 'not stored';
            final saved = await store.insert(gauges, original);
            expect(saved, isNot(same(original)));
            expect(saved.id, 1);
            expect((saved.level, saved.label), (8, 'north'));
            expect(saved.scratch, 'not stored');

            // The stored row has the settable columns, not the @Transient one.
            final found = (await store.findById(gauges, 1))!;
            expect((found.name, found.level, found.label), ('g', 8, 'north'));
            expect(found.scratch, isNull);
          },
        );

        test('children go with their root', () async {
          final line = OrderLine(
            items: [
              Item(sku: 'a'),
              Item(sku: 'b', qty: 3),
            ],
            tags: {Tag('x'), Tag('y')},
            notes: {'k': Note(text: 't')},
            extras: [Item(sku: 'c')],
          );
          await store.insert(lines, line);
          final found = (await store.findById(lines, line.id!))!;
          expect(found.items.map((i) => (i.sku, i.qty)), [('a', 1), ('b', 3)]);
          expect(found.tags.map((t) => t.label), unorderedEquals(['x', 'y']));
          expect(found.notes['k']!.text, 't');
          expect(found.extras!.single.sku, 'c');

          found.items.removeLast();
          await store.update(lines, found);
          expect((await store.findById(lines, found.id!))!.items, hasLength(1));
          expect(await store.deleteById(lines, found.id!), isTrue);
          expect(await store.findById(lines, found.id!), isNull);
        });
      },
    );
  }
}
