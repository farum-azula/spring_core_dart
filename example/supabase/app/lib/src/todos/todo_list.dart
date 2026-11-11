import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart'
    show DataAccessException;
import 'package:supabase_example_app/src/todos/todo.dart';

/// `todos.list` in application.yml: the list the app shows.
@ConfigurationProperties('todos')
class TodoProperties {
  String list = 'home';
}

/// The beans of [TodoList].
typedef TodoListBeans = (
  Todos,
  TodoProperties,
);

/// The user's todos, live: the list is what the repository's watched
/// query gives, so a todo added here, in another window or by the server
/// of the example shows up by itself. Adding, ticking and deleting only
/// write through the repository; none of them touches the list.
class TodoList extends SpringStatefulWidget<TodoListBeans> {
  const TodoList({super.key});

  @override
  State<TodoList> createState() => _TodoListState();
}

class _TodoListState extends SpringState<TodoList, TodoListBeans> {
  final _title = TextEditingController();

  // One subscription for the life of the widget, which is the time one
  // user is signed in.
  late final Stream<List<Todo>> _todos = beans.$1.watchByListIdOrderByIdAsc(
    beans.$2.list,
  );

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// Runs a write; what the project refuses is shown, not thrown.
  Future<void> _write(Future<void> Function(Todos todos) write) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await write(beans.$1);
    } on DataAccessException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Not saved: ${error.runtimeType}')),
      );
    }
  }

  Future<void> _add() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      return;
    }
    _title.clear();
    await _write(
      (todos) => todos.save(
        Todo(
          title: title,
          listId: beans.$2.list,
          createdAt: DateTime.now().toUtc(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('todo-title'),
                controller: _title,
                decoration: const InputDecoration(labelText: 'What to do'),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('todo-add'),
              onPressed: _add,
              tooltip: 'Add',
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      Expanded(
        child: StreamBuilder(
          stream: _todos,
          builder: (context, todos) {
            if (todos.hasError) {
              return Center(
                child: Text('No list: ${todos.error.runtimeType}'),
              );
            }
            if (!todos.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (todos.requireData.isEmpty) {
              return const Center(child: Text('Nothing to do'));
            }
            return ListView(
              children: [
                for (final todo in todos.requireData)
                  CheckboxListTile(
                    key: ValueKey(todo.id),
                    value: todo.done,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      todo.title,
                      style: todo.done
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                    onChanged: (done) => _write(
                      (todos) => todos.save(todo..done = done ?? false),
                    ),
                    secondary: IconButton(
                      onPressed: () =>
                          _write((todos) => todos.deleteById(todo.id!)),
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}
