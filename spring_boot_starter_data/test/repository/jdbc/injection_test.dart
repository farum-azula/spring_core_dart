import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

// Hostile text in every operator of the derived queries and in the
// parameters of the @Query methods is matched literally: it never changes
// a statement, and the SQL store answers as the in-memory store does.
const List<String> hostile = [
  "' OR 1=1 --",
  '"; DROP TABLE books; --',
  "'; DELETE FROM books; --",
  r'\',
  '%',
  '_',
  r'100\%',
  "a'b",
  '"quoted"',
  '--',
  '/* comment */',
  ':name',
  '?',
  r'${x}',
  '#{1+1}',
  ':#{1+1}',
  '`tick`',
  'Ünï\ncode',
  _union,
];

const String _union =
    "x' UNION SELECT id, name, 1, null, 1, null, null, null, null, null "
    'FROM authors --';

void main() {
  late Jdbc jdbc;
  late BookQueries sql;
  late BookQueries memory;
  late SqlBooks queries;

  Future<void> run(FutureOr<void> Function() body) => withJdbc((j) async {
    jdbc = j;
    sql = j.sqlBooks;
    memory = j.memoryBooks;
    queries = j.sqlBooks;
    // The same books in both stores: the normal ones, and one for each
    // hostile text as its title and its subtitle.
    for (final books in [sql, memory]) {
      await books.saveAll([
        Book(title: 'Dune', year: 1965, subtitle: 'sequel'),
        Book(title: 'Neuromancer', year: 1984),
        Book(title: 'plain', year: 1999, subtitle: 'a_b'),
        for (final (i, text) in hostile.indexed)
          Book(title: text, year: 3000 + i, subtitle: text),
      ]);
    }
    await body();
  });

  setUpAll(() => SpringLog.handler = (_) {});

  Future<void> expectIntact() async {
    expect(
      await jdbc.jdbc.queryForObject<int>(
        "select count(*) from sqlite_master where name = 'books'",
      ),
      1,
    );
    expect(await sql.count(), 3 + hostile.length);
    expect(await jdbc.sqlAuthors.count(), 0);
  }

  group('derived queries: the same literal answers on both stores', () {
    final operators =
        <String, Future<List<Book>> Function(BookQueries, String)>{
          'is': (b, h) => b.findByTitle(h),
          'is, ignoring the case': (b, h) => b.findByTitleIgnoreCase(h),
          'not': (b, h) => b.findByTitleNot(h),
          'not, ignoring the case': (b, h) => b.findByTitleNotIgnoreCase(h),
          'starting with': (b, h) => b.findByTitleStartingWith(h),
          'ending with': (b, h) => b.findByTitleEndingWith(h),
          'containing': (b, h) => b.findByTitleContaining(h),
          'not containing': (b, h) => b.findByTitleNotContaining(h),
          'containing, ignoring the case': (b, h) =>
              b.findByTitleContainingIgnoreCase(h),
          'starting with, ignoring the case': (b, h) =>
              b.findByTitleStartingWithIgnoreCase(h),
          'ending with, ignoring the case': (b, h) =>
              b.findByTitleEndingWithIgnoreCase(h),
          'like': (b, h) => b.findByTitleLike(h),
          'not like': (b, h) => b.findByTitleNotLike(h),
          'like, ignoring the case': (b, h) => b.findByTitleLikeIgnoreCase(h),
          'in': (b, h) => b.findByTitleIn([h, 'Dune']),
          'in, ignoring the case': (b, h) => b.findByTitleInIgnoreCase([h]),
          'subtitle is': (b, h) => b.findBySubtitle(h),
          'subtitle not': (b, h) => b.findBySubtitleNot(h),
          'subtitle less than': (b, h) => b.findBySubtitleLessThan(h),
          'subtitle between': (b, h) => b.findBySubtitleBetween(h, '~~~~'),
          'subtitle in': (b, h) => b.findBySubtitleIn([h, h]),
          'subtitle not in': (b, h) => b.findBySubtitleNotIn([h]),
          'subtitle like': (b, h) => b.findBySubtitleLike(h),
          'and': (b, h) => b.findByTitleAndYear(h, 1965),
          'or': (b, h) => b.findByTitleOrYear(h, 1984),
        };
    for (final MapEntry(:key, :value) in operators.entries) {
      test(
        key,
        () => run(() async {
          for (final text in hostile) {
            final fromSql = ids(await value(sql, text));
            final fromMemory = ids(await value(memory, text));
            expect(fromSql, fromMemory, reason: '$key with "$text"');
          }
          await expectIntact();
        }),
      );
    }

    test(
      'a title that equals the hostile text is found by it, only it',
      () => run(() async {
        for (final (i, text) in hostile.indexed) {
          final found = await sql.findByTitle(text);
          expect([for (final b in found) b.title], [text]);
          expect(found.single.year, 3000 + i);
          expect(await sql.countByTitleContaining(text), greaterThan(0));
          expect(await sql.existsByTitle(text), isTrue);
        }
        await expectIntact();
      }),
    );

    test(
      'deleting by a hostile text deletes only what matches',
      () => run(() async {
        expect(await sql.deleteByTitleIn(["' OR 1=1 --"]), 1);
        expect(await memory.deleteByTitleIn(["' OR 1=1 --"]), 1);
        expect(await sql.count(), 2 + hostile.length);
        expect(ids(await sql.findAll()), ids(await memory.findAll()));
        expect(await jdbc.sqlAuthors.count(), 0);
      }),
    );

    test(
      'the SQL text of every statement is free of the values',
      () => run(() async {
        final statements = <String>[];
        SpringLog.setLevel(
          'spring.jdbc.core.JdbcTemplate',
          SpringLogLevel.debug,
        );
        final stop = SpringLog.listen((r) {
          if (r.loggerName == 'spring.jdbc.core.JdbcTemplate') {
            statements.add(r.message);
          }
        });
        try {
          for (final text in hostile) {
            await sql.findByTitleContaining(text);
            await sql.findByTitleLike(text);
            await sql.findByTitle(text);
            await sql.findBySubtitleIn([text]);
          }
        } finally {
          stop();
          SpringLog.resetLevels();
        }
        expect(statements, hasLength(4 * hostile.length));
        for (final statement in statements) {
          expect(statement, isNot(contains('DROP')));
          expect(statement, isNot(contains('DELETE')));
          expect(statement, isNot(contains('OR 1=1')));
          expect(statement, isNot(contains('UNION')));
        }
      }),
    );
  });

  group('@Query: parameters are bound, never text', () {
    test(
      'by name, by pattern, by SpEL, by a list',
      () => run(() async {
        for (final (i, text) in hostile.indexed) {
          final byName = await queries.byTitle(text);
          expect([for (final b in byName) b.title], [text]);
          expect(byName.single.year, 3000 + i);
          expect(
            ids(await queries.bySubtitleText(text)),
            ids(await sql.findBySubtitle(text)),
          );
          // The query's own LIKE is SQLite's (case blind, no escape): what
          // the same statement answers when run by hand.
          expect(
            ids(await queries.byTitleLike(text)),
            await jdbc.jdbc.queryForList<int>(
              'select id from books where title like ? order by id',
              [text],
            ),
            reason: '"$text" as a pattern',
          );
          expect(
            ids(await queries.sameTitle(Book(title: text, year: 0))),
            ids(byName),
          );
          expect(
            ids(await queries.viaEntityName(text)),
            ids(byName),
          );
        }
        await expectIntact();
      }),
    );

    test(
      'a hostile value in a modifying query changes only what it says',
      () => run(() async {
        await queries.retitle(1, "'; drop table books; --");
        expect((await queries.one(1))!.subtitle, "'; drop table books; --");
        await expectIntact();
      }),
    );

    test(
      'a sort that is a statement is refused before anything runs',
      () => run(() async {
        for (final text in hostile) {
          if (RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*$').hasMatch(text)) {
            continue;
          }
          await expectLater(
            queries.afterSorted(0, Sort.by([text])),
            throwsA(isA<InvalidDataAccessApiUsageException>()),
            reason: '"$text"',
          );
          await expectLater(
            sql.findAllSorted(Sort.by([text])),
            throwsA(isA<InvalidDataAccessApiUsageException>()),
            reason: '"$text"',
          );
        }
        await expectIntact();
      }),
    );
  });
}
