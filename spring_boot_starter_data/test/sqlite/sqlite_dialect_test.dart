// SqliteDialect without a database: SQL, column types, affinity rules and
// the translation of every result code.
import 'dart:typed_data';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

enum Color { red }

void main() {
  const dialect = SqliteDialect();

  test('names, quoting, clauses and locking', () {
    expect(dialect.name, 'sqlite');
    expect(dialect.quote('order'), '"order"');
    expect(dialect.quote('a"b'), '"a""b"');
    expect(dialect.table('book', 'main'), '"main"."book"');
    expect(dialect.limitOffset(10, 20), 'LIMIT 10 OFFSET 20');
    expect(dialect.limitOffset(null, 5), 'LIMIT -1 OFFSET 5');
    expect(dialect.lockStrategy, LockStrategy.databaseLock);
    expect(dialect.lockClause(LockMode.pessimisticWrite), isEmpty);
    expect(dialect.supportsSavepoints, isTrue);
    expect(
      dialect.identityColumn(const ClassType<int>()),
      'INTEGER PRIMARY KEY',
    );
  });

  test('column types', () {
    final types = <TypeInfo<Object?>, String?>{
      const ClassType<int>(): 'INTEGER',
      const ClassType<bool>(): 'INTEGER',
      const ClassType<double>(): 'REAL',
      const ClassType<num>(): 'REAL',
      const ClassType<String>(): 'TEXT',
      const EnumType<Color>(Color.values): 'TEXT',
      const ClassType<DateTime>(): 'TEXT',
      const ClassType<BigInt>(): 'TEXT',
      const ClassType<Uint8List>(): 'BLOB',
      const ListType<int>(ClassType<int>()): 'BLOB',
      const ListType<String>(ClassType<String>()): null,
    };
    for (final MapEntry(key: type, value: column) in types.entries) {
      expect(dialect.columnType(type), column, reason: '$type');
    }
  });

  test('columns fit by SQLite affinity', () {
    const integer = ClassType<int>();
    const text = ClassType<String>();
    const real = ClassType<double>();
    const blob = ClassType<Uint8List>();
    expect(dialect.columnFits('INTEGER', integer), isTrue);
    expect(dialect.columnFits('bigint', integer), isTrue);
    expect(dialect.columnFits('INT8', const ClassType<bool>()), isTrue);
    expect(dialect.columnFits('INTEGER', text), isFalse);
    expect(dialect.columnFits('VARCHAR(40)', text), isTrue);
    expect(dialect.columnFits('NCHAR(2)', text), isTrue);
    expect(dialect.columnFits('clob', const ClassType<DateTime>()), isTrue);
    expect(dialect.columnFits('TEXT', integer), isFalse);
    expect(dialect.columnFits('REAL', real), isTrue);
    expect(
      dialect.columnFits('DOUBLE PRECISION', const ClassType<num>()),
      isTrue,
    );
    expect(dialect.columnFits('FLOAT', integer), isFalse);
    expect(dialect.columnFits('NUMERIC', integer), isTrue);
    expect(dialect.columnFits('DECIMAL(10,2)', real), isTrue);
    expect(dialect.columnFits('DECIMAL(10,2)', text), isFalse);
    // No affinity: anything fits.
    expect(dialect.columnFits('BLOB', blob), isTrue);
    expect(dialect.columnFits('', text), isTrue);
    expect(dialect.columnFits('BLOB', integer), isTrue);
    expect(dialect.columnFits('TEXT', blob), isFalse);
    // A type with no column.
    expect(dialect.columnFits('TEXT', const ClassType<Object>()), isFalse);
  });

  test('isolation', () {
    expect(dialect.isolationLevels, {
      Isolation.defaultLevel,
      Isolation.serializable,
    });
  });

  group('translate', () {
    DataAccessException translate(
      int code, {
      int? extended,
      String message = 'oops',
    }) => dialect.translate(
      SqlError(message, vendorCode: code, extendedCode: extended ?? code),
      sql: 'SQL ?',
    );

    test('duplicates', () {
      for (final extended in [1555, 2067]) {
        final error = translate(
          19,
          extended: extended,
          message: 'UNIQUE constraint failed: books.isbn, books.lang',
        );
        expect(error, isA<DuplicateKeyException>());
        expect(
          (error as DuplicateKeyException).constraint,
          'books.isbn, books.lang',
        );
        expect(error.sql, 'SQL ?');
      }
    });

    test('other constraints', () {
      for (final extended in [787, 1299, 275, 19, 2579, 3091]) {
        final error = translate(19, extended: extended);
        expect(error, isA<DataIntegrityViolationException>());
        expect(error, isNot(isA<DuplicateKeyException>()));
      }
      expect(
        (translate(
          19,
          message: 'FOREIGN KEY constraint failed',
        ) as DataIntegrityViolationException).constraint,
        isNull,
      );
    });

    test('the primary code is taken from the extended one when missing', () {
      final error = dialect.translate(
        const SqlError('x', extendedCode: 2067),
      );
      expect(error, isA<DuplicateKeyException>());
    });

    test('locks, timeouts, usage and resources', () {
      expect(translate(5), isA<CannotAcquireLockException>());
      expect(translate(6), isA<CannotAcquireLockException>());
      expect(translate(5, extended: 261), isA<CannotAcquireLockException>());
      expect(translate(9), isA<QueryTimeoutException>());
      expect(translate(8), isA<InvalidDataAccessResourceUsageException>());
      for (final code in [14, 10, 11, 26]) {
        expect(
          translate(code),
          isA<DataAccessResourceFailureException>(),
          reason: '$code',
        );
      }
    });

    test('ERROR is grammar only for its known messages', () {
      for (final message in [
        'no such table: x',
        'no such column: y',
        'near "SELEC": syntax error',
        'table book has no column named z',
        'incomplete input',
      ]) {
        expect(translate(1, message: message), isA<BadSqlGrammarException>());
      }
      expect(
        translate(1, message: 'something else'),
        isA<UncategorizedSqlException>(),
      );
    });

    test('anything else is unknown', () {
      expect(translate(21), isA<UncategorizedSqlException>());
      expect(
        dialect.translate(const SqlError('gone', connectionLost: true)),
        isA<DataAccessResourceFailureException>(),
      );
    });
  });
}
