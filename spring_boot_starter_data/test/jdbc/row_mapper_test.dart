import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/fake_jdbc.dart';
import 'support/people.dart';

void main() {
  JdbcRow row(List<String> columns, List<Object?> values) =>
      JdbcRow(columns, values);

  DataClassRowMapper<Person> mapper() => DataClassRowMapper<Person>(
    dialect: FakeDialect(),
    introspector: peopleIntrospector(),
  );

  Matcher mappingError(String text) => throwsA(
    isA<MappingException>().having((e) => e.message, 'message', contains(text)),
  );

  group('DataClassRowMapper', () {
    test('snake case columns fill camel case parameters, any case', () {
      final p = mapper()(
        row(
          ['FIRST_NAME', 'last_name', 'Age'],
          ['Ada', 'Lovelace', 36],
        ),
      );
      expect(p.firstName, 'Ada');
      expect(p.lastName, 'Lovelace');
      expect(p.age, 36);
    });

    test('a column named in camel case matches too', () {
      final p = mapper()(row(['firstName', 'lastName'], ['A', 'B']));
      expect(p.firstName, 'A');
    });

    test('a required parameter without a column is an error naming the '
        'columns', () {
      expect(
        () => mapper()(row(['first_name'], ['Ada'])),
        mappingError('requires lastName'),
      );
      expect(
        () => mapper()(row(['first_name'], ['Ada'])),
        mappingError('columns: first_name'),
      );
    });

    test('an optional parameter without a column keeps its default', () {
      final p = mapper()(row(['first_name', 'last_name'], ['A', 'B']));
      expect(p.age, isNull);
      expect(p.active, isFalse);
    });

    test('a null for a required parameter is an error', () {
      expect(
        () => mapper()(row(['first_name', 'last_name'], ['A', null])),
        mappingError('is null'),
      );
    });

    test('a null for a nullable parameter is kept', () {
      final p = mapper()(
        row(['first_name', 'last_name', 'age'], ['A', 'B', null]),
      );
      expect(p.age, isNull);
    });

    test(
      'a null for an optional non-nullable parameter leaves the default',
      () {
        final p = mapper()(
          row(['first_name', 'last_name', 'active'], ['A', 'B', null]),
        );
        expect(p.active, isFalse);
      },
    );

    test('enums by name, dates and bools through the dialect', () {
      final p = mapper()(
        row(
          ['first_name', 'last_name', 'status', 'joined', 'active'],
          ['A', 'B', 'closed', '2024-05-06T00:00:00.000Z', 1],
        ),
      );
      expect(p.status, Status.closed);
      expect(p.joined, DateTime.utc(2024, 5, 6));
      expect(p.active, isTrue);
    });

    test('an unknown enum constant is a mapping error', () {
      expect(
        () => mapper()(
          row(['first_name', 'last_name', 'status'], ['A', 'B', 'nope']),
        ),
        mappingError('not a constant'),
      );
    });

    test('settable properties outside the constructor are set after', () {
      final p = mapper()(
        row(['first_name', 'last_name', 'nickname'], ['A', 'B', 'Ace']),
      );
      expect(p.nickname, 'Ace');
    });

    test('columns nobody wants are ignored', () {
      final p = mapper()(
        row(['first_name', 'last_name', 'extra'], ['A', 'B', 1]),
      );
      expect(p.firstName, 'A');
    });

    test('works for many rows of a result (the plan is reused)', () {
      final result = JdbcResult(
        ['first_name', 'last_name'],
        [
          ['A', 'B'],
          ['C', 'D'],
        ],
      );
      final m = mapper();
      expect(result.rows.map(m.call).map((p) => p.firstName), ['A', 'C']);
    });

    test('a class that is not introspected is refused with advice', () {
      final m = DataClassRowMapper<Person>(introspector: BeanIntrospector());
      expect(
        () => m(row(['first_name'], ['A'])),
        throwsA(
          isA<InvalidDataAccessApiUsageException>().having(
            (e) => e.message,
            'message',
            contains('not introspected'),
          ),
        ),
      );
    });

    test('an introspection given directly is used', () {
      final m = DataClassRowMapper<Person>(
        introspection: personIntrospection(),
      );
      expect(m(row(['first_name', 'last_name'], ['A', 'B'])).lastName, 'B');
    });
  });

  group('SingleColumnRowMapper', () {
    test('reads and converts the column', () {
      expect(
        SingleColumnRowMapper<double>()(row(['x'], [2])),
        2.0,
      );
      expect(
        SingleColumnRowMapper<bool>(dialect: FakeDialect())(row(['x'], [1])),
        isTrue,
      );
    });

    test('wrong column count and a null', () {
      expect(
        () => SingleColumnRowMapper<int>()(row(['a', 'b'], [1, 2])),
        throwsA(isA<IncorrectResultSetColumnCountException>()),
      );
      expect(SingleColumnRowMapper<int?>()(row(['a'], [null])), isNull);
      expect(
        () => SingleColumnRowMapper<int>()(row(['a'], [null])),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
    });

    test('a value of the wrong kind is a mapping error', () {
      expect(
        () => SingleColumnRowMapper<int>()(row(['a'], ['text'])),
        throwsA(isA<MappingException>()),
      );
    });
  });

  group('ColumnMapRowMapper and row readers', () {
    test('map of label to value', () {
      expect(const ColumnMapRowMapper()(row(['a', 'b'], [1, 'x'])), {
        'a': 1,
        'b': 'x',
      });
    });

    test('typed reads widen; nulls need the OrNull form', () {
      final r = row(
        ['i', 'd', 'b', 't', 's', 'n'],
        [3, 2, 1, '2024-01-01T00:00:00Z', 7, null],
      );
      expect(r.int_('i'), 3);
      expect(r.double_('d'), 2.0);
      expect(r.bool_('b'), isTrue);
      expect(r.dateTime('t'), DateTime.utc(2024));
      expect(r.string('s'), '7');
      expect(r.intOrNull('n'), isNull);
      expect(r.stringOrNull('n'), isNull);
      expect(
        () => r.int_('n'),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
      expect(
        () => r.int_('t'),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
    });
  });

  test('isSimpleType', () {
    expect(isSimpleType<int>(), isTrue);
    expect(isSimpleType<String?>(), isTrue);
    expect(isSimpleType<Status>(), isTrue);
    expect(isSimpleType<DateTime>(), isTrue);
    expect(isSimpleType<Person>(), isFalse);
    expect(isSimpleType<Map<String, Object?>>(), isFalse);
  });
}
