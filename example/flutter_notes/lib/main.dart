// Notes in a Flutter app that also serves them over HTTP: the app starts
// a REST API (spring_boot_starter_web) on 127.0.0.1, in the same isolate
// and with the same beans as the widgets. A note added on the screen is
// at GET /api/notes; one POSTed to the API shows up on the screen.
//
//   flutter run -d macos          # or linux, windows, android, ios
//   curl localhost:8080/api/notes
//   curl -i localhost:8080/api/notes -H 'Content-Type: application/json' \
//       -d '{"text": "Buy milk"}'
//   curl -N localhost:8080/api/notes/events     # server-sent events
import 'package:flutter/widgets.dart';
import 'package:flutter_notes/main.spring.dart';
import 'package:flutter_notes/src/notes/notes_page.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const NotesPage(),
  ),
);
