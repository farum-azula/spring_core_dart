import 'dart:async';
import 'dart:isolate';

import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_binding.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_engine.dart';

/// The engine that runs a connection's database on an isolate of its own, so
/// SQLite's synchronous calls (a long query, a busy wait) hold that isolate
/// and not the caller's: the UI isolate of a Flutter app, the event loop of a
/// server.
///
/// The database is opened inside the worker, through the same
/// [SqliteBinding] (it is sent to the isolate, which shares the code of the
/// caller's isolate group: the binding must hold no native resource, and the
/// generated one holds nothing). Each command is a message and each answer
/// another. The values cross as copies; the errors keep their type, and the
/// worker's stack trace comes as text.
///
/// If the worker dies (an uncaught error, a kill), the pending command and
/// every later one fail with a [SqlError] saying so, with `connectionLost`.
final class WorkerSqliteEngine implements SqliteEngine {
  WorkerSqliteEngine._() {
    _port = RawReceivePort(_onMessage, 'sqlite worker replies');
  }

  /// How many rows a stream reads in one message.
  static const streamBatchSize = 100;

  late final RawReceivePort _port;
  late SendPort _commands;
  final _pending = <int, Completer<Object?>>{};
  int _nextId = 1;
  bool _closing = false;
  bool _dead = false;
  String? _crash;

  /// Starts a worker that opens the database of [request] through [binding].
  ///
  /// Throws what the binding throws when it cannot open it.
  static Future<WorkerSqliteEngine> start(
    SqliteBinding binding,
    SqliteOpenRequest request,
  ) async {
    final engine = WorkerSqliteEngine._();
    final ready = engine._expect(_startId);
    try {
      await Isolate.spawn(
        _serve,
        _Start(binding, request, engine._port.sendPort),
        onError: engine._port.sendPort,
        onExit: engine._port.sendPort,
        debugName: 'spring.jdbc.sqlite',
      );
    } on ArgumentError catch (error) {
      engine._port.close();
      throw ArgumentError.value(
        binding,
        'binding',
        'Cannot be sent to the isolate of a SQLite connection (it must hold '
            'no native resource, no port, no open file): $error. Turn '
            'spring.datasource.sqlite.isolate off.',
      );
    } on Object {
      engine._port.close();
      rethrow;
    }
    engine._commands = (await ready.future)! as SendPort;
    return engine;
  }

  @override
  int get fetchSize => streamBatchSize;

  @override
  bool get isBroken => _dead;

  @override
  Future<T> run<T>(SqliteCommand<T> command) async {
    if (_closing) {
      throw const SqlError(
        'The connection is closed',
        connectionLost: true,
      );
    }
    return await _request(command) as T;
  }

  @override
  Future<void> close() async {
    if (_dead || _closing) {
      return;
    }
    _closing = true;
    try {
      await _request(const CloseCommand());
    } on SqlError {
      // The worker died while closing: it is gone, which is what was asked.
      if (!_dead) {
        rethrow;
      }
    } finally {
      _port.close();
    }
  }

  static const _startId = 0;

  Completer<Object?> _expect(int id) {
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _port.keepIsolateAlive = true;
    return completer;
  }

  Future<Object?> _request(SqliteCommand<Object?> command) {
    if (_dead) {
      throw _death();
    }
    final id = _nextId++;
    final reply = _expect(id);
    try {
      _commands.send(_Request(id, command));
    } on ArgumentError catch (error) {
      _forget(id);
      throw ArgumentError(
        'A value of the statement cannot be sent to the isolate of the SQLite '
        'connection (use ints, doubles, Strings, bools, bytes and null): '
        '$error',
      );
    }
    return reply.future;
  }

  void _forget(int id) {
    _pending.remove(id);
    // Idle, the port must not keep the isolate (the process) alive: a
    // connection nobody closed is not a reason to run forever.
    if (_pending.isEmpty) {
      _port.keepIsolateAlive = false;
    }
  }

  void _onMessage(Object? message) {
    switch (message) {
      case _Reply():
        final completer = _pending[message.id];
        _forget(message.id);
        if (message.error case final error?) {
          completer?.completeError(
            error,
            StackTrace.fromString(message.stackTrace ?? ''),
          );
        } else {
          completer?.complete(message.value);
        }
      case null:
        _onExit();
      case _:
        // An uncaught error of the worker; it ends the isolate next.
        _crash = crashText(message) ?? _crash;
    }
  }

  /// The text of [message] when it is an uncaught error the worker's isolate
  /// reports (a list of the error and its stack trace, both as text), else
  /// null. The stack trace is null for some errors: the error counts all the
  /// same.
  static String? crashText(Object? message) => switch (message) {
    [final String error, final String stack] => '$error\n$stack',
    [final String error, null] => error,
    _ => null,
  };

  void _onExit() {
    final pending = [..._pending.values];
    _pending.clear();
    // After a close, the exit is the expected end, unless the worker left
    // without answering.
    if (!_closing || pending.isNotEmpty) {
      _dead = true;
    }
    _port.keepIsolateAlive = false;
    final error = _death();
    for (final completer in pending) {
      completer.completeError(error);
    }
    _port.close();
  }

  SqlError _death() => SqlError(
    'The isolate of the SQLite connection ended'
    '${_crash == null ? '' : ': $_crash'}',
    connectionLost: true,
  );
}

// What the worker needs to start.
final class _Start {
  const _Start(this.binding, this.request, this.replies);

  final SqliteBinding binding;
  final SqliteOpenRequest request;
  final SendPort replies;
}

final class _Request {
  const _Request(this.id, this.command);

  final int id;
  final SqliteCommand<Object?> command;
}

// An answer: the [value] of the command, or the [error] it threw with the
// worker's [stackTrace] as text.
final class _Reply {
  const _Reply.value(this.id, this.value) : error = null, stackTrace = null;

  const _Reply.error(this.id, Object this.error, String this.stackTrace)
    : value = null;

  final int id;
  final Object? value;
  final Object? error;
  final String? stackTrace;

  // The same answer as a SqlError of text, for when the value or the error
  // itself cannot be sent.
  _Reply described() => _Reply.error(
    id,
    SqlError(
      error == null
          ? 'The result of a SQLite command cannot be sent to its caller'
          : '${error.runtimeType}: $error',
    ),
    stackTrace ?? '',
  );
}

// The worker isolate's entry point.
void _serve(_Start start) {
  final SqliteSession session;
  try {
    session = SqliteSession(
      openSqliteDatabase(start.binding, start.request),
    );
  } on Object catch (error, stack) {
    _finish(
      start.replies,
      _Reply.error(WorkerSqliteEngine._startId, error, stack.toString()),
    );
  }
  final commands = ReceivePort('sqlite worker commands');
  start.replies.send(
    _Reply.value(WorkerSqliteEngine._startId, commands.sendPort),
  );
  commands.listen((message) {
    final request = message as _Request;
    _Reply reply;
    try {
      reply = _Reply.value(request.id, request.command.run(session));
    } on Object catch (error, stack) {
      reply = _Reply.error(request.id, error, stack.toString());
    }
    if (session.isClosed) {
      // The close was the last command: answer and end the isolate.
      commands.close();
      _finish(start.replies, reply);
    } else {
      _send(start.replies, reply);
    }
  });
}

void _send(SendPort port, _Reply reply) {
  try {
    port.send(reply);
  } on ArgumentError {
    port.send(reply.described());
  }
}

// Sends the last answer and ends the isolate.
Never _finish(SendPort port, _Reply reply) {
  try {
    Isolate.exit(port, reply);
  } on ArgumentError {
    Isolate.exit(port, reply.described());
  }
}
