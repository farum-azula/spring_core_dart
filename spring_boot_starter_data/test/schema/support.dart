// What the schema tests share: real SQLite data sources made with the
// driver the generated glue wrote (../sqlite/app), and classpath
// directories holding scripts and migrations.
import 'dart:io';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../sqlite/support.dart';

export '../sqlite/support.dart' show deleteTemp, fileSettings, newTemp, scalar;

/// The driver of the generated glue; the pools of the tests stay quiet.
Future<SqliteJdbcDriver> driver() {
  SpringLog.setLevel(
    'spring.jdbc.datasource',
    SpringLogLevel.warning,
  );
  return startDriver();
}

/// A data source over one private in-memory database: a pool of one
/// connection, so every user sees the same database.
Future<DataSource> memorySource([
  Map<String, String> properties = const {},
]) async {
  final source = PooledDataSource(
    name: 'memory',
    driver: await driver(),
    settings: memorySettings(properties),
    pool: const PoolSettings(maxSize: 1, minIdle: 1),
  );
  addTearDown(source.close);
  return source;
}

/// A data source over the file [name] of [directory]; [busyTimeout] is
/// how long a connection waits for a lock (0: it fails at once, so the
/// single isolate is never blocked).
Future<DataSource> fileSource(
  Directory directory,
  String name, {
  int busyTimeout = 0,
}) async {
  final source = PooledDataSource(
    name: name,
    driver: await driver(),
    settings: fileSettings(
      directory,
      name,
      properties: {'busy-timeout': '$busyTimeout'},
    ),
    pool: const PoolSettings(maxSize: 2),
  );
  addTearDown(source.close);
  return source;
}

/// Runs [action] on a connection of [source].
Future<T> using<T>(
  DataSource source,
  Future<T> Function(JdbcConnection connection) action,
) async {
  final connection = await source.getConnection();
  try {
    return await action(connection);
  } finally {
    await source.releaseConnection(connection);
  }
}

/// The names of the tables of [source], without SQLite's own.
Future<List<String>> tablesOf(DataSource source) =>
    using(source, (c) async => (await source.dialect.listTables(c))!);

/// The value of the first column of the first row of [sql].
Future<Object?> value(DataSource source, String sql) =>
    using(source, (c) => scalar(c, sql));

/// Runs the statement [sql] on [source].
Future<void> run(DataSource source, String sql) =>
    using(source, (c) => c.execute(sql));

/// The rows of [sql] as lists of values.
Future<List<List<Object?>>> rowsOf(DataSource source, String sql) => using(
  source,
  (c) async => [for (final row in (await c.query(sql)).rows) row.values],
);

/// A directory on the classpath holding the [files] (path below the
/// directory to text), removed when the test ends; returns the directory.
Directory classpath(Map<String, String> files) {
  final directory = newTemp();
  for (final MapEntry(:key, :value) in files.entries) {
    File('${directory.path}/$key')
      ..createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  final remove = ClasspathResources.addDirectory(directory.path);
  addTearDown(() {
    remove();
    deleteTemp(directory);
  });
  return directory;
}

/// The log records of [action], as `logger: message` lines.
Future<List<String>> logged(Future<void> Function() action) async {
  final records = <SpringLogRecord>[];
  final stop = SpringLog.listen(records.add);
  try {
    await action();
  } finally {
    stop();
  }
  return [for (final r in records) '${r.loggerName}: ${r.message}'];
}

/// What [action] throws, which the test expects to be a [T].
Future<T> failure<T extends Object>(Future<Object?> Function() action) async {
  try {
    await action();
  } on T catch (error) {
    return error;
  }
  throw StateError('The action did not fail with a $T');
}
