@Tags(['postgres'])
library;

// What the starter does to a PostgreSQL schema, against a real server
// (SPRING_TEST_POSTGRES_URL): creating the tables of the entities, checking
// them (types, foreign keys, unique keys), SQL scripts and migrations, whose
// DDL is transactional there.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../mapping/support.dart';
import '../repository/jdbc/support.dart' show referenceTypes, withJdbc;
import 'support.dart';

Future<T> _using<T>(
  DataSource source,
  Future<T> Function(JdbcConnection connection) action,
) async {
  final connection = await source.getConnection();
  try {
    return await action(connection);
  } finally {
    await source.releaseConnection(connection);
  }
}

Future<void> _run(DataSource source, String sql) =>
    _using(source, (c) => c.execute(sql));

Future<Object?> _value(DataSource source, String sql) =>
    _using(source, (c) => scalar(c, sql));

MigrationRunner _runner(
  DataSource source,
  Map<String, String> files, [
  MigrationSettings settings = const MigrationSettings(),
]) => MigrationRunner(source, settings, source: MapMigrationSource(files));

Future<List<String>> _history(DataSource source) => _using(
  source,
  (c) async => [
    for (final row in (await c.query(
      'SELECT script FROM schema_history ORDER BY installed_rank',
    )).rows)
      row.values.first! as String,
  ],
);

void main() => group('PostgreSQL', _tests, skip: postgresSkip);

