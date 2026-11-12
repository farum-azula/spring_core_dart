// Screenshots of the pages, compared with the PNGs in test/goldens/: a
// change to a look fails here, and test/failures/ shows the difference.
//
//   flutter test --tags golden                    # compare
//   flutter test --tags golden --update-goldens   # accept the new look
//
// The PNGs are made on macOS and only match there (Linux and Windows draw
// the letters differently), so CI runs this file on a macOS runner; the
// `golden` tag keeps it out of the other runs (`--exclude-tags golden`).
@Tags(['golden'])
library;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';

import 'support/app.dart';

/// Decodes the images on screen for real: the test's fake clock never
/// finishes an image decode, so screenshots would show none.
Future<void> loadImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await settle(tester);
}

/// A widget test with real shadows (flutter_test draws them as black
/// outlines by default; the switch must be back before the test ends).
void goldenTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
      await stopApp(tester);
    }
  });
}

Future<void> matchesScreen(WidgetTester tester, String name) =>
    expectLater(find.byType(SpringApp), matchesGoldenFile('goldens/$name.png'));

void main() {
  // The first page, in the light theme and the one with a picture behind.
  for (final theme in [AppThemes.light, AppThemes.sunset]) {
    goldenTest('colors in $theme', (tester) async {
      await startApp(tester, theme: theme);
      await loadImages(tester);
      await matchesScreen(tester, 'colors_$theme');
    });
  }

  // The controls on a phone: the tab bar and the iOS controls.
  goldenTest('controls on a phone in light', (tester) async {
    await startApp(tester, size: phoneSize, page: 4);
    await loadImages(tester);
    await matchesScreen(tester, 'controls_phone_light');
  });

  goldenTest('controls on a phone in dark', (tester) async {
    await startApp(tester, theme: AppThemes.dark, size: phoneSize, page: 4);
    await loadImages(tester);
    await matchesScreen(tester, 'controls_phone_dark');
  });

  goldenTest('own widgets in graphite', (tester) async {
    await startApp(tester, theme: AppThemes.graphite, page: 3);
    await loadImages(tester);
    await matchesScreen(tester, 'styles_graphite');
  });

  goldenTest('the themes page in sunset', (tester) async {
    await startApp(tester, theme: AppThemes.sunset, page: 10);
    await loadImages(tester);
    await matchesScreen(tester, 'themes_sunset');
  });
}
