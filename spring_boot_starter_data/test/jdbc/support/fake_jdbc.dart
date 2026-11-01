// A fake database for the JDBC core: connections that record what they are
// asked and answer from a script, a dialect with simple conversions and
// translations, and a driver that hands the connections out.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

/// A [SqlError] code the fake dialect translates to a duplicate key.
const duplicateKey = SqlError('UNIQUE failed', vendorCode: 19);

/// A statement that does not parse, for the fake dialect.
const badGrammar = SqlError('syntax error', sqlState: '42000');

/// The dialect of the fake: `bool` as 0/1, `DateTime` as ISO text, errors by
/// code.
class FakeDialect extends SqlDialect {
  FakeDialect({
    this.lockStrategy = LockStrategy.rowLocks,
    this.writeLockStatement,
    this.isolationLevels = const {
      Isolation.defaultLevel,
      Isolation.readCommitted,
      Isolation.serializable,
    },
  });

  @override
  String get name => 'fake';

  @override
  final LockStrategy lockStrategy;

  @override
  final String? writeLockStatement;

  @override
  final Set<Isolation> isolationLevels;

  @override
  String lockClause(
    LockMode mode, {
    Duration? timeout,
    bool skipLocked = false,
  }) => '';

  @override
  String identityColumn(TypeInfo<Object?> type) => 'INTEGER PRIMARY KEY';

  @override
  String? columnType(TypeInfo<Object?> type) => 'TEXT';

  @override
  bool columnFits(String declared, TypeInfo<Object?> type) => true;

  @override
  Object? toDatabase(Object? value) => switch (value) {
    final bool b => b ? 1 : 0,
    final DateTime d => d.toUtc().toIso8601String(),
    _ => value,
  };

  @override
  Object? fromDatabase(Object? value, TypeInfo<Object?> type) {
    if (type.type == bool && value is int) {
      return value != 0;
    }
    if (type.type == DateTime && value is String) {
      return DateTime.parse(value);
    }
    return value;
  }

  @override
  DataAccessException translate(SqlError error, {String? sql}) {
    if (error.vendorCode == 19) {
      return DuplicateKeyException(error.message, cause: error, sql: sql);
    }
    if (error.sqlState?.startsWith('42') ?? false) {
      return BadSqlGrammarException(error.message, cause: error, sql: sql);
    }
    if (error.message == 'timeout') {
      return QueryTimeoutException(error.message, cause: error, sql: sql);
    }
    return unknown(error, sql: sql);
  }
}

/// A connection that records its calls in [calls] (one line each) and
/// answers queries from [onQuery].
class FakeJdbcConnection implements JdbcConnection {
  FakeJdbcConnection(this.id, [this.driver]);

  final int id;
  final FakeJdbcDriver? driver;

  /// Every call: `query select 1 [a]`, `begin`, `commit`...
  final calls = <String>[];

  /// The statements run (query, update, execute, batch).
  final statements = <String>[];

  /// The parameters of each statement run, in order.
  final parameters = <List<Object?>>[];

  /// The values given to `setStatementTimeout`.
  final timeouts = <Duration?>[];

  /// The answer to a query; default: an empty result of one column `x`.
  JdbcResult Function(String sql, List<Object?> parameters)? onQuery;

  /// An error to throw for a statement, or null.
  SqlError? Function(String sql)? failOn;

  /// An error for `commit`, `rollback`.
  SqlError? failCommit;
  SqlError? failRollback;

  /// A completer the next statements wait for (to hold a connection busy).
  Future<void>? gate;

  bool valid = true;
  bool _closed = false;
  Future<void> _statementsDone = Future.value();

  JdbcResult rows(List<String> columns, List<List<Object?>> rows) =>
      JdbcResult(columns, rows);

  Future<T> _statement<T>(
    String call,
    String sql,
    List<Object?> params,
    T Function() answer,
  ) {
    calls.add('$call $sql${params.isEmpty ? '' : ' $params'}');
    statements.add(sql);
    parameters.add(params);
    return _serial(() async {
      if (gate case final gate?) {
        await gate;
      }
      if (failOn?.call(sql) case final error?) {
        throw error;
      }
      return answer();
    });
  }

