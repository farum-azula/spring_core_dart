// A PostgresBinding that records what the driver asks and answers from a
// script: the driver's logic (URLs, TLS fallback, transactions, markers,
// errors) is tested without a server.
//
// The scripts throw SqlErrors and plain objects on purpose.
// ignore_for_file: only_throw_errors
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

/// One statement the fake session ran.
typedef Ran = ({
  String sql,
  List<Object?> parameters,
  bool simple,
  Duration? timeout,
});

/// The answer to a statement, or an error to throw.
typedef Answer = PostgresResult Function(Ran ran);

PostgresResult noRows([int affected = 0]) =>
    PostgresResult(const [], const [], affected);

/// A session that records its statements and answers with [answer].
class FakeSession implements PostgresSession {
  FakeSession(this.endpoint, {this.answer});

  final PostgresEndpoint endpoint;
  Answer? answer;

  final ran = <Ran>[];
  bool closed = false;
  bool open = true;

  /// Rows the next [stream] gives.
  List<PostgresRow> streamRows = const [];
  Object? streamError;
  bool streamCancelled = false;

  @override
  bool get isOpen => open && !closed;

  @override
  Future<PostgresResult> execute(
    String sql, {
    List<Object?> parameters = const [],
    bool simple = false,
    Duration? timeout,
  }) async {
    final statement = (
      sql: sql,
      parameters: parameters,
      simple: simple,
      timeout: timeout,
    );
    ran.add(statement);
    return (answer ?? (_) => noRows())(statement);
  }

  @override
  Stream<PostgresRow> stream(
    String sql, {
    List<Object?> parameters = const [],
    Duration? timeout,
  }) async* {
    ran.add((
      sql: sql,
      parameters: parameters,
      simple: false,
      timeout: timeout,
    ));
    try {
      for (final row in streamRows) {
        yield row;
      }
      if (streamError case final error?) {
        throw error;
      }
    } finally {
      streamCancelled = true;
    }
  }

  @override
  Future<void> close() async => closed = true;

  /// The SQL of the statements run so far.
  List<String> get statements => [for (final r in ran) r.sql];
}

/// A binding whose attempts to open are scripted.
class FakeBinding implements PostgresBinding {
  FakeBinding({this.failures = const []});

  /// The error of the n-th attempt, null to succeed (after the list: succeed).
  final List<Object?> failures;

  final endpoints = <PostgresEndpoint>[];
  final sessions = <FakeSession>[];
  Answer? answer;

  @override
  Future<PostgresSession> open(PostgresEndpoint endpoint) async {
    final attempt = endpoints.length;
    endpoints.add(endpoint);
    if (attempt < failures.length && failures[attempt] != null) {
      throw failures[attempt]!;
    }
    final session = FakeSession(endpoint, answer: answer);
    sessions.add(session);
    return session;
  }
}
