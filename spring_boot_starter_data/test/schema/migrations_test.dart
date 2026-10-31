import 'dart:io';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

const _v1 = 'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT);';
const _v2 = 'ALTER TABLE book ADD COLUMN year INTEGER;';
const _v3 = "INSERT INTO book (title, year) VALUES ('Dune', 1965);";

const Map<String, String> _files = {
  'V1__create_books.sql': _v1,
  'V2__add_year.sql': _v2,
  'V3__first_book.sql': _v3,
};

MigrationRunner runnerOf(
  DataSource db,
  Map<String, String> files, [
  MigrationSettings settings = const MigrationSettings(),
]) => MigrationRunner(db, settings, source: MapMigrationSource(files));

Future<List<String>> history(DataSource db) async => [
  for (final row in await rowsOf(
    db,
    'SELECT script FROM schema_history ORDER BY installed_rank',
  ))
    row.first! as String,
];

Future<MigrationVersion?> versionOf(DataSource db) async =>
    (await runnerOf(db, const {}).migrate()).currentVersion;

void main() {
  group('a run', () {
    test('applies the files in order and records them', () async {
      final db = await memorySource();
      final lines = await logged(() async {
        final result = await runnerOf(db, _files).migrate();
        expect(result.count, 3);
        expect(result.currentVersion.toString(), '3');
        expect(result.baselined, isFalse);
      });
      expect(await value(db, 'SELECT title FROM book'), 'Dune');
      expect(await history(db), _files.keys.toList());
      expect(
        lines,
        containsAllInOrder([
          'spring.sql.migration: Migrating schema to version 1 - create books',
          'spring.sql.migration: Migrating schema to version 2 - add year',
          'spring.sql.migration: Migrating schema to version 3 - first book',
          matches(
            r'spring\.sql\.migration: Successfully applied 3 migrations to '
            r'schema, now at version v3 \(execution time \d\d:\d\d\.\d{3}s\)',
          ),
        ]),
      );
    });

    test('the history table has the columns of Flyway', () async {
      final db = await memorySource();
      await runnerOf(db, {'V1__create_books.sql': _v1}).migrate();
      final rows = await using(
        db,
        (c) async => (await c.query(
          'SELECT * FROM schema_history',
        )).rows.single.toMap(),
      );
      expect(rows.keys, [
        'installed_rank',
        'version',
        'description',
        'type',
        'script',
        'checksum',
        'installed_by',
        'installed_on',
        'execution_time',
        'success',
      ]);
      expect(rows['installed_rank'], 1);
      expect(rows['version'], '1');
      expect(rows['description'], 'create books');
      expect(rows['type'], 'SQL');
      expect(rows['script'], 'V1__create_books.sql');
      expect(rows['checksum'], MigrationRunnerChecksum.of(_v1));
      expect(rows['installed_by'], isNotEmpty);
      expect(DateTime.parse(rows['installed_on']! as String).isUtc, isTrue);
      expect(rows['execution_time'], isA<int>());
      expect(rows['success'], 1);
    });

    test('a second run has nothing to do', () async {
      final db = await memorySource();
      await runnerOf(db, _files).migrate();
      final lines = await logged(() async {
        final result = await runnerOf(db, _files).migrate();
        expect(result.count, 0);
        expect(result.currentVersion.toString(), '3');
      });
      expect(lines, [
        'spring.sql.migration: Schema is up to date. No migration necessary.',
      ]);
      expect(await history(db), hasLength(3));
    });

    test('a new migration is applied on the next run', () async {
      final db = await memorySource();
      await runnerOf(db, {'V1__create_books.sql': _v1}).migrate();
      final result = await runnerOf(db, _files).migrate();
      expect(result.applied.map((m) => m.script), [
        'V2__add_year.sql',
        'V3__first_book.sql',
      ]);
      expect(await history(db), _files.keys.toList());
    });

    test('versions are compared number by number', () async {
      final db = await memorySource();
      final result = await runnerOf(db, {
        'V1.10__ten.sql': 'CREATE TABLE t110 (x);',
        'V1.9__nine.sql': 'CREATE TABLE t19 (x);',
        'V1_1__one.sql': 'CREATE TABLE t11 (x);',
        'V2__two.sql': 'CREATE TABLE t2 (x);',
        'V10__ten.sql': 'CREATE TABLE t10 (x);',
      }).migrate();
      expect(result.applied.map((m) => m.version.toString()), [
        '1.1',
        '1.9',
        '1.10',
        '2',
        '10',
      ]);
      expect(result.currentVersion.toString(), '10');
    });

    test('the same version twice is refused', () async {
      final db = await memorySource();
      final error = await failure<MigrationException>(
        () => runnerOf(db, {
          'V1__a.sql': 'SELECT 1;',
          'V1.0__b.sql': 'SELECT 1;',
        }).migrate(),
      );
      expect(error.message, contains('V1__a.sql'));
      expect(error.message, contains('V1.0__b.sql'));
    });

    test('a file that is no migration name is refused, naming it', () async {
      final db = await memorySource();
      for (final name in ['V1_create.sql', 'create.sql', 'Vx__a.sql']) {
        final error = await failure<MigrationException>(
          () => runnerOf(db, {name: 'SELECT 1;'}).migrate(),
        );
        expect(error.message, contains(name));
        expect(error.script, name);
      }
    });

    test('no files, or disabled: nothing happens, no history table', () async {
      final db = await memorySource();
      expect((await runnerOf(db, const {}).migrate()).count, 0);
      expect(
        (await runnerOf(
          db,
          _files,
          const MigrationSettings(enabled: false),
        ).migrate()).count,
        0,
      );
      expect(await tablesOf(db), isEmpty);
      expect(await runnerOf(db, const {}).hasMigrations(), isFalse);
      expect(await runnerOf(db, _files).hasMigrations(), isTrue);
    });

    test('the history table can have another name', () async {
      final db = await memorySource();
      await runnerOf(
        db,
        {'V1__a.sql': 'CREATE TABLE a (x);'},
        const MigrationSettings(table: 'my_history'),
      ).migrate();
      expect(await tablesOf(db), ['a', 'my_history']);
    });
  });

  group('repeatable migrations', () {
    test('run after the versioned ones, again when changed', () async {
      final db = await memorySource();
      var view = 'CREATE VIEW titles AS SELECT title FROM book;';
      Map<String, String> files() => {
        // Sorts before V1 by name, but runs after it.
        'R__titles_view.sql': 'DROP VIEW IF EXISTS titles;\n$view',
        ..._files,
      };
      var result = await runnerOf(db, files()).migrate();
      expect(result.applied.map((m) => m.script), [
        'V1__create_books.sql',
        'V2__add_year.sql',
        'V3__first_book.sql',
        'R__titles_view.sql',
      ]);
      expect(await value(db, 'SELECT title FROM titles'), 'Dune');

      result = await runnerOf(db, files()).migrate();
      expect(result.count, 0);

      view = 'CREATE VIEW titles AS SELECT upper(title) AS title FROM book;';
      result = await runnerOf(db, files()).migrate();
      expect(result.applied.map((m) => m.script), ['R__titles_view.sql']);
      expect(await value(db, 'SELECT title FROM titles'), 'DUNE');
      expect(await history(db), [
        ..._files.keys,
        'R__titles_view.sql',
        'R__titles_view.sql',
      ]);
      expect(
        await value(
          db,
          "SELECT version FROM schema_history WHERE type = 'SQL' "
          "AND script LIKE 'R__%' LIMIT 1",
        ),
        isNull,
      );
    });

    test('a repeatable migration runs after a new versioned one', () async {
      final db = await memorySource();
      await runnerOf(db, {
        'V1__create_books.sql': _v1,
        'R__count.sql': 'CREATE TABLE IF NOT EXISTS c (x);',
      }).migrate();
      final result = await runnerOf(db, {
        'V1__create_books.sql': _v1,
        'V2__year.sql': _v2,
        'R__count.sql': 'CREATE TABLE IF NOT EXISTS c (x); -- changed',
      }).migrate();
      expect(result.applied.map((m) => m.script), [
        'V2__year.sql',
        'R__count.sql',
      ]);
    });
  });

  group('validation', () {
    test('a changed applied file stops the start, naming it', () async {
      final db = await memorySource();
      await runnerOf(db, _files).migrate();
      final error = await failure<MigrationException>(
        () => runnerOf(db, {
          ..._files,
          'V2__add_year.sql': '$_v2 -- edited',
        }).migrate(),
      );
      expect(error.message, contains('V2__add_year.sql'));
      expect(error.message, contains('checksum'));
      expect(error.script, 'V2__add_year.sql');
    });

    test('validate-on-migrate=false lets it pass', () async {
      final db = await memorySource();
      await runnerOf(db, _files).migrate();
      final result = await runnerOf(
        db,
        {..._files, 'V2__add_year.sql': '$_v2 -- edited'},
        const MigrationSettings(validateOnMigrate: false),
      ).migrate();
      expect(result.count, 0);
    });

    test('line endings and a trailing newline do not change the checksum', () {
      expect(
        ResolvedMigration.checksumOf('a\r\nb\r\n'),
        ResolvedMigration.checksumOf('a\nb'),
      );
      expect(
        ResolvedMigration.checksumOf('\uFEFFa\rb'),
        ResolvedMigration.checksumOf('a\nb\n'),
      );
      expect(
        ResolvedMigration.checksumOf('ab'),
        isNot(ResolvedMigration.checksumOf('a\nb')),
      );
      // CRC32 of "123456789" is 0xCBF43926.
      expect(ResolvedMigration.checksumOf('123456789'), 0xCBF43926);
    });

    test(
      'a file that was edited only in line endings still validates',
      () async {
        final db = await memorySource();
        await runnerOf(db, {
          'V1__a.sql': 'CREATE TABLE a (x);\nSELECT 1;\n',
        }).migrate();
        final result = await runnerOf(db, {
          'V1__a.sql': 'CREATE TABLE a (x);\r\nSELECT 1;\r\n',
        }).migrate();
        expect(result.count, 0);
      },
    );

    test(
      'an applied migration missing from the files stops the start',
      () async {
        final db = await memorySource();
        await runnerOf(db, _files).migrate();
        // V2 is gone, V3 is still there: V2 is missing, not future.
        final error = await failure<MigrationException>(
          () => runnerOf(db, {
            'V1__create_books.sql': _v1,
            'V3__first_book.sql': _v3,
          }).migrate(),
        );
        expect(error.message, contains('V2__add_year.sql'));
        expect(error.message, contains('missing'));
      },
    );

    test('a missing applied migration passes with *:missing', () async {
      final db = await memorySource();
      await runnerOf(db, _files).migrate();
      final result = await runnerOf(
        db,
        {'V1__create_books.sql': _v1, 'V3__first_book.sql': _v3},
        const MigrationSettings(ignoreMigrationPatterns: ['versioned:missing']),
      ).migrate();
      expect(result.count, 0);
    });

    test(
      'applied versions newer than the files are ignored by default',
      () async {
        final db = await memorySource();
        await runnerOf(db, _files).migrate();
        // An older build of the application: it knows only V1.
        final result = await runnerOf(db, {
          'V1__create_books.sql': _v1,
        }).migrate();
        expect(result.count, 0);
        expect(result.currentVersion.toString(), '3');
      },
    );

    test('they stop the start when the default pattern is replaced', () async {
      final db = await memorySource();
      await runnerOf(db, _files).migrate();
      final error = await failure<MigrationException>(
        () => runnerOf(
          db,
          {'V1__create_books.sql': _v1},
          const MigrationSettings(ignoreMigrationPatterns: ['repeatable:*']),
        ).migrate(),
      );
      expect(error.message, contains('V2__add_year.sql'));
      expect(error.message, contains('newer than every file'));
    });

    test('a wrong pattern is refused', () async {
      final db = await memorySource();
      await expectLater(
        runnerOf(
          db,
          _files,
          const MigrationSettings(ignoreMigrationPatterns: ['future']),
        ).migrate(),
        throwsA(isA<MigrationException>()),
      );
      await expectLater(
        runnerOf(
          db,
          _files,
          const MigrationSettings(ignoreMigrationPatterns: ['x:y']),
        ).migrate(),
        throwsA(isA<MigrationException>()),
      );
    });

    test('a removed repeatable migration is reported as missing', () async {
      final db = await memorySource();
      await runnerOf(db, {'V1__a.sql': _v1, 'R__x.sql': 'SELECT 1;'}).migrate();
      final error = await failure<MigrationException>(
        () => runnerOf(db, {'V1__a.sql': _v1}).migrate(),
      );
      expect(error.message, contains('R__x.sql'));
    });
  });

  group('out of order', () {
    Future<DataSource> atV3() async {
      final db = await memorySource();
      await runnerOf(db, {
        'V1__a.sql': 'CREATE TABLE a (x);',
        'V3__c.sql': 'CREATE TABLE c (x);',
      }).migrate();
      return db;
    }

    const withV2 = {
      'V1__a.sql': 'CREATE TABLE a (x);',
      'V2__b.sql': 'CREATE TABLE b (x);',
      'V3__c.sql': 'CREATE TABLE c (x);',
    };

    test('a file below the latest applied version stops the start', () async {
      final db = await atV3();
      final error = await failure<MigrationException>(
        () => runnerOf(db, withV2).migrate(),
      );
      expect(error.message, contains('V2__b.sql'));
      expect(error.message, contains('out-of-order'));
      expect(await tablesOf(db), isNot(contains('b')));
    });

    test('out-of-order=true applies it', () async {
      final db = await atV3();
      final result = await runnerOf(
        db,
        withV2,
        const MigrationSettings(outOfOrder: true),
      ).migrate();
      expect(result.applied.map((m) => m.script), ['V2__b.sql']);
      expect(await tablesOf(db), contains('b'));
      expect(await history(db), [
        'V1__a.sql',
        'V3__c.sql',
        'V2__b.sql',
      ]);
    });

    test('without validation it is skipped with a warning', () async {
      final db = await atV3();
      final lines = await logged(() async {
        final result = await runnerOf(
          db,
          withV2,
          const MigrationSettings(validateOnMigrate: false),
        ).migrate();
        expect(result.count, 0);
      });
      expect(
        lines.any((l) => l.contains('Skipping the migration V2__b')),
        isTrue,
      );
    });
  });

  group('baseline', () {
    Future<DataSource> existing({bool withYear = false}) async {
      final db = await memorySource();
      await run(db, _v1);
      if (withYear) {
        await run(db, _v2);
      }
      return db;
    }

    test('an existing database without history stops the start', () async {
      final db = await existing();
      final error = await failure<MigrationException>(
        () => runnerOf(db, _files).migrate(),
      );
      expect(error.message, contains('baseline-on-migrate'));
      expect(await tablesOf(db), ['book']);
    });

    test('baseline-on-migrate takes it as version 1 and goes on', () async {
      final db = await existing();
      final result = await runnerOf(
        db,
        _files,
        const MigrationSettings(baselineOnMigrate: true),
      ).migrate();
      expect(result.baselined, isTrue);
      // V1 is the baseline: only V2 and V3 ran.
      expect(result.applied.map((m) => m.script), [
        'V2__add_year.sql',
        'V3__first_book.sql',
      ]);
      expect(await value(db, 'SELECT title FROM book'), 'Dune');
      expect(
        await rowsOf(
          db,
          'SELECT installed_rank, version, description, type '
          'FROM schema_history ORDER BY installed_rank',
        ),
        [
          [1, '1', '<< Baseline >>', 'BASELINE'],
          [2, '2', 'add year', 'SQL'],
          [3, '3', 'first book', 'SQL'],
        ],
      );
    });

    test(
      'baseline-version and description are used; next run is a no-op',
      () async {
        final db = await existing(withYear: true);
        const settings = MigrationSettings(
          baselineOnMigrate: true,
          baselineVersion: '2',
          baselineDescription: 'existing',
        );
        final result = await runnerOf(db, _files, settings).migrate();
        expect(result.applied.map((m) => m.script), ['V3__first_book.sql']);
        expect(
          await value(
            db,
            "SELECT description FROM schema_history WHERE type = 'BASELINE'",
          ),
          'existing',
        );
        expect((await runnerOf(db, _files, settings).migrate()).count, 0);
      },
    );

    test('an empty database is not baselined', () async {
      final db = await memorySource();
      final result = await runnerOf(
        db,
        _files,
        const MigrationSettings(baselineOnMigrate: true),
      ).migrate();
      expect(result.baselined, isFalse);
      expect(result.count, 3);
    });
  });

  group('target', () {
    test('stops at the given version', () async {
      final db = await memorySource();
      final result = await runnerOf(
        db,
        {..._files, 'R__x.sql': 'CREATE TABLE IF NOT EXISTS x (a);'},
        const MigrationSettings(target: '2'),
      ).migrate();
      expect(result.applied.map((m) => m.script), [
        'V1__create_books.sql',
        'V2__add_year.sql',
      ]);
      expect(result.currentVersion.toString(), '2');
      // Repeatable migrations wait for the latest.
      expect(await tablesOf(db), isNot(contains('x')));
      final rest = await runnerOf(db, {
        ..._files,
        'R__x.sql': 'CREATE TABLE IF NOT EXISTS x (a);',
      }).migrate();
      expect(rest.applied.map((m) => m.script), [
        'V3__first_book.sql',
        'R__x.sql',
      ]);
    });

    test('latest is the default and a wrong target is refused', () async {
      final db = await memorySource();
      expect(
        (await runnerOf(db, _files).migrate()).count,
        3,
      );
      await expectLater(
        runnerOf(
          db,
          _files,
          const MigrationSettings(target: 'newest'),
        ).migrate(),
        throwsA(isA<MigrationException>()),
      );
    });
  });

  group('placeholders', () {
    test(
      'are replaced from the settings, the checksum is of the file',
      () async {
        final db = await memorySource();
        const sql =
            r'CREATE TABLE ${prefix}_item (id INTEGER, '
            r"kind TEXT DEFAULT '${kind}');";
        const settings = MigrationSettings(
          placeholders: {'prefix': 'shop', 'kind': 'book'},
        );
        await runnerOf(db, {'V1__a.sql': sql}, settings).migrate();
        expect(await tablesOf(db), ['schema_history', 'shop_item']);
        expect(
          await value(db, 'SELECT checksum FROM schema_history'),
          ResolvedMigration.checksumOf(sql),
        );
        // A changed placeholder value is not a changed migration.
        final again = await runnerOf(
          db,
          {'V1__a.sql': sql},
          const MigrationSettings(
            placeholders: {'prefix': 'other', 'kind': 'x'},
          ),
        ).migrate();
        expect(again.count, 0);
      },
    );

    test('an unknown placeholder fails, naming the file', () async {
      final db = await memorySource();
      final error = await failure<MigrationException>(
        () => runnerOf(db, {
          'V1__a.sql': 'SELECT 1;',
          'V2__b.sql': r'CREATE TABLE ${missing} (x);',
        }).migrate(),
      );
      expect(error.message, contains('V2__b.sql'));
      expect(error.message, contains(r'${missing}'));
      expect(error.message, contains('placeholders.missing'));
      // V1 is applied, V2 is not.
      expect(await history(db), ['V1__a.sql']);
    });

    test('prefix and suffix can be changed', () async {
      final db = await memorySource();
      await runnerOf(
        db,
        {'V1__a.sql': 'CREATE TABLE <<name>> (x);'},
        const MigrationSettings(
          placeholders: {'name': 'custom'},
          placeholderPrefix: '<<',
          placeholderSuffix: '>>',
        ),
      ).migrate();
      expect(await tablesOf(db), contains('custom'));
    });

    test('replacement can be turned off', () async {
      final db = await memorySource();
      await runnerOf(
        db,
        {'V1__a.sql': r"CREATE TABLE a (x TEXT DEFAULT '${raw}');"},
        const MigrationSettings(placeholderReplacement: false),
      ).migrate();
      expect(await tablesOf(db), contains('a'));
    });
  });

  group('failures', () {
    const failing = {
      'V1__create_books.sql': _v1,
      'V2__bad.sql':
          'CREATE TABLE half (x INTEGER);\n'
          'INSERT INTO half VALUES (1);\n'
          '\n'
          'INSERT INTO nowhere VALUES (2);\n',
    };

    test('a failed migration is rolled back and not recorded', () async {
      final db = await memorySource();
      final error = await failure<MigrationException>(
        () => runnerOf(db, failing).migrate(),
      );
      expect(error.script, 'V2__bad.sql');
      expect(error.message, contains('V2__bad.sql'));
      expect(error.message, contains('statement #3'));
      expect(error.message, contains('line 4'));
      expect(error.message, contains('no such table'));
      // The database is at the previous version.
      expect(await history(db), ['V1__create_books.sql']);
      expect(await tablesOf(db), ['book', 'schema_history']);
      expect(await value(db, 'SELECT count(*) FROM schema_history'), 1);
    });

    test('after a fix the migration runs', () async {
      final db = await memorySource();
      await expectLater(
        runnerOf(db, failing).migrate(),
        throwsA(isA<MigrationException>()),
      );
      final result = await runnerOf(db, {
        ...failing,
        'V2__bad.sql': 'CREATE TABLE half (x INTEGER);',
      }).migrate();
      expect(result.applied.map((m) => m.script), ['V2__bad.sql']);
      expect(await history(db), ['V1__create_books.sql', 'V2__bad.sql']);
    });

    test('the log does not hold the statement', () async {
      final db = await memorySource();
      final lines = await logged(() async {
        await expectLater(
          runnerOf(db, {
            'V1__a.sql': "INSERT INTO nowhere VALUES ('secret-value');",
          }).migrate(),
          throwsA(isA<MigrationException>()),
        );
      });
      expect(lines.join('\n'), isNot(contains('secret-value')));
    });

    test('group: all pending migrations are one transaction', () async {
      final db = await memorySource();
      final error = await failure<MigrationException>(
        () => runnerOf(
          db,
          failing,
          const MigrationSettings(group: true),
        ).migrate(),
      );
      expect(error.script, 'V2__bad.sql');
      // V1 ran in the same transaction, so it is rolled back too.
      expect(await tablesOf(db), isEmpty);
    });

    test('group: success applies all in one go', () async {
      final db = await memorySource();
      final result = await runnerOf(
        db,
        _files,
        const MigrationSettings(group: true),
      ).migrate();
      expect(result.count, 3);
      expect(await history(db), _files.keys.toList());
    });

    test('without group the earlier migrations stay applied', () async {
      final db = await memorySource();
      await expectLater(
        runnerOf(db, failing).migrate(),
        throwsA(isA<MigrationException>()),
      );
      expect(await tablesOf(db), contains('book'));
    });
  });

  group('two runners on one database file', () {
    test('one migrates, the other waits and finds nothing to do', () async {
      final dir = newTemp();
      addTearDown(() => deleteTemp(dir));
      final a = await fileSource(dir, 'shared.db');
      final b = await fileSource(dir, 'shared.db');
      // Open the file (and switch it to WAL) before they compete.
      await run(a, 'SELECT 1');
      var waits = 0;
      MigrationRunner racer(DataSource db) => MigrationRunner(
        db,
        const MigrationSettings(group: true),
        source: const MapMigrationSource(_files),
        sleep: (d) {
          waits++;
          return Future<void>.delayed(d);
        },
      );
      final results = await Future.wait([
        racer(a).migrate(),
        racer(b).migrate(),
      ]);
      expect(results.map((r) => r.count).toList()..sort(), [0, 3]);
      expect(waits, greaterThan(0));
      expect(await history(a), _files.keys.toList());
      expect(await value(a, 'SELECT count(*) FROM book'), 1);
    });

    test('without group every migration is applied exactly once', () async {
      final dir = newTemp();
      addTearDown(() => deleteTemp(dir));
      final a = await fileSource(dir, 'shared.db');
      final b = await fileSource(dir, 'shared.db');
      await run(a, 'SELECT 1');
      final results = await Future.wait([
        runnerOf(a, _files).migrate(),
        runnerOf(b, _files).migrate(),
      ]);
      expect(results.fold<int>(0, (n, r) => n + r.count), 3);
      expect(await history(a), _files.keys.toList());
    });

    test(
      'a lock that is never released fails after the lock timeout',
      () async {
        final dir = newTemp();
        addTearDown(() => deleteTemp(dir));
        final a = await fileSource(dir, 'shared.db');
        final b = await fileSource(dir, 'shared.db');
        final holder = await a.getConnection();
        addTearDown(() => a.releaseConnection(holder));
        await holder.begin(lockForWrite: true);
        final error = await failure<MigrationException>(
          () => runnerOf(
            b,
            _files,
            const MigrationSettings(lockTimeout: Duration(milliseconds: 100)),
          ).migrate(),
        );
        expect(error.message, contains('migration lock'));
        await holder.rollback();
      },
    );
  });

  group('locations', () {
    test('{vendor} is the name of the dialect', () async {
      classpath({
        'db/migration/sqlite/V1__sqlite_only.sql': 'CREATE TABLE s (x);',
        'db/migration/postgresql/V1__pg_only.sql': 'CREATE TABLE p (x);',
        'db/migration/common/V2__common.sql': 'CREATE TABLE c (x);',
        'db/migration/V9__not_here.sql': 'CREATE TABLE n (x);',
      });
      final db = await memorySource();
      final result = await MigrationRunner(
        db,
        const MigrationSettings(
          locations: [
            'classpath:db/migration/{vendor}',
            'classpath:db/migration/common/',
          ],
        ),
      ).migrate();
      expect(result.applied.map((m) => m.script), [
        'V1__sqlite_only.sql',
        'V2__common.sql',
      ]);
      expect(await tablesOf(db), ['c', 's', 'schema_history']);
    });

    test('the default location is classpath:db/migration', () async {
      classpath({
        'db/migration/V1__a.sql': 'CREATE TABLE a (x);',
        'db/migration/V2__b.sql': 'CREATE TABLE b (x);',
        'db/migration/README.md': 'not a migration',
        'db/migration/sub/V3__c.sql': 'CREATE TABLE c (x);',
      });
      final db = await memorySource();
      final result = await MigrationRunner(
        db,
        const MigrationSettings(),
      ).migrate();
      expect(result.count, 2);
      expect(await tablesOf(db), ['a', 'b', 'schema_history']);
    });

    test('a location with no files means nothing to do', () async {
      classpath({});
      final db = await memorySource();
      final runner = MigrationRunner(db, const MigrationSettings());
      expect(await runner.hasMigrations(), isFalse);
      expect((await runner.migrate()).count, 0);
      expect(await tablesOf(db), isEmpty);
    });

    test('a file: location reads a directory', () async {
      final dir = newTemp();
      addTearDown(() => deleteTemp(dir));
      final source = ResourceMigrationSource(['file:${dir.path}']);
      expect(await source.findMigrations('sqlite'), isEmpty);
      final db = await memorySource();
      classpath({});
      await _write(dir, 'V1__a.sql', 'CREATE TABLE a (x);');
      final result = await MigrationRunner(
        db,
        MigrationSettings(locations: ['file:${dir.path}']),
      ).migrate();
      expect(result.count, 1);
    });
  });

  group('settings from the environment', () {
    Environment envOf(Map<String, Object?> properties) =>
        StandardEnvironment(systemEnvironment: const {})
          ..propertySources.addFirst(MapPropertySource('test', properties));

    test("the defaults are Flyway's", () {
      final s = MigrationSettings.fromEnvironment(envOf(const {}));
      expect(s.enabled, isTrue);
      expect(s.locations, ['classpath:db/migration']);
      expect(s.table, 'schema_history');
      expect(s.validateOnMigrate, isTrue);
      expect(s.outOfOrder, isFalse);
      expect(s.ignoreMigrationPatterns, ['*:future']);
      expect(s.baselineOnMigrate, isFalse);
      expect(s.baselineVersion, '1');
      expect(s.target, 'latest');
      expect(s.placeholders, isEmpty);
      expect(s.placeholderReplacement, isTrue);
      expect(s.placeholderPrefix, r'${');
      expect(s.placeholderSuffix, '}');
      expect(s.group, isFalse);
      expect(s.connectRetries, 0);
      expect(s.connectRetriesInterval, const Duration(seconds: 10));
    });

    test('every key is read, placeholders included', () {
      final s = MigrationSettings.fromEnvironment(
        envOf({
          'spring.sql.migration.enabled': 'false',
          'spring.sql.migration.locations':
              'classpath:db/{vendor}, classpath:extra',
          'spring.sql.migration.table': 'hist',
          'spring.sql.migration.validate-on-migrate': 'false',
          'spring.sql.migration.out-of-order': 'true',
          'spring.sql.migration.ignore-migration-patterns':
              '*:missing,*:future',
          'spring.sql.migration.baseline-on-migrate': 'true',
          'spring.sql.migration.baseline-version': '5',
          'spring.sql.migration.baseline-description': 'start',
          'spring.sql.migration.target': '7',
          'spring.sql.migration.placeholders.schema': 'main',
          'spring.sql.migration.placeholders.owner': 'me',
          'spring.sql.migration.placeholder-replacement': 'false',
          'spring.sql.migration.placeholder-prefix': '@@',
          'spring.sql.migration.placeholder-suffix': '@@',
          'spring.sql.migration.group': 'true',
          'spring.sql.migration.connect-retries': '3',
          'spring.sql.migration.connect-retries-interval': '2s',
        }),
      );
      expect(s.enabled, isFalse);
      expect(s.locations, ['classpath:db/{vendor}', 'classpath:extra']);
      expect(s.table, 'hist');
      expect(s.validateOnMigrate, isFalse);
      expect(s.outOfOrder, isTrue);
      expect(s.ignoreMigrationPatterns, ['*:missing', '*:future']);
      expect(s.baselineOnMigrate, isTrue);
      expect(s.baselineVersion, '5');
      expect(s.baselineDescription, 'start');
      expect(s.target, '7');
      expect(s.placeholders, {'schema': 'main', 'owner': 'me'});
      expect(s.placeholderReplacement, isFalse);
      expect(s.placeholderPrefix, '@@');
      expect(s.group, isTrue);
      expect(s.connectRetries, 3);
      expect(s.connectRetriesInterval, const Duration(seconds: 2));
    });

    test('a named data source has its own prefix', () {
      final s = MigrationSettings.fromEnvironment(
        envOf({
          'spring.datasources.audit.sql.migration.table': 'audit_history',
          'spring.sql.migration.table': 'other',
        }),
        'spring.datasources.audit.',
      );
      expect(s.table, 'audit_history');
    });

    test('a wrong value names the property', () {
      expect(
        () => MigrationSettings.fromEnvironment(
          envOf({'spring.sql.migration.group': 'maybe'}),
        ),
        throwsA(
          isA<SchemaException>().having(
            (e) => e.message,
            'message',
            contains('spring.sql.migration.group'),
          ),
        ),
      );
    });
  });

  group('MigrationVersion', () {
    test('compares part by part and treats missing parts as zero', () {
      MigrationVersion v(String s) => MigrationVersion.parse(s);
      expect(v('1.10') > v('1.9'), isTrue);
      expect(v('2') > v('1.99'), isTrue);
      expect(v('1') == v('1.0'), isTrue);
      expect(v('1_1') == v('1.1'), isTrue);
      expect({v('1'), v('1.0.0')}, hasLength(1));
      expect(v('1_1').toString(), '1.1');
      expect(
        () => MigrationVersion.parse('1.x'),
        throwsA(isA<MigrationException>()),
      );
    });
  });
}

Future<void> _write(Directory dir, String name, String content) =>
    File('${dir.path}/$name').writeAsString(content);

/// The checksum of a text, as the history stores it.
abstract final class MigrationRunnerChecksum {
  static int of(String text) => ResolvedMigration.checksumOf(text);
}
