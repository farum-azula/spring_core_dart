import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';
import 'package:supabase_example_function/src/todos/todo.dart';

@Introspected()
class NewTodo {
  const NewTodo({required this.title, required this.listId});

  @NotBlank()
  final String title;

  @NotBlank()
  final String listId;
}

@Introspected()
class Closed {
  const Closed(this.closed);

  final int closed;
}

/// `/functions/v1/api/todos`: the name of the function is the context
/// path, so the mappings are those of a server.
@RestController()
@RequestMapping('/todos')
class TodoController {
  TodoController(this.todos);

  final Todos todos;

  @GetMapping()
  Future<List<Todo>> list(@RequestParam('list') String listId) =>
      todos.findByListIdOrderById(listId);

  // Ten a minute for each user, counted in the project's database: every
  // instance of the function shares the count.
  @PostMapping()
  @ResponseStatus(HttpStatus.created)
  @RateLimiter('10/1m', key: '#{authentication.name}', name: 'add-todo')
  Future<Todo> add(@RequestBody() @Valid() NewTodo todo) => todos.save(
    Todo(
      title: todo.title,
      listId: todo.listId,
      createdAt: DateTime.now().toUtc(),
    ),
  );

  @PostMapping('/close-all')
  Future<Closed> closeAll(@RequestParam('list') String listId) async =>
      Closed(await todos.closeAll(listId));
}
