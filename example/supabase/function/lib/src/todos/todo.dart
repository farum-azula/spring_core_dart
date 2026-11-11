import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

/// A row of the project's table `todos`. The owner is set by the database
/// (`auth.uid()`), and its policy shows a user their own rows only.
@Introspected()
@Table('todos')
class Todo {
  Todo({
    required this.title,
    required this.listId,
    this.done = false,
    this.id,
    this.createdAt,
    this.version,
  });

  @Id()
  int? id;

  String title;
  String listId;
  bool done;
  DateTime? createdAt;

  @Version()
  int? version;
}

/// The todos over the project's REST API, as the caller of the function:
/// the token of the request goes on to the project.
abstract interface class Todos implements ListCrudRepository<Todo, int> {
  Future<List<Todo>> findByListIdOrderById(String listId);

  /// The database function `close_all`.
  @Procedure('close_all')
  Future<int> closeAll(String listId);
}
