// NEON Books, the bookstore's app: the Flutter guide of spring_core_dart.
// A client of the server guide (example/server_guide): start the server
// there with `dart run bin/main.dart`, then this app with `flutter run`.
// The README walks through it chapter by chapter.
//
// The app widget (a MaterialApp here) is built from spring.flutter.app.*
// in lib/resources/application.properties, its themes from
// spring.flutter.theme.* in lib/resources/application.yml.
import 'package:flutter/widgets.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/app/home_page.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const HomePage(),
  ),
);
