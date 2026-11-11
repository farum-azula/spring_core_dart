// The rate limiter's SQL store on SQLite (a file several connections
// share), and which store an application with a data source gets.
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/sqlite/app/sqlite_app.spring.dart';
import '../sqlite/support.dart';
import 'support.dart';

final class _AppStore implements RateLimitStore {
  @override
  Future<RateLimitDecision> tryAcquire(
    String key,
    RateLimit limit, {
    int permits = 1,
  }) async => const RateLimitDecision(allowed: true, remaining: 1);
}

void main() {
  late Directory directory;

  setUp(() => directory = newTemp());
  tearDown(() => deleteTemp(directory));

  group('on SQLite', () {
    rateLimitStoreContract(
      () async {
        final source = PooledDataSource(
          name: 'sqlite',
          driver: await startDriver(),
          settings: fileSettings(directory, 'limits.db'),
          pool: const PoolSettings(maxSize: 4),
        );
        addTearDown(source.close);
        return source;
      },
      ddlFile: _shipped('lib/sql/rate_limit/sqlite.sql').readAsStringSync(),
    );
  });

  group('the store itself', () {
    Future<DataSource> source() async {
      final source = PooledDataSource(
        name: 'sqlite',
        driver: await startDriver(),
        settings: fileSettings(directory, 'limits.db'),
      );
      addTearDown(source.close);
      return source;
    }

    test('refuses a table that is no name', () async {
      final dataSource = await source();
      for (final table in ['', 'a b', 'x; drop table y', '"quoted"', 'a.b.c']) {
        expect(
          () => JdbcRateLimitStore(dataSource, table: table),
          throwsArgumentError,
          reason: table,
        );
      }
      expect(
        JdbcRateLimitStore(dataSource, table: 'app.limits').table,
        'app.limits',
      );
    });

    test("the application's statements come before the built-in", () async {
      final store = JdbcRateLimitStore(
        await source(),
        statements: const [_NoStatements(), _OwnStatements()],
      );
      expect(store.statements, isA<_OwnStatements>());
      expect(
        JdbcRateLimitStore(await source()).statements,
        isA<SqliteRateLimitStatements>(),
      );
    });

    test('the SQL of PostgreSQL is one statement with its values named', () {
      const statements = PostgresRateLimitStatements();
      final sql = statements.acquire('rate_limit');
      expect(sql, startsWith('insert into rate_limit as b'));
      expect(sql, contains('on conflict (key) do update set'));
      expect(sql, contains('returning allowed, tokens'));
      expect(sql, isNot(contains(';')));
      expect(statements.createTable('app.limits').first, contains('unlogged'));
      expect(
        statements.createTable('app.limits').last,
        contains('app_limits_expires_at'),
      );
    });
  });

  group('which store', () {
    ApplicationContextRunner runner(List<String> properties) =>
        const ApplicationContextRunner()
            .withUserConfiguration($application)
            .withAutoConfiguration(springBootStarterDataAutoConfiguration)
            .withPropertyValues([
              'logging.level.root=warn',
              ...properties,
            ]);

    List<String> database() => [
      'spring.datasource.url=sqlite:file:${directory.path}/app.db',
      'spring.data.jdbc.schema=none',
    ];

    test('the SQL store when the application has a primary data source and '
        'the rate limiter is on', () async {
      await runner([
        ...database(),
        'spring.web.rate-limit.enabled=true',
        'spring.data.jdbc.rate-limit.create-table=true',
        'spring.data.jdbc.rate-limit.table=limits',
      ]).runAsync((context) async {
        expect(context.startupFailure, isNull);
        final store = context.getBean<RateLimitStore>();
        expect(store, isA<JdbcRateLimitStore>());
        expect((store as JdbcRateLimitStore).table, 'limits');
        const limit = RateLimit(2, Duration(hours: 1));
        expect((await store.tryAcquire('k', limit)).remaining, 1);
        expect((await store.tryAcquire('k', limit)).remaining, 0);
        expect((await store.tryAcquire('k', limit)).allowed, isFalse);
      });
    });

    test('a rule turns the rate limiter on as well', () async {
      await runner([
        ...database(),
        'spring.web.rate-limit.rules[0].limit=5/1m',
      ]).runAsync((context) async {
        expect(context.getBean<RateLimitStore>(), isA<JdbcRateLimitStore>());
      });
    });

    test('the table is created with spring.data.jdbc.schema=create, not '
        'otherwise', () async {
      Future<bool> creates(List<String> properties) async {
        late bool created;
        await runner([
          'spring.datasource.url=sqlite:file:${directory.path}/app.db',
          'spring.web.rate-limit.enabled=true',
          ...properties,
        ]).runAsync((context) async {
          created = context.getBean<JdbcRateLimitStore>().createTable;
        });
        return created;
      }

      expect(await creates(['spring.data.jdbc.schema=create']), isTrue);
      expect(await creates(['spring.data.jdbc.schema=create-drop']), isTrue);
      expect(await creates(['spring.data.jdbc.schema=none']), isFalse);
      expect(await creates(['spring.data.jdbc.schema=validate']), isFalse);
      expect(
        await creates([
          'spring.data.jdbc.schema=create',
          'spring.data.jdbc.rate-limit.create-table=false',
        ]),
        isFalse,
      );
    });

    test('no store without the rate limiter, with it turned off, or with '
        'another store asked for', () async {
      for (final properties in [
        <String>[],
        ['spring.web.rate-limit.enabled=false'],
        [
          'spring.web.rate-limit.enabled=false',
          'spring.web.rate-limit.rules[0].limit=5/1m',
        ],
        [
          'spring.web.rate-limit.enabled=true',
          'spring.web.rate-limit.store=memory',
        ],
        [
          'spring.web.rate-limit.enabled=true',
          'spring.web.rate-limit.store=procedure',
        ],
      ]) {
        await runner([...database(), ...properties]).runAsync((context) async {
          expect(context.startupFailure, isNull);
          expect(
            context.containsBean('jdbcRateLimitStore'),
            isFalse,
            reason: '$properties',
          );
        });
      }
    });

    test('no store by default without a data source; asked for, the start '
        'says what is missing', () async {
      await runner(['spring.web.rate-limit.enabled=true']).runAsync((
        context,
      ) async {
        expect(context.startupFailure, isNull);
        expect(context.containsBean('jdbcRateLimitStore'), isFalse);
      });
      final failure = await runner([
        'spring.web.rate-limit.enabled=true',
        'spring.web.rate-limit.store=jdbc',
      ]).runAsync((context) async => context.startupFailure);
      expect('$failure', contains('primary DataSource'));
    });

    test('a store bean of the application wins', () async {
      await runner([...database(), 'spring.web.rate-limit.enabled=true'])
          .withUserConfiguration(
            BeanModule('appStore', [
              BeanDefinition<_AppStore>(
                name: 'appStore',
                types: const [_AppStore, RateLimitStore],
                create: (_) => _AppStore(),
              ),
            ]),
          )
          .runAsync((context) async {
            expect(context.getBean<RateLimitStore>(), isA<_AppStore>());
            expect(context.containsBean('jdbcRateLimitStore'), isFalse);
          });
    });
  });
}

final class _NoStatements implements RateLimitStatements {
  const _NoStatements();

  @override
  bool supports(SqlDialect dialect) => false;

  @override
  List<String> createTable(String table) => const [];

  @override
  String acquire(String table) => '';

  @override
  String purge(String table) => '';
}

final class _OwnStatements extends _NoStatements {
  const _OwnStatements();

  @override
  bool supports(SqlDialect dialect) => dialect.name == 'sqlite';

  @override
  String acquire(String table) =>
      const SqliteRateLimitStatements().acquire(table);
}

// The file of this package, wherever the tests are run from.
File _shipped(String path) => File.fromUri(
  Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_boot_starter_data/spring_boot_starter_data.dart'),
  )!.resolve('../$path'),
);
