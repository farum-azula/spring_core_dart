// A @DataTest on an application with three stores: the primary database, a
// named one and the memory. Each has its own transaction manager, and the
// transaction of a test must cover all of them: nothing written to any of
// them outlives a test that rolls back. The generator writes
// spring_gen/data_test/mixed_stores.test.spring.dart.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/data_test/mixed_stores.test.spring.dart';
import 'mixed_app/mixed_app.dart';

@DataTest(application: 'test/data_test/mixed_app/mixed_app.dart')
class MixedStoresTest {
  @Autowired()
  late BookRepository books;

  @Autowired()
  late LogRepository logs;

  @Autowired()
  late NoteRepository notes;

  Future<List<int>> counts() async => [
    await books.count(),
    await logs.count(),
    await notes.count(),
  ];

  @Test()
  Future<void> writesToEveryStore() async {
    await books.save(Book(title: 'Dune'));
    await logs.save(LogEntry(text: 'saved'));
    await notes.save(Note(text: 'milk'));
    expect(await counts(), [1, 1, 1]);
  }

  @Test()
  Future<void> everyStoreIsEmptyAgain() async {
    expect(await counts(), [0, 0, 0]);
  }

  @Test()
  @Commit()
  Future<void> commitsToEveryStore() async {
    await books.save(Book(title: 'Dune'));
    await logs.save(LogEntry(text: 'saved'));
    await notes.save(Note(text: 'milk'));
  }

  @Test()
  @Commit()
  Future<void> seesWhatWasCommittedAndCleansUp() async {
    expect(await counts(), [1, 1, 1]);
    await books.deleteAll();
    await logs.deleteAll();
    await notes.deleteAll();
  }

  @Test()
  Future<void> startsEmptyAfterTheCleanUp() async {
    expect(await counts(), [0, 0, 0]);
  }
}

void main() => runSpringTests();
