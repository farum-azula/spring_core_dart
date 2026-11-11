// One suite, three stores: the same calls and the same assertions run on the
// in-memory store, on SQLite and, when a PostgreSQL is there
// (SPRING_TEST_POSTGRES_URL, or Docker), on PostgreSQL (through the JDBC
// store), so they behave identically. Where a database cannot match the
// in-memory store, the test says so and asserts the difference explicitly
// (`if (sqlite)`); what only reads the tables of a SQL store is under
// `if (sql)`.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../../postgres/support.dart' show postgresServerSkip, usePostgresServer;
import 'support.dart';

// The stores' repositories the suite works with.
final class Kit {
  Kit(
    this.books,
    this.orders,
    this.shelves,
    this.accounts,
    this.tickets,
    this.notes,
    this.authors,
  );

  final BookQueries books;
  final OrderQueries orders;
  final ListCrudRepository<Shelf, int> shelves;
  final CrudRepository<Account, String> accounts;
  final ListCrudRepository<Ticket, int> tickets;
  final ListCrudRepository<Note, int> notes;
  final ListCrudRepository<Author, int> authors;
}

Future<void> seed(Kit kit) => seedBooks(kit.authors, kit.books);

void main() {
  for (final store in const ['memory', 'sqlite', 'postgres']) {
    group(
      store,
      () {
        if (store == 'postgres') {
          usePostgresServer();
        }
        _suite(store);
      },
      skip: store == 'postgres' ? postgresServerSkip : null,
      tags: store == 'postgres' ? 'postgres' : null,
    );
  }
}

