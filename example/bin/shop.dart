// The same shop started the Spring Boot way: one annotation on main, one
// import of the generated file — no modules, no environment setup.
//
//   dart run bin/shop.dart
//   dart run bin/shop.dart --spring.profiles.active=prod --shop.max-basket-size=0
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'shop.beans.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
