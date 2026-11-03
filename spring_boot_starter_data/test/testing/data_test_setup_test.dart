// A @DataTest written as functions, on an application of beans and
// migrations written by hand over the generated SQLite driver: the slice
// (the data beans of the application, no service), the in-memory SQLite
// database with the migrations applied, and a transaction around each test.
// The class form generates the same calls and runs on repositories
// (test/data_test/).
import 'dart:io';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart'
    show CacheManager;
import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_data/testing.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/sqlite/app/sqlite_app.spring.dart' as sqlite;
import '../sqlite/support.dart' show startDriver;

/// A service: not a data bean.
class Orders {}

/// The application's own auditor: a data bean.
class Clerk implements AuditorAware<String> {
  @override
  String? getCurrentAuditor() => 'clerk';
}

/// The beans and the migrations of the application, as the generator would
/// write them for a package with `lib/resources/db/migration/`.
final _shop = BeanModule(
  'shop',
  [
    BeanDefinition<Orders>(
      name: 'orders',
      types: const [Orders],
      create: (_) => Orders(),
      annotations: const [Service()],
    ),
    BeanDefinition<Clerk>(
      name: 'clerk',
      types: const [Clerk, AuditorAware<String>, AuditorAware<dynamic>],
      create: (_) => Clerk(),
    ),
  ],
  resources: const {
    'db/migration/V1__books.sql': EmbeddedResource.text('''
create table books (
  id integer primary key,
  title text not null,
  year integer not null
);

create unique index books_title on books (title);
'''),
    'db/migration/V2__book_titles.sql': EmbeddedResource.text(
      'create view book_titles as select title from books;',
    ),
  },
);

/// The application: its module, the SQLite driver of the generated glue
/// (which comes with a bean of its own, a `Marker`), the auto-configuration
/// of the other starters and, as in a package that lists the starter, the
/// Data one.
SpringApplication get _application {
  final glue = sqlite.springApplication;
  return SpringApplication(
    [sqlite.$application, _shop],
    autoConfigurations: glue.autoConfigurations,
    autoConfigurationMetadata: glue.autoConfigurationMetadata,
  );
}

