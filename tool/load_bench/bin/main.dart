// The server the load tests measure: one endpoint per scenario of
// tool/load.dart (docs/load-testing.md). Everything is found by the
// generator: the beans of lib/src/ (lib/src/app.dart), the files of
// lib/resources/ and the auto-configuration of the starters in
// pubspec.yaml.
//
//   dart run build_runner build               # after changing beans
//   dart run bin/main.dart --server.port=18080
//   dart run bin/main.dart --bench.directory=/tmp/bench
//   dart run bin/main.dart --bench.files.huge-size=1GB
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

import 'spring_gen/main.spring.dart';

// Asynchronous: the SQL data source migrates its schema at startup.
@SpringBootApplication()
Future<void> main(List<String> args) => runApplicationAsync(args);
