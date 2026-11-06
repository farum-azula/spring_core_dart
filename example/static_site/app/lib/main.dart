// A small Flutter web site served by its Spring server (../server).
//
//   flutter build web                # writes build/web/
//   cd ../server && dart run bin/main.dart
//   open http://localhost:8081       # the pages and /api/info, one origin
//
// The pages are the @ScreenRoute screens of lib/src/pages.dart; the app
// widget and its theme come from lib/resources/application.yml.
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:static_site_app/spring_gen/main.spring.dart';

@SpringBootApplication()
void main() =>
    runApp(SpringApplicationWidget(application: () => springApplication));
