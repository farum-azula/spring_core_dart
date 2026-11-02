import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../mapping/support.dart';
import 'support.dart';

// Book.author references authors: both tables, with the foreign key.
const _books =
    'CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT NOT NULL);\n'
    'CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT NOT NULL, '
    'year INTEGER, genre TEXT, price REAL NOT NULL, available INTEGER NOT '
    'NULL, writer_id INTEGER REFERENCES authors (id), version INTEGER NOT '
    'NULL, created_at TEXT, modified_at TEXT, created_by TEXT, modified_by '
    'TEXT)';

/// A data source that cannot connect the first [failures] times.
class FlakyDataSource extends DriverDataSource {
  FlakyDataSource(DataSource real, this.failures)
    : _real = real,
      super(
        name: 'flaky',
        driver: real.driver,
        settings: real.settings,
      );

  final DataSource _real;
  int failures;
  int attempts = 0;

  @override
  Future<JdbcConnection> getConnection() {
    attempts++;
    if (failures > 0) {
      failures--;
      throw CannotGetJdbcConnectionException('the database is starting');
    }
    return _real.getConnection();
  }

  @override
  Future<void> releaseConnection(JdbcConnection connection) =>
      _real.releaseConnection(connection);
}

Environment envOf(Map<String, Object?> properties) =>
    StandardEnvironment(systemEnvironment: const {})
      ..propertySources.addFirst(MapPropertySource('test', properties));

