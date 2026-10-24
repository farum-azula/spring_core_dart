// The same shop started the Spring Boot way: one annotation on main, one
// import of the generated file — no modules, no environment setup.
//
//   dart run bin/shop.dart
//   dart run bin/shop.dart --spring.profiles.active=prod --shop.max-basket-size=0
//
// Like any Spring Boot application with @Scheduled tasks (StockJobs), it
// keeps running until stopped (Ctrl+C). Without the tasks it starts and
// exits:
//
//   dart run bin/shop.dart --spring.task.scheduling.enabled=false
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'shop.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
