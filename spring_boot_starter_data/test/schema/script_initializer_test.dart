import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

const _schema = 'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT);';
const _data = "INSERT INTO book (title) VALUES ('Dune');";

void main() {
  Future<DataSource> memory() => memorySource();

  ScriptDatabaseInitializer initializer(
    DataSource source, [
    SqlInitSettings settings = const SqlInitSettings(),
  ]) => ScriptDatabaseInitializer(source, settings);

  group('mode', () {
    test('embedded (the default) runs on an in-memory database', () async {
      classpath({'schema.sql': _schema, 'data.sql': _data});
      final db = await memory();
      expect(ScriptDatabaseInitializer.isEmbedded(db), isTrue);
      expect(await initializer(db).initialize(), isTrue);
      expect(await value(db, 'SELECT title FROM book'), 'Dune');
    });

    test('embedded skips a file database', () async {
      classpath({'schema.sql': _schema});
      final dir = newTemp();
      addTearDown(() => deleteTemp(dir));
      final db = await fileSource(dir, 'a.db');
      expect(ScriptDatabaseInitializer.isEmbedded(db), isFalse);
      final init = initializer(db);
      expect(init.isEnabled, isFalse);
      expect(await init.initialize(), isFalse);
      expect(await tablesOf(db), isEmpty);
    });

    test('always runs on a file database', () async {
      classpath({'schema.sql': _schema});
      final dir = newTemp();
      addTearDown(() => deleteTemp(dir));
      final db = await fileSource(dir, 'a.db');
      await initializer(
        db,
        const SqlInitSettings(mode: SqlInitMode.always),
      ).initialize();
      expect(await tablesOf(db), ['book']);
    });

    test('never runs nothing, even in memory', () async {
      classpath({'schema.sql': _schema});
      final db = await memory();
      final init = initializer(
        db,
        const SqlInitSettings(mode: SqlInitMode.never),
      );
      expect(await init.initialize(), isFalse);
      expect(init.hasScriptsToRun, isFalse);
      expect(await tablesOf(db), isEmpty);
    });

    test('the mode is parsed, and a wrong one is refused', () {
      expect(SqlInitMode.parse('ALWAYS'), SqlInitMode.always);
      expect(
        () => SqlInitMode.parse('sometimes'),
        throwsA(isA<SchemaException>()),
      );
    });
  });

  group('locations', () {
    test('missing default scripts are optional', () async {
      classpath({});
      final db = await memory();
      final init = initializer(db);
      expect(init.schemaScripts(), isEmpty);
      expect(await init.initialize(), isFalse);
      expect(init.hasScriptsToRun, isFalse);
    });

    test('schema runs before data', () async {
      classpath({
        // data.sql would fail if it ran first.
        'data.sql': _data,
        'schema.sql': _schema,
      });
      final db = await memory();
      await initializer(db).initialize();
      expect(await value(db, 'SELECT count(*) FROM book'), 1);
    });

    test('a missing script asked for by name stops the start', () async {
      classpath({});
      final db = await memory();
      final error = await failure<SchemaException>(
        () => initializer(
          db,
          const SqlInitSettings(schemaLocations: ['resources:nope.sql']),
        ).initialize(),
      );
      expect(error.message, contains('nope.sql'));
      expect(error.message, contains('optional:'));
    });

    test('optional: makes a given location optional', () async {
      classpath({'a.sql': _schema});
      final db = await memory();
      await initializer(
        db,
        const SqlInitSettings(
          schemaLocations: ['optional:resources:gone.sql', 'resources:a.sql'],
        ),
      ).initialize();
      expect(await tablesOf(db), ['book']);
    });

    test('several locations and a wildcard run in order', () async {
      classpath({
        'sql/1.sql': 'CREATE TABLE one (x);',
        'sql/2.sql': 'CREATE TABLE two (x);',
        'sql/3.sql': 'INSERT INTO two VALUES (1);',
      });
      final db = await memory();
      await initializer(
        db,
        const SqlInitSettings(
          schemaLocations: ['resources:sql/1.sql', 'resources:sql/2.sql'],
          dataLocations: ['resources:sql/3.sql'],
        ),
      ).initialize();
      expect(await tablesOf(db), ['one', 'two']);
      expect(await value(db, 'SELECT count(*) FROM two'), 1);
    });
  });

  group('platform', () {
    test(
      'the default platform is all: schema.sql and schema-all.sql',
      () async {
        classpath({
          'schema.sql': _schema,
          'schema-all.sql': 'CREATE TABLE extra (x);',
          'schema-sqlite.sql': 'CREATE TABLE other (x);',
        });
        final db = await memory();
        await initializer(db).initialize();
        expect(await tablesOf(db), ['book', 'extra']);
      },
    );

    test(
      'a platform picks schema-<platform>.sql and data-<platform>.sql',
      () async {
        classpath({
          'schema.sql': _schema,
          'schema-sqlite.sql': 'CREATE TABLE only_sqlite (x);',
          'data-sqlite.sql': 'INSERT INTO only_sqlite VALUES (5);',
          'schema-all.sql': 'CREATE TABLE ignored (x);',
        });
        final db = await memory();
        await initializer(
          db,
          const SqlInitSettings(platform: 'sqlite'),
        ).initialize();
        expect(await tablesOf(db), ['book', 'only_sqlite']);
        expect(await value(db, 'SELECT x FROM only_sqlite'), 5);
      },
    );

    test('@@platform@@ in a location is replaced', () async {
      classpath({'db-sqlite.sql': _schema});
      final db = await memory();
      await initializer(
        db,
        const SqlInitSettings(
          platform: 'sqlite',
          schemaLocations: ['resources:db-@@platform@@.sql'],
        ),
      ).initialize();
      expect(await tablesOf(db), ['book']);
    });
  });

  group('errors', () {
    test('a failing statement names the file and the line', () async {
      classpath({'schema.sql': '$_schema\n\nINSERT INTO nowhere VALUES (1);'});
      final db = await memory();
      final error = await failure<ScriptException>(
        () => initializer(db).initialize(),
      );
      expect(error.message, contains('schema.sql'));
      expect(error.message, contains('line 3'));
      expect(error.line, 3);
    });

    test('continue-on-error logs and goes on', () async {
      classpath({
        'schema.sql':
            '$_schema\nBROKEN STATEMENT;\n'
            "INSERT INTO book (title) VALUES ('x');",
      });
      final db = await memory();
      await initializer(
        db,
        const SqlInitSettings(continueOnError: true),
      ).initialize();
      expect(await value(db, 'SELECT count(*) FROM book'), 1);
    });

    test('a custom separator and encoding are used', () async {
      classpath({
        'schema.sql': 'CREATE TABLE a (x)\n@@\nINSERT INTO a VALUES (1; 2)\n@@',
      });
      final db = await memory();
      // The second statement holds a ';' that is not a separator here, so
      // it fails as SQL, not as a split.
      final error = await failure<ScriptException>(
        () => initializer(
          db,
          const SqlInitSettings(separator: '@@'),
        ).initialize(),
      );
      expect(error.statementNumber, 2);
      expect(
        () => initializer(
          db,
          const SqlInitSettings(encoding: 'klingon'),
        ).initialize(),
        throwsA(isA<SchemaException>()),
      );
    });

    test('latin1 files are read with their encoding', () async {
      final dir = classpath({});
      // 0xE9 is é in latin1 and an invalid byte in utf-8.
      await _writeBytes(
        dir,
        'schema.sql',
        latin1.encode("CREATE TABLE t (x); INSERT INTO t VALUES ('café');"),
      );
      final db = await memory();
      await initializer(
        db,
        const SqlInitSettings(encoding: 'iso-8859-1'),
      ).initialize();
      expect(await value(db, 'SELECT x FROM t'), 'café');
    });
  });

  group('settings from the environment', () {
    test('every key of spring.sql.init is read', () {
      final env = StandardEnvironment(systemEnvironment: const {})
        ..propertySources.addFirst(
          const MapPropertySource('test', {
            'spring.sql.init.mode': 'always',
            'spring.sql.init.schema-locations':
                'resources:a.sql, resources:b.sql',
            'spring.sql.init.data-locations': 'resources:c.sql',
            'spring.sql.init.platform': 'sqlite',
            'spring.sql.init.continue-on-error': 'true',
            'spring.sql.init.separator': '@@',
            'spring.sql.init.encoding': 'latin1',
          }),
        );
      final settings = SqlInitSettings.fromEnvironment(env);
      expect(settings.mode, SqlInitMode.always);
      expect(settings.schemaLocations, ['resources:a.sql', 'resources:b.sql']);
      expect(settings.dataLocations, ['resources:c.sql']);
      expect(settings.platform, 'sqlite');
      expect(settings.continueOnError, isTrue);
      expect(settings.separator, '@@');
      expect(settings.encoding, 'latin1');
    });

    test(
      "a named data source reads its own prefix; the defaults are Boot's",
      () {
        final env = StandardEnvironment(systemEnvironment: const {})
          ..propertySources.addFirst(
            const MapPropertySource('test', {
              'spring.datasources.main.sql.init.mode': 'never',
            }),
          );
        expect(
          SqlInitSettings.fromEnvironment(env, 'spring.datasources.main.').mode,
          SqlInitMode.never,
        );
        const defaults = SqlInitSettings();
        final plain = SqlInitSettings.fromEnvironment(env);
        expect(plain.mode, SqlInitMode.embedded);
        expect(plain.platform, defaults.platform);
        expect(plain.separator, ';');
        expect(plain.continueOnError, isFalse);
      },
    );
  });
}

Future<void> _writeBytes(Directory dir, String name, List<int> bytes) =>
    File('${dir.path}/$name').writeAsBytes(bytes);
