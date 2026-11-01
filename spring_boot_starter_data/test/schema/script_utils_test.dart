import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

List<String> sqls(String script, {String separator = ';'}) => [
  for (final s in ScriptUtils.splitSqlScript(script, separator: separator))
    s.sql,
];

void main() {
  group('splitSqlScript', () {
    test('splits on the separator and numbers the statements', () {
      final statements = ScriptUtils.splitSqlScript(
        'CREATE TABLE a (x INT);\nINSERT INTO a VALUES (1);\n\n'
        'INSERT INTO a VALUES (2)',
      );
      expect(statements.map((s) => s.sql), [
        'CREATE TABLE a (x INT)',
        'INSERT INTO a VALUES (1)',
        'INSERT INTO a VALUES (2)',
      ]);
      expect(statements.map((s) => s.number), [1, 2, 3]);
      expect(statements.map((s) => s.line), [1, 2, 4]);
    });

    test('skips empty statements and a trailing separator', () {
      expect(sqls(';;SELECT 1;;\n;'), ['SELECT 1']);
      expect(sqls(''), isEmpty);
      expect(sqls('  \n -- only a comment\n'), isEmpty);
    });

    test('drops line comments, also after a statement', () {
      final statements = ScriptUtils.splitSqlScript(
        '-- header\nSELECT 1; -- tail; with a separator\n'
        '-- between\nSELECT 2 -- inside\n + 1;',
      );
      expect(statements.map((s) => s.sql), ['SELECT 1', 'SELECT 2 \n + 1']);
      expect(statements.map((s) => s.line), [2, 4]);
    });

    test('drops block comments, over several lines too', () {
      final statements = ScriptUtils.splitSqlScript(
        '/* header;\n  more; */ SELECT 1;\n'
        'SELECT /* a; b */ 2;\n'
        '/* x */\nSELECT 3;',
      );
      expect(statements.map((s) => s.sql), [
        'SELECT 1',
        'SELECT   2',
        'SELECT 3',
      ]);
      expect(statements.map((s) => s.line), [2, 3, 5]);
    });

    test('a separator inside a string, or an identifier, is kept', () {
      expect(
        sqls(
          "INSERT INTO t VALUES ('a;b', 'it''s; ok');\n"
          'SELECT "we;ird" FROM t;\n'
          'SELECT `x;y` FROM t',
        ),
        [
          "INSERT INTO t VALUES ('a;b', 'it''s; ok')",
          'SELECT "we;ird" FROM t',
          'SELECT `x;y` FROM t',
        ],
      );
    });

    test('comment markers inside a string are not comments', () {
      expect(
        sqls("INSERT INTO t VALUES ('-- not; a comment', '/* nor */');"),
        ["INSERT INTO t VALUES ('-- not; a comment', '/* nor */')"],
      );
    });

    test('a string over several lines counts its lines', () {
      final statements = ScriptUtils.splitSqlScript(
        "INSERT INTO t VALUES ('a\nb;\nc');\nSELECT 1;",
      );
      expect(statements.map((s) => s.line), [1, 4]);
    });

    test('a dollar quote keeps its separators', () {
      const function =
          r'CREATE FUNCTION f() RETURNS int AS $$ BEGIN RETURN 1; END; $$ '
          'LANGUAGE plpgsql';
      expect(
        sqls(
          r'CREATE FUNCTION f() RETURNS int AS $$ BEGIN RETURN 1; END; $$ '
          'LANGUAGE plpgsql; SELECT 1;',
        ),
        [
          function,
          'SELECT 1',
        ],
      );
      expect(
        sqls(r'SELECT $tag$ a; $$ b; $tag$; SELECT 2'),
        [r'SELECT $tag$ a; $$ b; $tag$', 'SELECT 2'],
      );
    });

    test('a SQLite trigger is one statement', () {
      final statements = ScriptUtils.splitSqlScript(
        'CREATE TABLE t (x INT, y INT);\n'
        'CREATE TRIGGER t_ai AFTER INSERT ON t BEGIN\n'
        '  UPDATE t SET y = x * 2 WHERE rowid = new.rowid;\n'
        '  INSERT INTO log VALUES (new.x);\n'
        'END;\n'
        'SELECT 1;',
      );
      expect(statements, hasLength(3));
      expect(statements[1].sql, startsWith('CREATE TRIGGER t_ai'));
      expect(statements[1].sql, endsWith('END'));
      expect(statements[1].sql, contains('INSERT INTO log'));
      expect(statements[2].sql, 'SELECT 1');
      expect(statements.map((s) => s.line), [1, 2, 6]);
    });

    test('a trigger with a CASE and a TEMP trigger stay whole', () {
      final statements = ScriptUtils.splitSqlScript(
        'CREATE TEMP TRIGGER g AFTER UPDATE ON t BEGIN\n'
        '  UPDATE t SET y = CASE WHEN x > 1 THEN 1 ELSE 0 END;\n'
        '  SELECT 1;\n'
        'END;\n'
        'CREATE TABLE after_it (a);',
      );
      expect(statements, hasLength(2));
      expect(statements[0].sql, endsWith('END'));
      expect(statements[1].sql, 'CREATE TABLE after_it (a)');
    });

    test('BEGIN outside a trigger does not swallow separators', () {
      expect(sqls('BEGIN; INSERT INTO t VALUES (1); COMMIT;'), [
        'BEGIN',
        'INSERT INTO t VALUES (1)',
        'COMMIT',
      ]);
    });

    test('another separator, longer than one character too', () {
      expect(sqls('a; b\n/\nc; d\n/', separator: '/'), ['a; b', 'c; d']);
      expect(sqls('one^^^two ^^^ three', separator: '^^^'), [
        'one',
        'two',
        'three',
      ]);
    });

    test('a byte order mark is dropped', () {
      expect(sqls('﻿SELECT 1;'), ['SELECT 1']);
    });

    test('an unterminated quote or comment names the script and line', () {
      expect(
        () => ScriptUtils.splitSqlScript(
          "SELECT 1;\nSELECT 'oops;",
          description: 'schema.sql',
        ),
        throwsA(
          isA<ScriptException>()
              .having((e) => e.line, 'line', 2)
              .having((e) => e.message, 'message', contains('schema.sql')),
        ),
      );
      expect(
        () => ScriptUtils.splitSqlScript('SELECT 1; /* never closed'),
        throwsA(isA<ScriptException>()),
      );
    });
  });

  group('executeSqlScript', () {
    test('runs the statements and counts them', () async {
      final db = await memorySource();
      final count = await using(
        db,
        (c) => ScriptUtils.executeSqlScript(
          c,
          'CREATE TABLE a (x INTEGER);\nINSERT INTO a VALUES (1);\n'
          'INSERT INTO a VALUES (2); -- two\n',
        ),
      );
      expect(count, 3);
      expect(await value(db, 'SELECT sum(x) FROM a'), 3);
    });

    test('a failed statement names the script, number and line', () async {
      final db = await memorySource();
      final error = await failure<ScriptException>(
        () => using(
          db,
          (c) => ScriptUtils.executeSqlScript(
            c,
            'CREATE TABLE a (x INTEGER);\n\n'
            'INSERT INTO nowhere VALUES (1);',
            description: 'class path resource [schema.sql]',
          ),
        ),
      );
      expect(error.statementNumber, 2);
      expect(error.line, 3);
      expect(error.message, contains('schema.sql'));
      expect(error.message, contains('statement #2'));
      expect(error.message, contains('line 3'));
      expect(error.message, contains('no such table'));
      expect(error.message, isNot(contains('INSERT INTO')));
    });

    test('continue-on-error skips the failed statements', () async {
      final db = await memorySource();
      final count = await using(
        db,
        (c) => ScriptUtils.executeSqlScript(
          c,
          'CREATE TABLE a (x INTEGER);\nBROKEN;\nINSERT INTO a VALUES (7);',
          continueOnError: true,
        ),
      );
      expect(count, 2);
      expect(await value(db, 'SELECT x FROM a'), 7);
    });

    test('a trigger script runs on SQLite', () async {
      final db = await memorySource();
      await using(
        db,
        (c) => ScriptUtils.executeSqlScript(
          c,
          'CREATE TABLE t (x INTEGER, y INTEGER);\n'
          'CREATE TRIGGER t_ai AFTER INSERT ON t BEGIN\n'
          '  UPDATE t SET y = new.x * 2 WHERE rowid = new.rowid;\n'
          'END;\n'
          'INSERT INTO t (x) VALUES (21);',
        ),
      );
      expect(await value(db, 'SELECT y FROM t'), 42);
    });
  });
}
