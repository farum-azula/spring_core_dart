// @Transactional(transactionManager:) on a test method of a @DataTest class:
// that test runs in a transaction of the named manager only, the others
// (without it) in one of every manager. The generator writes
// spring/data_test/per_test_manager.test.spring.dart.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring/data_test/per_test_manager.test.spring.dart';
import 'mixed_app/mixed_app.dart';

@DataTest(application: 'test/data_test/mixed_app/mixed_app.dart')
class PerTestManagerTest {
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

  Future<void> writeEverywhere() async {
    await books.save(Book(title: 'Dune'));
    await logs.save(LogEntry(text: 'saved'));
    await notes.save(Note(text: 'milk'));
  }

  @Test()
  @Transactional(transactionManager: 'archive')
  Future<void> namesTheArchiveManager() async {
    await writeEverywhere();
    expect(await counts(), [1, 1, 1]);
  }

  @Test()
  Future<void> thenOnlyTheArchiveWasRolledBack() async {
    expect(await counts(), [1, 0, 1]);
    await logs.save(LogEntry(text: 'gone with the test'));
  }

  @Test()
  @Transactional(transactionManager: 'archive')
  Future<void> cleansUpTheOthers() async {
    await books.deleteAll();
    await notes.deleteAll();
    expect(await counts(), [0, 0, 0]);
  }

  @Test()
  Future<void> withoutTheAnnotationEveryManagerRollsBack() async {
    expect(await counts(), [0, 0, 0]);
    await writeEverywhere();
    expect(await counts(), [1, 1, 1]);
  }

  @Test()
  Future<void> soNothingIsLeft() async {
    expect(await counts(), [0, 0, 0]);
  }
}

void main() => runSpringTests();
