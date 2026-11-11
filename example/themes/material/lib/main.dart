// Theme Showcase: an app about the theme of spring_boot_starter_flutter and
// nothing else. Run it with `flutter run` (desktop, `-d chrome` for the web)
// and read lib/resources/application.yml next to it: every look is there.
//
// The app widget (a MaterialApp) and its six themes are built from
// spring.flutter.* in lib/resources/, the pages read the theme through
// `context.theme` (generated in lib/spring_gen/theme.spring.keys.dart).
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';

// No home: the screens of the navigation make the app (the pages, in the
// branches of the Shell); `/` opens the colors
// (spring.flutter.navigation.initial).
@SpringBootApplication()
void main() =>
    runApp(SpringApplicationWidget(application: () => springApplication));
