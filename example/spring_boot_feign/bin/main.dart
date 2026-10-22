// A Spring Boot application talking to real public servers: a REST API
// through a Feign client, an event stream (server-sent events) and a
// WebSocket echo server. Everything else is found by the generator: the
// clients, their models, the configuration and the runners in lib/src/.
//
//   dart run build_runner build   # after changing beans or clients
//   dart run bin/main.dart
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'main.beans.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
