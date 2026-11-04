// Theme Showcase NEON: a custom design system on the theme of
// spring_boot_starter_flutter. App type `widgets`: no Material, no Cupertino.
// Run it with `flutter run` (desktop, `-d chrome` for the web) and read
// lib/resources/application.yml and neon_ui's themes/neon.yml next to it.
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/app/shell.dart';

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const Shell(),
  ),
);
