import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

// The @Query methods of SqlBooks on SQLite, over the seed of support.dart.
void main() {
  late Jdbc jdbc;
  late SqlBooks books;

  Future<void> run(
    Future<void> Function() body, {
    List<String> properties = const ['books.page-size=2', 'books.cutoff=1990'],
  }) => withJdbc(properties: properties, (j) async {
    jdbc = j;
    books = j.sqlBooks;
    await seedBooks(j.sqlAuthors, j.sqlBooks);
    await body();
  });

  // The SQL statements the body ran, as the template logs them at debug.
  Future<List<String>> statements(Future<void> Function() body) async {
    final records = <SpringLogRecord>[];
    SpringLog.setLevel('spring.jdbc.core.JdbcTemplate', SpringLogLevel.debug);
    final stop = SpringLog.listen(records.add);
    try {
      await body();
    } finally {
      stop();
      SpringLog.resetLevels();
    }
    return [
      for (final r in records)
        if (r.loggerName == 'spring.jdbc.core.JdbcTemplate') r.message,
    ];
  }

  setUpAll(() => SpringLog.handler = (_) {});

  group('named parameters', () {
    test(
      'bound by the name of the method parameter',
      () => run(() async {
        expect(ids(await books.byYear(1992)), [4]);
        expect(ids(await books.byTitle('Dune')), [1]);
        expect(await books.byYear(1800), isEmpty);
      }),
    );

    test(
      'a name used twice is bound twice',
      () => run(() async {
        expect(ids(await books.aroundYear(1964)), [1]);
        expect(ids(await books.aroundYear(1968)), [2]);
      }),
    );

    test(
      'a list becomes in (?, ?, ...)',
      () => run(() async {
        expect(ids(await books.byIds([5, 1, 3])), [1, 3, 5]);
        final sql = await statements(() => books.byIds([5, 1, 3]));
        expect(sql.single, contains('id in (?, ?, ?)'));
      }),
    );

    test(
      'an empty list is refused with its reason, not run as in ()',
      () => run(() async {
        await expectLater(
          books.byIds([]),
          throwsA(
            isA<InvalidDataAccessApiUsageException>().having(
              (e) => e.message,
              'message',
              contains('empty'),
            ),
          ),
        );
      }),
    );

    test(
      'enums, references and booleans are bound as their column values',
      () => run(() async {
        expect(ids(await books.byGenre(Genre.crime)), [5]);
        expect(ids(await books.byAuthor(author(2))), [3, 4, 5]);
        expect(ids(await books.byStock(false)), [3, 5]);
        expect(ids(await books.byTitleLike('Dune%')), [1, 2]);
      }),
    );

    test(
      'a value is never in the text of the statement',
      () => run(() async {
        final sql = await statements(() => books.byTitle('Dune'));
        expect(sql.single, contains('title = ?'));
        expect(sql.single, isNot(contains('Dune')));
      }),
    );
  });

  group('SpEL and placeholders', () {
    test(
      'a property of a parameter, the arguments, the parameters by index',
      () => run(() async {
        expect(
          ids(await books.sameTitle(Book(title: 'Dune', year: 0))),
          [1],
        );
        expect(ids(await books.byFirstArgument(1999)), [5]);
        expect(ids(await books.afterSum(1980, 4)), [4, 5, 6, 7, 8]);
      }),
    );

    test(
      'a bean: a property and a call with a parameter',
      () => run(() async {
        expect(ids(await books.sinceCutoff()), [4, 5, 6, 7, 8]);
        expect(ids(await books.yearBefore(2000)), [5]);
      }),
    );

    test(
      'the environment, through the environment bean',
      () => run(() async {
        expect(ids(await books.afterConfiguredCutoff()), [4, 5, 6, 7, 8]);
      }),
    );

    test(
      'an expression is a bound value, never SQL text',
      () => run(() async {
        // An int compared with a text column: bound, so no match and no
        // error.
        expect(await books.broken(2000), isEmpty);
      }),
    );

    test(
      '#{#entityName} is the quoted table',
      () => run(() async {
        expect(ids(await books.viaEntityName('Dune')), [1]);
        final sql = await statements(() => books.viaEntityName('Dune'));
        expect(sql.single, startsWith('[test] select * from "books" where'));
      }),
    );

    test(
      '{Book} is the quoted table, {Book.inStock} the quoted column',
      () => run(() async {
        expect(ids(await books.byAuthorName('Gib%', true)), [4]);
        expect(ids(await books.byAuthorName('Gib%', false)), [3, 5]);
        final sql = await statements(() => books.byAuthorName('Gib%', true));
        expect(
          sql.single,
          contains(
            'select b.* from "books" b join "authors" a on a."id" = '
            'b."author" where a."name" like ? and b."in_stock" = ? '
            'order by b."id"',
          ),
        );
      }),
    );

    test(
      r'${property:default} is resolved when the repository is created',
      () async {
        await run(() async {
          expect(ids(await books.firstPage()), [1, 2]);
        });
        await run(properties: const [], () async {
          expect(ids(await books.firstPage()), [1, 2, 3]);
        });
      },
    );
  });

  group('results', () {
    test(
      'a DTO: columns by name, author_name into authorName',
      () => run(() async {
        final found = await books.withAuthor('Her%');
        expect(found, hasLength(2));
        expect(found.first.id, 1);
        expect(found.first.title, 'Dune');
        expect(found.first.authorName, 'Herbert');
        expect(found.last.title, 'Dune Messiah');
        expect(await books.withAuthor('Nobody'), isEmpty);
      }),
    );

    test(
      'a DTO the result lacks a column of is a mapping error naming them',
      () => run(() async {
        await expectLater(
          books.missingColumn(),
          throwsA(
            isA<MappingException>().having(
              (e) => e.message,
              'message',
              allOf(contains('authorName'), contains('id, title')),
            ),
          ),
        );
      }),
    );

    test(
      'one column: int, String, bool, double, DateTime, enum, a Set',
      () => run(() async {
        expect(await books.countAfter(1990), 5);
        expect(await books.titleOf(1), 'Dune');
        expect(await books.titleOf(99), isNull);
        expect(await books.titlesAfter(1999), ['100% Pure', 'a_b', 'axb']);
        expect(await books.yearsAfter(2000), {2001, 2002, 2003});
        expect(await books.yearsAfter(2000), isA<Set<int>>());
        expect(await books.inStockOf(3), isFalse);
        expect(await books.inStockOf(1), isTrue);
        expect(await books.ratingOf(1), 4.5);
        expect(await books.ratingOf(6), isNull);
        expect(
          (await books.releasedOf(1))!.isAtSameMomentAs(day(1965, 8, 1)),
          isTrue,
        );
        expect(await books.releasedOf(6), isNull);
        expect(await books.genreOf(5), Genre.crime);
        expect(await books.genreOf(7), isNull);
      }),
    );

    test(
      'one result: null or an error for none, an error for several',
      () => run(() async {
        expect((await books.one(1))!.title, 'Dune');
        expect(await books.one(99), isNull);
        expect((await books.requiredOne(2)).subtitle, 'sequel');
        await expectLater(
          books.requiredOne(99),
          throwsA(isA<EmptyResultDataAccessException>()),
        );
        await expectLater(
          books.requiredTitleOf(99),
          throwsA(isA<EmptyResultDataAccessException>()),
        );
        await expectLater(
          books.theOnlyOne(),
          throwsA(
            isA<IncorrectResultSizeDataAccessException>().having(
              (e) => e.actualSize,
              'actualSize',
              8,
            ),
          ),
        );
      }),
    );

    test(
      'the entity as the table has it, with its references and values',
      () => run(() async {
        final book = (await books.one(3))!;
        expect(book.title, 'Neuromancer');
        expect(book.inStock, isFalse);
        expect(book.author, author(2));
        expect(book.genre, Genre.scifi);
        expect(book.rating, 4.0);
        expect(book.version, 1);
        expect(book.released!.isAtSameMomentAs(day(1984, 7, 1)), isTrue);
      }),
    );

    test(
      'a row as a map',
      () => run(() async {
        expect(await books.asMap(1), {'id': 1, 'title': 'Dune', 'year': 1965});
        expect(await books.asMap(99), isNull);
      }),
    );

    test(
      'an entity with children: loaded whole (Spring maps only the columns)',
      () => run(() async {
        final orders = jdbc.sqlOrders;
        await orders.saveAll([
          PurchaseOrder(
            customer: 'ada',
            lines: [OrderLine(sku: 'a', quantity: 1)],
            notes: {'n': OrderNote(text: 'hi')},
          ),
          PurchaseOrder(
            customer: 'bob',
            lines: [
              OrderLine(sku: 'b', quantity: 2),
              OrderLine(sku: 'c', quantity: 3),
            ],
          ),
        ]);
        final found = await orders.viaQuery('bob');
        expect(found.single.lines.map((l) => l.sku), ['b', 'c']);
        expect(found.single.notes, isEmpty);
        // Without the id the children cannot be tied to their root.
        await expectLater(
          orders.withoutId('ada'),
          throwsA(
            isA<MappingException>().having(
              (e) => e.message,
              'message',
              contains('no column id'),
            ),
          ),
        );
      }),
    );

    test(
      'a result set extractor: one to many in one answer',
      () => run(() async {
        final found = await books.authorsWithBooks();
        expect([for (final a in found) a.name], ['Herbert', 'Gibson']);
        expect(found.first.titles, ['Dune', 'Dune Messiah']);
        expect(found.last.titles, [
          'Neuromancer',
          'Snow Crash',
          'Cryptonomicon',
        ]);
        expect(found, isA<List<AuthorWithBooks>>());
      }),
    );

    test(
      'a row mapper',
      () => run(() async {
        final found = await books.shouted();
        expect(found.first, 'DUNE');
        expect(found, hasLength(8));
      }),
    );
  });

  group('sorting and paging', () {
    test(
      'a Sort parameter becomes quoted columns; properties map to columns',
      () => run(() async {
        expect(
          ids(await books.afterSorted(1990, Sort.by(['title']))),
          [6, 5, 4, 7, 8],
        );
        expect(
          ids(
            await books.afterSorted(
              1990,
              Sort.byOrders([
                const SortOrder.desc('inStock'),
                const SortOrder.asc('year'),
              ]),
            ),
          ),
          [4, 6, 7, 8, 5],
        );
        expect(
          ids(
            await books.afterSorted(
              1990,
              Sort.byOrders([const SortOrder.asc('title').ignoringCase()]),
            ),
          ),
          [6, 7, 8, 5, 4],
        );
        // Unsorted: the query as it is.
        expect(
          ids(await books.afterSorted(1990, Sort.unsorted)),
          [4, 5, 6, 7, 8],
        );
      }),
    );

    test(
      'the sort follows the order by of the query, with a comma',
      () => run(() async {
        expect(
          ids(await books.afterSortedAndOrdered(1990, Sort.by(['title']))),
          [6, 4, 7, 8, 5],
        );
        final sql = await statements(
          () => books.afterSortedAndOrdered(1990, Sort.by(['title'])),
        );
        expect(
          sql.single,
          contains('order by in_stock desc, "title" ASC NULLS LAST'),
        );
      }),
    );

    test(
      'a sort that is not a name is refused, and nothing runs',
      () => run(() async {
        await expectLater(
          books.afterSorted(1990, Sort.by(['title; drop table books'])),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
        await expectLater(
          books.afterSorted(1990, Sort.by(['title) --'])),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
        expect(await books.count(), 8);
      }),
    );

    test(
      'a List with a Pageable gets limit and offset',
      () => run(() async {
        final found = await books.afterWindow(
          1990,
          PageRequest.of(1, 2, Sort.by(['year'])),
        );
        expect(ids(found), [6, 7]);
        final sql = await statements(
          () => books.afterWindow(1990, PageRequest.of(1, 2)),
        );
        expect(sql.single, contains('LIMIT 2 OFFSET 2'));
      }),
    );

    test(
      'a Page counts the query, unless the page is not full',
      () => run(() async {
        final sort = Sort.by(['year']);
        late Page<Book> first;
        final sql = await statements(() async {
          first = await books.pageAfter(1990, PageRequest.of(0, 2, sort));
        });
        expect(ids(first.content), [4, 5]);
        expect(first.totalElements, 5);
        expect(first.totalPages, 3);
        expect(sql, hasLength(2));
        expect(
          sql.last,
          contains(
            'select count(*) from (select * from books where year > ?) '
            'as "spring_count"',
          ),
        );
        late Page<Book> last;
        final lastSql = await statements(() async {
          last = await books.pageAfter(1990, PageRequest.of(2, 2, sort));
        });
        expect(ids(last.content), [8]);
        expect(last.totalElements, 5);
        expect(last.isLast, isTrue);
        expect(lastSql, hasLength(1));
        final beyond = await books.pageAfter(
          1990,
          PageRequest.of(9, 2, sort),
        );
        expect(beyond.content, isEmpty);
        expect(beyond.totalElements, 5);
        final all = await books.pageAfter(1990, const Pageable.unpaged());
        expect(all.content, hasLength(5));
        expect(all.totalElements, 5);
        final empty = await books.pageAfter(3000, PageRequest.of(0, 2));
        expect(empty.totalElements, 0);
      }),
    );

    test(
      'a Page of a DTO with its countQuery',
      () => run(() async {
        late Page<BookWithAuthor> page;
        final sql = await statements(() async {
          page = await books.pageWithAuthor(
            PageRequest.of(0, 2, Sort.by(['b.id'])),
          );
        });
        expect([for (final b in page.content) b.id], [1, 2]);
        expect(page.content.first.authorName, 'Herbert');
        expect(page.totalElements, 5);
        expect(
          sql.last,
          contains('select count(*) from books b join authors a'),
        );
        expect(sql.first, contains('order by "b"."id" ASC NULLS LAST'));
        expect(sql.first, contains('LIMIT 2 OFFSET 0'));
      }),
    );

    test(
      'a Slice reads one more to know about the next',
      () => run(() async {
        final sort = Sort.by(['id']);
        late Slice<Book> first;
        final sql = await statements(() async {
          first = await books.sliceAfter(1990, PageRequest.of(0, 2, sort));
        });
        expect(ids(first.content), [4, 5]);
        expect(first.hasNext, isTrue);
        expect(sql, hasLength(1));
        expect(sql.single, contains('LIMIT 3 OFFSET 0'));
        final last = await books.sliceAfter(1990, PageRequest.of(2, 2, sort));
        expect(ids(last.content), [8]);
        expect(last.hasNext, isFalse);
        final exact = await books.sliceAfter(1990, PageRequest.of(0, 5, sort));
        expect(exact.content, hasLength(5));
        expect(exact.hasNext, isFalse);
      }),
    );
  });

  group('streams', () {
    test(
      'entities, one column and DTOs, as the rows come',
      () => run(() async {
        final entities = books.streamAfter(1990);
        expect(entities, isA<Stream<Book>>());
        expect(ids(await entities.toList()), [4, 5, 6, 7, 8]);
        final titles = books.streamTitles();
        expect(titles, isA<Stream<String>>());
        expect((await titles.toList()).first, 'Dune');
        final joined = books.streamWithAuthor();
        expect(joined, isA<Stream<BookWithAuthor>>());
        expect([for (final b in await joined.toList()) b.id], [1, 2, 3, 4, 5]);
      }),
    );

    test(
      'a stream runs when listened to, and releases the connection',
      () => run(() async {
        final stream = books.streamTitles();
        await books.deleteAll();
        expect(await stream.toList(), isEmpty);
        expect(jdbc.dataSource.activeCount, 0);
        final first = await books.streamTitles().take(1).toList();
        expect(first, isEmpty);
      }),
    );

    test(
      'cancelling a stream releases its connection',
      () => run(() async {
        final first = await books.streamTitles().first;
        expect(first, 'Dune');
        expect(jdbc.dataSource.activeCount, 0);
      }),
    );
  });

  group('changes', () {
    test(
      '@Modifying returns the rows changed, whether any, or nothing',
      () => run(() async {
        expect(await books.shift(1970, 100), 2);
        expect(
          [(await books.one(1))!.year, (await books.one(2))!.year],
          [
            2065,
            2069,
          ],
        );
        expect(await books.shift(1000, 1), 0);
        expect(await books.deleteOlder(1990), isTrue);
        expect(await books.deleteOlder(1000), isFalse);
        expect(ids(await books.findAll()), [1, 2, 4, 5, 6, 7, 8]);
        await books.retitle(4, 'a subtitle');
        expect((await books.one(4))!.subtitle, 'a subtitle');
        await books.retitle(4, null);
        expect((await books.one(4))!.subtitle, isNull);
      }),
    );

    test(
      '@Modifying runs in a transaction: it is atomic and joins the caller',
      () => run(() async {
        await expectLater(
          jdbc.transaction().execute((_) async {
            await books.shift(1970, 100);
            throw StateError('stop');
          }),
          throwsStateError,
        );
        expect((await books.one(1))!.year, 1965);
        await jdbc.transaction().execute((_) async {
          await books.shift(1970, 100);
        });
        expect((await books.one(1))!.year, 2065);
      }),
    );
  });
}
