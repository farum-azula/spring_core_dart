// The driver's own settings (`spring.datasource.postgresql.*`,
// `spring.datasource.sqlite.*`, and the same under
// `spring.datasources.<name>.`) come from every kind of property source: a
// variable of the process (`SPRING_DATASOURCE_POSTGRESQL_SSLMODE`), a
// command line argument and a file. A setting dropped silently would be a
// `verify-full` that checks nothing.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../postgres/fake_postgres.dart';
import 'support/fake_jdbc.dart';

// The sources a setting may come from, each set the way it is written there.
typedef _Form = ({String name, Environment Function(Map<String, String>) make});

// [settings]: property name (`spring.datasource.postgresql.sslmode`) to
// value, as an argument or a file writes it; the variable form is made by
// the way Spring Boot writes variables.
Environment _environment(
  Map<String, String> settings, {
  required Map<String, String> variables,
}) {
  final environment = StandardEnvironment(systemEnvironment: variables)
    ..propertySources.addFirst(MapPropertySource('test', settings));
  ConfigurationPropertySources.attach(environment);
  return environment;
}

String _variable(String property) =>
    property.toUpperCase().replaceAll(RegExp('[.-]'), '_');

final _forms = <_Form>[
  (
    name: 'an environment variable',
    make: (settings) => _environment(
      const {},
      variables: {
        for (final MapEntry(:key, :value) in settings.entries)
          _variable(key): value,
      },
    ),
  ),
  (
    name: 'an environment variable without the dashes',
    make: (settings) => _environment(
      const {},
      variables: {
        for (final MapEntry(:key, :value) in settings.entries)
          key.toUpperCase().replaceAll('-', '').replaceAll('.', '_'): value,
      },
    ),
  ),
  (
    name: 'an argument',
    make: (settings) => _environment(settings, variables: const {}),
  ),
  (
    name: 'a file',
    make: (settings) => _environment({
      // A file may write the name in camel case.
      for (final MapEntry(:key, :value) in settings.entries)
        key.replaceAllMapped(
          RegExp('-([a-z])'),
          (m) => m[1]!.toUpperCase(),
        ): value,
    }, variables: const {}),
  ),
];

