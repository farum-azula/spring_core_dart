// NEON Books, the bookstore's server. Everything else is found by the
// generator: the beans of lib/src/ (lib/src/app.dart), the files of
// lib/resources/ and the auto-configuration of every starter in
// pubspec.yaml.
//
//   dart run build_runner build                       # after changing beans
//   dart run bin/main.dart                            # dev: sample data, port 8080
//   dart run bin/main.dart --spring.profiles.active=prod
//   dart run bin/main.dart --server.port=9090 --neon.shop.name="Night Books"
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
