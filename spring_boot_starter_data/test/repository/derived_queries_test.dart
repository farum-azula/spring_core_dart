import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../support/app.dart';

// The seed: 1 Dune 1965, 2 Dune Messiah 1969, 3 Neuromancer 1984 (out of
// stock), 4 Snow Crash 1992, 5 Cryptonomicon 1999 (out of stock), 6 "100%
// Pure" 2001, 7 "a_b" 2002, 8 "axb" 2003. Subtitles: 2, 3 and 5 have one.
// Authors: 1 and 2 by author 1, 3 to 5 by author 2, the rest none.
void main() {
  late BookRepository books;

  Future<void> run(Future<void> Function() body) =>
      withExample((example) async {
        books = example.books;
        await seedBooks(books);
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
        expect(ids(await books.findByYear(1999)), [5]);
      }),
    );

    test(
      'greater, less, between',
      () => run(() async {
        expect(ids(await books.findByYearGreaterThan(1992)), [5, 6, 7, 8]);
        expect(ids(await books.findByYearGreaterThanEqual(1992)), [
          4,
          5,
          6,
          7,
          8,
        ]);
        expect(ids(await books.findByYearLessThan(1969)), [1]);
        expect(ids(await books.findByYearLessThanEqual(1969)), [1, 2]);
        // Inclusive on both ends.
        expect(ids(await books.findByYearBetween(1965, 1984)), [1, 2, 3]);
      }),
    );

    test(
      'in and not in',
      () => run(() async {
        expect(ids(await books.findByYearIn([1965, 1984, 3000])), [1, 3]);
        expect(ids(await books.findByYearIn([])), isEmpty);
        expect(
          ids(await books.findByYearNotIn({1965, 1969, 1984, 1992})),
          [5, 6, 7, 8],
        );
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
        expect(
          ids(await books.findByTitleNotContaining('Dune')),
          [3, 4, 5, 6, 7, 8],
        );
        expect(ids(await books.findByTitleContainingIgnoreCase('SNOW')), [4]);
      }),
    );

    test(
      'like and not like take % and _ as wildcards',
      () => run(() async {
        expect(ids(await books.findByTitleLike('Dune%')), [1, 2]);
        expect(ids(await books.findByTitleLike('a_b')), [7, 8]);
        expect(ids(await books.findByTitleLike('%')), hasLength(8));
        expect(ids(await books.findByTitleLike(r'100\%%')), [6]);
        expect(ids(await books.findByTitleLike('Dune')), [1]);
        expect(
          ids(await books.findByTitleNotLike('Dune%')),
          [3, 4, 5, 6, 7, 8],
        );
      }),
    );
  });

  group('nulls, booleans and references', () {
    test(
      'is null and not null',
      () => run(() async {
        expect(ids(await books.findBySubtitleIsNull()), [1, 4, 6, 7, 8]);
        expect(ids(await books.findBySubtitleIsNotNull()), [2, 3, 5]);
      }),
    );

    test(
      'true and false',
      () => run(() async {
        expect(ids(await books.findByInStockTrue()), [1, 2, 4, 6, 7, 8]);
        expect(ids(await books.findByInStockFalse()), [3, 5]);
        expect(await books.findByInStockFalse(), isA<List<Book>>());
      }),
    );

    test(
      'an aggregate reference compares by id',
      () => run(() async {
        expect(ids(await books.findByAuthor(author(1))), [1, 2]);
        expect(ids(await books.findByAuthor(author(2))), [3, 4, 5]);
        expect(ids(await books.findByAuthor(author(9))), isEmpty);
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
        final iterable = await books.findByYearLessThanOrderByYear(1970);
        expect(ids(iterable), [1, 2]);
        final streamed = await books.streamByInStock(false).toList();
        expect(ids(streamed), [3, 5]);
        expect(books.streamByInStock(false), isA<Stream<Book>>());
      }),
    );

    test(
      'a stream runs when listened to',
      () => run(() async {
        final stream = books.streamByInStock(true);
        await books.deleteAll();
        expect(await stream.toList(), isEmpty);
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
      'a Sort parameter',
      () => run(() async {
        final found = await books.findByInStock(
          true,
          Sort.by(['title']),
        );
        expect(
          [for (final b in found) b.title],
          ['100% Pure', 'Dune', 'Dune Messiah', 'Snow Crash', 'a_b', 'axb'],
        );
        final desc = await books.findByInStock(
          true,
          Sort.byOrders([const SortOrder.desc('year')]),
        );
        expect(ids(desc), [8, 7, 6, 4, 2, 1]);
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
        expect(first.isFirst, isTrue);
        expect(first, isA<Page<Book>>());
        final last = await books.findByYearAfter(
          1984,
          first.nextPageable().next().next().first().withPage(2),
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
        expect(first, isA<Slice<Book>>());
        final second = await books.findByInStockIsTrue(
          PageRequest.of(1, 4, Sort.by(['id'])),
        );
        expect(ids(second.content), [7, 8]);
        expect(second.hasNext, isFalse);
        // Exactly full: no next.
        final exact = await books.findByInStockIsTrue(
          PageRequest.of(0, 6, Sort.by(['id'])),
        );
        expect(exact.content, hasLength(6));
        expect(exact.hasNext, isFalse);
      }),
    );

    test(
      'a List with a Pageable gives the window',
      () => run(() async {
        final window = await books.findByInStockEquals(
          true,
          PageRequest.of(1, 2, Sort.by(['id'])),
        );
        expect(ids(window), [4, 6]);
      }),
    );

    test(
      'an unpaged Pageable gives everything, sorted',
      () => run(() async {
        final all = await books.findByInStockEquals(
          true,
          const Pageable.unpaged(),
        );
        expect(all, hasLength(6));
      }),
    );
  });

  group('Top and First', () {
    test(
      'First and Top limit the result',
      () => run(() async {
        expect((await books.findFirstByOrderByYearAsc())?.id, 1);
        expect(ids(await books.findTop2ByOrderByYearDesc()), [8, 7]);
      }),
    );

    test(
      'Top combines with a Pageable: the window is cut at the limit',
      () => run(() async {
        final sort = Sort.by(['year']);
        final first = await books.findTop3ByInStock(
          true,
          PageRequest.of(0, 2, sort),
        );
        expect(ids(first.content), [1, 2]);
        expect(first.totalElements, 3);
        expect(first.totalPages, 2);
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
        expect(await books.existsByTitle('Dune'), isTrue);
        expect(await books.existsByTitle('Nope'), isFalse);
      }),
    );

    test(
      'delete returns the number, nothing or the deleted',
      () => run(() async {
        expect(await books.deleteByYearLessThan(1970), 2);
        expect(await books.count(), 6);
        await books.removeByTitle('Snow Crash');
        expect(await books.existsByTitle('Snow Crash'), isFalse);
        final deleted = await books.deleteByInStock(false);
        expect(ids(deleted), [3, 5]);
        expect(deleted, isA<List<Book>>());
        expect(ids(await books.findAll()), [6, 7, 8]);
      }),
    );
  });

  test('queries on an empty table give empty results', () async {
    await withExample((app) async {
      expect(await app.books.findByTitle('x'), isEmpty);
      expect(await app.books.countByInStock(true), 0);
      expect(await app.books.findFirstByOrderByYearAsc(), isNull);
      final page = await app.books.findByYearAfter(
        0,
        PageRequest.of(0, 5),
      );
      expect(page.totalElements, 0);
      expect(page.content, isEmpty);
    });
  });
}
