// An application on the SQL path (spring.supabase.db.url): its repository
// names no store, so it uses SQL over that address, with transactions and
// locks. The generator writes its beans
// (../spring_gen/sql_app/sql_app.spring.dart) and, because the package
// lists `postgres`, the driver's glue.
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

import '../spring_gen/sql_app/sql_app.spring.dart';

@Table('todos')
class SqlTodo {
  SqlTodo({
    required this.title,
    required this.listId,
    this.done = false,
    this.id,
    this.version,
  });

  @Id()
  int? id;

  String title;
  String listId;
  bool done;

  @Version()
  int? version;
}

abstract interface class SqlTodos implements ListCrudRepository<SqlTodo, int> {
  Future<List<SqlTodo>> findByListIdOrderById(String listId);

  @Lock(LockMode.pessimisticWrite)
  Future<SqlTodo?> findFirstByListIdOrderById(String listId);

  @Query('select count(*) from todos')
  Future<int> visible();
}

@Service()
class TodoLists {
  TodoLists(this.todos);

  final SqlTodos todos;

  /// Adds both or neither: the second title must not be empty.
  @Transactional()
  Future<void> addTwo(String listId, String first, String second) async {
    await todos.save(SqlTodo(title: first, listId: listId));
    if (second.isEmpty) {
      throw ArgumentError('the second title is empty');
    }
    await todos.save(SqlTodo(title: second, listId: listId));
  }

  /// Closes the first open todo of a list, holding its row.
  @Transactional()
  Future<SqlTodo?> closeFirst(String listId) async {
    final first = await todos.findFirstByListIdOrderById(listId);
    if (first == null) {
      return null;
    }
    return await todos.save(first..done = true);
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
