// A Spring Boot application calling a real public REST API with a Feign
// client. Everything else is found by the generator: the client, its
// models, the configuration and the runner in lib/src/.
//
//   dart run build_runner build   # after changing beans or clients
//   dart run bin/main.dart
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'main.beans.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
