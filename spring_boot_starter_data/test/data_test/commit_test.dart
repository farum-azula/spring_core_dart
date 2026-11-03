// @Commit and @Rollback(false): what commits stays for the tests after it,
// in the context's database; a failing test is rolled back even so. The
// generator writes spring_gen/data_test/commit.test.spring.dart.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/data_test/commit.test.spring.dart';
import 'app/data_test_app.dart';

@DataTest(application: 'test/data_test/app/data_test_app.dart')
class CommitTest {
  @Autowired()
  late BookRepository books;

  @Test()
  @Commit()
  Future<void> commitsABook() async {
    await books.save(Book(title: 'Dune', year: 1965));
  }

  @Test()
  Future<void> theNextTestSeesTheCommittedBook() async {
    expect(await books.count(), 1);
    // Rolled back: this test's own book is gone with it.
    await books.save(Book(title: 'Emma', year: 1815));
    expect(await books.count(), 2);
  }

  @Test()
  @Rollback(false)
  Future<void> rollbackFalseCommitsToo() async {
    expect(await books.count(), 1);
    await books.save(Book(title: 'Emma', year: 1815));
  }

  @Test()
  @Commit()
  Future<void> cleansUpAndCommitsTheDeletion() async {
    expect(await books.count(), 2);
    await books.deleteAll();
  }

  @Test()
  Future<void> startsEmptyAgain() async {
    expect(await books.count(), 0);
  }
}

// A class that commits all its tests; a method may roll back.
@DataTest(application: 'test/data_test/app/data_test_app.dart')
@Commit()
class CommitEverythingTest {
  @Autowired()
  late BookRepository books;

  @Test()
  Future<void> keepsThisBook() async {
    await books.save(Book(title: 'Dune', year: 1965));
  }

  @Test()
  @Rollback()
  Future<void> undoesThisOne() async {
    expect(await books.count(), 1);
    await books.save(Book(title: 'Emma', year: 1815));
  }

  @Test()
  Future<void> seesOnlyTheCommittedBook() async {
    expect(await books.count(), 1);
    await books.deleteAll();
  }
}

void main() => runSpringTests();
