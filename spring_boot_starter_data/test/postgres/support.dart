// What the tests that need a PostgreSQL server share. They run on the server
// the environment variable SPRING_TEST_POSTGRES_URL names (CI's service
// container), or else on a PostgresContainer each test file starts when Docker
// is there, and are skipped without either:
//
//   dart test -t postgres      # starts its own containers
//
//   docker run --rm -d --name spring-pg-test -e POSTGRES_PASSWORD=test \
//     -p 55432:5432 postgres:17
//   SPRING_TEST_POSTGRES_URL=postgresql://postgres:test@localhost:55432/postgres \
//     dart test -t postgres
//
// Each test works in a schema of its own (created for it, dropped with
// everything in it afterwards), so tests that run side by side never see each
// other's tables. The user needs the right to create schemas.
import 'dart:io';
import 'dart:math';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/containers.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/postgres/app/postgres_app.spring.dart';

final String? _environmentUrl = _url(Platform.environment);

String? _url(Map<String, String> environment) {
  final url = environment['SPRING_TEST_POSTGRES_URL'];
  return url == null || url.isEmpty ? null : url;
}

// The URL of the container a file started with [usePostgresServer].
String? _containerUrl;

/// The server the tests run on: SPRING_TEST_POSTGRES_URL, else the container
/// of [usePostgresServer] once it started, else null.
String? get postgresUrl => _environmentUrl ?? _containerUrl;

/// Why the tests that need SPRING_TEST_POSTGRES_URL are skipped, or null when
/// they run. Tests that can start a container use [postgresServerSkip].
final String? postgresSkip = _environmentUrl == null
    ? 'Set SPRING_TEST_POSTGRES_URL (postgresql://user:password@host:port/db) '
          'to run the tests on a PostgreSQL server'
    : null;

/// Why the tests that run on SPRING_TEST_POSTGRES_URL or on a container are
/// skipped, or null when they run: neither the variable nor Docker.
final String? postgresServerSkip =
    _environmentUrl != null || TestContainers.skipReason() == null
    ? null
    : 'Set SPRING_TEST_POSTGRES_URL (postgresql://user:password@host:port/db) '
          'or start Docker, to run the tests on a PostgreSQL server';

/// Starts a PostgreSQL container before the tests of the file or group that
/// calls it, and removes it after them, unless SPRING_TEST_POSTGRES_URL names
/// a server. Call it in `main` or in the group whose `skip:` is
/// [postgresServerSkip]; [postgresUrl] holds the server's URL from then on.
void usePostgresServer() {
  PostgresContainer? container;
  setUpAll(() async {
    if (_environmentUrl != null) {
      return;
    }
    // The image of CI's service container.
    container = PostgresContainer('postgres:17');
    await container!.start();
    _containerUrl = container!.url;
  });
  tearDownAll(() async {
    _containerUrl = null;
    await container?.stop();
  });
}

PostgresJdbcDriver? _driver;

/// The driver of the generated glue (the same for every test).
Future<PostgresJdbcDriver> postgresDriver() async {
  if (_driver case final started?) {
    return started;
  }
  late PostgresJdbcDriver driver;
  await const ApplicationContextRunner()
      .withUserConfiguration($application)
      .runAsync((context) async {
        if (context.startupFailure case final failure?) {
          throw StateError('The application did not start: $failure');
        }
        driver = context.getBean<JdbcDriver>(
          qualifier: 'postgresJdbcDriver',
        ) as PostgresJdbcDriver;
      });
  SpringLog.setLevel('spring.jdbc.datasource', SpringLogLevel.warning);
  return _driver = driver;
}

/// The settings of the server of [postgresUrl], with the extra [query]
/// (`currentSchema=x`) and the driver's [properties].
ConnectionSettings serverSettings({
  String query = '',
  Map<String, String> properties = const {},
}) {
  final url = Uri.parse(postgresUrl!);
  final joined = [
    if (url.query.isNotEmpty) url.query,
    if (query.isNotEmpty) query,
  ].join('&');
  return ConnectionSettings(
    url: url.replace(query: joined),
    properties: properties,
  );
}

/// A connection to the server, closed when the test ends.
Future<JdbcConnection> serverConnection({
  String query = '',
  Map<String, String> properties = const {},
}) async {
  final connection = await (await postgresDriver()).connect(
    serverSettings(query: query, properties: properties),
  );
  addTearDown(connection.close);
  return connection;
}

/// A new schema, dropped with its tables when the test ends; returns its
/// name.
Future<String> newSchema() async {
  final name = 'spring_test_${Random().nextInt(1 << 32).toRadixString(36)}';
  final admin = await (await postgresDriver()).connect(serverSettings());
  await admin.execute('CREATE SCHEMA "$name"');
  addTearDown(() async {
    try {
      await admin.execute('DROP SCHEMA "$name" CASCADE');
    } finally {
      await admin.close();
    }
  });
  return name;
}

/// The settings of a connection whose `search_path` is [schema].
ConnectionSettings schemaSettings(
  String schema, {
  Map<String, String> properties = const {},
}) => serverSettings(query: 'currentSchema=$schema', properties: properties);

/// A pool over [schema], closed when the test ends (before the schema is
/// dropped: the tear downs run in reverse order).
Future<PooledDataSource> postgresSource(
  String schema, {
  int maxSize = 1,
  Map<String, String> properties = const {},
}) async {
  final source = PooledDataSource(
    name: 'postgres',
    driver: await postgresDriver(),
    settings: schemaSettings(schema, properties: properties),
    pool: PoolSettings(
      maxSize: maxSize,
      minIdle: maxSize == 1 ? 1 : 0,
      connectionTimeout: const Duration(seconds: 10),
    ),
  );
  addTearDown(source.close);
  return source;
}

/// A new schema with a pool over it.
Future<PooledDataSource> newPostgresSource({int maxSize = 1}) async {
  final schema = await newSchema();
  final source = await postgresSource(schema, maxSize: maxSize);
  return source;
}

/// Connects with [settings], without closing the connection at the end.
Future<JdbcConnection> connectWith(ConnectionSettings settings) async {
  final driver = await postgresDriver();
  final connection = await driver.connect(settings);
  return connection;
}

/// The value of the first column of the first row of [sql].
Future<Object?> scalar(
  JdbcConnection connection,
  String sql, [
  List<Object?> parameters = const [],
]) async => (await connection.query(sql, parameters)).rows.first.values.first;

/// What [action] throws, which the test expects to be a [SqlError].
Future<SqlError> sqlError(Future<Object?> Function() action) async {
  try {
    await action();
  } on SqlError catch (error) {
    return error;
  }
  throw StateError('The action did not fail');
}

/// The data access exception [action]'s `SqlError` becomes.
Future<DataAccessException> translated(
  Future<Object?> Function() action,
) async => const PostgresDialect().translate(await sqlError(action));