void main() {
  const url = 'postgresql://app@db.example:5432/books';
  final postgres = PostgresJdbcDriver(FakeBinding());
  final sqlite = SqliteJdbcDriver(_NoBinding());

  Map<String, String> read(
    Environment environment,
    JdbcDriver driver, {
    String prefix = DataSourceProperties.primaryPrefix,
    String name = DataSourceProperties.primaryName,
  }) => DataSourceProperties.fromEnvironment(
    environment,
    prefix: prefix,
    name: name,
  ).connectionSettings(driver).properties;

  for (final form in _forms) {
    group('as ${form.name}', () {
      test('the PostgreSQL settings of the primary data source', () {
        final environment = form.make({
          'spring.datasource.url': url,
          'spring.datasource.postgresql.sslmode': 'verify-full',
          'spring.datasource.postgresql.ssl-root-cert': '/etc/ca.pem',
          'spring.datasource.postgresql.connect-timeout': '3s',
          'spring.datasource.postgresql.application-name': 'books',
          'spring.datasource.postgresql.search-path': 'shop',
        });
        expect(read(environment, postgres), {
          'sslmode': 'verify-full',
          'ssl-root-cert': '/etc/ca.pem',
          'connect-timeout': '3s',
          'application-name': 'books',
          'search-path': 'shop',
        });
      });

      test('the SQLite settings of the primary data source', () {
        final environment = form.make({
          'spring.datasource.url': 'sqlite:file:books.db',
          'spring.datasource.sqlite.base-directory': '/data',
          'spring.datasource.sqlite.isolate': 'true',
          'spring.datasource.sqlite.busy-timeout': '1500',
        });
        expect(read(environment, sqlite), {
          'base-directory': '/data',
          'isolate': 'true',
          'busy-timeout': '1500',
        });
      });

      test('the settings of a named data source', () {
        final environment = form.make({
          'spring.datasource.url': url,
          'spring.datasource.postgresql.sslmode': 'disable',
          'spring.datasources.shop.url': url,
          'spring.datasources.shop.postgresql.sslmode': 'verify-full',
          'spring.datasources.audit.url': 'sqlite:file:audit.db',
          'spring.datasources.audit.sqlite.busy-timeout': '250',
          'spring.datasources.audit.sqlite.isolate': 'false',
        });
        expect(
          read(
            environment,
            postgres,
            prefix: DataSourceProperties.prefixOf('shop'),
            name: 'shop',
          ),
          {'sslmode': 'verify-full'},
        );
        expect(read(environment, postgres), {'sslmode': 'disable'});
        expect(
          read(
            environment,
            sqlite,
            prefix: DataSourceProperties.prefixOf('audit'),
            name: 'audit',
          ),
          {'busy-timeout': '250', 'isolate': 'false'},
        );
      });

      test('sslmode=verify-full reaches the connection', () async {
        final environment = form.make({
          'spring.datasource.url': url,
          'spring.datasource.postgresql.sslmode': 'verify-full',
        });
        final binding = FakeBinding();
        final driver = PostgresJdbcDriver(binding);
        final properties = DataSourceProperties.fromEnvironment(environment);
        await driver.connect(properties.connectionSettings(driver));
        expect(binding.endpoints.single.sslMode, PostgresSslMode.verifyFull);
      });
    });
  }

  group('unknown settings are still refused by the driver', () {
    test('as an argument, a file and a variable', () {
      for (final environment in [
        _environment(const {
          'spring.datasource.url': url,
          'spring.datasource.postgresql.sslmod': 'require',
        }, variables: const {}),
        _environment(const {
          'spring.datasource.url': url,
          'spring.datasource.postgresql.bogusSetting': 'x',
        }, variables: const {}),
        _environment(
          const {},
          variables: const {
            'SPRING_DATASOURCE_URL': url,
            'SPRING_DATASOURCE_POSTGRESQL_BOGUS': 'x',
          },
        ),
      ]) {
        final properties = read(environment, postgres);
        expect(properties, hasLength(1));
        expect(
          () => PostgresTarget.parse(
            ConnectionSettings(url: Uri.parse(url), properties: properties),
          ),
          throwsArgumentError,
        );
      }
    });

    test('a name the driver knows is never reported as unknown', () {
      final environment = _environment(const {
        'spring.datasource.url': url,
        'spring.datasource.postgresql.sslMode': 'require',
      }, variables: const {});
      expect(read(environment, postgres), {'sslmode': 'require'});
    });
  });

  group('a URL as it is logged', () {
    String safe(String url) => ConnectionSettings(url: Uri.parse(url)).safeUrl;

    test('the password of the user info is dropped', () {
      expect(
        safe('postgresql://app:hunter2@db:5432/books'),
        'postgresql://app@db:5432/books',
      );
    });

    test('the value of a query parameter with a secret name is masked', () {
      expect(
        safe('postgresql://db:5432/books?user=app&password=PW-S3cret'),
        'postgresql://db:5432/books?user=app&password=******',
      );
      expect(
        safe(
          'postgresql://db/books?sslmode=require&sslPassword=a%20b'
          '&api_token=t0k&secretKey=k&Password=x&application_name=shop',
        ),
        'postgresql://db/books?sslmode=require&sslPassword=******'
        '&api_token=******&secretKey=******&Password=******'
        '&application_name=shop',
      );
      // Escapes are read as the driver reads them; a parameter without a
      // value has nothing to hide; a word that only contains one is no
      // secret (`monkey`).
      expect(
        safe('postgresql://db/books?client%2Dsecret=x&token&monkey=1'),
        'postgresql://db/books?client-secret=******&token&monkey=1',
      );
    });

    test('a URL without a secret is unchanged', () {
      expect(
        safe('postgresql://db:5432/books?sslmode=require&connect_timeout=3'),
        'postgresql://db:5432/books?sslmode=require&connect_timeout=3',
      );
      expect(
        safe('sqlite:file:books.db?mode=ro'),
        'sqlite:file:books.db?mode=ro',
      );
      expect(safe('sqlite::memory:'), 'sqlite::memory:');
    });

    test('a secret in the user info and in the query', () {
      expect(
        safe('postgresql://app:one@db/books?password=two'),
        'postgresql://app@db/books?password=******',
      );
    });

    test('the pool never logs it, nor does a message or toString', () async {
      SpringLog.level = SpringLogLevel.trace;
      final records = <SpringLogRecord>[];
      final stop = SpringLog.listen(records.add);
      addTearDown(() {
        stop();
        SpringLog.level = SpringLogLevel.info;
        SpringLog.resetLevels();
      });
      final driver = FakeJdbcDriver();
      final settings = ConnectionSettings(
        url: Uri.parse('postgresql://db/books?user=app&password=PW-S3cret'),
      );
      final pool = PooledDataSource(
        name: 'shop',
        driver: driver,
        settings: settings,
        pool: const PoolSettings(
          minIdle: 1,
          connectionTimeout: Duration(milliseconds: 100),
        ),
      );
      await pool.start();
      driver.connectError = const SqlError('refused', connectionLost: true);
      final failing = PooledDataSource(
        name: 'down',
        driver: driver,
        settings: settings,
        pool: const PoolSettings(
          connectionTimeout: Duration(milliseconds: 100),
        ),
      );
      Object? error;
      try {
        await failing.getConnection();
      } on Object catch (e) {
        error = e;
      }
      await pool.close();
      await failing.close();
      final all = [
        ...records.map((r) => r.message),
        '$error',
        '$pool',
        '$settings',
      ].join('\n');
      expect(all, contains('Starting...'));
      expect(all, contains('password=******'));
      expect(all, isNot(contains('PW-S3cret')));
    });

    test('the URL of a configuration error is masked too', () {
      final environment = _environment(const {
        'spring.datasource.url':
            'oracle://db/books?user=app&password=PW-S3cret',
      }, variables: const {});
      final properties = DataSourceProperties.fromEnvironment(environment);
      expect('$properties', isNot(contains('PW-S3cret')));
      Object? error;
      try {
        properties.selectDriver([postgres]);
      } on DataSourceConfigurationException catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect('$error', isNot(contains('PW-S3cret')));
      expect('$error', contains('password=******'));
    });
  });

  test('no driver settings: nothing passed on', () {
    final environment = _environment(const {
      'spring.datasource.url': url,
      'spring.datasource.pool.max-size': '3',
    }, variables: const {});
    expect(read(environment, postgres), isEmpty);
  });

  test('the fake driver declares no setting', () {
    expect(FakeJdbcDriver().propertyNames, isEmpty);
    expect(postgres.propertyNames, contains('sslmode'));
    expect(
      sqlite.propertyNames,
      unorderedEquals(['base-directory', 'isolate', 'busy-timeout']),
    );
  });
}

final class _NoBinding implements SqliteBinding {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