  // Statements run one at a time, in order.
  Future<T> _serial<T>(Future<T> Function() body) {
    final result = _statementsDone.then((_) => body());
    _statementsDone = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<JdbcResult> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) => _statement(
    'query',
    sql,
    parameters,
    () => (onQuery ?? (_, _) => JdbcResult(['x'], []))(sql, parameters),
  );

  @override
  Stream<JdbcRow> queryStream(
    String sql, [
    List<Object?> parameters = const [],
  ]) async* {
    final result = await _statement(
      'stream',
      sql,
      parameters,
      () => (onQuery ?? (_, _) => JdbcResult(['x'], []))(sql, parameters),
    );
    for (final row in result.rows) {
      yield row;
    }
    calls.add('stream done');
  }

  @override
  Future<JdbcUpdate> update(
    String sql, [
    List<Object?> parameters = const [],
    bool returnGeneratedKey = false,
    String? keyColumn,
  ]) => _statement(
    'update',
    sql,
    parameters,
    () => JdbcUpdate(1, returnGeneratedKey ? 42 : null),
  );

  @override
  Future<List<int>> batchUpdate(String sql, List<List<Object?>> batch) =>
      _statement('batch', sql, [
        batch.length,
      ], () => [for (final _ in batch) 1]);

  @override
  Future<void> execute(String sql) =>
      _statement('execute', sql, const [], () {});

  Future<void> _control(String call, [SqlError? error]) {
    calls.add(call);
    return _serial(() async {
      if (error != null) {
        throw error;
      }
    });
  }

  @override
  Future<void> begin({
    Isolation isolation = Isolation.defaultLevel,
    bool readOnly = false,
    bool lockForWrite = false,
  }) => _control(
    'begin${isolation == Isolation.defaultLevel ? '' : ' ${isolation.name}'}'
    '${readOnly ? ' readOnly' : ''}${lockForWrite ? ' lockForWrite' : ''}',
  );

  @override
  Future<void> commit() => _control('commit', failCommit);

  @override
  Future<void> rollback() => _control('rollback', failRollback);

  @override
  Future<void> savepoint(String name) => _control('savepoint $name');

  @override
  Future<void> rollbackToSavepoint(String name) => _control('rollbackTo $name');

  @override
  Future<void> releaseSavepoint(String name) => _control('release $name');

  @override
  Future<void> setStatementTimeout(Duration? timeout) async {
    timeouts.add(timeout);
  }

  @override
  Future<bool> isValid() async {
    calls.add('isValid');
    return valid && !_closed;
  }

  @override
  bool get isClosed => _closed;

  /// Makes the connection break, as a lost connection does.
  void breakNow() => _closed = true;

  @override
  Future<void> close() async {
    calls.add('close');
    _closed = true;
  }
}

/// A driver whose connections are [FakeJdbcConnection]s, in [connections].
class FakeJdbcDriver implements JdbcDriver {
  FakeJdbcDriver({SqlDialect? dialect}) : dialect = dialect ?? FakeDialect();

  @override
  final SqlDialect dialect;

  @override
  String get name => 'fake';

  @override
  List<String> get schemes => const ['fake'];

  /// The connections opened, in order.
  final connections = <FakeJdbcConnection>[];

  /// Called with each new connection, to script it.
  void Function(FakeJdbcConnection connection)? onConnect;

  /// An error `connect` throws, or null.
  SqlError? connectError;

  /// A future `connect` waits for first (a slow database).
  Future<void>? connectGate;

  @override
  Future<JdbcConnection> connect(ConnectionSettings settings) async {
    if (connectGate case final gate?) {
      await gate;
    }
    if (connectError case final error?) {
      throw error;
    }
    final connection = FakeJdbcConnection(connections.length + 1, this);
    onConnect?.call(connection);
    connections.add(connection);
    return connection;
  }
}

/// Settings with a password in the URL and as a field, to check it is never
/// logged.
final secretSettings = ConnectionSettings(
  url: Uri.parse('fake://admin:hunter2@db:5432/shop'),
  password: 'hunter2',
);

PooledDataSource fakePool(
  FakeJdbcDriver driver, {
  PoolSettings pool = const PoolSettings(),
  String name = 'shop',
}) => PooledDataSource(
  name: name,
  driver: driver,
  settings: secretSettings,
  pool: pool,
);
