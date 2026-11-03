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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';

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
  // The first page, in a light and a dark look.
  for (final theme in [AppThemes.light, AppThemes.dark]) {
    goldenTest('colors in $theme', (tester) async {
      await startApp(tester, theme: theme);
      await loadImages(tester);
      await matchesScreen(tester, 'colors_$theme');
    });
  }

  // The page that is all about themes, in a theme of a file.
  goldenTest('themes in ocean', (tester) async {
    await startApp(tester, theme: AppThemes.ocean, page: 8);
    await loadImages(tester);
    await matchesScreen(tester, 'themes_ocean');
  });

  goldenTest('own widgets in neon', (tester) async {
    await startApp(tester, page: 4);
    await loadImages(tester);
    await matchesScreen(tester, 'states_neon');
  });

  goldenTest('the components gallery in ocean', (tester) async {
    await startApp(tester, theme: AppThemes.ocean, page: 3);
    await loadImages(tester);
    await matchesScreen(tester, 'components_ocean');
  });

  goldenTest('the background page in neon', (tester) async {
    await startApp(tester, page: 6);
    await loadImages(tester);
    await matchesScreen(tester, 'background_neon');
  });
}
