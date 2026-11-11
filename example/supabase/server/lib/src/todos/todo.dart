import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

/// A row of the project's table `todos`. Its `owner` column is not here:
/// the database sets it to the caller (`default auth.uid()`), and its
/// policy shows a user only their own rows.
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

  /// Optimistic locking: an update of a row someone else changed since it
  /// was read is an `OptimisticLockingFailureException` (409).
  @Version()
  int? version;
}

/// The todos, over SQL (`spring.supabase.db.url`): the repository names no
/// store, so it uses the application's default one. Every statement runs
/// as the caller (`spring.supabase.db.rls: user`).
abstract interface class Todos implements ListCrudRepository<Todo, int> {
  Future<List<Todo>> findByListIdOrderById(String listId);

  /// The database function `close_all(list_id text)`:
  /// `select * from "close_all"(...)` in the caller's transaction. It
  /// closes the caller's open todos of a list and says how many.
  @Procedure('close_all')
  Future<int> closeAll(String listId);
}
