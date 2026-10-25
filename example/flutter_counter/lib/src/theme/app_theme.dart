import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The app's Material theme as a bean: `SpringApplicationWidget(home: ...)`
/// puts the `ThemeData` bean `theme` into the `MaterialApp` it builds
/// (`spring.flutter.app.type=material` in application.properties).
@Configuration()
class AppTheme {
  @Bean()
  ThemeData theme() => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
    // Japanese glyphs: the system's fonts on devices; in tests (which
    // see no system fonts) the cut-down font of test/fonts/.
    fontFamilyFallback: const ['Noto Sans JP'],
  );
}
