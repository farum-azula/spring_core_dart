import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../../repository/jdbc/support.dart';
import 'row_lock_dialect.dart';

// The SQL of the generator, as text: with a dialect of row locks and a case
// sensitive LIKE (the PostgreSQL way) and with SQLite's.
void main() {
  late PersistentEntity<Book> books;
  late PersistentEntity<Account> accounts;
  late PersistentEntity<PurchaseOrder> orders;
  late SqlGenerator pg;
  late SqlGenerator lite;
  late EntityConverter converter;

  Future<void> run(FutureOr<void> Function() body) => withJdbc((j) async {
    books = j.entity<Book>();
    accounts = j.entity<Account>();
    orders = j.entity<PurchaseOrder>();
    converter = j.factory.converter;
    pg = SqlGenerator(dialect: RowLockDialect(), converter: converter);
    lite = SqlGenerator(dialect: const SqliteDialect(), converter: converter);
    await body();
  });

  Criteria criteria(
    PartType type,
    List<Object?> arguments, {
    String property = 'title',
    bool ignoreCase = false,
  }) => Criteria(
    [
      OrPart([
        Part(property, type, ignoreCase),
      ]),
    ],
    arguments,
  );

  BoundSql where(SqlGenerator generator, Criteria criteria) =>
      generator.select(books, criteria: criteria);

  String condition(BoundSql statement) {
    final sql = statement.sql;
    return sql.substring(sql.indexOf(' where ') + ' where '.length);
  }

  group('writes', () {
    test(
      'insert, update and delete',
      () => run(() async {
        final insert = pg.insert(accounts, {
          'iban': 'DE01',
          'owner': 'Ada',
          'version': 1,
        });
        expect(
          insert.sql,
          'insert into "accounts" ("iban", "owner", "version") '
          'values (?, ?, ?)',
        );
        expect(insert.parameters, ['DE01', 'Ada', 1]);
        expect(
          pg.insert(accounts, const {}).sql,
          'insert into "accounts" default values',
        );

        final update = pg.update(
          accounts,
          {'iban': 'DE01', 'owner': 'Ada L.', 'version': 2},
          id: 'DE01',
          expectedVersion: 1,
        );
        expect(
          update.sql,
          'update "accounts" set "owner" = ?, "version" = ? '
          'where "iban" = ? and "version" = ?',
        );
        expect(update.parameters, ['Ada L.', 2, 'DE01', 1]);

        final plain = pg.update(
          books.introspection.className == 'Book' ? books : books,
          {'id': 3, 'title': 'T'},
          id: 3,
          expectedVersion: 7,
        );
        expect(plain.sql, endsWith('where "id" = ? and "version" = ?'));
        expect(plain.parameters, ['T', 3, 7]);

        expect(
          pg.deleteById(accounts, 'DE01', expectedVersion: 1).sql,
          'delete from "accounts" where "iban" = ? and "version" = ?',
        );
        expect(
          pg.deleteById(accounts, 'DE01').sql,
          'delete from "accounts" where "iban" = ?',
        );
        expect(
          pg.deleteWhere(books, criteria(PartType.isNull, const [])).sql,
          'delete from "books" where ("title" is null)',
        );
        expect(pg.deleteWhere(books, null).sql, 'delete from "books"');
      }),
    );

    test(
      'a table with a schema is qualified',
      () => run(() async {
        final entity = PersistentEntity<Book>(
          introspection: books.introspection,
          tableName: 'books',
          schema: 'shop',
          properties: books.properties,
        );
        expect(pg.table(entity), '"shop"."books"');
        expect(
          pg.selectById(entity, 1).sql,
          startsWith('select '),
        );
        expect(pg.selectById(entity, 1).sql, contains('from "shop"."books"'));
      }),
    );
  });

  group('reads', () {
    test(
      'by id, by ids, with a lock clause',
      () => run(() async {
        expect(
          pg.selectById(accounts, 'DE01').sql,
          'select "iban", "owner", "version" from "accounts" '
          'where "iban" = ?',
        );
        expect(
          pg.selectById(accounts, 'DE01', lock: 'FOR UPDATE SKIP LOCKED').sql,
          endsWith('where "iban" = ? FOR UPDATE SKIP LOCKED'),
        );
        final many = pg.selectByIds(accounts, ['a', 'b', 'c']);
        expect(many.sql, endsWith('where "iban" in (?, ?, ?) order by "iban"'));
        expect(many.parameters, ['a', 'b', 'c']);
      }),
    );

    test(
      'count and exists',
      () => run(() async {
        final c = criteria(PartType.simpleProperty, ['x']);
        expect(
          pg.count(books, c).sql,
          'select count(*) from "books" where ("title" = ?)',
        );
        expect(pg.count(books, null).sql, 'select count(*) from "books"');
        expect(
          pg.exists(books, c).sql,
          'select 1 from "books" where ("title" = ?) LIMIT 1',
        );
      }),
    );

    test(
      'the values carry the column they are bound to (for the logs)',
      () => run(() async {
        List<String> names(BoundSql statement) =>
            (statement.parameters as BoundParameters).names;
        expect(
          names(
            pg.insert(accounts, {'iban': 'DE01', 'owner': 'Ada', 'version': 1}),
          ),
          ['iban', 'owner', 'version'],
        );
        expect(
          names(
            pg.update(
              accounts,
              {'iban': 'DE01', 'owner': 'Ada L.', 'version': 2},
              id: 'DE01',
              expectedVersion: 1,
            ),
          ),
          ['owner', 'version', 'iban', 'version'],
        );
        expect(names(pg.deleteById(accounts, 'DE01')), ['iban']);
        expect(names(pg.selectById(accounts, 'DE01')), ['iban']);
        expect(names(pg.selectByIds(books, [1, 2, 3])), ['id', 'id', 'id']);
        expect(
          names(
            where(
              pg,
              criteria(PartType.between, [1, 5], property: 'year'),
            ),
          ),
          ['year', 'year'],
        );
        expect(
          names(
            where(
              pg,
              criteria(PartType.in_, [
                [1, 2, 3],
              ], property: 'year'),
            ),
          ),
          ['year', 'year', 'year'],
        );
        expect(
          names(where(pg, criteria(PartType.containing, ['x']))),
          ['title'],
        );
        expect(names(pg.count(books, null)), isEmpty);
        // Every marker has a name.
        final statement = where(
          pg,
          criteria(PartType.like, ['a%'], ignoreCase: true),
        );
        expect(
          statement.parameters.length,
          (statement.parameters as BoundParameters).names.length,
        );
      }),
    );

    test(
      'a negative offset is refused, not dropped',
      () => run(() async {
        expect(
          () => pg.select(books, offset: -1),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
        expect(
          () => lite.select(books, offset: -10, limit: 5),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      }),
    );

    test(
      'a sort property that is no column is a PropertyReferenceException with '
      'the name escaped',
      () => run(() async {
        expect(
          () => pg.orderBy(books, Sort.by(['title\r\nINFO forged'])),
          throwsA(
            isA<PropertyReferenceException>()
                .having((e) => e.propertyName, 'propertyName', contains('\r'))
                .having(
                  (e) => e.message,
                  'message',
                  allOf(
                    isNot(contains('\n')),
                    isNot(contains('\r')),
                    contains('"title<EOL><EOL>INFO forged"'),
                  ),
                ),
          ),
        );
      }),
    );

    test(
      'a window: limit and offset by the dialect, id order without a sort',
      () => run(() async {
        final both = pg.select(books, limit: 5, offset: 10);
        expect(both.sql, endsWith('order by "id" ASC LIMIT 5 OFFSET 10'));
        expect(
          pg.select(books, limit: 5).sql,
          endsWith('order by "id" ASC LIMIT 5'),
        );
        expect(pg.select(books).sql, isNot(contains('order by')));
        expect(pg.select(books, offset: 0).sql, isNot(contains('OFFSET')));
        expect(
          pg.select(books, limit: -3).sql,
          endsWith('LIMIT 0'),
        );
        // SQLite has no offset without a limit.
        expect(
          lite.select(books, offset: 4).sql,
          endsWith('order by "id" ASC LIMIT -1 OFFSET 4'),
        );
      }),
    );

    test(
      'distinct only where rows could repeat',
      () => run(() async {
        expect(pg.select(books, distinct: true).sql, startsWith('select "id"'));
      }),
    );

    test(
      'a lock clause after the window',
      () => run(() async {
        final statement = pg.select(
          books,
          limit: 1,
          lock: 'FOR SHARE',
        );
        expect(statement.sql, endsWith('LIMIT 1 FOR SHARE'));
      }),
    );
  });

  group('conditions', () {
    test(
      'comparison with and without ignoring the case',
      () => run(() async {
        expect(
          condition(where(pg, criteria(PartType.simpleProperty, ['a']))),
          '("title" = ?)',
        );
        expect(
          condition(
            where(
              pg,
              criteria(PartType.simpleProperty, ['a'], ignoreCase: true),
            ),
          ),
          '(lower("title") = lower(?))',
        );
        expect(
          condition(
            where(pg, criteria(PartType.negatingSimpleProperty, ['a'])),
          ),
          '("title" <> ?)',
        );
        for (final (type, operator) in [
          (PartType.lessThan, '<'),
          (PartType.lessThanEqual, '<='),
          (PartType.greaterThan, '>'),
          (PartType.greaterThanEqual, '>='),
        ]) {
          expect(
            condition(where(pg, criteria(type, ['a']))),
            '("title" $operator ?)',
          );
        }
        final between = where(pg, criteria(PartType.between, ['a', 'z']));
        expect(condition(between), '("title" between ? and ?)');
        expect(between.parameters, ['a', 'z']);
      }),
    );

    test(
      'null: is null for equality, nothing for the rest',
      () => run(() async {
        expect(
          condition(where(pg, criteria(PartType.simpleProperty, [null]))),
          '("title" is null)',
        );
        expect(
          condition(
            where(pg, criteria(PartType.negatingSimpleProperty, [null])),
          ),
          '("title" is not null)',
        );
        for (final type in [
          PartType.lessThan,
          PartType.lessThanEqual,
          PartType.greaterThan,
          PartType.greaterThanEqual,
        ]) {
          final statement = where(pg, criteria(type, [null]));
          expect(condition(statement), '(1 = 0)');
          expect(statement.parameters, isEmpty);
        }
        expect(
          condition(where(pg, criteria(PartType.between, [null, 'z']))),
          '(1 = 0)',
        );
        expect(
          condition(where(pg, criteria(PartType.like, [null]))),
          '(1 = 0)',
        );
        expect(
          condition(where(pg, criteria(PartType.containing, [null]))),
          '(1 = 0)',
        );
        expect(
          condition(where(pg, criteria(PartType.isNull, const []))),
          '("title" is null)',
        );
        expect(
          condition(where(pg, criteria(PartType.isNotNull, const []))),
          '("title" is not null)',
        );
      }),
    );

    test(
      'booleans are bound',
      () => run(() async {
        final statement = where(
          pg,
          criteria(PartType.isTrue, const [], property: 'inStock'),
        );
        expect(condition(statement), '("in_stock" = ?)');
        expect(statement.parameters, [true]);
        expect(
          where(
            pg,
            criteria(PartType.isFalse, const [], property: 'inStock'),
          ).parameters,
          [false],
        );
      }),
    );

    test(
      'like: ESCAPE, the argument of containing escaped, like taken as is',
      () => run(() async {
        final containing = where(
          pg,
          criteria(PartType.containing, [r'50%_\off']),
        );
        expect(condition(containing), r"""("title" like ? escape '\')""");
        expect(containing.parameters, [r'%50\%\_\\off%']);
        expect(
          where(pg, criteria(PartType.startingWith, ['a_b'])).parameters,
          [r'a\_b%'],
        );
        expect(
          where(pg, criteria(PartType.endingWith, ['a%'])).parameters,
          [r'%a\%'],
        );
        final like = where(pg, criteria(PartType.like, [r'a%\_b_']));
        expect(like.parameters, [r'a%\_b_']);
        expect(
          condition(where(pg, criteria(PartType.notLike, ['a%']))),
          r"""("title" not like ? escape '\')""",
        );
        expect(
          condition(where(pg, criteria(PartType.notContaining, ['a']))),
          r"""("title" not like ? escape '\')""",
        );
        expect(
          condition(
            where(
              pg,
              criteria(PartType.containing, ['A'], ignoreCase: true),
            ),
          ),
          r"""(lower("title") like lower(?) escape '\')""",
        );
        // A trailing backslash is a plain backslash: escaped for the DB.
        expect(
          where(pg, criteria(PartType.like, [r'a\'])).parameters,
          [r'a\\'],
        );
      }),
    );

    test(
      "SQLite's LIKE ignores case: a case sensitive GLOB takes its place",
      () => run(() async {
        final containing = where(
          lite,
          criteria(PartType.containing, ['a*b?c[d']),
        );
        expect(condition(containing), '("title" GLOB ?)');
        expect(containing.parameters, ['*a[*]b[?]c[[]d*']);
        expect(
          where(lite, criteria(PartType.like, [r'a%\_b_'])).parameters,
          ['a*_b?'],
        );
        expect(
          condition(where(lite, criteria(PartType.notLike, ['a%']))),
          '("title" NOT GLOB ?)'.replaceFirst('NOT GLOB', 'not GLOB'),
        );
        // Ignoring the case, LIKE already does what is wanted.
        expect(
          condition(
            where(
              lite,
              criteria(PartType.startingWith, ['A'], ignoreCase: true),
            ),
          ),
          r"""(spring_lower("title") like spring_lower(?) escape '\')""",
        );
      }),
    );

    test(
      'in and not in on PostgreSQL: one array parameter, any length',
      () => run(() async {
        final gen = SqlGenerator(
          dialect: const PostgresDialect(),
          converter: converter,
        );
        final inside = where(
          gen,
          criteria(PartType.in_, [
            ['a', null, 'b'],
          ]),
        );
        expect(condition(inside), '("title" = any(?))');
        expect(inside.parameters, [
          ['a', 'b'],
        ]);
        final many = where(
          gen,
          criteria(PartType.in_, [
            List.generate(70000, (i) => 'v$i'),
          ]),
        );
        expect(condition(many), '("title" = any(?))');
        expect(many.parameters, hasLength(1));
        final notInside = where(
          gen,
          criteria(PartType.notIn, [
            {'a', 'b'},
          ]),
        );
        expect(condition(notInside), '("title" <> all(?))');
        expect(
          condition(
            where(
              gen,
              criteria(PartType.in_, [
                ['A'],
              ], ignoreCase: true),
            ),
          ),
          '(lower("title") = any(array(select lower(element) '
          'from unnest(cast(? as text[])) as element)))',
        );
        // Null and empty keep their meaning.
        expect(
          condition(where(gen, criteria(PartType.in_, [<String>[]]))),
          '(1 = 0)',
        );
        expect(
          condition(
            where(
              gen,
              criteria(PartType.notIn, [
                ['a', null],
              ]),
            ),
          ),
          '(1 = 0)',
        );
        expect(
          condition(where(gen, criteria(PartType.notIn, [<String>[]]))),
          '(1 = 1)',
        );
      }),
    );

    test(
      'in on SQLite: a list past the limit of bound values is refused',
      () => run(() async {
        final fits = where(
          lite,
          criteria(PartType.in_, [
            List.generate(32766, (i) => 'v$i'),
          ]),
        );
        expect(fits.parameters, hasLength(32766));
        for (final type in [PartType.in_, PartType.notIn]) {
          expect(
            () => where(
              lite,
              criteria(type, [
                List.generate(70000, (i) => 'v$i'),
              ]),
            ),
            throwsA(
              isA<InvalidDataArgumentException>().having(
                (e) => e.message,
                'message',
                allOf(contains('70000'), contains('32766')),
              ),
            ),
          );
        }
      }),
    );

    test(
      'a NUL in a text argument is refused, without the value',
      () => run(() async {
        for (final type in [
          PartType.simpleProperty,
          PartType.containing,
          PartType.startingWith,
          PartType.like,
        ]) {
          for (final generator in [pg, lite]) {
            expect(
              () => where(generator, criteria(type, ['a\u0000b'])),
              throwsA(
                isA<InvalidDataArgumentException>().having(
                  (e) => e.message,
                  'message',
                  allOf(contains('NUL'), contains("'title'")),
                ),
              ),
              reason: type.name,
            );
          }
        }
        expect(
          () => where(
            pg,
            criteria(PartType.in_, [
              ['a', 'b\u0000'],
            ]),
          ),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      }),
    );

    test(
      'in and not in: expanded, empty without invalid SQL, null aside',
      () => run(() async {
        final inside = where(
          pg,
          criteria(PartType.in_, [
            ['a', null, 'b'],
          ]),
        );
        expect(condition(inside), '("title" in (?, ?))');
        expect(inside.parameters, ['a', 'b']);
        expect(
          condition(where(pg, criteria(PartType.in_, [<String>[]]))),
          '(1 = 0)',
        );
        expect(
          condition(
            where(
              pg,
              criteria(PartType.in_, [
                <String?>[null],
              ]),
            ),
          ),
          '(1 = 0)',
        );
        expect(
          condition(where(pg, criteria(PartType.notIn, [<String>[]]))),
          '(1 = 1)',
        );
        final notInside = where(
          pg,
          criteria(PartType.notIn, [
            {'a', 'b'},
          ]),
        );
        expect(condition(notInside), '("title" not in (?, ?))');
        expect(
          condition(
            where(
              pg,
              criteria(PartType.notIn, [
                ['a', null],
              ]),
            ),
          ),
          '(1 = 0)',
        );
        expect(
          condition(
            where(
              pg,
              criteria(PartType.in_, [
                ['A'],
              ], ignoreCase: true),
            ),
          ),
          '(lower("title") in (lower(?)))',
        );
        expect(
          () => where(pg, criteria(PartType.in_, ['not a list'])),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      }),
    );

    test(
      'references by id, enums by name',
      () => run(() async {
        final reference = where(
          pg,
          criteria(PartType.simpleProperty, [author(7)], property: 'author'),
        );
        expect(reference.parameters, [7]);
        final many = where(
          pg,
          criteria(PartType.in_, [
            [author(1), author(2)],
          ], property: 'author'),
        );
        expect(many.parameters, [1, 2]);
        expect(
          where(
            pg,
            criteria(PartType.simpleProperty, [Genre.crime], property: 'genre'),
          ).parameters,
          ['crime'],
        );
      }),
    );

    test(
      'and, or: each alternative in parentheses',
      () => run(() async {
        final both = Criteria(
          [
            const OrPart([
              Part('title'),
              Part('year', PartType.greaterThan),
            ]),
            const OrPart([
              Part('subtitle', PartType.isNull),
            ]),
          ],
          ['a', 1990],
        );
        final statement = where(pg, both);
        expect(
          condition(statement),
          '("title" = ? and "year" > ?) or ("subtitle" is null)',
        );
        expect(statement.parameters, ['a', 1990]);
        expect(
          pg.select(books, criteria: Criteria(const [], const [])).sql,
          isNot(contains('where')),
        );
      }),
    );

    test(
      'an unknown column or a collection is refused',
      () => run(() async {
        expect(
          () => where(
            pg,
            criteria(PartType.simpleProperty, ['a'], property: 'nope'),
          ),
          throwsA(
            isA<InvalidDataAccessApiUsageException>().having(
              (e) => e.message,
              'message',
              contains('"nope"'),
            ),
          ),
        );
        expect(
          () => pg.select(
            orders,
            criteria: criteria(
              PartType.simpleProperty,
              ['a'],
              property: 'lines',
            ),
          ),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      }),
    );

    test(
      'hostile values are parameters, never part of the statement',
      () => run(() async {
        const hostile = [
          "' OR 1=1 --",
          '"; DROP TABLE books; --',
          r'\',
          "'' ; delete from books; --",
        ];
        for (final dialect in [pg, lite]) {
          for (final type in PartType.values) {
            if (type.argumentCount == 0) {
              continue;
            }
            for (final text in hostile) {
              final arguments = switch (type) {
                PartType.between => [text, text],
                PartType.in_ || PartType.notIn => [
                  [text, text],
                ],
                _ => [text],
              };
              final statement = where(
                dialect,
                criteria(type, arguments, ignoreCase: type.index.isEven),
              );
              expect(statement.sql, isNot(contains('DROP')), reason: '$type');
              expect(statement.sql, isNot(contains('1=1')), reason: '$type');
              expect(statement.sql, isNot(contains('delete')), reason: '$type');
              expect(
                statement.sql.split('?').length - 1,
                statement.parameters.length,
                reason: '$type: one value for each marker',
              );
            }
          }
        }
      }),
    );
  });

  group('order by', () {
    test(
      'direction, ignore case and explicit nulls, the id last',
      () => run(() async {
        final statement = pg.select(
          books,
          sort: Sort.byOrders([
            const SortOrder.asc('title').ignoringCase(),
            const SortOrder.desc('subtitle'),
            const SortOrder(
              'year',
              nullHandling: NullHandling.nullsFirst,
            ),
            const SortOrder(
              'rating',
              direction: Direction.desc,
              nullHandling: NullHandling.nullsLast,
            ),
          ]),
        );
        expect(
          statement.sql,
          endsWith(
            'order by lower("title") ASC NULLS LAST, "subtitle" DESC NULLS '
            'FIRST, "year" ASC NULLS FIRST, "rating" DESC NULLS LAST, '
            '"id" ASC',
          ),
        );
      }),
    );

    test(
      'a property that is not a column is refused unless named freely',
      () => run(() async {
        expect(
          () => pg.orderBy(books, Sort.by(['nope'])),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
        expect(
          pg.orderBy(
            books,
            Sort.by(['nope']),
            tieBreak: false,
            free: (name) => '"$name"',
          ),
          ' order by "nope" ASC NULLS LAST',
        );
        expect(pg.orderBy(books, Sort.unsorted), '');
      }),
    );
  });

  group('children', () {
    test(
      'insert, delete by root, delete by criteria, select of many roots',
      () => run(() async {
        final child = orders.property('lines')!.childEntity!;
        expect(
          pg.deleteChildren(child, 'orders_id', 4).sql,
          'delete from "order_lines" where "orders_id" = ?',
        );
        final byCriteria = pg.deleteChildrenWhere(
          child,
          'orders_id',
          orders,
          criteria(PartType.simpleProperty, ['ada'], property: 'customer'),
        );
        expect(
          byCriteria.sql,
          'delete from "order_lines" where "orders_id" in '
          '(select "id" from "orders" where ("customer" = ?))',
        );
        expect(byCriteria.parameters, ['ada']);
        final select = pg.selectChildren(child, 'orders_id', 'orders_key', [
          1,
          2,
          3,
        ]);
        expect(
          select.sql,
          'select "sku", "quantity", "orders_id", "orders_key" '
          'from "order_lines" where "orders_id" in (?, ?, ?) '
          'order by "orders_id", "orders_key"',
        );
        final set = pg.selectChildren(child, 'orders_id', null, [1]);
        expect(set.sql, endsWith('order by "orders_id"'));
        expect(set.sql, isNot(contains('orders_key')));
        expect(
          pg.insert(child, {
            'sku': 'a',
            'quantity': 1,
            'orders_id': 1,
            'orders_key': 0,
          }).sql,
          'insert into "order_lines" ("sku", "quantity", "orders_id", '
          '"orders_key") values (?, ?, ?, ?)',
        );
      }),
    );
  });
}
