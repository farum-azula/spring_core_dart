import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../mapping/support.dart';
import 'support.dart';

void main() {
  late RelationalMappingContext context;
  late PersistentEntity<Book> book;
  late PersistentEntity<OrderLine> orderLine;
  late PersistentEntity<Reading> reading;

  setUp(() {
    context = testContext();
    book = context.getRequiredPersistentEntity<Book>();
    orderLine = context.getRequiredPersistentEntity<OrderLine>();
    reading = context.getRequiredPersistentEntity<Reading>();
  });

  group('the statements', () {
    test('a root table: identity id, NOT NULL, @Column, @Version', () async {
      final db = await memorySource();
      final statements = SchemaCreator(db).createStatements([book]);
      // The authors the book references come first; the reference is also
      // indexed.
      expect(statements, hasLength(3));
      expect(
        statements.first,
        startsWith('CREATE TABLE IF NOT EXISTS "authors"'),
      );
      final sql = statements[1];
      expect(sql, startsWith('CREATE TABLE IF NOT EXISTS "books" ('));
      expect(sql, contains('"id" INTEGER PRIMARY KEY'));
      expect(sql, contains('"title" TEXT NOT NULL'));
      expect(sql, contains('"year" INTEGER,'));
      expect(sql, contains('"genre" TEXT,'));
      expect(sql, contains('"price" REAL NOT NULL'));
      expect(sql, contains('"available" INTEGER NOT NULL'));
      expect(
        sql,
        contains('"writer_id" INTEGER REFERENCES "authors" ("id"),'),
      );
      expect(sql, contains('"version" INTEGER NOT NULL'));
      expect(sql, contains('"created_at" TEXT,'));
      expect(sql, isNot(contains('note')));
    });

    test(
      'children come after their parent, with reverse and key columns',
      () async {
        final db = await memorySource();
        final statements = SchemaCreator(db).createStatements([orderLine]);
        final tables = [
          for (final s in statements)
            RegExp(r'CREATE TABLE IF NOT EXISTS "(\w+)"')
                .firstMatch(s)!
                .group(1),
        ];
        expect(tables.first, 'order_line');
        expect(tables, unorderedEquals(['order_line', 'item', 'tags', 'note']));
        String sql(String table) =>
            statements.singleWhere((s) => s.contains('"$table" ('));
        // @MappedCollection(idColumn: 'line_ref', keyColumn: 'position');
        // `item` is shared with `extras`, so both stay nullable (see below).
        expect(
          sql('item'),
          contains(
            '"line_ref" INTEGER REFERENCES "order_line" ("id") ON DELETE '
            'CASCADE',
          ),
        );
        expect(sql('item'), contains('"position" INTEGER,'));
        // The default names, a Set has no key, a Map has a key of its type.
        expect(
          sql('tags'),
          contains('"order_line_id" INTEGER NOT NULL REFERENCES'),
        );
        expect(sql('tags'), isNot(contains('order_line_key')));
        expect(sql('note'), contains('"order_line_key" TEXT NOT NULL'));
        expect(sql('note'), contains('"text" TEXT NOT NULL'));
      },
    );

    test('a child class used twice is one table with both parents', () async {
      final db = await memorySource();
      final sql = SchemaCreator(db)
          .createStatements([orderLine])
          .singleWhere((s) => s.contains('"item" ('));
      // `items` and `extras` are both Item children of OrderLine.
      expect(sql, contains('"order_line_id" INTEGER REFERENCES'));
      expect('"item" ('.allMatches(sql), hasLength(1));
      // Not in both: no longer NOT NULL.
      expect(sql, contains('"line_ref" INTEGER REFERENCES'));
    });

    test('a non-identity id is its type as the primary key', () async {
      final db = await memorySource();
      final sql = SchemaCreator(db).createStatements([reading]).single;
      expect(sql, contains('"id" INTEGER PRIMARY KEY'));
      expect(sql, contains('"score" REAL,'));
      // A final field that is no constructor parameter is not mapped.
      expect(sql, isNot(contains('kind')));
    });

    test('drop statements go in the reverse order', () async {
      final db = await memorySource();
      final creator = SchemaCreator(db);
      final drops = creator.dropStatements([orderLine]);
      expect(drops.last, 'DROP TABLE IF EXISTS "order_line"');
      expect(drops, hasLength(4));
    });
  });

  group('creation on SQLite', () {
    test('the tables are usable', () async {
      final db = await memorySource();
      await SchemaCreator(db).create([book]);
      await run(
        db,
        'INSERT INTO books (title, price, available, version) '
        "VALUES ('Dune', 9.5, 1, 0)",
      );
      await run(
        db,
        'INSERT INTO books (title, price, available, version) '
        "VALUES ('Emma', 7, 0, 0)",
      );
      expect(await rowsOf(db, 'SELECT id, title FROM books ORDER BY id'), [
        [1, 'Dune'],
        [2, 'Emma'],
      ]);
    });

    test('NOT NULL is enforced', () async {
      final db = await memorySource();
      await SchemaCreator(db).create([book]);
      await expectLater(
        run(db, 'INSERT INTO books (year) VALUES (1)'),
        throwsA(isA<SqlError>()),
      );
    });

    test('creating twice leaves the tables and their rows', () async {
      final db = await memorySource();
      final creator = SchemaCreator(db);
      await creator.create([book]);
      await run(
        db,
        'INSERT INTO books (title, price, available, version) '
        "VALUES ('Dune', 9.5, 1, 0)",
      );
      await creator.create([book]);
      expect(await value(db, 'SELECT count(*) FROM books'), 1);
    });

    test('child rows follow their parent: foreign key and cascade', () async {
      final db = await memorySource();
      await SchemaCreator(db).create([orderLine]);
      await run(db, 'INSERT INTO order_line DEFAULT VALUES');
      await run(
        db,
        'INSERT INTO item (sku, qty, line_ref, position) '
        "VALUES ('a', 1, 1, 0), ('b', 2, 1, 1)",
      );
      await run(db, "INSERT INTO tags (label, order_line_id) VALUES ('x', 1)");
      await run(
        db,
        'INSERT INTO note (text, order_line_id, order_line_key) '
        "VALUES ('hi', 1, 'k')",
      );
      // A child needs its parent.
      await expectLater(
        run(
          db,
          'INSERT INTO item (sku, qty, line_ref, position) '
          "VALUES ('c', 1, 99, 0)",
        ),
        throwsA(isA<SqlError>()),
      );
      await run(db, 'DELETE FROM order_line WHERE id = 1');
      for (final table in ['item', 'tags', 'note']) {
        expect(
          await value(db, 'SELECT count(*) FROM $table'),
          0,
          reason: table,
        );
      }
    });

    test('drop removes the tables, children first', () async {
      final db = await memorySource();
      final creator = SchemaCreator(db);
      await creator.create([book, orderLine]);
      expect(await tablesOf(db), hasLength(6));
      await creator.drop([book, orderLine]);
      expect(await tablesOf(db), isEmpty);
      // Dropping again is harmless.
      await creator.drop([book, orderLine]);
    });

    test('a failing statement is a SchemaException', () async {
      final dir = newTemp();
      addTearDown(() => deleteTemp(dir));
      await run(await fileSource(dir, 'ro.db'), 'CREATE TABLE x (a)');
      final readOnly = PooledDataSource(
        name: 'ro',
        driver: await driver(),
        settings: fileSettings(dir, 'ro.db', query: '?mode=ro'),
        pool: const PoolSettings(maxSize: 1),
      );
      addTearDown(readOnly.close);
      final error = await failure<SchemaException>(
        () => SchemaCreator(readOnly).create([book]),
      );
      expect(error.message, contains('readonly'));
      expect(await tablesOf(readOnly), ['x']);
    });
  });

  test('a type without a column type is named', () async {
    final db = await memorySource();
    final entity = PersistentEntity<Object>(
      introspection: book.introspection,
      tableName: 'odd',
      properties: [
        PersistentProperty(
          name: 'thing',
          columnName: 'thing',
          type: const ClassType<Duration>(),
          accessor: book.properties.first.accessor,
        ),
      ],
    );
    final error = await failure<SchemaException>(
      () async => SchemaCreator(db).createStatements([entity]),
    );
    expect(error.message, contains('Book.thing'));
    expect(error.message, contains('Duration'));
  });

  test('a mapped collection under an entity without @Id is refused', () async {
    final db = await memorySource();
    final noId = PersistentEntity<Object>(
      introspection: orderLine.introspection,
      tableName: 'order_line',
      properties: [
        for (final p in orderLine.properties)
          if (!p.isId) p,
      ],
    );
    final error = await failure<SchemaException>(
      () async => SchemaCreator(db).createStatements([noId]),
    );
    expect(error.message, contains('needs an @Id'));
  });
}
