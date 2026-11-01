// An application whose repositories are on three stores: the primary SQL
// database, a second one (`@UseDataSource`) and the one in memory
// (`@UseStore`). Each has a transaction manager of its own, and a @DataTest
// rolls all of them back (mixed_app.spring.dart, from
// `dart run build_runner build`).
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import 'mixed_app.spring.dart';

/// In the primary database.
@Table('books')
class Book {
  Book({required this.title, this.id});

  @Id()
  int? id;

  String title;
}

/// In the second database.
@Table('log_entries')
class LogEntry {
  LogEntry({required this.text, this.id});

  @Id()
  int? id;

  String text;
}

/// In memory.
@Table('notes')
class Note {
  Note({required this.text, this.id});

  @Id()
  int? id;

  String text;
}

abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {}

@UseDataSource('archive')
abstract interface class LogRepository
    implements ListCrudRepository<LogEntry, int> {}

@UseStore('memory')
abstract interface class NoteRepository
    implements ListCrudRepository<Note, int> {}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
