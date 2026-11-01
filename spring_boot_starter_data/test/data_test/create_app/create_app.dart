// An application with a SQLite database and no migrations: a @DataTest
// creates the tables from the entities (create_app.spring.dart, from
// `dart run build_runner build`).
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import 'create_app.spring.dart';

@Table('tasks')
class Task {
  Task({required this.title, this.done = false, this.id});

  @Id()
  int? id;

  String title;
  bool done;
}

abstract interface class TaskRepository
    implements ListCrudRepository<Task, int> {
  Future<List<Task>> findByDone(bool done);
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
