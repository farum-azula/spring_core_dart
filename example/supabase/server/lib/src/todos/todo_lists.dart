import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:supabase_example_server/src/todos/todo.dart';

/// What a list of todos can do in one transaction.
@Service()
class TodoLists {
  TodoLists(this.todos);

  final Todos todos;

  /// Adds both todos or neither: two writes in one transaction of the
  /// project's database, as the caller. A second title that is empty is
  /// refused after the first row was written, and the transaction takes
  /// that row back.
  @Transactional()
  Future<List<Todo>> addPair(String listId, String first, String second) async {
    final now = DateTime.now().toUtc();
    final one = await todos.save(
      Todo(title: first, listId: listId, createdAt: now),
    );
    if (second.trim().isEmpty) {
      throw ArgumentError.value(second, 'second', 'The title is empty');
    }
    final two = await todos.save(
      Todo(title: second, listId: listId, createdAt: now),
    );
    return [one, two];
  }
}
