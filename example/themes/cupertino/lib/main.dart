// Theme Showcase Cupertino: the theme of spring_boot_starter_flutter on a
// CupertinoApp, with Cupertino widgets only. Run it with `flutter run`
// (desktop, `-d chrome` for the web) and read lib/resources/application.yml
// next to it: every look is there.
//
// The pages are the @ScreenRoute screens of lib/src/pages/, in the tabs of
// the Shell (lib/src/app/shell.dart): SpringApp builds a
// CupertinoApp.router on them, with addresses in the browser.
//
// The app widget (a CupertinoApp) and its four themes are built from
// spring.flutter.* in lib/resources/, the pages read the theme through
// `context.theme` (generated in lib/spring_gen/theme.spring.keys.dart).
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
  ),
);
