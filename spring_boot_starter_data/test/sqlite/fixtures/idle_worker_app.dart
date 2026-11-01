// Opens a connection on a worker isolate, uses it and returns from main
// without closing it: the process must end all the same (an idle connection
// is no reason to keep it alive). The binding is a fake: no native library.
import 'dart:io';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

Future<void> main(List<String> args) async {
  final driver = SqliteJdbcDriver(const _Binding(), isolate: true);
  final connection = await driver.connect(
    ConnectionSettings(url: Uri.parse('sqlite::memory:')),
  );
  final result = await connection.query('SELECT 1');
  stdout.writeln('rows ${result.rows.length}');
  if (args.contains('--close')) {
    await connection.close();
  }
}

final class _Binding implements SqliteBinding {
  const _Binding();

  @override
  SqliteDatabase open(
    String filename, {
    SqliteOpenMode mode = SqliteOpenMode.readWriteCreate,
    bool uri = false,
  }) => _Database();
}

final class _Database implements SqliteDatabase {
  @override
  void execute(String sql, [List<Object?> parameters = const []]) {}

  @override
  ({List<String> columns, List<List<Object?>> rows}) select(
    String sql, [
    List<Object?> parameters = const [],
  ]) => (
    columns: ['one'],
    rows: [
      [1],
    ],
  );

  @override
  SqliteCursor cursor(String sql, [List<Object?> parameters = const []]) =>
      throw UnimplementedError();

  @override
  void createFunction(
    String name,
    int argumentCount,
    Object? Function(List<Object?> arguments) function,
  ) {}

  @override
  int get updatedRows => 0;

  @override
  int get lastInsertRowId => 0;

  @override
  bool get autocommit => true;

  @override
  void close() {}
}
