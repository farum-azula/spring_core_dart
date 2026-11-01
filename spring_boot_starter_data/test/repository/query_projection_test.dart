// The classes a @Query returns that are not entities: the build describes
// them (an EntityIntrospection in the mapping context), and the rows are
// mapped through that description. A class that is only @Introspected is
// still mapped through its BeanIntrospection.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../jdbc/support/people.dart';
import '../mapping/support.dart';
import '../schema/support.dart' show memorySource;

/// A class nothing describes.
class Stranger {
  const Stranger(this.name);
  final String name;
}

QueryMethod findPeople(TypeInfo<Object?> element) => QueryMethod(
  'findPeople',
  const Query(
    'select first_name, last_name, age, nickname from people '
    'where age >= :age order by first_name',
  ),
  parameters: const ['age'],
  element: element,
);

void main() {
  late DataSource db;

  setUp(() async {
    db = await memorySource();
    final jdbc = JdbcTemplate(db);
    await jdbc.execute(
      'create table people (first_name text not null, last_name text not null,'
      ' age integer, nickname text)',
    );
    await jdbc.update(
      "insert into people values ('Ada', 'Lovelace', 36, 'Countess')",
    );
    await jdbc.update("insert into people values ('Alan', 'Turing', 41, null)");
    await jdbc.update("insert into people values ('Zed', 'Young', 20, 'Z')");
  });

  RepositoryOperations<Book, int> operationsFor(
    QueryMethod method, {
    List<EntityIntrospection<Object>> described = const [],
    BeanIntrospector? introspector,
  }) =>
      RepositoryFactory(
        mappingContext: RelationalMappingContext(
          introspections: [
            bookIntrospection(),
            authorIntrospection(),
            ...described,
          ],
        ),
        converter: EntityConverter(introspector: introspector),
        jdbcDataSources: {RepositoryFactory.primaryDataSource: db},
      ).operations<Book, int>(
        'PeopleRepository',
        annotations: const [UseStore('jdbc')],
        queries: [method],
      );

  const people = ClassType<Person>();

  Future<List<T>> run<T>(
    RepositoryOperations<Book, int> operations,
    QueryMethod method,
    int age,
  ) => operations.query<List<T>>(method, [age]);

  test(
    'a class the build described is mapped through its description',
    () async {
      final method = findPeople(people);
      final operations = operationsFor(
        method,
        described: [personEntityIntrospection()],
      );
      final found = await run<Person>(operations, method, 30);
      expect(found.map((p) => (p.firstName, p.lastName, p.age)), [
        ('Ada', 'Lovelace', 36),
        ('Alan', 'Turing', 41),
      ]);
      // A settable property the constructor does not take is set as well.
      expect(found.map((p) => p.nickname), ['Countess', null]);
    },
  );

  test(
    'a class that is only @Introspected keeps its BeanIntrospection',
    () async {
      final method = findPeople(people);
      final operations = operationsFor(
        method,
        introspector: peopleIntrospector(),
      );
      final found = await run<Person>(operations, method, 30);
      expect(found.map((p) => p.firstName), ['Ada', 'Alan']);
      expect(found.map((p) => p.nickname), ['Countess', null]);
    },
  );

  test('the description wins over a BeanIntrospection', () async {
    // A description that shouts the first name, to tell the two apart.
    final base = personEntityIntrospection();
    final shouting = EntityIntrospection<Person>(
      'Person',
      base.properties,
      get: base.valueAt,
      create: (v) =>
          base.create([(v[0]! as String).toUpperCase(), ...v.skip(1)]),
      write: base.write,
    );
    final method = findPeople(people);
    final operations = operationsFor(
      method,
      described: [shouting],
      introspector: peopleIntrospector(),
    );
    final found = await run<Person>(operations, method, 30);
    expect(found.map((p) => p.firstName), ['ADA', 'ALAN']);
  });

  test('a class nobody describes stops the start, naming the way out', () {
    final method = findPeople(const ClassType<Stranger>());
    expect(
      () => operationsFor(method),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Stranger cannot be built from rows'),
            contains('@Introspected'),
          ),
        ),
      ),
    );
  });
}
