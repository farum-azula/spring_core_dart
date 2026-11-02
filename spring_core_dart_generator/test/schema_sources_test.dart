// Which files of `lib/resources/` tell the build the schema, and in which
// order: the migrations (the versions by number, then the repeatable ones)
// and the init scripts, at the default places or where the settings say.
import 'package:spring_core_dart_generator/src/schema_sources.dart';
import 'package:test/test.dart';

SchemaSources _find(Map<String, String> resources) =>
    SchemaSources.find(resources);

void main() {
  test('the migrations of db/migration run by version, then R__', () {
    final sources = _find({
      'db/migration/V10__ten.sql': 'ten',
      'db/migration/V2__two.sql': 'two',
      'db/migration/V1.10__one_ten.sql': 'one ten',
      'db/migration/V1.2__one_two.sql': 'one two',
      'db/migration/V1__one.sql': 'one',
      'db/migration/R__b_views.sql': 'b',
      'db/migration/R__a_views.sql': 'a',
    });
    expect(sources.scripts, [
      'one',
      'one two',
      'one ten',
      'two',
      'ten',
      'a',
      'b',
    ]);
    expect(sources.reliable, isTrue);
  });

  test('other files are no migrations, nor are those in subdirectories', () {
    final sources = _find({
      'db/migration/V1__one.sql': 'one',
      'db/migration/notes.txt': 'text',
      'db/migration/readme.sql': 'readme',
      'db/migration/old/V2__old.sql': 'old',
      'db/other/V3__other.sql': 'other',
    });
    expect(sources.scripts, ['one']);
  });

  test('schema.sql and schema-all.sql are read by default', () {
    final sources = _find({
      'schema.sql': 'schema',
      'schema-all.sql': 'all',
      'schema-h2.sql': 'h2',
      'data.sql': 'data',
    });
    expect(sources.scripts, ['schema', 'all']);
  });

  test('the migrations come before the scripts', () {
    final sources = _find({
      'schema.sql': 'schema',
      'db/migration/V1__one.sql': 'one',
    });
    expect(sources.scripts, ['one', 'schema']);
  });

  test('spring.sql.migration.locations, with {vendor} for any directory', () {
    final sources = _find({
      'application.properties':
          'spring.sql.migration.locations=resources:sql/{vendor}, '
          'resources:more\n',
      'sql/sqlite/V1__one.sql': 'sqlite',
      'sql/V2__two.sql': 'none',
      'more/V3__three.sql': 'three',
      'db/migration/V4__ignored.sql': 'ignored',
    });
    expect(sources.scripts, unorderedEquals(['sqlite', 'three']));
    expect(sources.reliable, isTrue);
  });

  test('the former classpath: prefix is read as resources:', () {
    final files = {
      'sql/V1__one.sql': 'one',
      'db/schema-h2.sql': 'schema',
    };
    final old = _find({
      ...files,
      'application.properties':
          'spring.sql.migration.locations=classpath:sql\n'
          'spring.sql.init.platform=h2\n'
          'spring.sql.init.schema-locations='
          'optional:classpath*:db/schema-@@platform@@.sql\n',
    });
    final current = _find({
      ...files,
      'application.properties':
          'spring.sql.migration.locations=resources:sql\n'
          'spring.sql.init.platform=h2\n'
          'spring.sql.init.schema-locations='
          'optional:resources*:db/schema-@@platform@@.sql\n',
    });
    expect(old.scripts, ['one', 'schema']);
    expect(old.scripts, current.scripts);
    expect(old.reliable, isTrue);
  });

  test('spring.sql.init.schema-locations, @@platform@@ and a * in a name', () {
    final sources = _find({
      'application.properties':
          'spring.sql.init.platform=h2\n'
          'spring.sql.init.schema-locations=resources:db/schema-@@platform@@.sql,'
          'optional:resources:sql/*.sql\n',
      'db/schema-h2.sql': 'h2',
      'db/schema-all.sql': 'all',
      'sql/a.sql': 'a',
      'sql/b.sql': 'b',
      'schema.sql': 'default',
    });
    expect(sources.scripts, ['h2', 'a', 'b']);
  });

  test('comments, other keys and spaces in the properties are fine', () {
    final sources = _find({
      'application.properties':
          '# a comment\n'
          '! another\n'
          'server.port = 8080\n'
          'spring.sql.migration.locations = resources:db/m\n',
      'db/m/V1__one.sql': 'one',
    });
    expect(sources.scripts, ['one']);
  });

  test(
    'a location that is not on the classpath makes the schema unreliable',
    () {
      for (final property in [
        'spring.sql.migration.locations=file:/var/migrations',
        r'spring.sql.migration.locations=resources:db/${vendor}',
        'spring.sql.init.schema-locations=file:schema.sql',
      ]) {
        final sources = _find({
          'application.properties': '$property\n',
          'db/migration/V1__one.sql': 'one',
        });
        expect(sources.reliable, isFalse, reason: property);
      }
    },
  );

  test('without files there is nothing, and the schema is reliable', () {
    final sources = _find({});
    expect(sources.scripts, isEmpty);
    expect(sources.reliable, isTrue);
  });

  group('the settings of YAML files', () {
    test('application.yml and application.yaml, nested or dotted', () {
      for (final file in ['application.yml', 'application.yaml']) {
        final sources = _find({
          file:
              'spring:\n'
              '  sql:\n'
              '    migration:\n'
              '      locations: resources:db/m\n',
          'db/m/V1__one.sql': 'one',
          'db/migration/V2__other.sql': 'other',
        });
        expect(sources.scripts, ['one'], reason: file);
        expect(sources.reliable, isTrue, reason: file);
      }
      final dotted = _find({
        'application.yml':
            'spring.sql.init.schema-locations: resources:s.sql\n',
        's.sql': 'init',
        'schema.sql': 'default',
      });
      expect(dotted.scripts, ['init']);
    });

    test('a list of locations, and config/ over the root', () {
      final sources = _find({
        'application.yml':
            'spring:\n'
            '  sql:\n'
            '    migration:\n'
            '      locations:\n'
            '        - resources:a\n'
            '        - resources:b\n',
        'a/V1__a.sql': 'a',
        'b/V2__b.sql': 'b',
        'c/V3__c.sql': 'c',
        'config/application.properties':
            'spring.sql.migration.locations=resources:c\n',
      });
      expect(sources.scripts, ['c']);
      expect(sources.reliable, isTrue);
      expect(
        _find({
          'application.yml':
              'spring:\n  sql:\n    migration:\n      locations:\n'
              '        - resources:a\n        - resources:b\n',
          'a/V1__a.sql': 'a',
          'b/V2__b.sql': 'b',
        }).scripts,
        ['a', 'b'],
      );
    });

    test('properties win over YAML', () {
      final sources = _find({
        'application.yml': 'spring.sql.migration.locations: resources:y\n',
        'application.properties':
            'spring.sql.migration.locations=resources:p\n',
        'y/V1__y.sql': 'y',
        'p/V1__p.sql': 'p',
      });
      expect(sources.scripts, ['p']);
    });
  });

  group('settings the build cannot read make the schema unreliable', () {
    const migration = {'db/migration/V1__one.sql': 'one'};

    test('a profile file that sets a location, or the platform', () {
      for (final file in [
        'application-prod.properties',
        'application-prod.yml',
        'config/application-prod.yaml',
      ]) {
        for (final text in [
          'spring.sql.migration.locations: resources:other\n',
          'spring.sql.init.platform: postgres\n',
          'spring.sql.init.schema-locations: resources:other.sql\n',
          'spring:\n  sql:\n    migration:\n      locations: resources:other\n',
        ]) {
          if (file.endsWith('.properties') && text.startsWith('spring:')) {
            continue;
          }
          final sources = _find({
            ...migration,
            file: file.endsWith('.properties')
                ? text.replaceFirst(': ', '=')
                : text,
          });
          expect(sources.reliable, isFalse, reason: '$file $text');
        }
      }
    });

    test('a profile file that sets nothing of the kind changes nothing', () {
      final sources = _find({
        ...migration,
        'application-prod.yml': 'server:\n  port: 80\n',
        'application-dev.properties': 'server.port=81\n',
      });
      expect(sources.reliable, isTrue);
      expect(sources.scripts, ['one']);
    });

    test('a document for some profiles, an import, a named data source', () {
      const conditional =
          'spring.sql.migration.locations: resources:dev\n'
          '---\n'
          'spring.config.activate.on-profile: dev\n'
          'spring.sql.migration.locations: resources:other\n';
      const nested =
          'spring:\n'
          '  datasources:\n'
          '    main:\n'
          '      sql:\n'
          '        init:\n'
          '          platform: h2\n';
      for (final text in [
        conditional,
        'spring.config.import: optional:resources:more.yml\n',
        'spring.datasources.main.sql.migration.locations: resources:main\n',
        nested,
      ]) {
        final sources = _find({...migration, 'application.yml': text});
        expect(sources.reliable, isFalse, reason: text);
      }
      // A document for some profiles that sets none of them is harmless.
      expect(
        _find({
          ...migration,
          'application.yml':
              'server.port: 1\n---\n'
              'spring.config.activate.on-profile: dev\n'
              'server.port: 2\n',
        }).reliable,
        isTrue,
      );
    });

    test('a file that does not parse', () {
      expect(
        _find({...migration, 'application.yml': 'a: [b\n  c: : d'}).reliable,
        isFalse,
      );
      expect(
        _find({...migration, 'application-dev.yml': 'a: [b\n  c: : d'})
            .reliable,
        isFalse,
      );
    });
  });

  group('migrations of several databases', () {
    const settings = {
      'application.properties':
          'spring.sql.migration.locations='
          'resources:db/{vendor}, resources:common\n',
    };

    test('each database is an alternative with the common files', () {
      final sources = _find({
        ...settings,
        'db/sqlite/V1__books.sql': 'sqlite 1',
        'db/sqlite/V2__more.sql': 'sqlite 2',
        'db/postgres/V1__books.sql': 'postgres 1',
        'common/V1_5__both.sql': 'common',
        'db/postgres/notes.txt': 'not a migration',
      });
      expect(sources.variants, [
        ['postgres 1', 'common'],
        ['sqlite 1', 'common', 'sqlite 2'],
      ]);
      expect(sources.scripts, ['postgres 1', 'common']);
      expect(sources.reliable, isTrue);
    });

    test('the init scripts come after the migrations of each', () {
      final sources = _find({
        ...settings,
        'db/a/V1__a.sql': 'a',
        'db/b/V1__b.sql': 'b',
        'schema.sql': 'init',
      });
      expect(sources.variants, [
        ['a', 'init'],
        ['b', 'init'],
      ]);
    });

    test('one database is the schema, as without {vendor}', () {
      final sources = _find({
        ...settings,
        'db/sqlite/V1__books.sql': 'sqlite',
        'common/V2__both.sql': 'common',
      });
      expect(sources.variants, [
        ['sqlite', 'common'],
      ]);
    });
  });
}
