// A @DataTest(transactionManager:) on the application with three stores:
// only the named manager's database is rolled back; the primary database
// and the memory write for real. The generator writes
// spring/data_test/named_manager.test.spring.dart.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring/data_test/named_manager.test.spring.dart';
import 'mixed_app/mixed_app.dart';

@DataTest(
  application: 'test/data_test/mixed_app/mixed_app.dart',
  transactionManager: 'archive',
)
class NamedManagerTest {
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
  Future<void> onlyTheNamedDatabaseWasRolledBack() async {
    expect(await counts(), [1, 0, 1]);
  }

  @Test()
  Future<void> cleansUp() async {
    await books.deleteAll();
    await notes.deleteAll();
    expect(await counts(), [0, 0, 0]);
  }
}

void main() => runSpringTests();
