import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../mapping/support.dart';
import 'support.dart';

const _authors =
    'CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT NOT NULL)';

// Book.author references authors: the books table has the foreign key.
const _books =
    'CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT NOT NULL, '
    'year INTEGER, genre TEXT, price REAL NOT NULL, available INTEGER NOT '
    'NULL, writer_id INTEGER REFERENCES authors (id), version INTEGER NOT '
    'NULL, created_at TEXT, '
    'modified_at TEXT, created_by TEXT, modified_by TEXT)';

void main() {
  late RelationalMappingContext context;
  late PersistentEntity<Book> book;
  late PersistentEntity<OrderLine> orderLine;

  setUp(() {
    context = testContext();
    book = context.getRequiredPersistentEntity<Book>();
    orderLine = context.getRequiredPersistentEntity<OrderLine>();
  });

  // A private database that has the authors the books reference.
  Future<DataSource> source() async {
    final db = await memorySource();
    await run(db, _authors);
    return db;
  }

  Future<SchemaValidationReport> validate(
    DataSource db,
    List<PersistentEntity<Object>> entities,
  ) => SchemaValidator(db).validate(entities);

  group('what is accepted', () {
    test('a schema that fits has no problem and no warning', () async {
      final db = await source();
      await run(db, _books);
      final report = await validate(db, [book]);
      expect(report.problems, isEmpty);
      expect(report.warnings, isEmpty);
      expect(report.isValid, isTrue);
    });

    test('extra tables and columns are fine', () async {
      final db = await source();
      await run(db, _books);
      await run(db, 'ALTER TABLE books ADD COLUMN isbn TEXT');
      await run(db, 'CREATE TABLE unrelated (x)');
      expect((await validate(db, [book])).isValid, isTrue);
    });

    test('column names are matched without regard to case', () async {
      final db = await source();
      await run(db, _books.toUpperCase().replaceFirst('BOOKS', 'books'));
      expect((await validate(db, [book])).problems, isEmpty);
    });

    test(
      'types that fit are accepted: affinity rules, references, enums',
      () async {
        final db = await source();
        await run(
          db,
          'CREATE TABLE books (id BIGINT PRIMARY KEY, title VARCHAR(80) NOT '
          'NULL, year INT, genre TEXT, price NUMERIC NOT NULL, available '
          'BOOLEAN NOT NULL DEFAULT 0, writer_id INTEGER REFERENCES authors '
          '(id), version INTEGER NOT NULL, created_at TIMESTAMP, '
          'modified_at TIMESTAMP, created_by TEXT, modified_by TEXT)',
        );
        // BOOLEAN has numeric affinity: it holds the 0 and 1 of a bool.
        expect((await validate(db, [book])).problems, isEmpty);
      },
    );

    test('a column without a declared type holds anything', () async {
      final db = await source();
      await run(db, 'CREATE TABLE tags (label NOT NULL, order_line_id)');
      await run(db, 'CREATE TABLE order_line (id INTEGER PRIMARY KEY)');
      final report = await validate(db, [orderLine]);
      expect(
        report.problems.where((p) => p.contains('"tags"')),
        isEmpty,
      );
    });

    test('no entities, nothing to check', () async {
      final db = await source();
      expect((await validate(db, const [])).isValid, isTrue);
    });
  });

  group('problems', () {
    test('a missing table names the entity and the table', () async {
      final db = await source();
      final report = await validate(db, [book]);
      expect(report.problems, hasLength(1));
      expect(report.problems.single, contains('Missing table "books"'));
      expect(report.problems.single, contains('Book'));
    });

    test(
      'missing columns: every one is listed with entity and property',
      () async {
        final db = await source();
        await run(
          db,
          'CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT)',
        );
        final report = await validate(db, [book]);
        final missing = report.problems.where(
          (p) => p.startsWith('Missing column'),
        );
        expect(missing, hasLength(10));
        final year = report.problems.singleWhere(
          (p) => p.contains('Book.year'),
        );
        expect(year, contains('"year"'));
        expect(year, contains('table "books"'));
        expect(year, contains('expected INTEGER'));
        expect(year, contains('found no such column'));
        // The column named by @Column, not the property.
        expect(
          report.problems.any(
            (p) => p.contains('"writer_id"') && p.contains('Book.author'),
          ),
          isTrue,
        );
        expect(report.problems.any((p) => p.contains('Book.note')), isFalse);
      },
    );

    test('a type that does not fit shows expected and found', () async {
      final db = await source();
      await run(
        db,
        _books
            .replaceFirst('price REAL', 'price TEXT')
            .replaceFirst('year INTEGER', 'year TEXT')
            .replaceFirst('title TEXT', 'title INTEGER'),
      );
      final report = await validate(db, [book]);
      expect(report.problems, hasLength(3));
      final price = report.problems.singleWhere(
        (p) => p.contains('Book.price'),
      );
      expect(price, contains('"price"'));
      expect(price, contains('wrong type'));
      expect(price, contains('expected REAL'));
      expect(price, contains('found TEXT'));
      expect(report.problems.any((p) => p.contains('Book.year')), isTrue);
      expect(report.problems.any((p) => p.contains('Book.title')), isTrue);
    });

    test(
      'a non-null property on a nullable column is a warning only',
      () async {
        final db = await source();
        await run(db, _books.replaceFirst('title TEXT NOT NULL', 'title TEXT'));
        final lines = await logged(() async {
          final report = await validate(db, [book]);
          expect(report.isValid, isTrue);
          expect(report.warnings, hasLength(1));
          expect(report.warnings.single, contains('"title"'));
          expect(report.warnings.single, contains('Book.title'));
          expect(report.warnings.single, contains('no default'));
        });
        expect(
          lines.where((l) => l.startsWith('spring.data.jdbc.schema:')),
          hasLength(1),
        );
      },
    );

    test('a default silences the warning', () async {
      final db = await source();
      await run(
        db,
        _books.replaceFirst('title TEXT NOT NULL', "title TEXT DEFAULT ''"),
      );
      expect((await validate(db, [book])).warnings, isEmpty);
    });

    test('validateOrThrow lists every problem in one error', () async {
      final db = await source();
      await run(db, 'CREATE TABLE books (id INTEGER PRIMARY KEY)');
      final error = await failure<SchemaValidationException>(
        () => SchemaValidator(db).validateOrThrow([book]),
      );
      expect(error.problems.length, greaterThan(5));
      expect(error.message, contains('${error.problems.length} problems'));
      for (final problem in error.problems) {
        expect(error.message, contains(problem));
      }
    });
  });

  group('mapped collections', () {
    test('missing child tables are reported with the collection', () async {
      final db = await source();
      await run(db, 'CREATE TABLE order_line (id INTEGER PRIMARY KEY)');
      final report = await validate(db, [orderLine]);
      final text = report.problems.join('\n');
      for (final table in ['item', 'tags', 'note']) {
        expect(text, contains('Missing table "$table"'));
      }
      expect(text, contains('OrderLine.items'));
      expect(text, contains('OrderLine.tags'));
      expect(text, contains('OrderLine.notes'));
    });

    test('missing reverse and key columns are reported', () async {
      final db = await source();
      await run(db, 'CREATE TABLE order_line (id INTEGER PRIMARY KEY)');
      await run(
        db,
        'CREATE TABLE item (id INTEGER PRIMARY KEY, sku TEXT NOT NULL, '
        'qty INTEGER NOT NULL)',
      );
      await run(db, 'CREATE TABLE tags (label TEXT NOT NULL)');
      await run(db, 'CREATE TABLE note (text TEXT NOT NULL)');
      final problems = (await validate(db, [orderLine])).problems;
      bool has(String column, String what) =>
          problems.any((p) => p.contains('"$column"') && p.contains(what));
      expect(has('line_ref', 'OrderLine.items (reverse column)'), isTrue);
      expect(has('position', 'OrderLine.items (key column)'), isTrue);
      expect(has('order_line_id', 'OrderLine.tags (reverse column)'), isTrue);
      expect(has('order_line_id', 'OrderLine.notes (reverse column)'), isTrue);
      expect(has('order_line_key', 'OrderLine.notes (key column)'), isTrue);
    });

    test('a key column of the wrong type is a misfit', () async {
      final db = await source();
      final creator = SchemaCreator(db);
      await creator.create([orderLine]);
      expect((await validate(db, [orderLine])).problems, isEmpty);
      await run(db, 'DROP TABLE note');
      await run(
        db,
        'CREATE TABLE note (text TEXT NOT NULL, order_line_id INTEGER NOT '
        'NULL, order_line_key INTEGER NOT NULL)',
      );
      final problems = (await validate(db, [orderLine])).problems;
      expect(problems, hasLength(1));
      expect(problems.single, contains('OrderLine.notes (key column)'));
      expect(problems.single, contains('expected TEXT'));
    });

    test('the tables a creator wrote validate', () async {
      final db = await source();
      await SchemaCreator(db).create([book, orderLine]);
      final report = await validate(db, [book, orderLine]);
      expect(report.problems, isEmpty);
      expect(report.warnings, isEmpty);
    });
  });
}