void _tests() {
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

  group('the tables of the entities', () {
    test('are created with the column types of the dialect', () async {
      final db = await newPostgresSource();
      await SchemaCreator(db).create([book, orderLine, reading]);
      final columns = await _using(
        db,
        (c) async => {
          for (final row in (await c.query(
            'SELECT column_name, data_type, is_nullable, is_identity '
            "FROM information_schema.columns WHERE table_name = 'books' "
            'AND table_schema = current_schema()',
          )).rows)
            row['column_name']! as String: row.toMap(),
        },
      );
      expect(columns['id']!['data_type'], 'bigint');
      expect(columns['id']!['is_identity'], 'YES');
      expect(columns['title']!['data_type'], 'text');
      expect(columns['title']!['is_nullable'], 'NO');
      expect(columns['price']!['data_type'], 'double precision');
      expect(columns['available']!['data_type'], 'boolean');
      expect(columns['version']!['data_type'], 'bigint');
      expect(columns['created_at']!['data_type'], 'timestamp with time zone');
      expect(columns, isNot(contains('note')));
    });

    test('are created once: a second run changes nothing', () async {
      final db = await newPostgresSource();
      final creator = SchemaCreator(db);
      await creator.create([book, orderLine, reading]);
      await creator.create([book, orderLine, reading]);
      expect(
        await _value(
          db,
          'SELECT count(*) FROM information_schema.tables WHERE '
          "table_schema = current_schema() AND table_name = 'books'",
        ),
        1,
      );
    });

    test('create-drop removes them, referenced ones too', () async {
      final db = await newPostgresSource();
      final creator = SchemaCreator(db);
      await creator.create([book, orderLine]);
      await creator.drop([book, orderLine]);
      expect(
        await _value(
          db,
          'SELECT count(*) FROM information_schema.tables '
          'WHERE table_schema = current_schema()',
        ),
        0,
      );
    });

    test('a schema the entities were created in validates', () async {
      final db = await newPostgresSource();
      await SchemaCreator(db).create([book, orderLine, reading]);
      final report = await SchemaValidator(
        db,
      ).validate([book, orderLine, reading]);
      expect(report.problems, isEmpty);
      expect(report.warnings, isEmpty);
    });

    test('keys of the references, in every direction, are created and '
        'validated', () async {
      await withJdbc(postgres: true, (j) async {
        final entities = [
          for (final type in referenceTypes)
            j.mapping.getRequiredPersistentEntityOfType(type),
        ];
        final report = await SchemaValidator(j.dataSource).validate(entities);
        expect(report.problems, isEmpty);
        // The keys are in the database: the foreign keys, the unique keys.
        final keys = await _using(
          j.dataSource,
          (c) async => (await c.query(
            'SELECT count(*) FROM pg_constraint c JOIN pg_namespace n '
            'ON n.oid = c.connamespace WHERE n.nspname = current_schema() '
            "AND c.contype = 'f'",
          )).rows.single.values.first,
        );
        expect(keys, greaterThan(5));
      });
    });
  });

  group('validation finds what differs', () {
    late PooledDataSource db;

    setUp(() async {
      db = await newPostgresSource();
      await SchemaCreator(db).create([book]);
    });

    Future<SchemaValidationReport> validate() =>
        SchemaValidator(db).validate([book]);

    test('a missing column', () async {
      await _run(db, 'ALTER TABLE books DROP COLUMN year');
      final report = await validate();
      expect(report.isValid, isFalse);
      expect(report.problems.join('\n'), contains('Missing column "year"'));
    });

    test('a column of the wrong type', () async {
      await _run(
        db,
        'ALTER TABLE books ALTER COLUMN title TYPE integer '
        'USING 0',
      );
      expect(
        (await validate()).problems.join('\n'),
        contains('Column "title" in table "books"'),
      );
    });

    test('types that fit are accepted: widths, varchar, numeric', () async {
      await _run(db, 'ALTER TABLE books ALTER COLUMN year TYPE smallint');
      await _run(db, 'ALTER TABLE books ALTER COLUMN title TYPE varchar(100)');
      await _run(db, 'ALTER TABLE books ALTER COLUMN price TYPE numeric(8,2)');
      await _run(
        db,
        'ALTER TABLE books ALTER COLUMN created_at TYPE timestamp',
      );
      expect((await validate()).problems, isEmpty);
    });

    test('a missing table', () async {
      await _run(db, 'DROP TABLE books');
      expect(
        (await validate()).problems.join('\n'),
        contains('Missing table "books"'),
      );
    });

    test(
      'a missing foreign key is a problem, a missing unique key too',
      () async {
        await _run(
          db,
          'ALTER TABLE books DROP CONSTRAINT books_writer_id_fkey',
        );
        final report = await validate();
        expect(
          report.problems.join('\n') + report.warnings.join('\n'),
          contains('foreign key'),
        );
      },
    );
  });

  group('the dialect describes tables', () {
    test('columns, primary keys, foreign keys with their actions, unique '
        'keys', () async {
      final db = await newPostgresSource();
      await _run(db, '''
CREATE TABLE parents (id INT PRIMARY KEY, code TEXT UNIQUE);
CREATE TABLE kids (
  id INT PRIMARY KEY,
  parent INT REFERENCES parents (id) ON DELETE CASCADE,
  other INT REFERENCES parents (id) ON DELETE SET NULL,
  name VARCHAR(40) NOT NULL DEFAULT 'x',
  CONSTRAINT kids_name_key UNIQUE (name, parent)
);
CREATE UNIQUE INDEX kids_partial ON kids (other) WHERE other > 0;
CREATE UNIQUE INDEX kids_lower ON kids (lower(name));
''');
      const dialect = PostgresDialect();
      await _using(db, (c) async {
        final columns = (await dialect.describeTable(c, 'kids'))!;
        expect(
          [for (final column in columns) column.name],
          [
            'id',
            'parent',
            'other',
            'name',
          ],
        );
        final id = columns.first;
        expect((id.type, id.primaryKey, id.notNull), ('integer', true, true));
        final name = columns.last;
        expect(name.type, 'character varying(40)');
        expect(name.notNull, isTrue);
        expect(name.defaultValue, contains("'x'"));
        expect(await dialect.describeTable(c, 'nope'), isEmpty);

        final foreignKeys = (await dialect.describeForeignKeys(c, 'kids'))!;
        expect(
          {
            for (final key in foreignKeys)
              key.column: (key.parentTable, key.parentColumn, key.onDelete),
          },
          {
            'parent': ('parents', 'id', OnDeleteAction.cascade),
            'other': ('parents', 'id', OnDeleteAction.setNull),
          },
        );

        // Partial and expression indexes make nothing unique.
        final uniques = (await dialect.describeUniqueKeys(c, 'kids'))!;
        expect(
          {for (final key in uniques) key.columns.join(',')},
          {'id', 'name,parent'},
        );
        expect(
          [
            for (final key in (await dialect.describeUniqueKeys(c, 'parents'))!)
              key.columns.join(','),
          ],
          unorderedEquals(['id', 'code']),
        );
        expect(await dialect.listTables(c), ['kids', 'parents']);
      });
    });

    test('the schema named is looked in, the current one by default', () async {
      final other = await newSchema();
      final db = await newPostgresSource();
      await _run(db, 'CREATE TABLE "$other".only_there (a INT)');
      await _run(db, 'CREATE TABLE here (a INT)');
      const dialect = PostgresDialect();
      await _using(db, (c) async {
        expect(await dialect.describeTable(c, 'only_there'), isEmpty);
        expect(
          await dialect.describeTable(c, 'only_there', other),
          hasLength(1),
        );
        expect(await dialect.describeTable(c, 'here'), hasLength(1));
        expect(await dialect.listTables(c), ['here']);
      });
    });
  });

  group('SQL scripts', () {
    test('run statement by statement, with dollar quoted bodies', () async {
      final db = await newPostgresSource();
      await _using(db, (c) async {
        final count = await ScriptUtils.executeSqlScript(c, r'''
CREATE TABLE notes (id INT PRIMARY KEY, text TEXT);
CREATE FUNCTION shout(t TEXT) RETURNS TEXT AS $$
  BEGIN RETURN upper(t) || '!'; END;
$$ LANGUAGE plpgsql;
INSERT INTO notes VALUES (1, shout('a;b'));
-- a comment; with a semicolon
INSERT INTO notes VALUES (2, 'it''s');
''');
        expect(count, 4);
        expect(
          [
            for (final row in (await c.query(
              'SELECT text FROM notes ORDER BY id',
            )).rows)
              row['text'],
          ],
          ['A;B!', "it's"],
        );
      });
    });
  });

  group('migrations', () {
    const files = {
      'V1__create_books.sql':
          'CREATE TABLE book (id BIGINT GENERATED BY DEFAULT AS IDENTITY '
          'PRIMARY KEY, title TEXT);',
      'V2__add_year.sql': 'ALTER TABLE book ADD COLUMN year INTEGER;',
      'V3__first_book.sql':
          "INSERT INTO book (title, year) VALUES ('Dune', 1965);",
    };

    test('apply the files in order and record them', () async {
      final db = await newPostgresSource();
      final result = await _runner(db, files).migrate();
      expect(result.count, 3);
      expect(result.currentVersion.toString(), '3');
      expect(await _value(db, 'SELECT title FROM book'), 'Dune');
      expect(await _history(db), files.keys.toList());
      // A second run has nothing to do.
      expect((await _runner(db, files).migrate()).count, 0);
    });

    test('the history table keeps typed columns', () async {
      final db = await newPostgresSource();
      await _runner(db, {'V1__create_books.sql': files.values.first}).migrate();
      final row = await _using(
        db,
        (c) async =>
            (await c.query('SELECT * FROM schema_history')).rows.single,
      );
      expect(row['installed_rank'], 1);
      expect(row['version'], '1');
      expect(row['type'], 'SQL');
      expect(row['checksum'], isA<int>());
      expect(row['installed_on'], isA<DateTime>());
      expect((row['installed_on']! as DateTime).isUtc, isTrue);
      expect(row['success'], isTrue);
    });

    test(
      'a failing migration leaves nothing of itself, DDL included',
      () async {
        final db = await newPostgresSource();
        await expectLater(
          _runner(db, {
            'V1__create_books.sql': files.values.first,
            'V2__broken.sql':
                'CREATE TABLE half (a INT); INSERT INTO nope VALUES (1);',
          }).migrate(),
          throwsA(isA<MigrationException>()),
        );
        expect(await _history(db), ['V1__create_books.sql']);
        expect(
          await _value(db, "SELECT to_regclass('half')::text"),
          isNull,
          reason: 'the transaction took the half-made table with it',
        );
        // The database is at version 1 and goes on from there.
        final fixed = await _runner(db, {
          'V1__create_books.sql': files.values.first,
          'V2__broken.sql': 'CREATE TABLE half (a INT);',
        }).migrate();
        expect(fixed.count, 1);
      },
    );

    test('two runners at once: one applies, the other waits and finds '
        'nothing to do', () async {
      final db = await newPostgresSource(maxSize: 2);
      final results = await Future.wait([
        _runner(db, files).migrate(),
        _runner(db, files).migrate(),
      ]);
      expect(results.map((r) => r.count).toList()..sort(), [0, 3]);
      expect(await _history(db), files.keys.toList());
    });

    test('an existing database is baselined on request', () async {
      final db = await newPostgresSource();
      await _run(db, 'CREATE TABLE legacy (a INT)');
      await expectLater(
        _runner(db, files).migrate(),
        throwsA(isA<MigrationException>()),
      );
      final result = await _runner(
        db,
        {'V2__add.sql': 'ALTER TABLE legacy ADD COLUMN b INT;'},
        const MigrationSettings(baselineOnMigrate: true),
      ).migrate();
      expect(result.baselined, isTrue);
      expect(result.count, 1);
    });
  });
}
