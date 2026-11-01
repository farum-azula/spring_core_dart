// The worker isolate of SqliteJdbcDriver: what only it does. The driver and
// error suites run in both modes (sqlite_driver_test.dart,
// sqlite_errors_test.dart); here are the isolate's own matters: where the
// database lives, close, streams in batches, a worker that dies.
import 'dart:async';
import 'dart:isolate';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_worker.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late SqliteJdbcDriver generated;
  late _Events events;
  late SqliteJdbcDriver driver;

  setUpAll(() async => generated = await startDriver());
  setUp(() {
    events = _Events();
    driver = SqliteJdbcDriver(
      _SpyBinding(generated.binding, events.sink),
      isolate: true,
    );
  });
  tearDown(() => events.close());

  Future<JdbcConnection> connect([Map<String, String> properties = const {}]) =>
      driver.connect(memorySettings(properties));

  group('where the database lives', () {
    test(
      'the database is opened inside a worker, with its functions',
      () async {
        final c = await connect();
        expect(await scalar(c, "SELECT spring_lower('ÄÖ')"), 'äö');
        final open = events.of('open').single;
        expect(open, isNot(events.caller));
        expect(events.of('function spring_lower'), [open]);
        expect(events.kinds, contains('name spring.jdbc.sqlite'));
        await c.close();
      },
    );

    test('each connection has an isolate of its own', () async {
      final a = await connect();
      final b = await connect();
      final opens = events.of('open');
      expect(opens, hasLength(2));
      expect(opens[0], isNot(opens[1]));
      await a.close();
      await b.close();
    });

    test('the data source property wins over the driver option', () async {
      final inCaller = SqliteJdbcDriver(
        _SpyBinding(generated.binding, events.sink),
      );
      Future<SendPort?> openedIn(
        SqliteJdbcDriver driver,
        Map<String, String> properties,
      ) async {
        final before = events.of('open').length;
        await (await driver.connect(memorySettings(properties))).close();
        await events.until(() => events.of('open').length > before);
        return events.of('open').last;
      }

      expect(await openedIn(inCaller, const {}), events.caller);
      expect(
        await openedIn(inCaller, {SqliteJdbcDriver.isolateProperty: ' True '}),
        isNot(events.caller),
      );
      expect(
        await openedIn(driver, {SqliteJdbcDriver.isolateProperty: 'false'}),
        events.caller,
      );
      expect(await openedIn(driver, const {}), isNot(events.caller));
    });

    test('a wrong isolate property is refused', () {
      expect(
        () => connect({SqliteJdbcDriver.isolateProperty: 'maybe'}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Must be true or false',
          ),
        ),
      );
    });
  });

  group('the point of it', () {
    // The longest the isolate of the test went without running its timers
    // while [wait] ran: a synchronous busy wait of SQLite shows as a gap.
    Future<Duration> longestStall(Future<void> Function() wait) async {
      var last = Stopwatch()..start();
      var longest = Duration.zero;
      final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
        if (last.elapsed > longest) {
          longest = last.elapsed;
        }
        last = Stopwatch()..start();
      });
      try {
        await wait();
        // The first tick after a stall tells how long it was.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } finally {
        ticker.cancel();
      }
      return longest;
    }

    Future<Duration> stallWaitingForALock(SqliteJdbcDriver waiting) async {
      final temp = newTemp();
      final holder = await generated.connect(fileSettings(temp, 'busy.db'));
      await holder.execute('CREATE TABLE t (v INTEGER)');
      await holder.begin(lockForWrite: true);
      final waiter = await waiting.connect(
        fileSettings(temp, 'busy.db', properties: {'busy-timeout': '1000'}),
      );
      final stall = await longestStall(() async {
        final busy = await sqlError(() => waiter.begin(lockForWrite: true));
        expect(busy.vendorCode, 5);
      });
      await holder.rollback();
      await holder.close();
      await waiter.close();
      deleteTemp(temp);
      return stall;
    }

    test(
      'a busy wait holds the isolate of the caller only without it',
      () async {
        final inCaller = SqliteJdbcDriver(generated.binding);
        expect(
          await stallWaitingForALock(inCaller),
          greaterThan(const Duration(milliseconds: 800)),
        );
        expect(
          await stallWaitingForALock(driver),
          lessThan(const Duration(milliseconds: 500)),
        );
      },
    );
  });

  group('close', () {
    test('closes the database and ends the isolate', () async {
      final c = await connect();
      await c.execute('CREATE TABLE t (v INTEGER)');
      await c.close();
      await events.until(() => events.of('exit').isNotEmpty);
      expect(events.kinds, containsAllInOrder(['open', 'closed', 'exit']));
      expect(events.of('exit'), hasLength(1));
      expect(c.isClosed, isTrue);
      // Closing again does nothing; the connection is lost, not hanging.
      await c.close();
      final error = await sqlError(() => c.query('SELECT 1'));
      expect(error.connectionLost, isTrue);
      expect(await c.isValid(), isFalse);
    });

    test(
      'a failed open ends the isolate and throws the binding error',
      () async {
        final error = await sqlError(
          () => driver.connect(
            fileSettings(newTemp(), 'missing.db', query: '?mode=ro'),
          ),
        );
        expect(error.message, contains('unable to open database file'));
        await events.until(() => events.of('exit').isNotEmpty);
      },
    );
  });

  group('streams', () {
    Future<JdbcConnection> numbers(int count) async {
      final c = await connect();
      await c.execute('CREATE TABLE n (i INTEGER)');
      await c.batchUpdate('INSERT INTO n VALUES (?)', [
        for (var i = 1; i <= count; i++) [i],
      ]);
      return c;
    }

    test('rows come in order whatever the number of batches', () async {
      const size = WorkerSqliteEngine.streamBatchSize;
      for (final count in [0, 1, size - 1, size, size + 1, 2 * size, 250]) {
        final c = await numbers(count);
        final rows = await c.queryStream('SELECT i FROM n ORDER BY i').toList();
        expect(rows.map((row) => row['i']), [
          for (var i = 1; i <= count; i++) i,
        ], reason: '$count rows');
        expect(rows.firstOrNull?.columns ?? ['i'], ['i']);
        await c.close();
      }
    });

    test(
      'a cancelled stream closes its cursor and frees the connection',
      () async {
        final c = await numbers(250);
        final first = await c
            .queryStream('SELECT i FROM n ORDER BY i')
            .take(3)
            .toList();
        expect(first.map((row) => row['i']), [1, 2, 3]);
        // The worker read one batch, not the whole table.
        expect(
          events.cursors.single,
          lessThanOrEqualTo(WorkerSqliteEngine.streamBatchSize),
        );
        expect(await scalar(c, 'SELECT count(*) FROM n'), 250);
        await c.close();
      },
    );

    test(
      'a stream that fails closes its cursor and frees the connection',
      () async {
        final c = await numbers(3);
        final error = await sqlError(
          () => c.queryStream('SELECT * FROM missing').toList(),
        );
        expect(error.message, contains('no such table'));
        expect(await scalar(c, 'SELECT count(*) FROM n'), 3);
        await c.close();
      },
    );
  });

  group('calls', () {
    test('run one after the other, in the order they were asked', () async {
      final c = await connect();
      await c.execute('CREATE TABLE n (i INTEGER)');
      final results = await Future.wait<Object?>([
        c.begin(),
        for (var i = 1; i <= 30; i++)
          c.update('INSERT INTO n VALUES (?)', [i], true),
        c.savepoint('s'),
        c.update('INSERT INTO n VALUES (100)'),
        c.rollbackToSavepoint('s'),
        c.releaseSavepoint('s'),
        c.query('SELECT count(*) AS c FROM n'),
        c.commit(),
        c.query('SELECT group_concat(i) AS list FROM n'),
      ]);
      expect(
        [
          for (final result in results.skip(1).take(30))
            (result! as JdbcUpdate).generatedKey,
        ],
        [for (var i = 1; i <= 30; i++) i],
      );
      expect((results[35]! as JdbcResult).rows.single['c'], 30);
      expect(
        (results[37]! as JdbcResult).rows.single['list'],
        [for (var i = 1; i <= 30; i++) i].join(','),
      );
      await c.close();
    });

    test('a stream holds the connection until it is done', () async {
      final c = await connect();
      await c.execute('CREATE TABLE n (i INTEGER)');
      await c.batchUpdate('INSERT INTO n VALUES (?)', [
        for (var i = 1; i <= 250; i++) [i],
      ]);
      final order = <String>[];
      final streamed = c
          .queryStream('SELECT i FROM n ORDER BY i')
          .length
          .then((rows) => order.add('stream $rows'));
      // Asked once the stream is under way.
      await Future<void>.delayed(Duration.zero);
      final deleted = c
          .update('DELETE FROM n')
          .then((result) => order.add('delete ${result.affectedRows}'));
      await Future.wait([streamed, deleted]);
      expect(order, ['stream 250', 'delete 250']);
      await c.close();
    });
  });

  group('errors', () {
    test('keep their type and message, with the stack of the worker', () async {
      final c = await connect();
      Object? caught;
      StackTrace? stack;
      try {
        await c.execute('ARGERR');
      } on Object catch (error, trace) {
        caught = error;
        stack = trace;
      }
      expect(
        caught,
        isA<ArgumentError>().having((e) => e.message, 'message', 'bad value'),
      );
      expect(stack.toString(), contains('_SpyDatabase.execute'));

      final raw = await sqlError(() => c.update('INSERT INTO nope VALUES (1)'));
      expect(raw.message, contains('no such table'));
      expect([raw.vendorCode, raw.extendedCode], [1, 1]);
      // Not broken by them.
      expect(await scalar(c, 'SELECT 1'), 1);
      await c.close();
    });

    test('that cannot be sent reach the caller as a SqlError', () async {
      final c = await connect();
      final error = await sqlError(() => c.execute('UNSENDABLE'));
      expect(error.message, contains('_Unsendable'));
      expect(await scalar(c, 'SELECT 1'), 1);
      await c.close();
    });

    test(
      'a value that cannot be sent is refused, the connection lives',
      () async {
        final c = await connect();
        await expectLater(
          c.query('SELECT ?', [Completer<void>().future]),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('cannot be sent'),
            ),
          ),
        );
        expect(await scalar(c, 'SELECT 1'), 1);
        await c.close();
      },
    );

    test('a binding that cannot be sent is refused', () async {
      final own = SqliteJdbcDriver(_PortBinding(), isolate: true);
      await expectLater(
        own.connect(memorySettings()),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('Cannot be sent'), contains('isolate')),
          ),
        ),
      );
    });
  });

  group('a worker that dies', () {
    test('fails the pending and the later calls, never hangs', () async {
      final c = await connect();
      await c.execute('CREATE TABLE t (v INTEGER)');
      // The first kills the worker; the others wait for their turn.
      final calls = [
        c.execute('CRASH'),
        c.query('SELECT 1'),
        c.update('INSERT INTO t VALUES (1)'),
      ];
      for (final call in calls) {
        await expectLater(
          call.timeout(const Duration(seconds: 10)),
          throwsA(
            isA<SqlError>()
                .having((e) => e.connectionLost, 'connectionLost', isTrue)
                .having((e) => e.message, 'message', contains('isolate')),
          ),
        );
      }
      expect(c.isClosed, isTrue);
      expect(await c.isValid(), isFalse);
      final later = await sqlError(() => c.query('SELECT 1'));
      expect(later.connectionLost, isTrue);
      expect(
        const SqliteDialect().translate(later),
        isA<DataAccessResourceFailureException>(),
      );
      // Closing a dead connection is quiet.
      await c.close();
      await c.close();
    });

    test(
      'an uncaught error in the worker is reported in the failure',
      () async {
        final c = await connect();
        await c.execute('BOOM');
        await events.until(() => c.isClosed);
        final error = await sqlError(() => c.query('SELECT 1'));
        expect(error.connectionLost, isTrue);
        expect(error.message, contains('boom'));
        expect(c.isClosed, isTrue);
        await c.close();
      },
    );

    test('an error reported without a stack trace is not dropped', () {
      // The isolate's error listener gets a null stack trace for some errors.
      expect(WorkerSqliteEngine.crashText(['boom', null]), 'boom');
      expect(
        WorkerSqliteEngine.crashText(['boom', '#0 main']),
        'boom\n#0 main',
      );
      expect(WorkerSqliteEngine.crashText('not a report'), isNull);
      expect(WorkerSqliteEngine.crashText(null), isNull);
    });

    test('fails a stream that is open', () async {
      final c = await connect();
      await c.execute('CREATE TABLE n (i INTEGER)');
      await c.batchUpdate('INSERT INTO n VALUES (?)', [
        for (var i = 1; i <= 300; i++) [i],
      ]);
      final seen = <Object?>[];
      // The worker dies reading the second batch.
      final error = await sqlError(
        () => c
            .queryStream('SELECT i FROM n ORDER BY i -- die')
            .forEach((row) => seen.add(row['i'])),
      );
      expect(error.connectionLost, isTrue);
      expect(seen, [for (var i = 1; i <= 100; i++) i]);
      expect(c.isClosed, isTrue);
    });

    test('a pool drops the connection of a dead worker', () async {
      final c = await connect();
      await sqlError(() => c.execute('CRASH'));
      expect(c.isClosed, isTrue);
      final fresh = await connect();
      expect(await scalar(fresh, 'SELECT 1'), 1);
      await fresh.close();
    });
  });
}

