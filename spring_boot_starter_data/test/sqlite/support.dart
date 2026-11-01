// What the SQLite tests share: the driver bean the generator wired into
// app/sqlite_app.spring.dart, and temporary database files.
import 'dart:io';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import 'app/sqlite_app.spring.dart';

/// The `SqliteJdbcDriver` of the started test application; with [isolate],
/// a driver over the same binding whose connections run on worker isolates.
Future<SqliteJdbcDriver> startDriver({bool isolate = false}) async {
  late SqliteJdbcDriver driver;
  await const ApplicationContextRunner()
      .withUserConfiguration($application)
      .runAsync((context) async {
        if (context.startupFailure case final failure?) {
          throw StateError('The application did not start: $failure');
        }
        driver = context.getBean<JdbcDriver>(
          qualifier: 'sqlite3JdbcDriver',
        ) as SqliteJdbcDriver;
      });
  return isolate ? SqliteJdbcDriver(driver.binding, isolate: true) : driver;
}

/// The two ways a connection runs, to give a group each: the suites of the
/// driver run in both.
const connectionModes = {
  'in the isolate of the caller': false,
  'on a worker isolate': true,
};

/// A new empty directory, to delete with [deleteTemp].
Directory newTemp() => Directory.systemTemp.createTempSync('sqlite_test');

/// Deletes [directory] and what it holds.
void deleteTemp(Directory directory) {
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
}

/// The settings for the database file [name] of [directory].
ConnectionSettings fileSettings(
  Directory directory,
  String name, {
  String query = '',
  Map<String, String> properties = const {},
}) => ConnectionSettings(
  url: Uri.parse('sqlite:file:${directory.path}/$name$query'),
  properties: properties,
);

/// The settings for a private in-memory database.
ConnectionSettings memorySettings([
  Map<String, String> properties = const {},
]) => ConnectionSettings(
  url: Uri.parse('sqlite::memory:'),
  properties: properties,
);

/// The `SqlError` [action] throws, which the test expects.
Future<SqlError> sqlError(Future<Object?> Function() action) async {
  try {
    await action();
  } on SqlError catch (error) {
    return error;
  }
  throw StateError('The action did not fail');
}

/// The exception of the dialect that [action]'s `SqlError` becomes.
Future<DataAccessException> translated(
  Future<Object?> Function() action, {
  String? sql,
}) async => const SqliteDialect().translate(await sqlError(action), sql: sql);

/// The first value of the first row of [sql].
Future<Object?> scalar(JdbcConnection connection, String sql) async =>
    (await connection.query(sql)).rows.first.values.first;
