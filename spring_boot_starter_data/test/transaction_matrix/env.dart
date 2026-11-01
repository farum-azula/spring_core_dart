// The SQL of the schema and the seed stays on one line each.
// ignore_for_file: lines_longer_than_80_chars
// The world of the transaction matrix scenarios: a PostgreSQL database of
// their own, a pool, the transaction manager, the helpers that turn what
// happens into the normalized outcome the Spring reference
// (tool/data_reference) prints too, and the two-transaction `Session`.
//
// Values of an outcome are numbers, strings and lists of them. An error
// becomes the string `!ClassName[SQLSTATE]` (the state when a driver error
// is behind it): Spring's exception classes have the starter's names.
import 'dart:async';
import 'dart:math';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import '../postgres/support.dart' as pg;
import '../repository/jdbc/support.dart';

/// One scenario's outcome.
typedef Outcome = Map<String, Object?>;

/// The DDL of the matrix tables (`accounts` and `stock` come with the
/// application of the repository tests).
const matrixSchema = [
  'create table wallets (id bigint primary key, owner text not null, balance bigint not null)',
  'create table doctors (name text primary key, on_call boolean not null)',
  'create table counters (id bigint primary key, value bigint not null)',
  'create table log (id bigint generated always as identity primary key, who text not null)',
];

/// What the scenarios start from.
const matrixSeed = [
  'truncate wallets, doctors, counters, log, accounts, stock',
  "insert into wallets values (1, 'ada', 100), (2, 'bob', 50)",
  "insert into doctors values ('alice', true), ('bob', true)",
  'insert into counters values (1, 0)',
  "insert into stock (id, sku, quantity) values (1, 'a', 5), (2, 'b', 1), (3, 'c', 9)",
  "insert into accounts values ('acc-1', 'ada', 1)",
];

/// The error of a scenario as its outcome string.
String kindOf(Object error) {
  final name = error.runtimeType.toString();
  final state = _sqlState(error);
  return state == null ? name : '$name[$state]';
}

String? _sqlState(Object? error) {
  for (var e = error, depth = 0; e != null && depth < 8; depth++) {
    if (e is SqlError) {
      return e.sqlState;
    }
    e = switch (e) {
      DataAccessException(:final cause) => cause,
      TransactionException(:final cause) => cause,
      _ => null,
    };
  }
  return null;
}

/// What [action] gives, or its error as `!Kind`.
Future<Object?> attempt(FutureOr<dynamic> Function() action) async {
  try {
    return await action();
  } on Object catch (error) {
    return '!${kindOf(error)}';
  }
}

/// `ok`, or the error of [action] as `!Kind`.
Future<String> completion(FutureOr<dynamic> Function() action) async {
  try {
    await action();
    return 'ok';
  } on Object catch (error) {
    return '!${kindOf(error)}';
  }
}

/// The environment of a run: the application's data source on a database of
/// its own, a template, the manager and the repositories.
final class Env {
  Env._(this.kit);

  final Jdbc kit;

  JdbcTemplate get jdbc => kit.jdbc;

  /// A template whose statements stop after [timeout].
  JdbcTemplate jdbcWithTimeout(Duration timeout) =>
      JdbcTemplate(kit.dataSource, queryTimeout: timeout);

  DataSourceTransactionManager get manager => kit.transactions;

  /// Puts the tables back to the seed.
  Future<void> reset() async {
    for (final statement in matrixSeed) {
      await jdbc.execute(statement);
    }
  }

  /// The first column of the first row of [sql].
  Future<T> scalar<T>(String sql, [List<Object?> params = const []]) =>
      jdbc.queryForObject<T>(sql, params);

  /// The `who` of the log, sorted: what the transactions committed.
  Future<List<String>> logRows() =>
      jdbc.queryForList<String>('select who from log order by who');

  /// The `xid` of the running transaction, or `none` outside one (two
  /// calls give two transaction ids when each is its own).
  Future<String> txState() async {
    final first = await scalar<int>('select txid_current()');
    final second = await scalar<int>('select txid_current()');
    return first == second ? '$first' : 'none';
  }

