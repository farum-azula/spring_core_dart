// An application without a database: its repositories use the in-memory
// store, and a @DataTest runs its tests in the transaction of that store
// (memory_app.spring.dart, from `dart run build_runner build`).
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import 'memory_app.spring.dart';

@Table('notes')
class Note {
  Note({required this.text, this.id});

  @Id()
  int? id;

  String text;
}

abstract interface class NoteRepository
    implements ListCrudRepository<Note, int> {
  Future<List<Note>> findByText(String text);
}

/// A service: left out of the slice.
@Service()
class NoteService {
  NoteService(this.notes);

  final NoteRepository notes;
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