// What the worker's code reports, as (kind, control port of the isolate it
// happened in) so that the test can tell the isolates apart; the exit has
// no port.
final class _Events {
  _Events() {
    _port.listen(
      (message) => _log.add(
        message is String ? (message, null) : message as (String, SendPort),
      ),
    );
  }

  final _port = ReceivePort();
  final _log = <(String, SendPort?)>[];

  SendPort get sink => _port.sendPort;

  // The isolate of the test.
  SendPort get caller => Isolate.current.controlPort;

  List<String> get kinds => [for (final (kind, _) in _log) kind];

  // The isolates in which [kind] happened (their control ports).
  List<SendPort?> of(String kind) => [
    for (final (k, isolate) in _log)
      if (k == kind) isolate,
  ];

  // How many rows each closed cursor had read.
  List<int> get cursors => [
    for (final (kind, _) in _log)
      if (kind.startsWith('cursor closed '))
        int.parse(kind.substring('cursor closed '.length)),
  ];

  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Did not happen: $kinds');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void close() => _port.close();
}

// A binding over the real one that tells what happens in the isolate it
// runs in, and misbehaves on demand.
final class _SpyBinding implements SqliteBinding {
  const _SpyBinding(this.inner, this.events);

  final SqliteBinding inner;
  final SendPort events;