  /// Waits until at least [count] backends wait for a lock in this
  /// database; false when nobody does within five seconds.
  Future<bool> awaitBlocked([int count = 1]) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final blocked = await scalar<int>(
        'select count(*) from pg_stat_activity '
        "where datname = current_database() and wait_event_type = 'Lock'",
      );
      if (blocked >= count) {
        return true;
      }
      if (DateTime.now().isAfter(deadline)) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}

/// Starts the application on a new database of the server of
/// SPRING_TEST_POSTGRES_URL, calls [body], and drops the database.
Future<void> withEnv(Future<void> Function(Env env) body) async {
  final name = 'matrix_${Random().nextInt(1 << 32).toRadixString(36)}';
  final admin = await pg.connectWith(pg.serverSettings());
  await admin.execute('CREATE DATABASE "$name"');
  try {
    final settings = ConnectionSettings(
      url: Uri.parse(pg.postgresUrl!).replace(path: '/$name'),
    );
    await withJdbc(postgres: true, postgresSettings: settings, connections: 8, (
      kit,
    ) async {
      for (final statement in matrixSchema) {
        await kit.jdbc.execute(statement);
      }
      await body(Env._(kit));
    });
  } finally {
    try {
      await admin.execute('DROP DATABASE "$name" WITH (FORCE)');
    } finally {
      await admin.close();
    }
  }
}

/// The URL of a database of the server (for the Spring reference): creates
/// it, drops it with the returned function.
Future<(Uri, Future<void> Function())> createDatabase(String prefix) async {
  final name = '${prefix}_${Random().nextInt(1 << 32).toRadixString(36)}';
  final admin = await pg.connectWith(pg.serverSettings());
  await admin.execute('CREATE DATABASE "$name"');
  Future<void> dispose() async {
    try {
      await admin.execute('DROP DATABASE "$name" WITH (FORCE)');
    } finally {
      await admin.close();
    }
  }

  return (Uri.parse(pg.postgresUrl!).replace(path: '/$name'), dispose);
}

class _Command {
  _Command(this.run, {this.end = false, this.commit = true});

  final Future<void> Function() run;
  final bool end;
  final bool commit;
}

/// One transaction driven step by step: [begin] starts it, [run] runs an
/// action in it (the action's value, or its error as `!Kind`), [end]
/// commits or rolls it back and gives the outcome of that (`ok`, or the
/// error of the commit). The actions of one session run in order; two
/// sessions run side by side.
final class Session {
  Session._(this.env);

  final Env env;
  final _queue = StreamController<_Command>();
  late final Future<Object?> _done;

  /// Starts a transaction with [definition] on its own connection.
  static Future<Session> begin(
    Env env, [
    TransactionDefinition definition = TransactionDefinition.defaults,
  ]) async {
    final session = Session._(env);
    final started = Completer<void>();
    session._done = TransactionTemplate(env.manager, definition)
        .execute<void>((status) async {
          started.complete();
          await for (final command in session._queue.stream) {
            if (command.end) {
              if (!command.commit) {
                status.setRollbackOnly();
              }
              return;
            }
            await command.run();
          }
        })
        .then<Object?>(
          (_) => 'ok',
          onError: (Object error) {
            if (!started.isCompleted) {
              started.complete();
            }
            return '!${kindOf(error)}';
          },
        );
    await started.future;
    return session;
  }

  /// Runs [action] in the transaction; completes with its value or `!Kind`.
  /// Not awaiting it lets another session act while it waits for a lock.
  Future<Object?> run(FutureOr<dynamic> Function() action) {
    final result = Completer<Object?>();
    _queue.add(
      _Command(() async {
        result.complete(await attempt(action));
      }),
    );
    return result.future;
  }

  /// Commits (or rolls back) and gives `ok` or the error of the end.
  Future<Object?> end({bool commit = true}) {
    _queue.add(_Command(() async {}, end: true, commit: commit));
    return _done;
  }
}

/// A transaction definition at [isolation].
TransactionDefinition at(Isolation isolation) =>
    TransactionDefinition(isolation: isolation);
