import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

/// The project's database, played in memory: a `JdbcDriver` in place of
/// the `postgres` one (the bean `postgresJdbcDriver`), whose connections
/// keep what was run on them. No statement is understood: a query answers
/// what [answer] gives (no rows without it), an insert the next id.
///
/// It shows what the server sends to the database, in which order; what
/// the database does with it (the policies, a rollback) is checked against
/// a real project in test/stack_test.dart.
final class FakeDatabase implements JdbcDriver {
  /// Everything run so far, in order: `begin`, `commit`, `rollback`, or
  /// the SQL of a statement.
  final statements = <String>[];

  /// The parameters of each statement of [statements] (empty for the
  /// others).
  final parameters = <List<Object?>>[];

  /// What a query answers.
  JdbcResult? Function(String sql, List<Object?> parameters)? answer;

  int _nextId = 1;

  /// Forgets what was run and the answers.
  void reset() {
    statements.clear();
    parameters.clear();
    answer = null;
  }

  /// The statements that contain [text].
  Iterable<String> containing(String text) =>
      statements.where((statement) => statement.contains(text));

  void _ran(String sql, [List<Object?> values = const []]) {
    statements.add(sql);
    parameters.add(values);
  }

  @override
  String get name => 'postgres';

  @override
  List<String> get schemes => const ['postgresql', 'postgres'];

  @override
  SqlDialect get dialect => const PostgresDialect();

  @override
  List<String> get propertyNames => const ['sslmode'];

  @override
  Future<JdbcConnection> connect(ConnectionSettings settings) async =>
      _FakeConnection(this);
}

final class _FakeConnection implements JdbcConnection {
  _FakeConnection(this._database);

  final FakeDatabase _database;

  @override
  bool isClosed = false;

  @override
  Future<JdbcResult> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    _database._ran(sql, parameters);
    return _database.answer?.call(sql, parameters) ??
        JdbcResult(const [], const []);
  }

  @override
  Stream<JdbcRow> queryStream(
    String sql, [
    List<Object?> parameters = const [],
  ]) async* {
    yield* Stream.fromIterable((await query(sql, parameters)).rows);
  }

  @override
  Future<JdbcUpdate> update(
    String sql, [
    List<Object?> parameters = const [],
    bool returnGeneratedKey = false,
    String? keyColumn,
  ]) async {
    _database._ran(sql, parameters);
    return JdbcUpdate(1, returnGeneratedKey ? _database._nextId++ : null);
  }

  @override
  Future<List<int>> batchUpdate(String sql, List<List<Object?>> batch) async {
    for (final values in batch) {
      _database._ran(sql, values);
    }
    return List.filled(batch.length, 1);
  }

  @override
  Future<void> execute(String sql) async => _database._ran(sql);

  @override
  Future<void> begin({
    Isolation isolation = Isolation.defaultLevel,
    bool readOnly = false,
    bool lockForWrite = false,
  }) async => _database._ran('begin');

  @override
  Future<void> commit() async => _database._ran('commit');

  @override
  Future<void> rollback() async => _database._ran('rollback');

  @override
  Future<void> savepoint(String name) async {}

  @override
  Future<void> rollbackToSavepoint(String name) async {}

  @override
  Future<void> releaseSavepoint(String name) async {}

  @override
  Future<void> setStatementTimeout(Duration? timeout) async {}

  @override
  Future<bool> isValid() async => !isClosed;

  @override
  Future<void> close() async => isClosed = true;
}