  @override
  SqliteDatabase open(
    String filename, {
    SqliteOpenMode mode = SqliteOpenMode.readWriteCreate,
    bool uri = false,
  }) {
    final isolate = Isolate.current;
    events
      ..send(('open', isolate.controlPort))
      ..send(('name ${isolate.debugName}', isolate.controlPort));
    // Only plain values can be the response: no record.
    isolate.addOnExitListener(events, response: 'exit');
    return _SpyDatabase(inner.open(filename, mode: mode, uri: uri), events);
  }
}

final class _SpyDatabase implements SqliteDatabase {
  _SpyDatabase(this._inner, this._events);

  final SqliteDatabase _inner;
  final SendPort _events;

  void _report(String kind) =>
      _events.send((kind, Isolate.current.controlPort));

  @override
  void execute(String sql, [List<Object?> parameters = const []]) {
    switch (sql) {
      case 'CRASH':
        Isolate.exit();
      case 'BOOM':
        unawaited(
          Future<void>.delayed(
            Duration.zero,
            () => throw StateError('boom in the worker'),
          ),
        );
        return;
      case 'ARGERR':
        throw ArgumentError('bad value');
      case 'UNSENDABLE':
        throw _Unsendable(ReceivePort());
    }
    _inner.execute(sql, parameters);
  }

