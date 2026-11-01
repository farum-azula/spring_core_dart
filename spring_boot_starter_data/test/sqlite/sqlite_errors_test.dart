// The errors of SQLite, provoked for real and translated by the dialect:
// each result code becomes the exception of the starter's hierarchy.
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  connectionModes.forEach(
    (mode, isolate) => group(mode, () => errorsSuite(isolate: isolate)),
  );
}

void errorsSuite({required bool isolate}) {
  late SqliteJdbcDriver driver;
  late Directory temp;
  late JdbcConnection c;

  setUpAll(() async => driver = await startDriver(isolate: isolate));
  setUp(() async {
    temp = newTemp();
    c = await driver.connect(memorySettings());
    await c.execute('''
      CREATE TABLE author (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
      CREATE TABLE book (
        id INTEGER PRIMARY KEY,
        isbn TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        pages INTEGER CHECK (pages > 0),
        author_id INTEGER REFERENCES author (id)
      );
      INSERT INTO author (id, name) VALUES (1, 'Herbert');
      INSERT INTO book (id, isbn, title, pages, author_id)
        VALUES (1, 'A-1', 'Dune', 600, 1);
    ''');
  });
  tearDown(() async {
    await c.close();
    deleteTemp(temp);
  });

  const insert =
      'INSERT INTO book (id, isbn, title, pages, author_id) '
      'VALUES (?, ?, ?, ?, ?)';

  Future<DataAccessException> failing(String sql, [List<Object?>? args]) =>
      translated(() => c.update(sql, args ?? const []), sql: sql);

  test('a duplicate unique value is a DuplicateKeyException', () async {
    final error = await failing(insert, [
      2,
      'A-1',
      'Other',
      10,
      1,
    ]) as DuplicateKeyException;
    expect(error.constraint, 'book.isbn');
    expect(error.sql, insert);
    expect(error.message, contains('UNIQUE constraint failed'));
    // The values are not in the message.
    expect(error.toString(), isNot(contains('Other')));
    final raw = await sqlError(
      () => c.update(insert, [2, 'A-1', 'Other', 10, 1]),
    );
    expect([raw.vendorCode, raw.extendedCode], [19, 2067]);
  });

  test('a duplicate primary key is a DuplicateKeyException', () async {
    final error = await failing(insert, [
      1,
      'B-2',
      'Other',
      10,
      1,
    ]) as DuplicateKeyException;
    expect(error.constraint, 'book.id');
    final raw = await sqlError(
      () => c.update(insert, [1, 'B-2', 'Other', 10, 1]),
    );
    expect(raw.extendedCode, 1555);
  });

  test('a broken foreign key needs foreign_keys ON', () async {
    final error = await failing(insert, [2, 'B-2', 'Other', 10, 99]);
    expect(error, isA<DataIntegrityViolationException>());
    expect(error, isNot(isA<DuplicateKeyException>()));
    expect(error.message, contains('FOREIGN KEY'));
    final raw = await sqlError(
      () => c.update(insert, [2, 'B-2', 'Other', 10, 99]),
    );
    expect(raw.extendedCode, 787);
    // Deleting a referenced row fails the same way.
    expect(
      await failing('DELETE FROM author WHERE id = 1'),
      isA<DataIntegrityViolationException>(),
    );
  });

  test('NOT NULL and CHECK are DataIntegrityViolationExceptions', () async {
    final notNull = await failing(insert, [
      2,
      'B-2',
      null,
      10,
      1,
    ]) as DataIntegrityViolationException;
    expect(notNull, isNot(isA<DuplicateKeyException>()));
    expect(notNull.constraint, 'book.title');
    final check = await failing(insert, [
      2,
      'B-2',
      'Other',
      -5,
      1,
    ]) as DataIntegrityViolationException;
    expect(check, isNot(isA<DuplicateKeyException>()));
    expect(check.message, contains('CHECK constraint failed'));
    final codes = [
      (await sqlError(() => c.update(insert, [2, 'B-2', null, 10, 1])))
          .extendedCode,
      (await sqlError(() => c.update(insert, [2, 'B-2', 'Other', -5, 1])))
          .extendedCode,
    ];
    expect(codes, [1299, 275]);
  });

  test('wrong SQL is a BadSqlGrammarException', () async {
    for (final sql in [
      'SELEC * FROM book',
      'SELECT * FROM nothing_here',
      'SELECT nope FROM book',
      'INSERT INTO book (nope) VALUES (1)',
    ]) {
      final error = await translated(() => c.query(sql), sql: sql);
      expect(error, isA<BadSqlGrammarException>(), reason: sql);
      expect(error.sql, sql);
    }
  });

  test('a lock held by another connection is a CannotAcquireLock', () async {
    final a = await driver.connect(fileSettings(temp, 'busy.db'));
    final b = await driver.connect(
      fileSettings(temp, 'busy.db', properties: {'busy-timeout': '20'}),
    );
    await a.execute('CREATE TABLE t (v INTEGER)');
    await a.begin(lockForWrite: true);
    final error = await translated(
      () => b.update('INSERT INTO t VALUES (1)'),
      sql: 'INSERT INTO t VALUES (1)',
    );
    expect(error, isA<CannotAcquireLockException>());
    expect(error, isA<TransientDataAccessException>());
    await a.rollback();
    await a.close();
    await b.close();
  });

  test('a read-only database refuses a write', () async {
    final writer = await driver.connect(fileSettings(temp, 'ro.db'));
    await writer.execute('CREATE TABLE t (v INTEGER)');
    await writer.close();
    final ro = await driver.connect(
      fileSettings(temp, 'ro.db', query: '?mode=ro'),
    );
    expect(
      await translated(() => ro.update('INSERT INTO t VALUES (1)')),
      isA<InvalidDataAccessResourceUsageException>(),
    );
    await ro.close();
  });

  test('a file that cannot be opened is a resource failure', () async {
    // A directory is not a database file.
    final error = await translated(
      () => driver.connect(
        ConnectionSettings(url: Uri.parse('sqlite:file:${temp.path}')),
      ),
    );
    expect(error, isA<DataAccessResourceFailureException>());
  });

  test('a file that is not a database is a resource failure', () async {
    File('${temp.path}/junk.db').writeAsBytesSync(
      Uint8List.fromList(List.generate(4096, (i) => (i * 7) % 251)),
    );
    final error = await translated(
      () => driver.connect(fileSettings(temp, 'junk.db')),
    );
    expect(error, isA<DataAccessResourceFailureException>());
  });

  test('a failed statement leaves the connection usable', () async {
    await sqlError(() => c.update(insert, [1, 'B-2', 'x', 1, 1]));
    expect(await scalar(c, 'SELECT count(*) FROM book'), 1);
    // And a transaction that failed halfway rolls back.
    await c.begin();
    await c.update(insert, [2, 'B-2', 'Two', 1, 1]);
    await sqlError(() => c.update(insert, [3, 'B-2', 'Three', 1, 1]));
    await c.rollback();
    expect(await scalar(c, 'SELECT count(*) FROM book'), 1);
  });
}
