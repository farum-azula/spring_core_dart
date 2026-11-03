// Theme Showcase Cupertino: the theme of spring_boot_starter_flutter on a
// CupertinoApp, with Cupertino widgets only. Run it with `flutter run`
// (desktop, `-d chrome` for the web) and read lib/resources/application.yml
// next to it: every look is there.
//
// The app widget (a CupertinoApp) and its four themes are built from
// spring.flutter.* in lib/resources/, the pages read the theme through
// `context.theme` (generated in lib/spring_gen/theme.spring.dart).
import 'package:flutter/cupertino.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/app/shell.dart';

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const Shell(),
  ),
);