  @override
  ({List<String> columns, List<List<Object?>> rows}) select(
    String sql, [
    List<Object?> parameters = const [],
  ]) => _inner.select(sql, parameters);

  @override
  SqliteCursor cursor(String sql, [List<Object?> parameters = const []]) =>
      _SpyCursor(
        _inner.cursor(sql, parameters),
        _report,
        dieAt: sql.endsWith('-- die') ? 150 : null,
      );

  @override
  void createFunction(
    String name,
    int argumentCount,
    Object? Function(List<Object?> arguments) function,
  ) {
    _report('function $name');
    _inner.createFunction(name, argumentCount, function);
  }

  @override
  int get updatedRows => _inner.updatedRows;

  @override
  int get lastInsertRowId => _inner.lastInsertRowId;

  @override
  bool get autocommit => _inner.autocommit;

  @override
  void close() {
    _report('closed');
    _inner.close();
  }
}

final class _SpyCursor implements SqliteCursor {
  _SpyCursor(this._inner, this._report, {this.dieAt});

  final SqliteCursor _inner;
  final void Function(String kind) _report;
  final int? dieAt;
  int _reads = 0;

  @override
  List<String> get columns => _inner.columns;

  @override
  List<Object?>? next() {
    _reads++;
    if (_reads == dieAt) {
      Isolate.exit();
    }
    return _inner.next();
  }

  @override
  void close() {
    _report('cursor closed $_reads');
    _inner.close();
  }
}

// An exception that cannot cross isolates: it holds a port.
final class _Unsendable implements Exception {
  _Unsendable(this.port);

  final ReceivePort port;
}

// A binding that cannot be sent to another isolate.
final class _PortBinding implements SqliteBinding {
  final port = ReceivePort();

  @override
  SqliteDatabase open(
    String filename, {
    SqliteOpenMode mode = SqliteOpenMode.readWriteCreate,
    bool uri = false,
  }) => throw UnimplementedError();
}