void main() {
  // The database the application is configured with: a file nobody may
  // create.
  final temp = Directory.systemTemp.createTempSync('data_test_setup');
  final file = '${temp.path}/shop.db';
  tearDownAll(() => temp.deleteSync(recursive: true));

  final data = DataTestSetup(_application);
  final app = springBootTest(
    _application,
    properties: {
      ...data.properties,
      'spring.datasource.url': 'sqlite:file:$file',
      'spring.datasource.pool.connection-timeout': '100ms',
      'spring.main.banner-mode': 'off',
    },
    initializers: [data.initializer],
  );

  JdbcClient client() => app.getBean<JdbcClient>();

  Future<void> insert(String title, [int year = 2000]) => client()
      .sql('insert into books (title, year) values (?, ?)')
      .params([title, year])
      .update();

  Future<int> count() =>
      client().sql('select count(*) from books').query<int>().single();

  /// Runs [body] as a test does, and tells how many books are left.
  Future<int> inTransaction(
    Future<void> Function() body, {
    bool rollback = true,
    List<Future<void> Function()> before = const [],
    List<Future<void> Function()> after = const [],
  }) async {
    await runInTestTransaction(
      app.context,
      body,
      rollback: rollback,
      before: before,
      after: after,
    );
    return await count();
  }

  group('the setup', () {
    test('leaves out the auto-configuration of other starters', () {
      expect(data.properties, {
        'spring.autoconfigure.exclude':
            'springBootStarterCacheAutoConfiguration',
      });
      expect(DataTestSetup.autoConfigurationNames, [
        'springBootAutoConfiguration',
        'springBootStarterLoggingAutoConfiguration',
        'springBootStarterDataAutoConfiguration',
      ]);
    });

    test('has no properties to exclude when there is nothing to leave out', () {
      final only = SpringApplication(
        [_shop],
        autoConfigurations: [
          springBootAutoConfiguration,
          springBootStarterLoggingAutoConfiguration,
          springBootStarterDataAutoConfiguration,
        ],
      );
      expect(DataTestSetup(only).properties, isEmpty);
    });
  });

  group('the context', () {
    test("holds the data beans of the application and the starter's", () {
      for (final name in [
        'sqlite3JdbcDriver',
        'clerk',
        'dataSource',
        'transactionManager',
        'transactionTemplate',
        'jdbcClient',
        'repositoryFactory',
      ]) {
        expect(app.context.containsBean(name), isTrue, reason: name);
      }
    });

    test(
      "has none of the application's other beans, and no other starter",
      () {
        expect(app.context.containsBean('orders'), isFalse);
        expect(app.context.containsBean('marker'), isFalse);
        expect(app.findBean<Orders>(), isNull);
        expect(app.findBean<CacheManager>(), isNull);
      },
    );
  });

  group('the database', () {
    test('is an in-memory SQLite one, whatever the properties say', () async {
      final source = app.getBean<DataSource>();
      expect(source.settings.url.toString(), 'sqlite::memory:');
      expect(source.driver, isA<SqliteJdbcDriver>());
      await count();
      expect(File(file).existsSync(), isFalse);
    });

    test('has the migrations of the application applied', () async {
      Future<List<String>> names(String sql) =>
          client().sql(sql).query<String>().list();

      expect(
        await names(
          "select name from sqlite_master where name in ('books', "
          "'book_titles', 'schema_history') order by name",
        ),
        ['book_titles', 'books', 'schema_history'],
      );
      expect(
        await client()
            .sql('select count(*) from schema_history')
            .query<int>()
            .single(),
        2,
      );
    });

    test('has one connection, which the pool keeps: every use sees the same '
        'tables', () async {
      final source = app.getBean<InitializingDataSource>();
      expect(source.pool.pool.maxSize, 1);
      expect(source.pool.pool.idleTimeout, Duration.zero);
      expect(source.pool.pool.maxLifetime, Duration.zero);

      Future<(JdbcConnection, Object?)> look() async {
        final connection = await source.getConnection();
        final tables = (await connection.query(
          "select count(*) from sqlite_master where name = 'books'",
        )).rows.first.values.first;
        await source.releaseConnection(connection);
        return (connection, tables);
      }

      final (first, seenFirst) = await look();
      final (second, seenSecond) = await look();
      expect(second, same(first));
      expect([seenFirst, seenSecond], [1, 1]);
    });

    test('is on one connection because the bundled SQLite cannot share an '
        'in-memory database between two', () async {
      // The reason of the pool of one: with a shared-cache URI the second
      // connection still sees none of the first one's tables. When this
      // starts to fail, the SQLite shares memory and the pool may grow.
      final driver = await startDriver();
      final settings = ConnectionSettings(
        url: Uri.parse('sqlite:file:data_test_shared?mode=memory&cache=shared'),
      );
      final first = await driver.connect(settings);
      final second = await driver.connect(settings);
      try {
        await first.execute('create table shared (v integer)');
        final seen = await second.query(
          "select count(*) from sqlite_master where name = 'shared'",
        );
        expect(seen.rows.first.values.first, 0);
      } finally {
        await first.close();
        await second.close();
      }
    });

    test('makes a second task wait for the connection and fail after the '
        'timeout: a test has no transaction of its own to start', () async {
      final source = app.getBean<DataSource>();
      final held = await source.getConnection();
      try {
        await expectLater(
          source.getConnection(),
          throwsA(isA<CannotGetJdbcConnectionException>()),
        );
      } finally {
        await source.releaseConnection(held);
      }
    });
  });

  group('the transaction of a test', () {
    test('rolls back what the test wrote', () async {
      expect(
        await inTransaction(() async {
          await insert('Dune');
          await insert('Emma');
          expect(await count(), 2);
        }),
        0,
      );
    });

    test('the next test starts without it', () async {
      expect(await count(), 0);
    });

    test('commits with rollback: false', () async {
      expect(await inTransaction(rollback: false, () => insert('Dune')), 1);
      // What a committing test leaves is for it to clean up.
      await client().sql('delete from books').update();
      expect(await count(), 0);
    });

    test('rolls back a failing test, though it should commit', () async {
      await expectLater(
        inTransaction(rollback: false, () async {
          await insert('Dune');
          throw StateError('the test failed');
        }),
        throwsA(isA<StateError>()),
      );
      expect(await count(), 0);
    });

    test('has the lifecycle methods in it', () async {
      final seen = <String>[];
      Future<void> see(String step) async {
        final inside = TransactionSynchronizationManager.currentTransaction;
        seen.add('$step ${inside != null} ${await count()}');
      }

      expect(
        await inTransaction(
          () async {
            await see('test');
            await insert('Dune');
          },
          before: [
            () async {
              await see('before');
              await insert('Seeded');
            },
          ],
          after: [() => see('after')],
        ),
        0,
      );
      // What the setUp seeded is in the transaction too, gone with it.
      expect(seen, ['before true 0', 'test true 1', 'after true 2']);
    });

    test('is joined by a TransactionTemplate', () async {
      final template = app.getBean<TransactionTemplate>();
      expect(
        await inTransaction(() async {
          await template.execute((status) async {
            expect(status.isNewTransaction, isFalse);
            await insert('Dune');
          });
          expect(await count(), 1);
        }),
        0,
      );
    });

    test('lets the constraints of the migrations hold inside it', () async {
      await inTransaction(() async {
        await insert('Dune');
        await expectLater(
          insert('Dune', 1984),
          throwsA(isA<DuplicateKeyException>()),
        );
        expect(await count(), 1);
      });
      expect(await count(), 0);
    });
  });
}
