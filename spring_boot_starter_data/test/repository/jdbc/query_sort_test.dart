// What a @Query sorts by when the build and the mapping know nothing of the
// columns of its result (one column, a Map, a row mapper): the name only has
// to be an identifier, it is quoted, and the database decides. QueryMethods
// are written by hand, as the generator writes them.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

String upper(JdbcRow row) => '${row.values.first}'.toUpperCase();

void main() {
  setUpAll(() => SpringLog.handler = (_) {});

  Future<void> run(
    Future<void> Function(
      RepositoryOperations<Book, int> operations,
      Future<List<String>> Function(Future<void> Function()) statements,
    )
    body,
  ) => withJdbc((jdbc) async {
    await seedBooks(jdbc.sqlAuthors, jdbc.sqlBooks);
    Future<List<String>> statements(Future<void> Function() action) async {
      final records = <SpringLogRecord>[];
      SpringLog.setLevel('spring.jdbc.core.JdbcTemplate', SpringLogLevel.debug);
      final stop = SpringLog.listen(records.add);
      try {
        await action();
      } finally {
        stop();
        SpringLog.resetLevels();
      }
      return [
        for (final r in records)
          if (r.loggerName == 'spring.jdbc.core.JdbcTemplate') r.message,
      ];
    }

    await body(
      jdbc.factory.operations<Book, int>(
        'SortRepository',
        annotations: const [UseStore('jdbc')],
        queries: const [_titles, _maps, _mapped],
      ),
      statements,
    );
  });

  test('a single column: the name is quoted, whatever it is called', () {
    return run((operations, statements) async {
      final sql = await statements(() async {
        expect(
          await operations.query<List<String>>(_titles, [
            Sort.by(['title']),
          ]),
          hasLength(8),
        );
        // A name of the select that is no column of the entity: it is a
        // column of this result, which only the database knows.
        expect(
          await operations.query<List<String>>(_titles, [
            Sort.by(['t']),
          ]),
          hasLength(8),
        );
      });
      expect(sql.first, contains('order by "title" ASC NULLS LAST'));
      expect(sql.last, contains('order by "t" ASC NULLS LAST'));
    });
  });

  test('a Map and a row mapper: the same', () {
    return run((operations, statements) async {
      final maps = await operations.query<List<Map<String, Object?>>>(_maps, [
        Sort.byOrders([const SortOrder.desc('n')]),
      ]);
      expect(maps.first['n'], 8);
      final mapped = await operations.query<List<String>>(_mapped, [
        Sort.byOrders([const SortOrder.desc('n')]),
      ]);
      expect(mapped.first, hasLength(greaterThan(0)));
    });
  });

  test("an unknown column is the database's error, a bad name ours", () {
    return run((operations, statements) async {
      await expectLater(
        operations.query<List<String>>(_titles, [
          Sort.by(['nothing']),
        ]),
        throwsA(isA<BadSqlGrammarException>()),
      );
      await expectLater(
        operations.query<List<String>>(_titles, [
          Sort.by(['a b']),
        ]),
        throwsA(isA<PropertyReferenceException>()),
      );
      await expectLater(
        operations.query<List<String>>(_titles, [
          Sort.by(['t; drop']),
        ]),
        throwsA(isA<PropertyReferenceException>()),
      );
    });
  });
}

const _titles = QueryMethod(
  'titles',
  Query('select title as t from books'),
  parameters: ['sort'],
  sort: 0,
  element: ClassType<String>(),
);

const _maps = QueryMethod(
  'maps',
  Query('select id as n from books'),
  parameters: ['sort'],
  sort: 0,
  element: MapType<String, Object?>(ClassType<String>(), DynamicType()),
);

const _mapped = QueryMethod(
  'mapped',
  Query('select title, id as n from books', rowMapper: upper),
  parameters: ['sort'],
  sort: 0,
  element: ClassType<String>(),
);
