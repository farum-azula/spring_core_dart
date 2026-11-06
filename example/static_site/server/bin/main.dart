// The server of the static site: the Flutter web build of ../app as
// static files, and the API under /api/, on port 8081.
//
//   (cd ../app && flutter build web)
//   dart run bin/main.dart
//   dart run bin/main.dart --spring.profiles.active=prod   # web/ next to it
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
