// SqliteJdbcDriver over the generated glue and the real sqlite3 library:
// statements, parameters, streams, transactions, URLs.
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  connectionModes.forEach(
    (mode, isolate) => group(mode, () => driverSuite(isolate: isolate)),
  );
}

void driverSuite({required bool isolate}) {
  late SqliteJdbcDriver driver;
  late Directory temp;
  const dialect = SqliteDialect();

  setUpAll(() async => driver = await startDriver(isolate: isolate));
  setUp(() => temp = newTemp());
  tearDown(() => deleteTemp(temp));

  Future<JdbcConnection> memory() => driver.connect(memorySettings());

  group('statements', () {
    test('the driver describes itself', () {
      expect(driver.name, 'sqlite3');
      expect(driver.schemes, ['sqlite']);
      expect(driver.dialect.name, 'sqlite');
    });

    test('query, update, generated keys, batch and execute', () async {
      final c = await memory();
      await c.execute(
        'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, year INTEGER); '
        "INSERT INTO book (title, year) VALUES ('Dune', 1965);",
      );
      final insert = await c.update(
        'INSERT INTO book (title, year) VALUES (?, ?)',
        ['Emma', 1815],
        true,
      );
      expect(insert.affectedRows, 1);
      expect(insert.generatedKey, 2);
      expect(
        (await c.update('DELETE FROM book WHERE id = 99')).generatedKey,
        isNull,
      );

      final counts = await c.batchUpdate(
        'INSERT INTO book (title, year) VALUES (?, ?)',
        [
          ['A', 1],
          ['B', 2],
          ['C', 3],
        ],
      );
      expect(counts, [1, 1, 1]);
      expect(
        (await c.update('UPDATE book SET year = year + 1 WHERE year < 10'))
            .affectedRows,
        3,
      );

      final result = await c.query(
        'SELECT id AS key, title FROM book WHERE year > ? ORDER BY id',
        [1000],
      );
      expect(result.columns, ['key', 'title']);
      expect(result.rows.map((row) => row['TITLE']), ['Dune', 'Emma']);
      expect(result.rows.first.values, [1, 'Dune']);
      expect(
        (await c.query('SELECT * FROM book WHERE id < 0')).isEmpty,
        isTrue,
      );
      await c.close();
    });

    test(
      'the same values cannot be written into the SQL: parameters only',
      () async {
        final c = await memory();
        await c.execute('CREATE TABLE t (v TEXT)');
        const nasty = "x'); DROP TABLE t; --";
        await c.update('INSERT INTO t VALUES (?)', [nasty]);
        expect(await scalar(c, 'SELECT v FROM t'), nasty);
        await c.close();
      },
    );

    test('a stream gives the rows one by one and can be cancelled', () async {
      final c = await memory();
      await c.execute('CREATE TABLE n (i INTEGER)');
      await c.batchUpdate('INSERT INTO n VALUES (?)', [
        for (var i = 1; i <= 5; i++) [i],
      ]);
      final all = await c.queryStream('SELECT i FROM n ORDER BY i').toList();
      expect(all.map((row) => row['i']), [1, 2, 3, 4, 5]);
      final first = await c
          .queryStream('SELECT i FROM n ORDER BY i')
          .take(2)
          .toList();
      expect(first.map((row) => row['i']), [1, 2]);
      // The cancelled stream gave the connection back.
      expect(await scalar(c, 'SELECT count(*) FROM n'), 5);
      expect(
        await c.queryStream('SELECT i FROM n WHERE i > 9').toList(),
        isEmpty,
      );
      await c.close();
    });

    test('a failing stream throws its SqlError', () async {
      final c = await memory();
      final error = await sqlError(
        () => c.queryStream('SELECT * FROM missing').toList(),
      );
      expect(error.message, contains('no such table'));
      // Not stuck: the connection still works.
      expect(await scalar(c, 'SELECT 1'), 1);
      await c.close();
    });

    test('statements of one connection never interleave', () async {
      final c = await memory();
      await c.execute('CREATE TABLE n (i INTEGER)');
      await c.batchUpdate('INSERT INTO n VALUES (?)', [
        for (var i = 1; i <= 3; i++) [i],
      ]);
      final events = <String>[];
      Future<void>? update;
      await for (final row in c.queryStream('SELECT i FROM n ORDER BY i')) {
        events.add('row ${row['i']}');
        // Asked while the cursor is open: waits until it is done.
        update ??= c
            .update('INSERT INTO n VALUES (9)')
            .then((_) => events.add('update'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await update;
      expect(events, ['row 1', 'row 2', 'row 3', 'update']);

      final both = await Future.wait([
        c.query('SELECT count(*) FROM n'),
        c.update('INSERT INTO n VALUES (10)'),
        c.query('SELECT count(*) FROM n'),
      ]);
      expect((both[0] as JdbcResult).rows.first.values.first, 4);
      expect((both[2] as JdbcResult).rows.first.values.first, 5);
      await c.close();
    });

    test('a closed connection fails with a lost connection', () async {
      final c = await memory();
      expect(await c.isValid(), isTrue);
      await c.close();
      await c.close();
      expect(c.isClosed, isTrue);
      expect(await c.isValid(), isFalse);
      final error = await sqlError(() => c.query('SELECT 1'));
      expect(error.connectionLost, isTrue);
      expect(
        dialect.translate(error),
        isA<DataAccessResourceFailureException>(),
      );
    });

    test('a statement timeout is accepted and ignored', () async {
      final c = await memory();
      await c.setStatementTimeout(const Duration(milliseconds: 1));
      await c.setStatementTimeout(null);
      expect(await scalar(c, 'SELECT 1'), 1);
      await c.close();
    });
  });

  group('values through the dialect', () {
    test('every type round-trips', () async {
      final c = await memory();
      await c.execute(
        'CREATE TABLE v (id INTEGER PRIMARY KEY, i INTEGER, d REAL, s TEXT, '
        'b INTEGER, at TEXT, big TEXT, bytes BLOB, empty TEXT)',
      );
      final at = DateTime.utc(2026, 3, 1, 10, 30, 15, 123);
      final big = BigInt.parse('123456789012345678901234567890');
      final bytes = Uint8List.fromList([0, 1, 2, 255]);
      await c.update(
        'INSERT INTO v (i, d, s, b, at, big, bytes, empty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          for (final value in [
            42,
            2.5,
            'héllo',
            true,
            at,
            big,
            bytes,
            null,
          ])
            dialect.toDatabase(value),
        ],
      );
      final row = (await c.query('SELECT * FROM v')).rows.single;
      T read<T>(String column, [TypeInfo<Object?>? type]) =>
          dialect.fromDatabase(row[column], type ?? ClassType<T>()) as T;

      expect(read<int>('i'), 42);
      expect(read<double>('d'), 2.5);
      expect(read<String>('s'), 'héllo');
      expect(read<bool>('b'), isTrue);
      expect(read<DateTime>('at'), at);
      expect(read<DateTime>('at').isUtc, isTrue);
      expect(read<BigInt>('big'), big);
      expect(read<Uint8List>('bytes'), bytes);
      expect(
        dialect.fromDatabase(row['empty'], const ClassType<String>()),
        isNull,
      );
      // How they are stored.
      expect(row['b'], 1);
      expect(row['at'], '2026-03-01T10:30:15.123Z');
      expect(row['big'], '123456789012345678901234567890');
      await c.close();
    });

    test('a local DateTime is stored as its UTC instant', () async {
      final local = DateTime(2026, 7, 4, 12);
      expect(
        dialect.toDatabase(local),
        local.toUtc().toIso8601String(),
      );
      expect(dialect.toDatabase(false), 0);
      expect(dialect.toDatabase([1, 2]), isA<Uint8List>());
    });

    test('dates stored as integers or without a zone are read as UTC', () {
      const type = ClassType<DateTime>();
      expect(
        dialect.fromDatabase(1700000000000, type),
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
      final plain = dialect.fromDatabase('2026-03-01 10:00:00', type);
      expect(plain, DateTime.utc(2026, 3, 1, 10));
      expect(dialect.fromDatabase(3, const ClassType<double>()), 3.0);
      expect(dialect.fromDatabase(0, const ClassType<bool>()), isFalse);
    });
  });

  group('transactions', () {
    test('commit makes changes visible to another connection', () async {
      final a = await driver.connect(fileSettings(temp, 'tx.db'));
      final b = await driver.connect(fileSettings(temp, 'tx.db'));
      await a.execute('CREATE TABLE t (v INTEGER)');
      await a.begin();
      await a.update('INSERT INTO t VALUES (1)');
      expect(await scalar(a, 'SELECT count(*) FROM t'), 1);
      expect(await scalar(b, 'SELECT count(*) FROM t'), 0);
      await a.commit();
      expect(await scalar(b, 'SELECT count(*) FROM t'), 1);

      await a.begin(isolation: Isolation.serializable);
      await a.update('INSERT INTO t VALUES (2)');
      await a.rollback();
      expect(await scalar(a, 'SELECT count(*) FROM t'), 1);
      await a.close();
      await b.close();
    });

    test('savepoints roll back part of a transaction', () async {
      final c = await memory();
      await c.execute('CREATE TABLE t (v INTEGER)');
      await c.begin();
      await c.update('INSERT INTO t VALUES (1)');
      await c.savepoint('inner one');
      await c.update('INSERT INTO t VALUES (2)');
      await c.rollbackToSavepoint('inner one');
      await c.update('INSERT INTO t VALUES (3)');
      await c.savepoint('second');
      await c.releaseSavepoint('second');
      await c.commit();
      final values = (await c.query('SELECT v FROM t ORDER BY v')).rows;
      expect(values.map((row) => row['v']), [1, 3]);
      await c.close();
    });

    test('an isolation SQLite lacks is refused, never weakened', () async {
      final c = await memory();
      for (final level in [
        Isolation.readUncommitted,
        Isolation.readCommitted,
        Isolation.repeatableRead,
      ]) {
        await expectLater(
          c.begin(isolation: level),
          throwsA(isA<InvalidIsolationLevelException>()),
        );
      }
      // Nothing was started.
      await c.begin();
      await c.commit();
      expect(dialect.isolationLevels, {
        Isolation.defaultLevel,
        Isolation.serializable,
      });
      await c.close();
    });

    test('a read-only transaction refuses writes, then writes work', () async {
      final c = await memory();
      await c.execute('CREATE TABLE t (v INTEGER)');
      await c.begin(readOnly: true);
      expect(await scalar(c, 'SELECT count(*) FROM t'), 0);
      final error = await sqlError(() => c.update('INSERT INTO t VALUES (1)'));
      expect(error.vendorCode, 8);
      await c.rollback();
      await c.update('INSERT INTO t VALUES (1)');

      await c.begin(readOnly: true);
      await c.commit();
      await c.update('INSERT INTO t VALUES (2)');
      expect(await scalar(c, 'SELECT count(*) FROM t'), 2);
      await c.close();
    });

    test('BEGIN IMMEDIATE takes the write lock at once', () async {
      const slow = {'busy-timeout': '30'};
      final a = await driver.connect(fileSettings(temp, 'lock.db'));
      final b = await driver.connect(
        fileSettings(temp, 'lock.db', properties: slow),
      );
      await a.execute('CREATE TABLE t (v INTEGER)');
      await a.begin(lockForWrite: true);

      // Another writer cannot start; a reader still can (WAL).
      final busy = await sqlError(() => b.begin(lockForWrite: true));
      expect(busy.vendorCode, 5);
      expect(dialect.translate(busy), isA<CannotAcquireLockException>());
      await b.begin();
      expect(await scalar(b, 'SELECT count(*) FROM t'), 0);
      await b.rollback();

      // A failed begin leaves no read-only mode behind.
      await sqlError(() => b.begin(readOnly: true, lockForWrite: true));
      await a.commit();
      await b.update('INSERT INTO t VALUES (1)');
      expect(await scalar(a, 'SELECT count(*) FROM t'), 1);

      // A deferred transaction takes the lock at its first write.
      await a.begin();
      await b.begin();
      await a.update('INSERT INTO t VALUES (2)');
      final late = await sqlError(() => b.update('INSERT INTO t VALUES (3)'));
      expect(late.vendorCode, 5);
      await b.rollback();
      await a.commit();
      await a.close();
      await b.close();
    });

    test('rollback after SQLite rolled back by itself does not fail', () async {
      final c = await memory();
      await c.begin();
      await c.execute('ROLLBACK');
      await c.rollback();
      await c.close();
    });
  });

  group('connect', () {
    test('sets the pragmas', () async {
      final file = await driver.connect(fileSettings(temp, 'p.db'));
      expect(await scalar(file, 'PRAGMA foreign_keys'), 1);
      expect(await scalar(file, 'PRAGMA journal_mode'), 'wal');
      expect(await scalar(file, 'PRAGMA busy_timeout'), 5000);
      await file.close();

      final mem = await driver.connect(
        memorySettings({'busy-timeout': '120'}),
      );
      expect(await scalar(mem, 'PRAGMA foreign_keys'), 1);
      expect(await scalar(mem, 'PRAGMA journal_mode'), 'memory');
      expect(await scalar(mem, 'PRAGMA busy_timeout'), 120);
      await mem.close();
    });

    test(
      'registers spring_lower: every letter folds, null stays null',
      () async {
        final c = await driver.connect(memorySettings());
        // SQLite's own lower() knows ASCII letters only.
        expect(await scalar(c, "SELECT lower('ÄÖ')"), 'ÄÖ');
        expect(
          await scalar(c, "SELECT spring_lower('ÄÖ Straße ÀB')"),
          'äö straße àb',
        );
        expect(await scalar(c, 'SELECT spring_lower(NULL)'), isNull);
        expect(await scalar(c, 'SELECT spring_lower(42)'), 42);
        // The dialect's lower() is the registered function.
        expect(
          await scalar(c, 'SELECT ${const SqliteDialect().lower("'Ä'")}'),
          'ä',
        );
        await c.close();
      },
    );

    test('a wrong busy-timeout is refused', () {
      for (final bad in ['soon', '-1', '']) {
        expect(
          driver.connect(memorySettings({'busy-timeout': bad})),
          throwsArgumentError,
        );
      }
    });

    test('each in-memory connection has its own database', () async {
      final a = await memory();
      final b = await memory();
      await a.execute('CREATE TABLE t (v INTEGER)');
      final error = await sqlError(() => b.query('SELECT * FROM t'));
      expect(error.message, contains('no such table'));
      await a.close();
      await b.close();
    });
  });

  group('URLs', () {
    test('an absolute file path', () async {
      final c = await driver.connect(fileSettings(temp, 'abs.db'));
      await c.execute('CREATE TABLE t (v INTEGER)');
      await c.close();
      expect(File('${temp.path}/abs.db').existsSync(), isTrue);
    });

    test('a relative path is resolved against the base directory', () async {
      final own = SqliteJdbcDriver(
        driver.binding,
        baseDirectory: temp.path,
        isolate: isolate,
      );
      for (final url in ['sqlite:file:rel.db', 'sqlite:other.db']) {
        final c = await own.connect(ConnectionSettings(url: Uri.parse(url)));
        await c.execute('CREATE TABLE t (v INTEGER)');
        await c.close();
      }
      expect(File('${temp.path}/rel.db').existsSync(), isTrue);
      expect(File('${temp.path}/other.db').existsSync(), isTrue);
      // The slash is not doubled.
      own.baseDirectory = '${temp.path}/';
      final c = await own.connect(
        ConnectionSettings(url: Uri.parse('sqlite:file:third.db')),
      );
      await c.close();
      expect(File('${temp.path}/third.db').existsSync(), isTrue);
    });

    test('?mode=ro opens read only; a missing file is not created', () async {
      final writer = await driver.connect(fileSettings(temp, 'ro.db'));
      await writer.execute('CREATE TABLE t (v INTEGER)');
      await writer.close();

      final c = await driver.connect(
        fileSettings(temp, 'ro.db', query: '?mode=ro'),
      );
      expect(await scalar(c, 'SELECT count(*) FROM t'), 0);
      final error = await sqlError(() => c.update('INSERT INTO t VALUES (1)'));
      expect(error.vendorCode, 8);
      expect(
        dialect.translate(error),
        isA<InvalidDataAccessResourceUsageException>(),
      );
      await c.close();

      for (final mode in ['ro', 'rw']) {
        final missing = await translated(
          () => driver.connect(
            fileSettings(temp, 'missing.db', query: '?mode=$mode'),
          ),
        );
        expect(missing, isA<DataAccessResourceFailureException>());
      }
      expect(File('${temp.path}/missing.db').existsSync(), isFalse);
    });

    test('a SQLite URI with other options is passed on', () async {
      final c = await driver.connect(
        fileSettings(temp, 'uri.db', query: '?mode=rwc&nolock=1'),
      );
      await c.execute('CREATE TABLE t (v INTEGER)');
      await c.close();
      expect(File('${temp.path}/uri.db').existsSync(), isTrue);
    });

    test('a memory URI opens a named in-memory database', () async {
      // The sqlite3 package's SQLite is built without shared cache, so two
      // connections do not see one database: keep one connection.
      final url = Uri.parse('sqlite:file:named?mode=memory&cache=shared');
      final c = await driver.connect(ConnectionSettings(url: url));
      await c.execute('CREATE TABLE t (v INTEGER)');
      await c.update('INSERT INTO t VALUES (7)');
      expect(await scalar(c, 'SELECT v FROM t'), 7);
      expect(await scalar(c, 'PRAGMA journal_mode'), 'memory');
      await c.close();
      expect(File('${Directory.current.path}/named').existsSync(), isFalse);
    });

    test('unknown modes and empty URLs are refused', () {
      expect(
        driver.connect(
          ConnectionSettings(url: Uri.parse('sqlite:file:x.db?mode=turbo')),
        ),
        throwsArgumentError,
      );
      expect(
        driver.connect(ConnectionSettings(url: Uri.parse('sqlite:'))),
        throwsArgumentError,
      );
    });

    test('the password is never in the safe URL', () {
      final settings = ConnectionSettings(
        url: Uri.parse('sqlite://admin:hunter2@host/db.sqlite'),
        password: 'hunter2',
      );
      expect(settings.safeUrl, isNot(contains('hunter2')));
      expect(settings.toString(), isNot(contains('hunter2')));
      expect(settings.safeUrl, contains('admin'));
    });
  });
}
