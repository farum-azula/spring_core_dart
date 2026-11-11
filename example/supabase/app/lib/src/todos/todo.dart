import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

/// A row of the project's table `todos`. Its `owner` column is not here:
/// the database sets it to the signed-in user (`default auth.uid()`), and
/// its policy shows a user only their own rows.
@Table('todos')
class Todo {
  Todo({
    required this.title,
    required this.listId,
    this.done = false,
    this.id,
    this.createdAt,
  });

  @Id()
  int? id;

  String title;
  String listId;
  bool done;
  DateTime? createdAt;
}

/// The todos, on the project's REST API (the app sets no
/// `spring.supabase.db.url`), each call with the user's token.
abstract interface class Todos implements ListCrudRepository<Todo, int> {
  /// The todos of a list, now and again after every change of the table
  /// (Realtime tells, the query runs again): a live list. One request of
  /// `GET /rest/v1/todos?list_id=eq.<list>&order=id.asc` each time.
  Stream<List<Todo>> watchByListIdOrderByIdAsc(String listId);
}