void _suite(String store) {
  final sql = store != 'memory';
  final sqlite = store == 'sqlite';
  late Kit kit;
  late Jdbc jdbc;
  late BookQueries books;

  Future<void> run(
    Future<void> Function() body, {
    bool seeded = true,
  }) => withJdbc(postgres: store == 'postgres', (j) async {
    jdbc = j;
    kit = sql
        ? Kit(
            j.sqlBooks,
            j.sqlOrders,
            j.sqlShelves,
            j.sqlAccounts,
            j.sqlTickets,
            j.sqlNotes,
            j.sqlAuthors,
          )
        : Kit(
            j.memoryBooks,
            j.memoryOrders,
            j.memoryShelves,
            j.memoryAccounts,
            j.memoryTickets,
            j.memoryNotes,
            j.memoryAuthors,
          );
    books = kit.books;
    if (seeded) {
      await seed(kit);
    }
    await body();
  });

  group('comparison and equality', () {
    test(
      'simple property, ignoring case, and, or, not',
      () => run(() async {
        expect(ids(await books.findByTitle('Dune')), [1]);
        expect(ids(await books.findByTitle('dune')), isEmpty);
        expect(ids(await books.findByTitleIgnoreCase('dUNE')), [1]);
        expect(ids(await books.findByTitleAndYear('Dune', 1965)), [1]);
        expect(ids(await books.findByTitleAndYear('Dune', 1969)), isEmpty);
        expect(ids(await books.findByTitleOrYear('Dune', 1969)), [1, 2]);
        expect(ids(await books.findByYearNot(1999)), [1, 2, 3, 4, 6, 7, 8]);
        expect(ids(await books.findByTitleNot('Dune')), [2, 3, 4, 5, 6, 7, 8]);
        expect(
          ids(await books.findByTitleNotIgnoreCase('DUNE')),
          [2, 3, 4, 5, 6, 7, 8],
        );
        expect(ids(await books.findByYear(1999)), [5]);
      }),
    );

    test(
      'greater, less, between (inclusive)',
      () => run(() async {
        expect(ids(await books.findByYearGreaterThan(1992)), [5, 6, 7, 8]);
        expect(
          ids(await books.findByYearGreaterThanEqual(1992)),
          [4, 5, 6, 7, 8],
        );
        expect(ids(await books.findByYearLessThan(1969)), [1]);
        expect(ids(await books.findByYearLessThanEqual(1969)), [1, 2]);
        expect(ids(await books.findByYearBetween(1965, 1984)), [1, 2, 3]);
        expect(ids(await books.findByYearBetween(1984, 1965)), isEmpty);
      }),
    );

    test(
      'in and not in, with empty lists',
      () => run(() async {
        expect(ids(await books.findByYearIn([1965, 1984, 3000])), [1, 3]);
        expect(ids(await books.findByYearIn([])), isEmpty);
        expect(
          ids(await books.findByYearNotIn({1965, 1969, 1984, 1992})),
          [5, 6, 7, 8],
        );
        expect(
          ids(await books.findByYearNotIn(<int>{})),
          [1, 2, 3, 4, 5, 6, 7, 8],
        );
        expect(ids(await books.findByTitleIn(['Dune', 'Snow Crash'])), [1, 4]);
        expect(
          ids(await books.findByTitleInIgnoreCase(['DUNE', 'snow crash'])),
          [1, 4],
        );
      }),
    );

    test(
      'a null argument: is null, is not null, and no other comparison',
      () => run(() async {
        expect(ids(await books.findBySubtitleIsNull()), [1, 4, 6, 7, 8]);
        expect(ids(await books.findBySubtitleIsNotNull()), [2, 3, 5]);
        expect(ids(await books.findBySubtitle(null)), [1, 4, 6, 7, 8]);
        expect(ids(await books.findBySubtitleNot(null)), [2, 3, 5]);
        expect(ids(await books.findBySubtitle('sequel')), [2]);
        // Null is never less, never between, never like.
        expect(ids(await books.findBySubtitleLessThan(null)), isEmpty);
        expect(ids(await books.findBySubtitleLessThan('d')), [3]);
        expect(ids(await books.findBySubtitleBetween(null, 'z')), isEmpty);
        expect(ids(await books.findBySubtitleBetween('a', 'z')), [2, 3, 5]);
        expect(ids(await books.findBySubtitleLike(null)), isEmpty);
        expect(ids(await books.findBySubtitleLike('%e%')), [2, 3, 5]);
        // A column that is null is not different from 'sequel' either.
        expect(ids(await books.findBySubtitleNot('sequel')), [3, 5]);
      }),
    );

    test(
      'null among the elements of in and not in',
      () => run(() async {
        expect(ids(await books.findBySubtitleIn(['sequel', null])), [2]);
        expect(ids(await books.findBySubtitleIn([null])), isEmpty);
        expect(ids(await books.findBySubtitleNotIn(['sequel'])), [3, 5]);
        // `x not in (..., null)` is never true.
        expect(ids(await books.findBySubtitleNotIn(['sequel', null])), isEmpty);
        // An empty `not in` matches everything, nulls too.
        expect(
          ids(await books.findBySubtitleNotIn([])),
          [1, 2, 3, 4, 5, 6, 7, 8],
        );
        expect(ids(await books.findBySubtitleIn([])), isEmpty);
      }),
    );

    test(
      'true and false, references, enums, doubles and dates',
      () => run(() async {
        expect(ids(await books.findByInStockTrue()), [1, 2, 4, 6, 7, 8]);
        expect(ids(await books.findByInStockFalse()), [3, 5]);
        expect(ids(await books.findByAuthor(author(1))), [1, 2]);
        expect(ids(await books.findByAuthor(author(2))), [3, 4, 5]);
        expect(ids(await books.findByAuthor(author(9))), isEmpty);
        expect(
          ids(await books.findByAuthorIn([author(1), author(9)])),
          [1, 2],
        );
        expect(ids(await books.findByAuthorIn([])), isEmpty);
        expect(ids(await books.findByAuthorIsNull()), [6, 7, 8]);
        expect(ids(await books.findByGenre(Genre.scifi)), [1, 2, 3, 4]);
        expect(
          ids(await books.findByGenreIn([Genre.crime, Genre.fantasy])),
          [5, 6],
        );
        expect(ids(await books.findByRatingBetween(3.5, 4.25)), [2, 3, 4]);
        expect(ids(await books.findByRatingGreaterThan(4.2)), [1, 4]);
        expect(
          ids(await books.findByReleasedAfter(day(1990, 1, 1))),
          [4, 5],
        );
        expect(ids(await books.findByReleased(day(1965, 8, 1))), [1]);
        expect(ids(await books.findByReleased(null)), [6, 7, 8]);
      }),
    );
  });

  group('strings', () {
    test(
      'starting, ending, containing take their argument literally',
      () => run(() async {
        expect(ids(await books.findByTitleStartingWith('Dune')), [1, 2]);
        expect(ids(await books.findByTitleEndingWith('Crash')), [4]);
        expect(ids(await books.findByTitleContaining('Snow')), [4]);
        expect(ids(await books.findByTitleContaining('%')), [6]);
        expect(ids(await books.findByTitleContaining('_')), [7]);
        expect(ids(await books.findByTitleStartingWith('a_')), [7]);
        expect(ids(await books.findByTitleStartingWith('%')), isEmpty);
        expect(ids(await books.findByTitleEndingWith('_b')), [7]);
        expect(
          ids(await books.findByTitleNotContaining('Dune')),
          [3, 4, 5, 6, 7, 8],
        );
        expect(ids(await books.findByTitleContaining('')), hasLength(8));
        expect(ids(await books.findByTitleContainingIgnoreCase('SNOW')), [4]);
        expect(ids(await books.findByTitleStartingWithIgnoreCase('dUNE')), [
          1,
          2,
        ]);
        expect(ids(await books.findByTitleEndingWithIgnoreCase('CRASH')), [4]);
      }),
    );

    test(
      'the case matters unless the part ignores it',
      () => run(() async {
        expect(ids(await books.findByTitleStartingWith('dune')), isEmpty);
        expect(ids(await books.findByTitleEndingWith('crash')), isEmpty);
        expect(ids(await books.findByTitleContaining('SNOW')), isEmpty);
        expect(ids(await books.findByTitleLike('dune%')), isEmpty);
        expect(ids(await books.findByTitleLike('Dune%')), [1, 2]);
        expect(ids(await books.findByTitleLikeIgnoreCase('dune%')), [1, 2]);
        expect(
          ids(await books.findByTitleNotLike('dune%')),
          [1, 2, 3, 4, 5, 6, 7, 8],
        );
      }),
    );

    test(
      r'like and not like take % and _ as wildcards, \ as the escape',
      () => run(() async {
        expect(ids(await books.findByTitleLike('Dune%')), [1, 2]);
        expect(ids(await books.findByTitleLike('a_b')), [7, 8]);
        expect(ids(await books.findByTitleLike(r'a\_b')), [7]);
        expect(ids(await books.findByTitleLike('%')), hasLength(8));
        expect(ids(await books.findByTitleLike(r'100\%%')), [6]);
        expect(ids(await books.findByTitleLike('Dune')), [1]);
        expect(ids(await books.findByTitleLike('%e')), [1, 6]);
        expect(
          ids(await books.findByTitleNotLike('Dune%')),
          [3, 4, 5, 6, 7, 8],
        );
      }),
    );

    test(
      'the special characters of every pattern language are plain text',
      () => run(() async {
        await books.saveAll([
          Book(title: 'wild*card', year: 3001),
          Book(title: 'q?mark', year: 3002),
          Book(title: 'br[ack]et', year: 3003),
          Book(title: r'back\slash', year: 3004),
          Book(title: "it's", year: 3005),
          Book(title: 'say "hi"', year: 3006),
        ]);
        expect(titles(await books.findByTitleContaining('*')), ['wild*card']);
        expect(titles(await books.findByTitleContaining('?')), ['q?mark']);
        expect(titles(await books.findByTitleContaining('[')), ['br[ack]et']);
        expect(titles(await books.findByTitleStartingWith('br[')), [
          'br[ack]et',
        ]);
        expect(titles(await books.findByTitleEndingWith(']et')), [
          'br[ack]et',
        ]);
        expect(titles(await books.findByTitleContaining(r'\')), [
          r'back\slash',
        ]);
        expect(titles(await books.findByTitleContaining("'")), ["it's"]);
        expect(titles(await books.findByTitleContaining('"')), ['say "hi"']);
        // In like, only % and _ are wildcards; * ? [ stay plain.
        expect(titles(await books.findByTitleLike('wild*card')), [
          'wild*card',
        ]);
        expect(titles(await books.findByTitleLike('wild*')), isEmpty);
        expect(titles(await books.findByTitleLike('q_mark')), ['q?mark']);
        expect(titles(await books.findByTitleLike('q?mark')), ['q?mark']);
        expect(titles(await books.findByTitleLike('br[ack]et')), [
          'br[ack]et',
        ]);
        expect(titles(await books.findByTitleLike(r'back\\slash')), [
          r'back\slash',
        ]);
        expect(titles(await books.findByTitleLike('%[%')), ['br[ack]et']);
      }),
    );

    test(
      'a backslash at the end, before a wildcard or doubled is plain text',
      () => run(() async {
        await books.saveAll([
          Book(title: r'end\', year: 3201),
          Book(title: r'50\%', year: 3202),
          Book(title: r'50\x', year: 3203),
          Book(title: r'two\\slashes', year: 3204),
          Book(title: r'under\_score', year: 3205),
          Book(title: 'end', year: 3206),
        ]);
        // Containing, StartingWith, EndingWith: the argument is text.
        expect(titles(await books.findByTitleEndingWith(r'\')), [r'end\']);
        expect(titles(await books.findByTitleContaining(r'd\')), [r'end\']);
        expect(titles(await books.findByTitleStartingWith(r'end\')), [
          r'end\',
        ]);
        expect(titles(await books.findByTitleContaining(r'\%')), [r'50\%']);
        expect(titles(await books.findByTitleStartingWith(r'50\')), [
          r'50\%',
          r'50\x',
        ]);
        expect(titles(await books.findByTitleContaining(r'\\')), [
          r'two\\slashes',
        ]);
        expect(titles(await books.findByTitleContaining(r'\_')), [
          r'under\_score',
        ]);
        expect(
          titles(await books.findByTitleNotContaining(r'\')),
          isNot(
            contains(r'end\'),
          ),
        );
        // The same, ignoring the case.
        expect(titles(await books.findByTitleEndingWithIgnoreCase(r'D\')), [
          r'end\',
        ]);
        expect(titles(await books.findByTitleContainingIgnoreCase(r'\%')), [
          r'50\%',
        ]);
        // Like: a lone backslash at the end is itself.
        expect(titles(await books.findByTitleLike(r'end\')), [r'end\']);
        expect(titles(await books.findByTitleLike(r'%\')), [r'end\']);
        expect(titles(await books.findByTitleLikeIgnoreCase(r'END\')), [
          r'end\',
        ]);
        expect(titles(await books.findByTitleLike(r'50\\%')), [
          r'50\%',
          r'50\x',
        ]);
        expect(titles(await books.findByTitleLike(r'50\\\%')), [r'50\%']);
        expect(
          titles(await books.findByTitleNotLike(r'%\')),
          isNot(
            contains(r'end\'),
          ),
        );
      }),
    );

    test(
      'a NUL in a text argument is refused the same way by every store',
      () => run(() async {
        final refused = throwsA(
          isA<InvalidDataArgumentException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('NUL'), isNot(contains('\u0000'))),
          ),
        );
        expect(books.findByTitle('Du\u0000ne'), refused);
        expect(books.findByTitleContaining('\u0000'), refused);
        expect(books.findByTitleStartingWithIgnoreCase('D\u0000'), refused);
        expect(books.findByTitleLike('%\u0000%'), refused);
        expect(books.findByTitleIn(['Dune', 'x\u0000']), refused);
        // The store is fine after it.
        expect(ids(await books.findByTitle('Dune')), [1]);
      }),
    );

    test(
      'case folding of letters outside ASCII',
      () => run(() async {
        await books.save(Book(title: 'Ärger', year: 3010));
        expect(titles(await books.findByTitleIgnoreCase('Ärger')), ['Ärger']);
        // Both fold every letter: SQLite's driver registers a lower() of
        // its own, as Dart's toLowerCase.
        expect(titles(await books.findByTitleIgnoreCase('ärger')), ['Ärger']);
        expect(
          titles(await books.findByTitleStartingWithIgnoreCase('ä')),
          ['Ärger'],
        );
      }),
    );

    test(
      'case folding: Cyrillic and German, whole words and parts',
      () => run(() async {
        await books.saveAll([
          Book(title: 'Дюна', year: 3101),
          Book(title: 'Мастер и Маргарита', year: 3102),
          Book(title: 'Über die Brücke', year: 3103),
          Book(title: 'Straße', year: 3104),
        ]);
        expect(titles(await books.findByTitleIgnoreCase('ДЮНА')), ['Дюна']);
        expect(titles(await books.findByTitleIgnoreCase('дюна')), ['Дюна']);
        expect(
          titles(await books.findByTitleContainingIgnoreCase('МАРГАРИТ')),
          ['Мастер и Маргарита'],
        );
        expect(
          titles(await books.findByTitleStartingWithIgnoreCase('МАСТЕР')),
          ['Мастер и Маргарита'],
        );
        expect(
          titles(await books.findByTitleEndingWithIgnoreCase('МАРГАРИТА')),
          ['Мастер и Маргарита'],
        );
        expect(
          titles(await books.findByTitleLikeIgnoreCase('дю%')),
          ['Дюна'],
        );
        expect(
          titles(await books.findByTitleStartingWithIgnoreCase('ÜBER')),
          ['Über die Brücke'],
        );
        expect(
          titles(await books.findByTitleContainingIgnoreCase('brücke')),
          ['Über die Brücke'],
        );
        expect(
          titles(await books.findByTitleInIgnoreCase(['ДЮНА', 'STRASSE'])),
          // ß has no one-letter upper case: lower('STRASSE') is not
          // 'straße' anywhere.
          ['Дюна'],
        );
        expect(titles(await books.findByTitleContainingIgnoreCase('ß')), [
          'Straße',
        ]);
        // Case sensitive, they stay different.
        expect(titles(await books.findByTitle('ДЮНА')), isEmpty);
        expect(titles(await books.findByTitleContaining('ДЮ')), isEmpty);
      }),
    );
  });

  group('long in lists', () {
    test(
      'a list of 70 000 values: one array on PostgreSQL, a clear refusal on '
      'SQLite, a plain match in memory',
      () => run(() async {
        final years = List.generate(70000, (i) => i + 1);
        final titlesList = [for (final y in years) 'title $y', 'Dune'];
        if (sqlite) {
          for (final call in [
            () => books.findByYearIn(years),
            () => books.findByYearNotIn(years.toSet()),
            () => books.findByTitleIn(titlesList),
          ]) {
            await expectLater(
              call(),
              throwsA(
                isA<InvalidDataArgumentException>().having(
                  (e) => e.toString(),
                  'message',
                  allOf(contains('values'), contains('32766')),
                ),
              ),
            );
          }
          // Under the limit it runs.
          expect(
            ids(await books.findByYearIn(List.generate(30000, (i) => i))),
            isNotEmpty,
          );
        } else {
          final all = ids(await books.findAll());
          final inList = await books.findByYearIn(years);
          expect(ids(inList), unorderedEquals(all));
          expect(await books.findByYearNotIn(years.toSet()), isEmpty);
          expect(ids(await books.findByTitleIn(titlesList)), [1]);
          expect(
            ids(
              await books.findByYearNotIn(
                List.generate(70000, (i) => i + 100000).toSet(),
              ),
            ),
            unorderedEquals(all),
          );
          expect(
            ids(
              await books.findByTitleInIgnoreCase(
                [for (final y in years) 'TITLE $y', 'DUNE'],
              ),
            ),
            [1],
          );
        }
      }),
    );
  });

  group('sorting', () {
    test(
      'the name sorts, with several keys',
      () => run(() async {
        expect(
          ids(await books.findByInStockOrderByYearDescTitleAsc(true)),
          [8, 7, 6, 4, 2, 1],
        );
      }),
    );

    test(
      'null is the greatest value: last when ascending, first when descending',
      () => run(() async {
        expect(
          ids(await books.findByInStockOrderBySubtitleAscIdAsc(true)),
          [2, 1, 4, 6, 7, 8],
        );
        expect(
          ids(await books.findByInStockOrderBySubtitleDescIdAsc(true)),
          [1, 4, 6, 7, 8, 2],
        );
      }),
    );

    test(
      'a Sort parameter: nulls first or last whatever the direction',
      () => run(() async {
        Sort by(String property, Direction direction, NullHandling nulls) =>
            Sort.byOrders([
              SortOrder(property, direction: direction, nullHandling: nulls),
              const SortOrder.asc('id'),
            ]);
        expect(
          ids(
            await books.findByInStock(
              true,
              by('subtitle', Direction.asc, NullHandling.nullsFirst),
            ),
          ),
          [1, 4, 6, 7, 8, 2],
        );
        expect(
          ids(
            await books.findByInStock(
              true,
              by('subtitle', Direction.desc, NullHandling.nullsLast),
            ),
          ),
          [2, 1, 4, 6, 7, 8],
        );
        expect(
          ids(
            await books.findByInStock(
              true,
              by('subtitle', Direction.asc, NullHandling.native),
            ),
          ),
          [2, 1, 4, 6, 7, 8],
        );
        final desc = await books.findByInStock(
          true,
          Sort.byOrders([const SortOrder.desc('year')]),
        );
        expect(ids(desc), [8, 7, 6, 4, 2, 1]);
      }),
    );

    test(
      'ignoring the case in the order',
      () => run(() async {
        final byTitle = ids(await books.findAllSorted(Sort.by(['title'])));
        if (store == 'postgres') {
          // The database's collation orders the text: bytewise (`C`), or the
          // locale's, which puts 'a_b' and 'axb' before 'Cryptonomicon'.
          expect(
            byTitle,
            anyOf(
              equals([6, 5, 1, 2, 3, 4, 7, 8]),
              equals([6, 7, 8, 5, 1, 2, 3, 4]),
            ),
          );
        } else {
          expect(byTitle, [6, 5, 1, 2, 3, 4, 7, 8]);
        }
        expect(
          ids(
            await books.findAllSorted(
              Sort.byOrders([const SortOrder.asc('title').ignoringCase()]),
            ),
          ),
          [6, 7, 8, 5, 1, 2, 3, 4],
        );
      }),
    );

    test(
      'ignoring the case of a property that is no text is a plain order',
      () => run(() async {
        // As text '900' would come after '1965', and PostgreSQL has no
        // lower(bigint): a client's `?sort=year,ignorecase` must not fail.
        await books.save(Book(title: 'Beowulf', year: 900, rating: 10));
        for (final property in const [
          'id',
          'year',
          'rating',
          'released',
          'inStock',
        ]) {
          for (final direction in Direction.values) {
            final order = SortOrder(property, direction: direction);
            expect(
              ids(
                await books.findAllSorted(
                  Sort.byOrders([order.ignoringCase()]),
                ),
              ),
              ids(await books.findAllSorted(Sort.byOrders([order]))),
              reason: '$property $direction',
            );
          }
        }
        expect(
          ids(
            await books.findAllSorted(
              Sort.byOrders([const SortOrder.asc('year').ignoringCase()]),
            ),
          ).first,
          9,
        );
      }),
    );

    test(
      'equal keys keep the order of the table',
      () => run(() async {
        await books.save(Book(title: 'Dune', year: 1965));
        final found = await books.findAllSorted(Sort.by(['year']));
        expect(ids(found).take(3), [1, 9, 2]);
      }),
    );

    test(
      'sorting by a property that is not a column is refused',
      () => run(() async {
        await expectLater(
          books.findAllSorted(Sort.by(['nope'])),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      }),
    );
  });

  group('result types', () {
    test(
      'Set, Iterable, Stream',
      () => run(() async {
        final set = await books.findByYear(1999);
        expect(set, isA<Set<Book>>());
        expect(ids(set), [5]);
        expect(ids(await books.findByYearLessThanOrderByYear(1970)), [1, 2]);
        expect(ids(await books.streamByInStock(false).toList()), [3, 5]);
      }),
    );

    test(
      'single results',
      () => run(() async {
        expect((await books.getByTitle('Dune')).id, 1);
        expect((await books.findOneByTitle('Dune'))?.id, 1);
        expect(await books.findOneByTitle('Nope'), isNull);
        await expectLater(
          books.getByTitle('Nope'),
          throwsA(isA<EmptyResultDataAccessException>()),
        );
        await books.save(Book(title: 'Dune', year: 2020));
        await expectLater(
          books.findOneByTitle('Dune'),
          throwsA(
            isA<IncorrectResultSizeDataAccessException>().having(
              (e) => e.actualSize,
              'actualSize',
              2,
            ),
          ),
        );
      }),
    );

    test(
      'distinct',
      () => run(() async {
        expect(await books.findDistinctByInStock(true), hasLength(6));
      }),
    );
  });

  group('paging', () {
    test(
      'a Page has its content, total and navigation',
      () => run(() async {
        final first = await books.findByYearAfter(
          1984,
          PageRequest.of(0, 2, Sort.by(['year'])),
        );
        expect(ids(first.content), [4, 5]);
        expect(first.totalElements, 5);
        expect(first.totalPages, 3);
        expect(first.hasNext, isTrue);
        final last = await books.findByYearAfter(
          1984,
          PageRequest.of(2, 2, Sort.by(['year'])),
        );
        expect(ids(last.content), [8]);
        expect(last.isLast, isTrue);
        final beyond = await books.findByYearAfter(
          1984,
          PageRequest.of(9, 2, Sort.by(['year'])),
        );
        expect(beyond.content, isEmpty);
        expect(beyond.totalElements, 5);
      }),
    );

    test(
      'a Slice knows whether there is a next one',
      () => run(() async {
        final first = await books.findByInStockIsTrue(
          PageRequest.of(0, 4, Sort.by(['id'])),
        );
        expect(ids(first.content), [1, 2, 4, 6]);
        expect(first.hasNext, isTrue);
        final second = await books.findByInStockIsTrue(
          PageRequest.of(1, 4, Sort.by(['id'])),
        );
        expect(ids(second.content), [7, 8]);
        expect(second.hasNext, isFalse);
        final exact = await books.findByInStockIsTrue(
          PageRequest.of(0, 6, Sort.by(['id'])),
        );
        expect(exact.content, hasLength(6));
        expect(exact.hasNext, isFalse);
      }),
    );

    test(
      'a List with a Pageable gives the window; unpaged gives all',
      () => run(() async {
        final window = await books.findByInStockEquals(
          true,
          PageRequest.of(1, 2, Sort.by(['id'])),
        );
        expect(ids(window), [4, 6]);
        final all = await books.findByInStockEquals(
          true,
          const Pageable.unpaged(),
        );
        expect(all, hasLength(6));
      }),
    );

    test(
      'a window without a sort is stable: ordered by id',
      () => run(() async {
        expect(
          ids(await books.findByInStockEquals(true, PageRequest.of(0, 3))),
          [1, 2, 4],
        );
        expect(
          ids(await books.findByInStockEquals(true, PageRequest.of(1, 3))),
          [6, 7, 8],
        );
        expect(ids((await books.findAllPaged(PageRequest.of(2, 3))).content), [
          7,
          8,
        ]);
      }),
    );

    test(
      'First and Top limit the result, also with a Pageable',
      () => run(() async {
        expect((await books.findFirstByOrderByYearAsc())?.id, 1);
        expect(ids(await books.findTop2ByOrderByYearDesc()), [8, 7]);
        final sort = Sort.by(['year']);
        final first = await books.findTop3ByInStock(
          true,
          PageRequest.of(0, 2, sort),
        );
        expect(ids(first.content), [1, 2]);
        expect(first.totalElements, 3);
        final second = await books.findTop3ByInStock(
          true,
          PageRequest.of(1, 2, sort),
        );
        expect(ids(second.content), [4]);
        final third = await books.findTop3ByInStock(
          true,
          PageRequest.of(2, 2, sort),
        );
        expect(third.content, isEmpty);
      }),
    );
  });

  group('count, exists, delete', () {
    test(
      'count and exists',
      () => run(() async {
        expect(await books.countByInStock(true), 6);
        expect(await books.countByInStock(false), 2);
        expect(await books.countByTitleContaining('Dune'), 2);
        expect(await books.existsByTitle('Dune'), isTrue);
        expect(await books.existsByTitle('Nope'), isFalse);
        expect(await books.count(), 8);
        expect(await books.existsById(3), isTrue);
        expect(await books.existsById(99), isFalse);
      }),
    );

    test(
      'delete returns the number, nothing or the deleted aggregates',
      () => run(() async {
        expect(await books.deleteByYearLessThan(1970), 2);
        expect(await books.count(), 6);
        await books.removeByTitle('Snow Crash');
        expect(await books.existsByTitle('Snow Crash'), isFalse);
        final deleted = await books.deleteByInStock(false);
        expect(ids(deleted), [3, 5]);
        expect(deleted.first.title, 'Neuromancer');
        expect(deleted.first.genre, Genre.scifi);
        expect(ids(await books.findAll()), [6, 7, 8]);
        expect(await books.deleteByTitleIn(['a_b', 'nope']), 1);
        expect(await books.deleteByTitleIn([]), 0);
        expect(ids(await books.findAll()), [6, 8]);
      }),
    );

    test(
      'queries on an empty table give empty results',
      () => run(seeded: false, () async {
        expect(await books.findByTitle('x'), isEmpty);
        expect(await books.countByInStock(true), 0);
        expect(await books.findFirstByOrderByYearAsc(), isNull);
        expect(await books.findAll(), isEmpty);
        final page = await books.findByYearAfter(0, PageRequest.of(0, 5));
        expect(page.totalElements, 0);
        expect(page.content, isEmpty);
        expect(await books.deleteByInStock(true), isEmpty);
      }),
    );
  });

  group('CRUD', () {
    test(
      'insert generates the ids and the version, and returns the copy',
      () => run(seeded: false, () async {
        final first = await books.save(Book(title: 'One', year: 1));
        final second = await books.save(Book(title: 'Two', year: 2));
        expect([first.id, second.id], [1, 2]);
        expect([first.version, second.version], [1, 1]);
        final loaded = await books.findById(2);
        expect(loaded!.title, 'Two');
        expect(loaded.version, 1);
        expect(await books.findById(3), isNull);
      }),
    );

    test(
      'the values of every type come back as they went',
      () => run(seeded: false, () async {
        await kit.authors.saveAll([
          for (var i = 1; i <= 7; i++) Author(name: 'Author $i'),
        ]);
        final saved = await books.save(
          Book(
            title: 'Every type',
            year: 2020,
            subtitle: 'with a subtitle',
            inStock: false,
            author: author(7),
            rating: 2.5,
            released: day(2020, 2, 29),
            genre: Genre.crime,
          ),
        );
        final loaded = (await books.findById(saved.id!))!;
        expect(loaded.title, 'Every type');
        expect(loaded.subtitle, 'with a subtitle');
        expect(loaded.inStock, isFalse);
        expect(loaded.author, author(7));
        expect(loaded.rating, 2.5);
        expect(loaded.released!.isAtSameMomentAs(day(2020, 2, 29)), isTrue);
        expect(loaded.genre, Genre.crime);
        final bare = (await books.findById(
          (await books.save(Book(title: 'Bare', year: 1))).id!,
        ))!;
        expect(bare.subtitle, isNull);
        expect(bare.author, isNull);
        expect(bare.rating, isNull);
        expect(bare.released, isNull);
        expect(bare.genre, isNull);
        expect(bare.inStock, isTrue);
      }),
    );

    test(
      'an update changes the row and raises the version',
      () => run(() async {
        final book = (await books.findById(1))!
          ..title = 'Dune (revised)'
          ..subtitle = 'epic';
        final saved = await books.save(book);
        expect(saved.version, 2);
        final loaded = (await books.findById(1))!;
        expect(loaded.title, 'Dune (revised)');
        expect(loaded.subtitle, 'epic');
        expect(loaded.version, 2);
        expect(await books.count(), 8);
      }),
    );

    test(
      'a stale or missing version is an optimistic locking failure',
      () => run(() async {
        final one = (await books.findById(1))!;
        final other = (await books.findById(1))!;
        await books.save(one..title = 'First writer');
        await expectLater(
          books.save(other..title = 'Second writer'),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
        expect((await books.findById(1))!.title, 'First writer');
        final ghost = Book(title: 'Ghost', year: 1, id: 99, version: 1);
        await expectLater(
          books.save(ghost),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
        expect(await books.count(), 8);
      }),
    );

    test(
      'delete checks the version; deleteById does not',
      () => run(() async {
        final stale = (await books.findById(2))!;
        await books.save((await books.findById(2))!..title = 'Changed');
        await expectLater(
          books.delete(stale),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
        expect(await books.existsById(2), isTrue);
        await books.delete((await books.findById(2))!);
        expect(await books.existsById(2), isFalse);
        await books.deleteById(1);
        await books.deleteById(99);
        await books.deleteAllById([3, 4, 99]);
        expect(ids(await books.findAll()), [5, 6, 7, 8]);
        await books.deleteAllOf(await books.findByYearGreaterThan(2000));
        expect(ids(await books.findAll()), [5]);
        await books.deleteAll();
        expect(await books.count(), 0);
      }),
    );

    test(
      'findAllById skips the missing, in the order of the table',
      () => run(() async {
        expect(ids(await books.findAllById([5, 3, 99, 1])), [1, 3, 5]);
        expect(await books.findAllById(<int>[]), isEmpty);
        expect(ids(await books.findAllById([2, 2, 2])), [2]);
      }),
    );

    test(
      'saveAll saves each, and a failure in it saves none',
      () => run(seeded: false, () async {
        final saved = await books.saveAll([
          Book(title: 'A', year: 1),
          Book(title: 'B', year: 2),
        ]);
        expect(ids(saved), [1, 2]);
        await expectLater(
          books.saveAll([
            Book(title: 'C', year: 3),
            Book(title: 'D', year: 4, id: 99, version: 1),
          ]),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
        expect(await books.count(), 2);
      }),
    );

    test(
      'a given id is used; the same id twice is a duplicate key',
      () => run(seeded: false, () async {
        final accounts = kit.accounts;
        final saved = await accounts.save(
          const Account(iban: 'DE01', owner: 'Ada'),
        );
        expect(saved.version, 1);
        await expectLater(
          accounts.save(const Account(iban: 'DE01', owner: 'Bob')),
          throwsA(isA<DuplicateKeyException>()),
        );
        final loaded = (await accounts.findById('DE01'))!;
        expect(loaded.owner, 'Ada');
        final updated = await accounts.save(
          Account(iban: 'DE01', owner: 'Ada L.', version: loaded.version),
        );
        expect(updated.version, 2);
        await expectLater(
          accounts.save(
            Account(iban: 'DE01', owner: 'Stale', version: loaded.version),
          ),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
        expect((await accounts.findById('DE01'))!.owner, 'Ada L.');
        expect(await accounts.existsById('DE02'), isFalse);
      }),
    );

    test(
      'an entity without a version: updating a missing row is refused',
      () => run(seeded: false, () async {
        final notes = kit.notes;
        final saved = await notes.save(Note(text: 'one'));
        await notes.save(saved..text = 'uno');
        expect((await notes.findById(saved.id!))!.text, 'uno');
        await expectLater(
          notes.save(Note(text: 'ghost', id: 99)),
          throwsA(isA<IncorrectUpdateSemanticsDataAccessException>()),
        );
      }),
    );

    test(
      'a version that is a time stamp rises with each save',
      () => run(seeded: false, () async {
        final tickets = kit.tickets;
        final first = await tickets.save(Ticket(subject: 'bug'));
        expect(first.stamp, isNotNull);
        final loaded = (await tickets.findById(first.id!))!;
        final second = await tickets.save(loaded..subject = 'bug (fixed)');
        expect(second.stamp!.isAfter(first.stamp!), isTrue);
        await expectLater(
          tickets.save(first..subject = 'stale'),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
        expect((await tickets.findById(first.id!))!.subject, 'bug (fixed)');
      }),
    );

    test(
      'ids after a delete: SQLite reuses the highest, memory counts on',
      () => run(seeded: false, () async {
        await books.saveAll([
          Book(title: 'a', year: 1),
          Book(title: 'b', year: 2),
          Book(title: 'c', year: 3),
        ]);
        await books.deleteById(3);
        final next = await books.save(Book(title: 'd', year: 4));
        // INTEGER PRIMARY KEY without AUTOINCREMENT is max(rowid) + 1; the
        // in-memory counter never goes back. (PostgreSQL's identity
        // columns never go back either.)
        expect(next.id, sqlite ? 3 : 4);
      }),
    );
  });

  group('aggregates with children', () {
    PurchaseOrder order(String customer, {int lines = 2}) => PurchaseOrder(
      customer: customer,
      lines: [
        for (var i = 0; i < lines; i++)
          OrderLine(sku: '$customer-$i', quantity: i + 1),
      ],
      notes: {
        'gift': OrderNote(text: 'wrap it'),
        'door': OrderNote(text: 'leave at the door'),
      },
      tags: {
        OrderTag(label: 'rush'),
        OrderTag(label: 'fragile'),
      },
    );

    test(
      'saved, read and replaced whole',
      () => run(seeded: false, () async {
        final orders = kit.orders;
        final saved = await orders.save(order('ada', lines: 3));
        expect(saved.id, 1);
        final loaded = (await orders.findById(1))!;
        expect(loaded.customer, 'ada');
        expect(
          [for (final l in loaded.lines) l.sku],
          [
            'ada-0',
            'ada-1',
            'ada-2',
          ],
        );
        expect([for (final l in loaded.lines) l.quantity], [1, 2, 3]);
        expect(loaded.notes.keys.toSet(), {'gift', 'door'});
        expect(loaded.notes['door']!.text, 'leave at the door');
        expect(
          {for (final t in loaded.tags) t.label},
          {'rush', 'fragile'},
        );

        // Replaced: fewer lines, other notes, no tags.
        loaded
          ..lines = [OrderLine(sku: 'only', quantity: 9)]
          ..notes = {'new': OrderNote(text: 'n')}
          ..tags = {};
        await orders.save(loaded);
        final again = (await orders.findById(1))!;
        expect([for (final l in again.lines) l.sku], ['only']);
        expect(again.notes.keys, ['new']);
        expect(again.tags, isEmpty);
        if (sql) {
          // Replaced in the child tables, not added to.
          expect(
            await jdbc.jdbc.queryForObject<int>(
              'select count(*) from order_lines',
            ),
            1,
          );
          expect(
            await jdbc.jdbc.queryForObject<int>(
              'select count(*) from order_tags',
            ),
            0,
          );
        }
      }),
    );

    test(
      'the children of many roots are told apart',
      () => run(seeded: false, () async {
        final orders = kit.orders;
        await orders.saveAll([
          order('ada', lines: 1),
          order('bob', lines: 3),
          PurchaseOrder(customer: 'cy'),
          order('dee'),
        ]);
        final all = await orders.findAll();
        expect([for (final o in all) o.customer], ['ada', 'bob', 'cy', 'dee']);
        expect([for (final o in all) o.lines.length], [1, 3, 0, 2]);
        expect([for (final o in all) o.notes.length], [2, 2, 0, 2]);
        expect([for (final o in all) o.tags.length], [2, 2, 0, 2]);
        for (final o in all) {
          expect(
            [for (final l in o.lines) l.sku.split('-').first],
            everyElement(o.customer),
          );
        }
        final some = await orders.findAllById([4, 2]);
        expect([for (final o in some) o.customer], ['bob', 'dee']);
        expect([for (final o in some) o.lines.length], [3, 2]);
        expect((await orders.findByCustomer('bob')).single.lines, hasLength(3));
      }),
    );

    test(
      'deleted with their children',
      () => run(seeded: false, () async {
        final orders = kit.orders;
        await orders.saveAll([
          order('ada'),
          order('bob'),
          order('bart'),
          order('cy'),
        ]);
        await orders.deleteById(1);
        expect(await orders.count(), 3);
        final deleted = await orders.deleteByCustomer('bob');
        expect(deleted.single.lines, hasLength(2));
        expect(deleted.single.notes, hasLength(2));
        expect(await orders.deleteByCustomerStartingWith('ba'), 1);
        expect([for (final o in await orders.findAll()) o.customer], ['cy']);
        if (sql) {
          for (final table in ['order_lines', 'order_notes', 'order_tags']) {
            expect(
              await jdbc.jdbc.queryForObject<int>(
                'select count(*) from $table',
              ),
              table == 'order_lines'
                  ? 2
                  : table == 'order_notes'
                  ? 2
                  : 2,
              reason: table,
            );
          }
        }
        await orders.deleteAll();
        expect(await orders.count(), 0);
        if (sql) {
          expect(
            await jdbc.jdbc.queryForObject<int>(
              'select count(*) from order_lines',
            ),
            0,
          );
        }
      }),
    );

    test(
      'children with ids of their own',
      () => run(seeded: false, () async {
        final shelves = kit.shelves;
        final saved = await shelves.save(
          Shelf(
            name: 'top',
            slots: [
              Slot(label: 'left'),
              Slot(label: 'right'),
            ],
          ),
        );
        final loaded = (await shelves.findById(saved.id!))!;
        expect([for (final s in loaded.slots) s.label], ['left', 'right']);
        expect(loaded.slots.map((s) => s.id), everyElement(isNotNull));
        await shelves.save(loaded..slots = [Slot(label: 'middle')]);
        final again = (await shelves.findById(saved.id!))!;
        expect([for (final s in again.slots) s.label], ['middle']);
      }),
    );

    test(
      'an update of a missing aggregate leaves the children alone',
      () => run(seeded: false, () async {
        final orders = kit.orders;
        await orders.save(order('ada'));
        await expectLater(
          orders.save(order('ghost')..id = 99),
          throwsA(isA<IncorrectUpdateSemanticsDataAccessException>()),
        );
        expect((await orders.findById(1))!.lines, hasLength(2));
        expect(await orders.count(), 1);
      }),
    );
  });
}
