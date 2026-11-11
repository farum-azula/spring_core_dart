// A Supabase project in a Spring Boot application: a table behind a
// Spring Data repository, a bucket and an Edge Function behind declared
// interfaces. The generator writes their implementations and picks the
// starter up (example.spring.dart, from `dart run build_runner build`).
//
//   dart run example/example.dart
//
// It starts a local server standing in for the project, so it runs
// anywhere. With a real project, set spring.supabase.url and
// spring.supabase.anon-key instead (see the README).

import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

import 'spring_gen/example.spring.dart';

/// A row of the table `todos`.
@Introspected()
@Table('todos')
class Todo {
  Todo({required this.title, this.done = false, this.id});

  @Id()
  int? id;

  String title;
  bool done;
}

/// The table through the project's REST API (`/rest/v1/todos`): the
/// methods are derived from their names, as in Spring Data.
abstract interface class Todos implements ListCrudRepository<Todo, int> {
  Future<List<Todo>> findByDoneOrderById(bool done);
}

/// The bucket `avatars` (`/storage/v1`).
@StorageBucket('avatars')
abstract interface class Avatars {
  /// The address anyone can read the file at (a public bucket).
  @PublicUrl('{userId}/avatar.png')
  Uri link(String userId);
}

/// The Edge Functions of the project (`/functions/v1`), a Feign client.
@EdgeFunctions()
abstract interface class Functions {
  @EdgeFunction('hello')
  Future<Map<String, Object?>> hello(@RequestBody() Map<String, Object?> body);
}

/// Uses the three once the application has started; `@Log` gives it the
/// `log` getter.
@Component()
@Log(topic: 'example')
class Tour implements CommandLineRunner {
  Tour(this.todos, this.avatars, this.functions);

  final Todos todos;
  final Avatars avatars;
  final Functions functions;

  @override
  Future<void> run(List<String> args) async {
    final saved = await todos.save(Todo(title: 'Write the example'));
    final open = await todos.findByDoneOrderById(false);
    final answer = await functions.hello({'name': 'Ada'});
    log
      ..info('saved: ${saved.id}') // saved: 1
      ..info('open: ${[for (final todo in open) todo.title]}')
      ..info('avatar: ${avatars.link('u1')}')
      ..info('function: ${answer['message']}'); // function: hello Ada
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final project = await _project();
  final context = await springApplication.runAsync(
    args,
    properties: {
      'spring.supabase.url': 'http://127.0.0.1:${project.port}',
      'spring.supabase.anon-key': 'anon-key',
      'spring.main.banner-mode': 'off',
      // The package's tests bring the web starter; the example serves
      // nothing.
      'spring.main.web-application-type': 'none',
    },
  );
  await context.closeAsync();
  await project.close(force: true);
}

/// A local server standing in for the project: its REST API over one
/// table kept in memory, and the function `hello`.
Future<io.HttpServer> _project() async {
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  final rows = <Map<String, Object?>>[];
  server.listen((request) async {
    final body = await utf8.decoder.bind(request).join();
    final response = request.response
      ..headers.contentType = io.ContentType.json;
    switch ((request.method, request.uri.path)) {
      case ('POST', '/rest/v1/todos'):
        final sent = jsonDecode(body);
        final row = {
          ...(sent is List ? sent.first : sent) as Map<String, Object?>,
          'id': rows.length + 1,
        };
        rows.add(row);
        response
          ..statusCode = 201
          ..write(jsonEncode([row]));
      case ('GET', '/rest/v1/todos'):
        final done = request.uri.queryParameters['done'] == 'eq.true';
        response.write(
          jsonEncode([
            for (final row in rows)
              if (row['done'] == done) row,
          ]),
        );
      case ('POST', '/functions/v1/hello'):
        final name = (jsonDecode(body) as Map)['name'];
        response.write(jsonEncode({'message': 'hello $name'}));
      default:
        response
          ..statusCode = 404
          ..write('{}');
    }
    await response.close();
  });
  return server;
}
