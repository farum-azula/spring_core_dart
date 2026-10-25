// Themes from properties: lib/resources/application.yml holds the shared
// part and the standard light / dark themes, lib/resources/themes/*.yml
// one custom theme each. No ThemeData in the code; the app type, title and
// banner come from spring.flutter.app.*.
//
//   flutter run
//   flutter run --dart-define=SPRING_FLUTTER_THEME_ACTIVE=sepia
import 'package:flutter/widgets.dart';
import 'package:flutter_themes/main.spring.dart';
import 'package:flutter_themes/src/gallery_page.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const GalleryPage(),
  ),
);
