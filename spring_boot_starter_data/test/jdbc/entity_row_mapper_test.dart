import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/fake_jdbc.dart';
import 'support/people.dart';

// The mapper of the classes a @Query returns: the rules of the
// DataClassRowMapper, through an EntityIntrospection.
void main() {
  JdbcRow row(List<String> columns, List<Object?> values) =>
      JdbcRow(columns, values);

  EntityRowMapper<Person> mapper() => EntityRowMapper<Person>(
    personEntityIntrospection(),
    dialect: FakeDialect(),
  );

  Matcher mappingError(String text) => throwsA(
    isA<MappingException>().having((e) => e.message, 'message', contains(text)),
  );

  test('snake case columns fill camel case parameters, any case', () {
    final p = mapper()(
      row(
        ['FIRST_NAME', 'last_name', 'Age'],
        ['Ada', 'Lovelace', 36],
      ),
    );
    expect((p.firstName, p.lastName, p.age), ('Ada', 'Lovelace', 36));
  });

  test('a column named in camel case matches too', () {
    expect(mapper()(row(['firstName', 'lastName'], ['A', 'B'])).firstName, 'A');
  });

  test('a parameter that cannot be null, without a column, is an error '
      'naming the columns', () {
    expect(
      () => mapper()(row(['first_name'], ['Ada'])),
      mappingError(
        'Person: the constructor requires lastName but the row '
        'has no column for it (columns: first_name)',
      ),
    );
  });

  test('a nullable parameter without a column is null, one with a default '
      'takes it', () {
    final p = mapper()(row(['first_name', 'last_name'], ['A', 'B']));
    expect(p.age, isNull);
    expect(p.status, isNull);
    expect(p.active, isFalse);
  });

  test('a null for a parameter that cannot be null is an error', () {
    expect(
      () => mapper()(row(['first_name', 'last_name'], ['A', null])),
      mappingError('Person.lastName is null but the constructor requires a'),
    );
  });

  test('a null for a nullable parameter is kept', () {
    final p = mapper()(
      row(['first_name', 'last_name', 'age'], ['A', 'B', null]),
    );
    expect(p.age, isNull);
  });

  test('a null for a parameter with a default leaves the default', () {
    final p = mapper()(
      row(['first_name', 'last_name', 'active'], ['A', 'B', null]),
    );
    expect(p.active, isFalse);
  });

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
}