void main() {
  late RelationalMappingContext context;
  late PersistentEntity<Book> book;
  late PersistentEntity<OrderLine> orderLine;

  setUp(() {
    context = testContext();
    book = context.getRequiredPersistentEntity<Book>();
    orderLine = context.getRequiredPersistentEntity<OrderLine>();
  });

  DatabaseInitializer initializer(
    DataSource db, {
    DatabaseInitSettings settings = const DatabaseInitSettings(),
    List<PersistentEntity<Object>> entities = const [],
    Map<String, String>? migrations,
    Future<void> Function(Duration)? sleep,
  }) => DatabaseInitializer(
    db,
    settings: settings,
    entities: entities,
    migrationSource: migrations == null ? null : MapMigrationSource(migrations),
    sleep: sleep,
  );

  group('the order', () {
    test('migrations, then validation of the entities', () async {
      final db = await memorySource();
      final init = initializer(
        db,
        entities: [book],
        migrations: {'V1__create_books.sql': _books},
      );
      await init.initialize();
      expect(init.migrationResult!.count, 1);
      expect(await tablesOf(db), ['authors', 'books', 'schema_history']);
    });

    test('validation fails when the migrations leave a gap', () async {
      final db = await memorySource();
      final error = await failure<SchemaValidationException>(
        () => initializer(
          db,
          entities: [book],
          migrations: {
            'V1__create_books.sql':
                'CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT)',
          },
        ).initialize(),
      );
      expect(error.problems.any((p) => p.contains('Book.price')), isTrue);
    });

    test('validate is the default: an empty database fails', () async {
      final db = await memorySource();
      await expectLater(
        initializer(db, entities: [book]).initialize(),
        throwsA(isA<SchemaValidationException>()),
      );
    });

    test('schema=none skips the validation', () async {
      final db = await memorySource();
      await initializer(
        db,
        settings: const DatabaseInitSettings(schema: SchemaMode.none),
        entities: [book],
      ).initialize();
      expect(await tablesOf(db), isEmpty);
    });

    test('SQL scripts run before the validation', () async {
      classpath({'schema.sql': _books});
      final db = await memorySource();
      await initializer(db, entities: [book]).initialize();
      expect(await tablesOf(db), ['authors', 'books']);
    });

    test(
      'create runs after the migrations step and before validation',
      () async {
        classpath({});
        final db = await memorySource();
        await initializer(
          db,
          settings: const DatabaseInitSettings(schema: SchemaMode.create),
          entities: [book, orderLine],
        ).initialize();
        expect(await tablesOf(db), hasLength(6));
      },
    );

    test(
      'works without entities and without the application (migrate only)',
      () async {
        final db = await memorySource();
        final init = initializer(
          db,
          migrations: {'V1__create_books.sql': _books},
        );
        await init.initialize();
        expect(init.migrationResult!.count, 1);
        await init.close();
        expect(await tablesOf(db), ['authors', 'books', 'schema_history']);
      },
    );

    test('initialize is idempotent', () async {
      final db = await memorySource();
      final init = initializer(
        db,
        entities: [book],
        migrations: {'V1__create_books.sql': _books},
      );
      final lines = await logged(() async {
        await init.initialize();
        await init.initialize();
        await Future.wait([init.initialize(), init.initialize()]);
      });
      expect(lines.where((l) => l.contains('Migrating schema')), hasLength(1));
      expect(
        lines.where((l) => l.contains('Schema is up to date')),
        isEmpty,
      );
    });

    test('a failed initialize can be tried again', () async {
      final db = await memorySource();
      final files = {'V1__create_books.sql': 'BROKEN;'};
      final init = initializer(db, migrations: files);
      await expectLater(init.initialize(), throwsA(isA<MigrationException>()));
      files['V1__create_books.sql'] = _books;
      await init.initialize();
      expect(await tablesOf(db), contains('books'));
    });
  });

  group('create-drop', () {
    test('close drops what initialize created', () async {
      final db = await memorySource();
      final init = initializer(
        db,
        settings: const DatabaseInitSettings(schema: SchemaMode.createDrop),
        entities: [book, orderLine],
      );
      await init.initialize();
      expect(await tablesOf(db), hasLength(6));
      await init.close();
      expect(await tablesOf(db), isEmpty);
      // A second close does nothing.
      await init.close();
    });

    test('create keeps the tables at close', () async {
      final db = await memorySource();
      final init = initializer(
        db,
        settings: const DatabaseInitSettings(schema: SchemaMode.create),
        entities: [book],
      );
      await init.initialize();
      await init.close();
      expect(await tablesOf(db), ['authors', 'books']);
    });

    test('close before initialize drops nothing', () async {
      final db = await memorySource();
      await run(db, _books);
      final init = initializer(
        db,
        settings: const DatabaseInitSettings(schema: SchemaMode.createDrop),
        entities: [book],
      );
      await init.close();
      expect(await tablesOf(db), ['authors', 'books']);
    });
  });

  group('one owner of the schema', () {
    const create = DatabaseInitSettings(schema: SchemaMode.create);
    const createDrop = DatabaseInitSettings(schema: SchemaMode.createDrop);

    test('create with migration files is refused', () async {
      final db = await memorySource();
      for (final settings in [create, createDrop]) {
        final error = await failure<SchemaException>(
          () => initializer(
            db,
            settings: settings,
            entities: [book],
            migrations: {'V1__a.sql': 'CREATE TABLE a (x);'},
          ).initialize(),
        );
        expect(error.message, contains('migrations'));
        expect(error.message, contains('spring.data.jdbc.schema='));
      }
      expect(await tablesOf(db), isEmpty);
    });

    test('create with sql.init scripts to run is refused', () async {
      classpath({'schema.sql': 'CREATE TABLE a (x);'});
      final db = await memorySource();
      final error = await failure<SchemaException>(
        () => initializer(db, settings: create, entities: [book]).initialize(),
      );
      expect(error.message, contains('spring.sql.init'));
      expect(await tablesOf(db), isEmpty);
    });

    test('scripts that would not run (mode never) do not count', () async {
      classpath({'schema.sql': 'CREATE TABLE a (x);'});
      final db = await memorySource();
      await initializer(
        db,
        settings: const DatabaseInitSettings(
          sqlInit: SqlInitSettings(mode: SqlInitMode.never),
          schema: SchemaMode.create,
        ),
        entities: [book],
      ).initialize();
      expect(await tablesOf(db), ['authors', 'books']);
    });

    test(
      'scripts that are not embedded-only do not count on a file database',
      () async {
        classpath({'schema.sql': 'CREATE TABLE a (x);'});
        final dir = newTemp();
        addTearDown(() => deleteTemp(dir));
        final db = await fileSource(dir, 'a.db');
        await initializer(db, settings: create, entities: [book]).initialize();
        expect(await tablesOf(db), ['authors', 'books']);
      },
    );

    test('disabled migrations do not count', () async {
      final db = await memorySource();
      await initializer(
        db,
        settings: const DatabaseInitSettings(
          migration: MigrationSettings(enabled: false),
          schema: SchemaMode.create,
        ),
        entities: [book],
        migrations: {'V1__a.sql': 'CREATE TABLE a (x);'},
      ).initialize();
      expect(await tablesOf(db), ['authors', 'books']);
    });

    test('a location without files does not count', () async {
      classpath({});
      final db = await memorySource();
      await initializer(db, settings: create, entities: [book]).initialize();
      expect(await tablesOf(db), ['authors', 'books']);
    });

    test('migrations and sql.init scripts together are refused', () async {
      classpath({'data.sql': 'SELECT 1;'});
      final db = await memorySource();
      final error = await failure<SchemaException>(
        () => initializer(
          db,
          migrations: {'V1__a.sql': 'CREATE TABLE a (x);'},
        ).initialize(),
      );
      expect(error.message, contains('two owners'));
      expect(error.message, contains('data.sql'));
      expect(await tablesOf(db), isEmpty);
    });
  });

  group('connect retries', () {
    Future<DataSource> real() => memorySource();

    test('a database that is not up yet is retried', () async {
      final flaky = FlakyDataSource(await real(), 2);
      final waits = <Duration>[];
      await initializer(
        flaky,
        settings: const DatabaseInitSettings(
          migration: MigrationSettings(
            connectRetries: 3,
            connectRetriesInterval: Duration(seconds: 7),
          ),
        ),
        migrations: {'V1__a.sql': 'CREATE TABLE a (x);'},
        sleep: (d) async => waits.add(d),
      ).initialize();
      expect(waits, [const Duration(seconds: 7), const Duration(seconds: 7)]);
      expect(await tablesOf(flaky), contains('a'));
    });

    test('the last failure is thrown when the retries run out', () async {
      final flaky = FlakyDataSource(await real(), 10);
      final waits = <Duration>[];
      final error = await failure<CannotGetJdbcConnectionException>(
        () => initializer(
          flaky,
          settings: const DatabaseInitSettings(
            migration: MigrationSettings(connectRetries: 2),
          ),
          sleep: (d) async => waits.add(d),
        ).initialize(),
      );
      expect(error.message, contains('starting'));
      expect(flaky.attempts, 3);
      expect(waits, hasLength(2));
    });

    test('by default there is no retry', () async {
      final flaky = FlakyDataSource(await real(), 1);
      await expectLater(
        initializer(flaky).initialize(),
        throwsA(isA<CannotGetJdbcConnectionException>()),
      );
      expect(flaky.attempts, 1);
    });
  });

  group('from the environment', () {
    test('the default data source: spring.*', () {
      final settings = DatabaseInitSettings.fromEnvironment(
        envOf({
          'spring.data.jdbc.schema': 'create-drop',
          'spring.sql.init.mode': 'never',
          'spring.sql.migration.table': 'hist',
        }),
      );
      expect(settings.schema, SchemaMode.createDrop);
      expect(settings.sqlInit.mode, SqlInitMode.never);
      expect(settings.migration.table, 'hist');
    });

    test('a named data source: spring.datasources.<name>.*', () {
      final env = envOf({
        'spring.datasources.audit.data.jdbc.schema': 'none',
        'spring.datasources.audit.sql.migration.locations':
            'resources:db/audit',
        'spring.data.jdbc.schema': 'create',
      });
      final audit = DatabaseInitSettings.fromEnvironment(
        env,
        'spring.datasources.audit.',
      );
      expect(audit.schema, SchemaMode.none);
      expect(audit.migration.locations, ['resources:db/audit']);
      expect(
        DatabaseInitSettings.fromEnvironment(env).schema,
        SchemaMode.create,
      );
    });

    test('the default schema mode is validate; a wrong one is refused', () {
      expect(
        DatabaseInitSettings.fromEnvironment(envOf(const {})).schema,
        SchemaMode.validate,
      );
      expect(
        () => DatabaseInitSettings.fromEnvironment(
          envOf({'spring.data.jdbc.schema': 'update'}),
        ),
        throwsA(
          isA<SchemaException>().having(
            (e) => e.message,
            'message',
            contains('create-drop'),
          ),
        ),
      );
    });

    test('an initializer built from an environment does the work', () async {
      classpath({});
      final db = await memorySource();
      final init = DatabaseInitializer.fromEnvironment(
        db,
        envOf({'spring.data.jdbc.schema': 'create'}),
        entities: [book],
      );
      await init.initialize();
      expect(await tablesOf(db), ['authors', 'books']);
    });
  });
}
