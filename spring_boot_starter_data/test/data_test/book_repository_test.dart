// A @DataTest class on the repositories of the application: the data beans
// without the service and the runner, an in-memory SQLite database with the
// migrations applied, and a transaction rolled back after each test. The
// generator writes spring/data_test/book_repository.test.spring.dart.
import 'dart:io';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring/data_test/book_repository.test.spring.dart';
import 'app/data_test_app.dart';

@DataTest(application: 'test/data_test/app/data_test_app.dart')
class BookRepositoryTest {
  @Autowired()
  late BookRepository books;

  @Autowired()
  late DataSource dataSource;

  @Autowired()
  late JdbcClient jdbc;

  @Autowired()
  late ApplicationContext context;

  @Autowired()
  late BookService? service;

  // Tests run in the order of the class: each of the next two starts with
  // what the one before left, which is nothing.
  @Test()
  Future<void> startsWithoutTheBookTheRunnerWouldSave() async {
    expect(await books.count(), 0);
  }

  @Test()
  Future<void> savesAndFindsBooks() async {
    await books.save(Book(title: 'Dune', year: 1965));
    await books.save(Book(title: 'Neuromancer', year: 1984));

    expect(await books.findByTitle('Dune'), hasLength(1));
    final recent = await books.findByYearGreaterThan(1970);
    expect(recent.map((book) => book.title), ['Neuromancer']);
    expect(await books.count(), 2);
  }

  @Test()
  Future<void> theBooksOfThePreviousTestAreGone() async {
    expect(await books.count(), 0);
    expect(await books.findByTitle('Dune'), isEmpty);
  }

  @Test()
  Future<void> auditsWithTheAuditorOfTheApplication() async {
    final book = await books.save(Book(title: 'Dune', year: 1965));

    expect(book.createdBy, 'reader');
    expect(book.createdAt, isNotNull);
  }

  @Test()
  void leavesOutTheServiceAndTheRunner() {
    expect(service, isNull);
    expect(context.containsBean('bookService'), isFalse);
    expect(context.containsBean('seeder'), isFalse);
    // The data beans are there.
    expect(context.containsBean('bookRepository'), isTrue);
    expect(context.containsBean('reader'), isTrue);
  }

  @Test()
  Future<void> runsOnInMemorySqliteWithTheMigrationsApplied() async {
    // The application is configured with a file, which is never opened.
    expect(dataSource.settings.url.toString(), 'sqlite::memory:');
    expect(File('build/data_test_app.db').existsSync(), isFalse);

    final applied = await jdbc
        .sql('select count(*) from schema_history')
        .query<int>()
        .single();
    expect(applied, 2);

    // The unique index of the second migration.
    await books.save(Book(title: 'Dune', year: 1965));
    await expectLater(
      books.save(Book(title: 'Dune', year: 1965)),
      throwsA(isA<DuplicateKeyException>()),
    );
  }
}

void main() => runSpringTests();
