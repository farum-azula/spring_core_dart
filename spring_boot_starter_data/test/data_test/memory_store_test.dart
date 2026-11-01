// A @DataTest on an application without a database: the repositories use
// the in-memory store, and the transaction of a test is the store's. The
// generator writes spring/data_test/memory_store.test.spring.dart.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring/data_test/memory_store.test.spring.dart';
import 'memory_app/memory_app.dart';

@DataTest(application: 'test/data_test/memory_app/memory_app.dart')
class MemoryStoreTest {
  @Autowired()
  late NoteRepository notes;

  @Autowired()
  late NoteService? service;

  @Autowired()
  late ApplicationContext context;

  @Autowired()
  late PlatformTransactionManager manager;

  @Test()
  void usesTheStoreInMemoryWithoutADataSource() {
    expect(context.containsBean('dataSource'), isFalse);
    expect(manager, isA<InMemoryTransactionManager>());
    expect(service, isNull);
  }

  @Test()
  Future<void> savesANote() async {
    await notes.save(Note(text: 'milk'));
    expect(await notes.findByText('milk'), hasLength(1));
  }

  @Test()
  Future<void> theNoteIsGone() async {
    expect(await notes.count(), 0);
  }

  @Test()
  @Commit()
  Future<void> commitsANote() async {
    await notes.save(Note(text: 'bread'));
  }

  @Test()
  @Commit()
  Future<void> seesTheCommittedNoteAndCleansUp() async {
    expect(await notes.count(), 1);
    await notes.deleteAll();
  }
}

void main() => runSpringTests();
