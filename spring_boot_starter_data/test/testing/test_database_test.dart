// What the database replacement of a @DataTest sets, read from the
// environment it prepares; the real database it opens is in
// data_test_setup_test.dart.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_data/testing.dart';
import 'package:test/test.dart';

import '../schema/support.dart' show classpath;

/// A context with [properties] in its environment, which [TestDatabase]
/// prepares like the real one before the refresh.
ConfigurableApplicationContext _context(Map<String, Object?> properties) {
  final environment = StandardEnvironment();
  environment.propertySources.addFirst(MapPropertySource('test', properties));
  return AnnotationConfigApplicationContext(const [], environment: environment);
}

/// The environment of a context with [properties] after the replacement.
Environment _replaced(
  Map<String, Object?> properties, {
  bool sqlite = true,
}) {
  final context = _context(properties);
  TestDatabase(hasSqliteDriver: sqlite).initialize(context);
  return context.environment;
}

const _file = {'spring.datasource.url': 'sqlite:file:books.db'};

void main() {
  group('the primary database', () {
    test('is replaced by an in-memory one on a pool of one connection', () {
      final environment = _replaced({
        ..._file,
        'spring.datasource.username': 'shop',
        'spring.datasource.pool.max-size': '20',
        'spring.datasource.pool.min-idle': '5',
        'spring.datasource.pool.idle-timeout': '10s',
        'spring.datasource.driver': 'other',
      });
      expect(
        environment.getProperty('spring.datasource.url'),
        'sqlite::memory:',
      );
      expect(environment.getProperty('spring.datasource.driver'), 'sqlite3');
      // One connection, which the pool never closes: it holds the database.
      expect(environment.getProperty('spring.datasource.pool.max-size'), '1');
      expect(environment.getProperty('spring.datasource.pool.min-idle'), '0');
      expect(
        environment.getProperty('spring.datasource.pool.idle-timeout'),
        '0',
      );
      expect(
        environment.getProperty('spring.datasource.pool.max-lifetime'),
        '0',
      );
      // The rest of the configuration stays.
      expect(environment.getProperty('spring.datasource.username'), 'shop');
    });

    test('the settings are valid for the pool', () {
      final environment = _replaced(_file);
      final properties = DataSourceProperties.fromEnvironment(environment);
      expect(properties.url.toString(), 'sqlite::memory:');
      expect(properties.pool.maxSize, 1);
      expect(properties.pool.minIdle, 0);
      expect(properties.pool.idleTimeout, Duration.zero);
      expect(properties.pool.maxLifetime, Duration.zero);
    });

    test('wins over every other source, the test properties included', () {
      final context = _context(_file);
      context.environment.propertySources.addFirst(
        const MapPropertySource('dynamic', {
          'spring.datasource.url': 'sqlite:file:other.db',
        }),
      );
      const TestDatabase(hasSqliteDriver: true).initialize(context);
      expect(
        context.environment.getProperty('spring.datasource.url'),
        'sqlite::memory:',
      );
    });
  });

  group('the databases that are not configured', () {
    test('are left alone, with or without a driver', () {
      for (final sqlite in [true, false]) {
        final environment = _replaced(const {'unrelated': 'x'}, sqlite: sqlite);
        expect(
          (environment as ConfigurableEnvironment).propertySources.any(
            (source) => source.name == TestDatabase.propertySourceName,
          ),
          isFalse,
        );
        expect(environment.getProperty('spring.datasource.url'), isNull);
      }
    });

    test('a named one without a URL is not replaced', () {
      final environment = _replaced({
        ..._file,
        'spring.datasources.archive.url': 'sqlite:file:archive.db',
        'spring.datasources.audit.pool.max-size': '3',
      });
      expect(
        environment.getProperty('spring.datasources.archive.url'),
        'sqlite::memory:',
      );
      expect(environment.getProperty('spring.datasources.audit.url'), isNull);
      expect(
        environment.getProperty('spring.datasources.audit.pool.max-size'),
        '3',
      );
    });
  });

  group('the named databases', () {
    test('are replaced the same way', () {
      final environment = _replaced({
        'spring.datasources.archive.url': 'postgresql://db/archive',
        'spring.datasources.archive.pool.max-size': '8',
      });
      const prefix = 'spring.datasources.archive.';
      expect(environment.getProperty('${prefix}url'), 'sqlite::memory:');
      expect(environment.getProperty('${prefix}driver'), 'sqlite3');
      expect(environment.getProperty('${prefix}pool.max-size'), '1');
      expect(environment.getProperty('${prefix}pool.max-lifetime'), '0');
      // The primary one does not exist, and stays so.
      expect(environment.getProperty('spring.datasource.url'), isNull);
    });
  });

  group('without a SQLite driver', () {
    test('a configured database cannot be replaced: the start fails and says '
        'what to do', () {
      expect(
        () => _replaced({
          ..._file,
          'spring.datasources.archive.url': 'sqlite:file:archive.db',
        }, sqlite: false),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('spring.datasource, spring.datasources.archive'),
              contains('add the sqlite3 package'),
              contains('@DataTest(replaceDatabase: false)'),
            ),
          ),
        ),
      );
    });

    test('is found among the definitions of the application', () {
      BeanDefinition<Object> bean(String name, List<Type> types) =>
          BeanDefinition<Object>(
            name: name,
            types: types,
            create: (_) => Object(),
          );
      expect(
        TestDatabase.hasSqliteDriverIn([
          bean('sqlite3JdbcDriver', [JdbcDriver]),
        ]),
        isTrue,
      );
      expect(
        TestDatabase.hasSqliteDriverIn([
          bean('driver', [SqliteJdbcDriver, JdbcDriver]),
        ]),
        isTrue,
      );
      expect(
        TestDatabase.hasSqliteDriverIn([
          bean('postgresJdbcDriver', [JdbcDriver]),
          bean('orders', [String]),
        ]),
        isFalse,
      );
      expect(TestDatabase.hasSqliteDriverIn(const []), isFalse);
    });
  });

  group('the schema', () {
    String? schema(Environment environment, [String prefix = 'spring.']) =>
        environment.getProperty('${prefix}data.jdbc.schema');

    test('is made from the entities when nothing else makes it', () {
      expect(schema(_replaced(_file)), 'create');
    });

    test("is the application's when it has migrations", () {
      classpath({'db/migration/V1__books.sql': 'create table books (id int);'});
      expect(schema(_replaced(_file)), isNull);
    });

    test(
      'is made from the entities when the migrations are off or elsewhere',
      () {
        classpath({
          'db/migration/V1__books.sql': 'create table books (id int);',
        });
        expect(
          schema(
            _replaced({..._file, 'spring.sql.migration.enabled': 'false'}),
          ),
          'create',
        );
        expect(
          schema(
            _replaced({
              ..._file,
              'spring.sql.migration.locations': 'resources:db/none',
            }),
          ),
          'create',
        );
      },
    );

    test('is the one of the scripts when schema.sql exists', () {
      classpath({'schema.sql': 'create table books (id int);'});
      expect(schema(_replaced(_file)), isNull);
      // Scripts that never run own nothing.
      expect(
        schema(_replaced({..._file, 'spring.sql.init.mode': 'never'})),
        'create',
      );
    });

    test('a data.sql counts as a script too, and so do configured scripts', () {
      classpath({
        'data.sql': 'insert into books values (1);',
        'seed/schema.sql': 'create table books (id int);',
      });
      expect(schema(_replaced(_file)), isNull);
      expect(
        schema(
          _replaced({
            ..._file,
            'spring.sql.init.schema-locations': 'resources:seed/schema.sql',
            'spring.sql.init.data-locations': 'optional:resources:none.sql',
          }),
        ),
        isNull,
      );
    });

    test('is left as the configuration says', () {
      expect(
        schema(_replaced({..._file, 'spring.data.jdbc.schema': 'validate'})),
        'validate',
      );
      expect(
        schema(_replaced({..._file, 'spring.data.jdbc.schema': 'none'})),
        'none',
      );
    });

    test('of a named database reads the settings of that one', () {
      classpath({'db/archive/V1__a.sql': 'create table a (id int);'});
      const prefix = 'spring.datasources.archive.';
      final environment = _replaced({
        'spring.datasources.archive.url': 'sqlite:file:archive.db',
        'spring.datasources.shop.url': 'sqlite:file:shop.db',
        'spring.datasources.archive.sql.migration.locations':
            'resources:db/archive',
      });
      // archive has migrations; shop looks at db/migration, which is empty.
      expect(schema(environment, prefix), isNull);
      expect(schema(environment, 'spring.datasources.shop.'), 'create');
      expect(schema(environment), isNull);
    });
  });
}
