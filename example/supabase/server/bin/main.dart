// The server of the Supabase example: a REST API whose callers are the
// users of a Supabase project. Their access tokens are its bearer tokens,
// and every statement it runs in the project's database runs as the
// caller, so the row-level security of the project decides what a request
// reads and writes. The README of ../ says how to start a project.
//
//   dart run build_runner build      # after changing beans
//   dart run bin/main.dart           # port 8082; SUPABASE_* from the environment
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

import 'spring_gen/main.spring.dart';

// Asynchronously: a SQL data source connects while the application starts.
@SpringBootApplication()
Future<void> main(List<String> args) => runApplicationAsync(args);
