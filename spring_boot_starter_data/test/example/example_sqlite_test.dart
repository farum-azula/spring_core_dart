// The example on SQLite: the application as `main` starts it (the real
// SpringApplication, lib/resources/application.properties, the runners) and
// as a test starts it (a context over the same beans).
import 'dart:async';
import 'dart:io';

import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../../example/example.dart';
import '../../example/example.spring.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('example_sqlite');
    SpringLog.level = SpringLogLevel.info;
    SpringLog.resetLevels();
  });

  tearDown(() {
    SpringLog.level = SpringLogLevel.info;
    SpringLog.resetLevels();
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  String database() => '${temp.path}/library.db';

  Future<void> withLibrary(
    FutureOr<void> Function(AssertableApplicationContext context) body,
  ) => const ApplicationContextRunner()
      .withUserConfiguration($application)
      .withAutoConfiguration(springBootStarterDataAutoConfiguration)
      .withPropertyValues(['spring.datasource.url=sqlite:file:${database()}'])
      .runAsync<void>((context) async {
        if (context.startupFailure case final failure?) {
          throw StateError('The example did not start: $failure');
        }
        await body(context);
      });

  test('main starts it: the migrations, then the runners', () async {
    final records = <SpringLogRecord>[];
    final stop = SpringLog.listen(records.add);
    try {
      final context = await springApplication.runAsync([
        '--spring.datasource.url=sqlite:file:${database()}',
        '--spring.main.banner-mode=off',
      ]);
      await context.closeAsync();
    } finally {
      stop();
    }
    final messages = records.map((r) => r.message).join('\n');
    // The tour of the runner and its report (the join and the view).
    expect(messages, contains('Successfully applied'));
    expect(messages, contains('saved Snow Crash as #3, version 1'));
    expect(messages, contains('BookCard(Snow Crash (1992) by Neal, 1992)'));
    expect(messages, contains('William Gibson: 1 book(s)'));
    expect(messages, contains('order of Ada: 2 lines'));
    // The bookmark went with its book.
    expect(messages, contains('bookmarks left: 0'));
    // application.properties turns show-sql on.
    expect(
      records.any(
        (r) =>
            r.loggerName == 'spring.jdbc.core.JdbcTemplate' &&
            r.level == SpringLogLevel.info,
      ),
      isTrue,
    );

    final db = sqlite.sqlite3.open(database());
    final titles = db.select('select title from books order by id');
    final history = db.select('select version from schema_history');
    db.close();
    expect(titles.map((r) => r['title']), [
      'Dune',
      'Neuromancer',
      'Snow Crash (1992)',
    ]);
    // V1 to V5 and the repeatable migration.
    expect(history, hasLength(6));
  });

  test('a URL no driver handles stops the start with a report', () async {
    final records = <SpringLogRecord>[];
    final stop = SpringLog.listen(records.add);
    Object? error;
    try {
      final context = await springApplication.runAsync([
        '--spring.datasource.url=mysql://db:3306/shop',
        '--spring.main.banner-mode=off',
      ]);
      await context.closeAsync();
    } on Object catch (caught) {
      error = caught;
    } finally {
      stop();
    }
    expect(error, isNotNull);
    final report = records
        .where((r) => r.message.contains('APPLICATION FAILED TO START'))
        .map((r) => r.message)
        .join();
    expect(
      report,
      contains('spring.datasource.url is mysql://db:3306/shop'),
    );
    // The example has the drivers of SQLite and PostgreSQL: not this one.
    expect(report, contains('No driver is known for the scheme "mysql"'));
  });

  test('a start without a database URL stays in memory', () async {
    await exampleRunnerWithoutDatabase().runAsync<void>((context) {
      expect(context.startupFailure, isNull);
      expect(
        context.getBean<PlatformTransactionManager>(),
        isA<InMemoryTransactionManager>(),
      );
      expect(context, isNot(hasBean<BookReportRepository>()));
      expect(context, isNot(hasBean<DataSource>()));
    });
  });

  test('the transaction manager of the example is the database one', () {
    return withLibrary((context) async {
      expect(
        context.getBean<PlatformTransactionManager>(),
        isA<DataSourceTransactionManager>(),
      );
      // The memory repository keeps its own store and manager.
      final reviews = context.getBean<ReviewRepository>();
      await reviews.save(Review(text: 'kept in memory'));
      expect(await reviews.count(), 1);
    });
  });

  test('@Transactional, @Version, the audit properties and @Lock', () {
    return withLibrary((context) async {
      final library = context.getBean<Library>();
      final books = context.getBean<BookRepository>();
      final dune = await library.add('Dune', 1965, author: 'Frank Herbert');
      expect(dune.version, 1);
      expect(dune.createdBy, 'librarian');
      expect(dune.createdAt, isNotNull);

      // The rename holds the row (the lock is its first statement) and
      // bumps the version.
      final renamed = await library.rename(1965, 'Dune', 'Dune (1965)');
      expect(renamed!.version, 2);
      expect(await library.rename(1965, 'Dune', 'again'), isNull);

      // A stale copy cannot overwrite: @Version.
      dune.title = 'Stale';
      await expectLater(
        books.save(dune),
        throwsA(isA<OptimisticLockingFailureException>()),
      );

      // Outside a transaction, @Lock refuses to run unlocked.
      await expectLater(
        books.findOneByYearAndTitle(1965, 'Dune (1965)'),
        throwsA(isA<IllegalTransactionStateException>()),
      );
    });
  });

  test('the join, the view and a derived query', () {
    return withLibrary((context) async {
      final library = context.getBean<Library>();
      final authors = context.getBean<AuthorRepository>();
      final books = context.getBean<BookRepository>();
      final herbert = await authors.save(Author(name: 'Frank Herbert'));
      final gibson = await authors.save(Author(name: 'William Gibson'));
      for (final (title, year, writer) in [
        ('Dune', 1965, herbert),
        ('Neuromancer', 1984, gibson),
        ('Count Zero', 1986, gibson),
      ]) {
        await books.save(
          Book(
            title: title,
            year: year,
            author: AggregateReference<Author, int>(writer.id!),
          ),
        );
      }
      await library.add('Anonymous', 1999);

      final reports = context.getBean<BookReportRepository>();
      final cards = await reports.cardsSince(1980);
      expect(cards.map((c) => '${c.title}/${c.authorName}'), [
        'Neuromancer/William Gibson',
        'Count Zero/William Gibson',
      ]);

      final counts = await context
          .getBean<JdbcClient>()
          .sql('select name, books from author_book_counts order by name')
          .query<String>((row) => '${row['name']}=${row['books']}')
          .list();
      expect(counts, ['Frank Herbert=1', 'William Gibson=2']);

      expect(await library.decade(1980), hasLength(2));
      final order = await library.order('Ada', {'dune-hc': 1, 'dune-pb': 2});
      final loaded = await library.orders.findById(order.id!);
      expect(loaded!.lines.map((l) => l.sku), ['dune-hc', 'dune-pb']);
    });
  });
}

// The example's beans with no database URL, as the other tests start it.
ApplicationContextRunner exampleRunnerWithoutDatabase() =>
    const ApplicationContextRunner()
        .withUserConfiguration($application)
        .withAutoConfiguration(springBootStarterDataAutoConfiguration);
