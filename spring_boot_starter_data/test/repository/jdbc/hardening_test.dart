// What the repositories do with what comes from outside: secrets in the
// logs, a sort property or a page from a request, a row stored at version 0.
// Runs on SQLite, on PostgreSQL (when a server or Docker is there), and
// where the in-memory store has the same behaviour, on it.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../../postgres/support.dart' show postgresServerSkip, usePostgresServer;
import 'support.dart';

// A Pageable that does not come from PageRequest.of.
final class _RawPageable implements Pageable {
  const _RawPageable(this.offset, this.pageSize);

  @override
  final int offset;

  @override
  final int pageSize;

  @override
  Sort get sort => Sort.unsorted;

  @override
  int get pageNumber => 0;

  @override
  bool get isPaged => true;

  @override
  bool get isUnpaged => false;

  @override
  bool get hasPrevious => false;

  @override
  Pageable next() => this;

  @override
  Pageable previousOrFirst() => this;

  @override
  Pageable first() => this;

  @override
  Pageable withPage(int pageNumber) => this;
}

void main() {
  setUpAll(() => SpringLog.handler = (_) {});

  for (final store in const ['sqlite', 'postgres']) {
    group(
      store,
      () {
        if (store == 'postgres') {
          usePostgresServer();
        }
        _suite(postgres: store == 'postgres');
      },
      skip: store == 'postgres' ? postgresServerSkip : null,
      tags: store == 'postgres' ? 'postgres' : null,
    );
  }

  group('memory', () {
    test('a sort property that is no property: a PropertyReferenceException, '
        'escaped', () {
      return withJdbc((jdbc) async {
        await expectLater(
          jdbc.memoryBooks.findAllSorted(Sort.by(['ti\r\ntle'])),
          throwsA(_escapedProperty('ti\r\ntle')),
        );
      });
    });

    test('a nullable version is new only when null', () {
      return withJdbc((jdbc) async {
        final gauges = jdbc.memoryGauges;
        final saved = await gauges.save(Gauge(name: 'a'));
        expect(saved.version, 1);
        saved.name = 'b';
        expect((await gauges.save(saved)).version, 2);
        // At version 0 it is an update: no such row.
        await expectLater(
          gauges.save(Gauge(name: 'c', id: 99, version: 0)),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
      });
    });
  });
}

// A refused sort property, whose message holds the name escaped.
Matcher _escapedProperty(String name) => isA<PropertyReferenceException>()
    .having((e) => e.propertyName, 'propertyName', name)
    .having(
      (e) => e.message,
      'message',
      allOf(
        isNot(contains('\r')),
        isNot(contains('\n')),
        contains('<EOL>'),
        contains('"ti<EOL><EOL>tle"'),
      ),
    );

void _suite({required bool postgres}) {
  late Jdbc jdbc;

  Future<void> run(
    FutureOr<void> Function() body, {
    JdbcLogSettings logSettings = const JdbcLogSettings(),
  }) => withJdbc(postgres: postgres, logSettings: logSettings, (j) async {
    jdbc = j;
    await body();
  });

  // The log of the statements' values made by [body].
  Future<String> valueLog(FutureOr<void> Function() body) async {
    final records = <SpringLogRecord>[];
    SpringLog.setLevel('spring.jdbc.core', SpringLogLevel.trace);
    final stop = SpringLog.listen(records.add);
    try {
      await body();
    } finally {
      stop();
      SpringLog.resetLevels();
    }
    return records
        .where((r) => r.loggerName == 'spring.jdbc.core.StatementCreatorUtils')
        .map((r) => '${r.level.name}: ${r.message}')
        .join('\n');
  }

  Future<void> useMembers() async {
    final members = jdbc.sqlMembers;
    final ada = await members.save(
      Member(
        username: 'ada',
        passwordHash: 'PW-MARKER-1',
        apiToken: 'TOKEN-MARKER-1',
      ),
    );
    ada.passwordHash = 'PW-MARKER-2';
    await members.save(ada);
    await members.saveAll([
      Member(username: 'bob', passwordHash: 'PW-MARKER-3'),
      Member(username: 'eve', passwordHash: 'PW-MARKER-4'),
    ]);
    await members.findOneByUsernameAndApiToken('ada', 'TOKEN-MARKER-2');
    await members.findByPasswordHash('PW-MARKER-5');
    await members.findByUsernameIn(['ada', 'bob']);
    await members.deleteById(ada.id!);
  }

  group('secrets in the values log', () {
    test(
      'trace: save, update, saveAll and derived queries mask the values of '
      'a secret-looking column and show the others',
      () => run(() async {
        final log = await valueLog(useMembers);
        expect(log, isNot(contains('MARKER')));
        expect(log, contains('password_hash = ******'));
        expect(log, contains('api_token = ******'));
        // The other values are written, with their names.
        expect(log, contains('username = "ada" (String)'));
        expect(log, contains('username = "bob" (String)'));
        expect(log, contains('id = '));
        // No value is written by position.
        expect(log, isNot(matches(RegExp(r'\?\d+ ='))));
      }),
    );

    test(
      'show-parameters: the same values at info, masked the same',
      () => run(
        logSettings: const JdbcLogSettings(showParameters: true),
        () async {
          final records = <SpringLogRecord>[];
          final stop = SpringLog.listen(records.add);
          try {
            await useMembers();
          } finally {
            stop();
          }
          final values = records
              .where((r) => r.loggerName.endsWith('StatementCreatorUtils'))
              .toList();
          expect(values, isNotEmpty);
          expect(values.every((r) => r.level == SpringLogLevel.info), isTrue);
          final log = values.map((r) => r.message).join('\n');
          expect(log, isNot(contains('MARKER')));
          expect(log, contains('password_hash = ******'));
          expect(log, contains('username = "ada" (String)'));
        },
      ),
    );

    test(
      'a @Query with named parameters keeps masking them',
      () => run(() async {
        final log = await valueLog(() async {
          await jdbc.sqlBooks.byTitle('PW-MARKER');
          await jdbc.jdbc.update('delete from members where api_token = ?', [
            'TOKEN-MARKER',
          ]);
        });
        // A plain list has no names: shown at trace (the log of
        // development), as Spring does.
        expect(log, contains('title = "PW-MARKER"'));
        expect(log, contains('?1 = "TOKEN-MARKER"'));
      }),
    );

    test(
      'values without a name are masked at info with show-parameters',
      () => run(
        logSettings: const JdbcLogSettings(showParameters: true),
        () async {
          final records = <SpringLogRecord>[];
          final stop = SpringLog.listen(records.add);
          try {
            await JdbcTemplate(
              jdbc.dataSource,
              logSettings: const JdbcLogSettings(showParameters: true),
            ).update('delete from members where api_token = ?', [
              'TOKEN-MARKER',
            ]);
          } finally {
            stop();
          }
          final log = records.map((r) => r.message).join('\n');
          expect(log, contains('?1 = ******'));
          expect(log, isNot(contains('TOKEN-MARKER')));
        },
      ),
    );
  });

  group('a sort property from a request', () {
    const name = 'ti\r\ntle';

    test(
      'derived, CRUD and @Query sorts: a PropertyReferenceException with the '
      'name escaped',
      () => run(() async {
        final books = jdbc.sqlBooks;
        await expectLater(
          books.findAllSorted(Sort.by([name])),
          throwsA(_escapedProperty(name)),
        );
        await expectLater(
          books.findAllPaged(PageRequest.of(0, 2, Sort.by([name]))),
          throwsA(_escapedProperty(name)),
        );
        await expectLater(
          books.findByInStock(true, Sort.by([name])),
          throwsA(_escapedProperty(name)),
        );
        // A @Query takes names of columns only: anything else is refused.
        await expectLater(
          books.afterSorted(0, Sort.by(['title\r\nx'])),
          throwsA(
            isA<PropertyReferenceException>().having(
              (e) => e.message,
              'message',
              allOf(isNot(contains('\n')), contains('<EOL>')),
            ),
          ),
        );
        await expectLater(
          books.afterSorted(0, Sort.by(['title; drop table books'])),
          throwsA(isA<PropertyReferenceException>()),
        );
        // The error is a data access error (a bad use of the API).
        await expectLater(
          books.findAllSorted(Sort.by([name])),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      }),
    );
  });

  group('the offset of a page', () {
    test(
      'a negative offset is an error, not page zero',
      () => run(() async {
        final books = jdbc.sqlBooks;
        const raw = _RawPageable(-5, 3);
        await expectLater(
          books.findByYearAfter(0, raw),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
        await expectLater(
          books.findByInStockIsTrue(raw),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
        await expectLater(
          books.pageAfter(0, raw),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
        await expectLater(
          books.sliceAfter(0, raw),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
        await expectLater(
          books.findAllPaged(raw),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      }),
    );
  });

  group('@Version int? (new only when null)', () {
    test(
      'a row stored at version 0 is updated, not inserted again',
      () => run(() async {
        await jdbc.jdbc.update(
          "insert into gauges (id, name, version) values (7, 'seeded', 0)",
        );
        final gauges = jdbc.sqlGauges;
        final seeded = (await gauges.findById(7))!;
        final stale = (await gauges.findById(7))!;
        expect(seeded.version, 0);
        seeded.name = 'changed';
        final saved = await gauges.save(seeded);
        expect(saved.version, 1);
        expect((await gauges.findById(7))!.name, 'changed');
        expect(await gauges.count(), 1);
        // A stale copy still conflicts.
        stale.name = 'stale';
        await expectLater(
          gauges.save(stale),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
      }),
    );

    test(
      'a null version is inserted with version 1, then updated',
      () => run(() async {
        final gauges = jdbc.sqlGauges;
        final first = await gauges.save(Gauge(name: 'new'));
        expect(first.version, 1);
        first.name = 'again';
        expect((await gauges.save(first)).version, 2);
        expect(await gauges.count(), 1);
      }),
    );

    test(
      'a non-nullable int version is still new at 0',
      () => run(() async {
        final accounts = jdbc.sqlAccounts;
        final saved = await accounts.save(
          const Account(iban: 'DE01', owner: 'ada'),
        );
        expect(saved.version, 1);
      }),
    );
  });
}
