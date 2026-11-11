// The REST API of the todos. Nothing here asks who the caller is: the
// database does (row-level security), so a user's list is theirs alone
// whatever id or list a request names.
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:supabase_example_server/src/todos/todo.dart';
import 'package:supabase_example_server/src/todos/todo_lists.dart';

/// The body of `POST /api/todos`.
@Introspected()
class NewTodo {
  const NewTodo({required this.title, required this.listId});

  @NotBlank()
  final String title;

  @NotBlank()
  final String listId;
}

/// The body of `POST /api/todos/pair`.
@Introspected()
class NewPair {
  const NewPair({
    required this.listId,
    required this.first,
    required this.second,
  });

  @NotBlank()
  final String listId;

  @NotBlank()
  final String first;

  /// Not validated: an empty one shows the transaction rolling back.
  final String second;
}

/// The answer of `POST /api/todos/close`.
@Introspected()
class Closed {
  const Closed(this.closed);

  final int closed;
}

@RestController()
@RequestMapping('/api/todos')
class TodoController {
  TodoController(this.todos, this.lists);

  final Todos todos;
  final TodoLists lists;

  /// `GET /api/todos?list=home`: the caller's todos of a list.
  @GetMapping()
  Future<List<Todo>> list(@RequestParam('list') String listId) =>
      todos.findByListIdOrderById(listId);

  @PostMapping()
  @ResponseStatus(HttpStatus.created)
  Future<Todo> add(@RequestBody() @Valid() NewTodo todo) => todos.save(
    Todo(
      title: todo.title,
      listId: todo.listId,
      createdAt: DateTime.now().toUtc(),
    ),
  );

  /// Two todos or none (`TodoLists.addPair`, `@Transactional`).
  @PostMapping('/pair')
  @ResponseStatus(HttpStatus.created)
  Future<List<Todo>> addPair(@RequestBody() @Valid() NewPair pair) =>
      lists.addPair(pair.listId, pair.first, pair.second);

  /// `PUT /api/todos/7/done?value=true`. A todo of another user is not
  /// there for the caller: 404.
  @PutMapping('/{id}/done')
  Future<Todo> setDone(
    @PathVariable() int id, {
    @RequestParam('value') bool done = true,
  }) async {
    final todo = await todos.findById(id);
    if (todo == null) {
      throw ResponseStatusException(HttpStatus.notFound, 'No todo $id');
    }
    return await todos.save(todo..done = done);
  }

  /// `POST /api/todos/close?list=home`: the database function `close_all`.
  @PostMapping('/close')
  Future<Closed> close(@RequestParam('list') String listId) async =>
      Closed(await todos.closeAll(listId));

  @DeleteMapping('/{id}')
  @ResponseStatus(HttpStatus.noContent)
  Future<void> delete(@PathVariable() int id) => todos.deleteById(id);
}
