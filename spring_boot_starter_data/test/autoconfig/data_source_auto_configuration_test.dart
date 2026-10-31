// The auto-configuration of the SQL databases, end to end: a real context
// over real SQLite files, set up only by properties and the driver glue.
import 'dart:async';
import 'dart:io';

import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'app/autoconfig_app.dart';
import 'app/autoconfig_app.spring.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('autoconfig_test');
    SpringLog.level = SpringLogLevel.info;
    SpringLog.resetLevels();
  });

  tearDown(() {
    SpringLog.level = SpringLogLevel.info;
    SpringLog.resetLevels();
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  // The application over two SQLite files in [temp] and a scratch name.
  ApplicationContextRunner runner([
    List<String> extra = const [],
  ]) => const ApplicationContextRunner()
      .withUserConfiguration($application)
      .withAutoConfiguration(springBootStarterDataAutoConfiguration)
      .withPropertyValues([
        'spring.datasource.url=sqlite:file:${temp.path}/app.db',
        'spring.datasources.stats.url=sqlite:file:${temp.path}/stats.db',
        'spring.datasources.stats.sql.migration.locations=classpath:db/stats',
        ...extra,
      ]);

  Future<void> started(
    FutureOr<void> Function(AssertableApplicationContext context) body, {
    List<String> properties = const [],
  }) => runner(properties).runAsync<void>((context) async {
    if (context.startupFailure case final failure?) {
      throw StateError('The application did not start: $failure');
    }
    await body(context);
  });

  Future<Object> failure(List<String> properties) async {
    Object? found;
    await runner(properties).runAsync<void>((context) {
      found = context.startupFailure;
    });
    expect(found, isNotNull, reason: 'the application should not start');
    return found!;
  }

  String report(Object error) {
    final analysis = analyzeFailure(
      error,
      analyzers: const [DataFailureAnalyzer()],
    );
    expect(analysis, isNotNull, reason: '$error');
    return analysis!.report;
  }

  group('the schema at startup', () {
    test('the migrations are applied and the repositories work at once', () {
      return started((context) async {
        final books = context.getBean<BookRepository>();
        final saved = await books.save(Book(title: 'Dune', year: 1965));
        expect(saved.id, isNotNull);
        expect(saved.version, 1);
        expect(await books.findByYearGreaterThan(1900), hasLength(1));

        final orders = context.getBean<OrderRepository>();
        final order = await orders.save(
          PurchaseOrder(
            customer: 'Ada',
            lines: [OrderLine(sku: 'dune', quantity: 2)],
          ),
        );
        expect((await orders.findById(order.id!))!.lines, hasLength(1));

        // V1, V2 and the repeatable migration are in the history, and
        // the view of the repeatable one works.
        final jdbc = context.getBean<JdbcTemplate>();
        expect(
          await jdbc.queryForObject<int>(
            'select count(*) from schema_history',
          ),
          3,
        );
        expect(
          await jdbc.queryForObject<String>('select title from book_titles'),
          'Dune',
        );
      });
    });

    test('beans that use a repository while the context starts', () {
      return started((context) async {
        // The synchronous @PostConstruct started its query without
        // waiting: it still ran on the migrated schema.
        expect(await context.getBean<EagerQuery>().count, 0);
        // The asynchronous one saved an order through the repository.
        expect(context.getBean<AsyncQuery>().count, 1);
        // The runners see the schema too.
        final command = context.getBean<SeedRunner>();
        await command.run(const []);
        expect(command.seen, ['command line: 0']);
        final application = context.getBean<SeedApplicationRunner>();
        await application.run(ApplicationArguments(const []));
        expect(application.seen, ['application: 0']);
      });
    });

    test('a schema that does not fit the entities stops the start', () async {
      final error = await failure([
        'spring.sql.migration.locations=classpath:db/partial',
      ]);
      expect('$error', contains('year'));
      expect('$error', contains('books'));
      final text = report(error);
      expect(text, contains('APPLICATION FAILED TO START'));
      expect(text, contains('does not fit the entities'));
      expect(text, contains('year'));
      expect(text, contains('migration'));
    });

    test('create-drop makes the tables and drops them at close', () async {
      final file = '${temp.path}/app.db';
      var existedWhileRunning = false;
      await runner([
        'spring.sql.migration.enabled=false',
        'spring.data.jdbc.schema=create-drop',
      ]).runAsync<void>((context) async {
        expect(context.startupFailure, isNull);
        await context.getBean<BookRepository>().save(
          Book(title: 'Temp', year: 2000),
        );
        final database = sqlite.sqlite3.open(file);
        existedWhileRunning = database
            .select("select name from sqlite_master where name = 'books'")
            .isNotEmpty;
        database.close();
      });
      expect(existedWhileRunning, isTrue);
      final database = sqlite.sqlite3.open(file);
      final tables = database
          .select("select name from sqlite_master where type = 'table'")
          .map((row) => row['name'])
          .toList();
      database.close();
      expect(tables, isNot(contains('books')));
      expect(tables, isNot(contains('authors')));
    });

    test('the context close closes the pools', () async {
      late PooledDataSource primary;
      late PooledDataSource stats;
      await started((context) async {
        await context.getBean<BookRepository>().count();
        primary =
            (context.getBean<DataSource>() as InitializingDataSource).pool;
        stats = (context.getBean<DataSource>(
          qualifier: 'stats',
        ) as InitializingDataSource).pool;
        expect(primary.isClosed, isFalse);
        expect(stats.isClosed, isFalse);
      });
      expect(primary.isClosed, isTrue);
      expect(stats.isClosed, isTrue);
    });
  });

  group('the data source from properties', () {
    test('the pool and the driver settings are read', () {
      return started(
        (context) {
          final source =
              context.getBean<DataSource>() as InitializingDataSource;
          expect(source.pool.pool.maxSize, 3);
          expect(source.pool.pool.minIdle, 1);
          expect(
            source.pool.pool.connectionTimeout,
            const Duration(seconds: 5),
          );
          expect(source.pool.pool.idleTimeout, const Duration(minutes: 2));
          expect(source.pool.pool.maxLifetime, const Duration(minutes: 20));
          expect(source.pool.pool.validation, isFalse);
          expect(source.settings.properties['busy-timeout'], '1500');
          expect(source.driver, isA<SqliteJdbcDriver>());
        },
        properties: [
          'spring.datasource.pool.max-size=3',
          'spring.datasource.pool.min-idle=1',
          'spring.datasource.pool.connection-timeout=5s',
          'spring.datasource.pool.idle-timeout=2m',
          'spring.datasource.pool.max-lifetime=20m',
          'spring.datasource.pool.validation=false',
          'spring.datasource.sqlite.busy-timeout=1500',
        ],
      );
    });

    test(
      'a relative file is in the base directory of its data source',
      () async {
        final base = Directory('${temp.path}/data')..createSync();
        await runner([
          'spring.datasource.url=sqlite:file:books.db',
          'spring.datasource.sqlite.base-directory=${base.path}',
        ]).runAsync<void>((context) async {
          expect(context.startupFailure, isNull);
          await context.getBean<BookRepository>().count();
        });
        expect(File('${base.path}/books.db').existsSync(), isTrue);
        expect(File('${temp.path}/stats.db').existsSync(), isTrue);
      },
    );

    test('a jdbc: prefix is accepted', () {
      return started(
        (context) async {
          await context.getBean<BookRepository>().count();
        },
        properties: [
          'spring.datasource.url=jdbc:sqlite:file:${temp.path}/other.db',
        ],
      );
    });

    test('the application declares its own DataSource', () async {
      final own = BeanModule('own', [
        BeanDefinition<DataSource>(
          name: 'dataSource',
          create: (r) => PooledDataSource(
            name: 'own',
            driver: r.dependency<JdbcDriver>(),
            settings: ConnectionSettings(
              url: Uri.parse('sqlite:file:${temp.path}/own.db'),
            ),
          ),
        ),
      ]);
      await runner(['app.early-queries=false'])
          .withUserConfiguration(own)
          .runAsync<void>((context) async {
            expect(context.startupFailure, isNull);
            final source = context.getBean<DataSource>();
            expect(source.name, 'own');
            expect(source, isNot(isA<InitializingDataSource>()));
            // Still a schema setup, a manager and templates over it.
            expect(context, hasBeanNamed('dataSourceInitialization'));
            expect(
              context.getBean<PlatformTransactionManager>(),
              isA<DataSourceTransactionManager>(),
            );
            expect(
              context.getBean<JdbcTemplate>().dataSource,
              same(source),
            );
            expect(await context.getBean<BookRepository>().count(), 0);
          });
    });
  });

  group('the failures', () {
    test('a URL no driver handles says what to add', () async {
      final error = await failure([
        'spring.datasource.url=postgresql://db:5432/shop',
      ]);
      expect(
        '$error',
        contains('spring.datasource.url is postgresql://db:5432/shop'),
      );
      expect(
        '$error',
        contains('add the postgres package to your dependencies'),
      );
      final text = report(error);
      expect(text, contains('APPLICATION FAILED TO START'));
      expect(text, contains('Add the postgres package'));
      expect(text, contains('sqlite3: sqlite'));
    });

    test('with no driver at all', () async {
      Object? found;
      await const ApplicationContextRunner()
          .withAutoConfiguration(springBootStarterDataAutoConfiguration)
          .withPropertyValues(['spring.datasource.url=sqlite:file:books.db'])
          .runAsync<void>((context) {
            found = context.startupFailure;
          });
      expect(
        '$found',
        contains('spring.datasource.url is sqlite:file:books.db'),
      );
      expect(
        '$found',
        contains('add the sqlite3 package to your dependencies'),
      );
      expect('$found', contains('no driver at all'));
      expect(report(found!), contains('Add the sqlite3 package'));
    });

    test('an unknown scheme', () async {
      final error = await failure(['spring.datasource.url=mysql://db/shop']);
      expect('$error', contains('no driver handles the scheme "mysql"'));
      expect(report(error), contains('No driver is known'));
    });

    test('a password in the URL is never shown', () async {
      final error = await failure([
        'spring.datasource.url=postgresql://shop:s3cr3t@db:5432/shop',
      ]);
      expect('$error', isNot(contains('s3cr3t')));
      expect(report(error), isNot(contains('s3cr3t')));
    });

    test('two drivers for one scheme, and driver chooses', () async {
      final second = BeanModule('second', [
        BeanDefinition<JdbcDriver>(
          name: 'otherSqliteDriver',
          create: (r) => _OtherDriver(r.dependency<JdbcDriver>()),
        ),
      ]);
      Object? found;
      await runner().withUserConfiguration(second).runAsync<void>((context) {
        found = context.startupFailure;
      });
      expect(found, isNotNull);
      expect('$found', contains('other, sqlite3'));
      expect('$found', contains('all handle the scheme "sqlite"'));
      expect(report(found!), contains('.driver (one of other, sqlite3)'));
    });

    test('spring.datasource.driver chooses between two drivers', () {
      final second = BeanModule('second', [
        BeanDefinition<JdbcDriver>(
          name: 'otherSqliteDriver',
          create: (r) => _OtherDriver(r.dependency<JdbcDriver>()),
        ),
      ]);
      return runner([
        'spring.datasource.driver=sqlite3',
        'spring.datasources.stats.driver=other',
      ]).withUserConfiguration(second).runAsync<void>((context) async {
        expect(context.startupFailure, isNull);
        expect(context.getBean<DataSource>().driver.name, 'sqlite3');
        expect(
          context.getBean<DataSource>(qualifier: 'stats').driver.name,
          'other',
        );
        expect(await context.getBean<VisitRepository>().count(), 0);
      });
    });

    test('a pool setting that is not valid', () async {
      final error = await failure(['spring.datasource.pool.max-size=0']);
      expect('$error', contains('spring.datasource.pool.max-size is "0"'));
      expect(report(error), contains('Failed to configure the data source'));
      final timeout = await failure([
        'spring.datasource.pool.connection-timeout=soon',
      ]);
      expect('$timeout', contains('spring.datasource.pool.connection-timeout'));
    });

    test('a named data source without a URL', () async {
      final error = await failure([
        'spring.datasources.other.pool.max-size=2',
      ]);
      expect('$error', contains('spring.datasources.other.url'));
    });
  });

  group('the transaction managers', () {
    test('the DataSource one is the manager when a database is set', () {
      return started((context) {
        final manager = context.getBean<PlatformTransactionManager>();
        expect(manager, isA<DataSourceTransactionManager>());
        expect(
          (manager as DataSourceTransactionManager).dataSource,
          same(context.getBean<DataSource>()),
        );
        expect(context.containsBean('transactionManager'), isTrue);
        final stats = context.getBean<PlatformTransactionManager>(
          qualifier: 'stats',
        );
        expect(stats, isA<DataSourceTransactionManager>());
        expect(
          (stats as DataSourceTransactionManager).dataSource,
          same(context.getBean<DataSource>(qualifier: 'stats')),
        );
        // The memory manager of the in-memory name stays.
        expect(
          context.getBean<PlatformTransactionManager>(qualifier: 'scratch'),
          isA<InMemoryTransactionManager>(),
        );
        // The template: the single candidate is the primary manager.
        final template = context.getBean<TransactionTemplate>();
        expect(template.manager, same(manager));
      });
    });

    test('the memory manager is the default without a database', () async {
      await const ApplicationContextRunner()
          .withAutoConfiguration(springBootStarterDataAutoConfiguration)
          .runAsync<void>((context) {
            expect(context.startupFailure, isNull);
            expect(
              context.getBean<PlatformTransactionManager>(),
              isA<InMemoryTransactionManager>(),
            );
            expect(context, isNot(hasBean<DataSource>()));
            expect(context, isNot(hasBean<JdbcTemplate>()));
            expect(context.getBean<RepositoryFactory>().defaultStore, 'memory');
          });
    });

    test('only a named database: no primary beans, memory by default', () {
      return const ApplicationContextRunner()
          .withUserConfiguration($application)
          .withAutoConfiguration(springBootStarterDataAutoConfiguration)
          .withPropertyValues([
            'spring.datasources.stats.url=sqlite:file:${temp.path}/stats.db',
            'spring.datasources.stats.sql.migration.locations=classpath:db/stats',
            'spring.sql.migration.enabled=false',
          ])
          .runAsync<void>((context) async {
            expect(context.startupFailure, isNull);
            final factory = context.getBean<RepositoryFactory>();
            expect(factory.defaultStore, 'memory');
            expect(factory.jdbcDataSources.keys, ['stats']);
            expect(context, isNot(hasBeanNamed('dataSource')));
            expect(context, isNot(hasBeanNamed('jdbcTemplate')));
            expect(
              context.getBean<PlatformTransactionManager>(),
              isA<InMemoryTransactionManager>(),
            );
            // The books are in memory, the visits in the named database.
            await context.getBean<BookRepository>().save(
              Book(title: 'Dune', year: 1965),
            );
            await context.getBean<VisitRepository>().save(Visit(page: '/'));
            expect(await context.getBean<BookRepository>().count(), 1);
            expect(await context.getBean<VisitRepository>().count(), 1);
          });
    });

    test('@Transactional uses the manager of the named data source', () {
      return started((context) async {
        final library = context.getBean<Library>();
        await library.visit('/home');
        await expectLater(
          library.visit('/lost', fail: true),
          throwsA(isA<StateError>()),
        );
        expect(await context.getBean<VisitRepository>().count(), 1);

        await library.addBook('Dune');
        await expectLater(
          library.addBook('boom'),
          throwsA(isA<StateError>()),
        );
        expect(await context.getBean<BookRepository>().count(), 1);
        expect(await context.getBean<AuthorRepository>().count(), 1);

        // The two databases are separate files.
        expect(File('${temp.path}/stats.db').existsSync(), isTrue);
        final stats = sqlite.sqlite3.open('${temp.path}/stats.db');
        final visits = stats.select('select page from visits');
        stats.close();
        expect(visits.map((r) => r['page']), ['/home']);
      });
    });

    test('a scratch memory repository works beside the databases', () {
      return started((context) async {
        final notes = context.getBean<NoteRepository>();
        await notes.save(Note(text: 'hi'));
        expect(await notes.count(), 1);
      });
    });
  });

  group('the templates', () {
    test('JdbcTemplate, NamedParameterJdbcTemplate and JdbcClient', () {
      return started((context) async {
        await context.getBean<BookRepository>().save(
          Book(title: 'Dune', year: 1965),
        );
        final jdbc = context.getBean<JdbcTemplate>();
        expect(jdbc.dataSource, same(context.getBean<DataSource>()));
        expect(
          await jdbc.queryForObject<int>('select count(*) from books'),
          1,
        );
        final named = context.getBean<NamedParameterJdbcTemplate>();
        expect(named.jdbc, same(jdbc));
        expect(
          await named.queryForObject<String>(
            'select title from books where year = :year',
            {'year': 1965},
          ),
          'Dune',
        );
        final client = context.getBean<JdbcClient>();
        expect(
          await client
              .sql('select count(*) from books where year > :y')
              .param('y', 1900)
              .query<int>()
              .single(),
          1,
        );
        // The named database has its own.
        final stats = context.getBean<JdbcTemplate>(qualifier: 'stats');
        expect(
          stats.dataSource,
          same(context.getBean<DataSource>(qualifier: 'stats')),
        );
        expect(
          await stats.queryForObject<int>('select count(*) from visits'),
          0,
        );
        expect(
          context.getBean<JdbcClient>(qualifier: 'stats'),
          isNot(same(client)),
        );
      });
    });

    test('the query timeout is passed on', () {
      return started(
        (context) {
          expect(
            context.getBean<JdbcTemplate>().queryTimeout,
            const Duration(seconds: 7),
          );
        },
        properties: ['spring.jdbc.template.query-timeout=7s'],
      );
    });

    test('the log switches become JdbcLogSettings, also in the factory', () {
      return started(
        (context) {
          final settings = context.getBean<JdbcLogSettings>();
          expect(settings.showSql, isTrue);
          expect(settings.formatSql, isTrue);
          expect(settings.showParameters, isTrue);
          expect(
            settings.slowQueryThreshold,
            const Duration(milliseconds: 250),
          );
          expect(
            context.getBean<RepositoryFactory>().jdbcLogSettings,
            same(settings),
          );
          expect(context.getBean<JdbcTemplate>().logSettings, same(settings));
        },
        properties: [
          'spring.data.jdbc.show-sql=true',
          'spring.data.jdbc.format-sql=true',
          'spring.data.jdbc.show-parameters=true',
          'spring.data.jdbc.slow-query-threshold=250ms',
        ],
      );
    });

    test('show-sql logs the statements at info, never the password', () async {
      final records = <SpringLogRecord>[];
      final stop = SpringLog.listen(records.add);
      try {
        await started(
          (context) async {
            await context.getBean<BookRepository>().save(
              Book(title: 'Dune', year: 1965),
            );
          },
          properties: [
            'spring.data.jdbc.show-sql=true',
            'spring.datasource.password=s3cr3t-pass',
          ],
        );
      } finally {
        stop();
      }
      final sql = records.where(
        (r) =>
            r.loggerName == 'spring.jdbc.core.JdbcTemplate' &&
            r.level == SpringLogLevel.info,
      );
      expect(sql.any((r) => r.message.contains('insert into')), isTrue);
      final everything = records.map((r) => r.message).join('\n');
      expect(everything, isNot(contains('s3cr3t-pass')));
      // The pool says where it connects, without credentials.
      expect(
        everything,
        contains('sqlite:file:${temp.path}/app.db'),
      );
    });
  });

  group('the repositories', () {
    test('the default store is jdbc with a database, memory without', () {
      return started((context) {
        final factory = context.getBean<RepositoryFactory>();
        expect(factory.defaultStore, 'jdbc');
        expect(factory.jdbcDataSources.keys.toSet(), {'default', 'stats'});
        expect(
          factory.jdbcDataSources['default'],
          same(context.getBean<DataSource>()),
        );
        expect(factory.environment, isNotNull);
        expect(factory.beanFactory, isNotNull);
      });
    });

    test('the entities of the repositories of each database', () {
      return started((context) {
        final beans = context.context.beanFactory;
        final mapping = context.getBean<RelationalMappingContext>();
        final primary = RepositoryEntities(
          beans: beans,
          mappingContext: mapping,
        );
        expect(primary.entityNames, ['Author', 'Book', 'PurchaseOrder']);
        final stats = RepositoryEntities(
          beans: beans,
          mappingContext: mapping,
          dataSource: 'stats',
        );
        expect(stats.entityNames, ['Visit']);
        expect(stats.map((e) => e.tableName), ['visits']);
      });
    });
  });
}

// A second driver for the sqlite scheme.
final class _OtherDriver implements JdbcDriver {
  _OtherDriver(this._delegate);

  final JdbcDriver _delegate;

  @override
  String get name => 'other';

  @override
  List<String> get schemes => const ['sqlite'];

  @override
  SqlDialect get dialect => _delegate.dialect;

  @override
  Future<JdbcConnection> connect(ConnectionSettings settings) =>
      _delegate.connect(settings);
}
