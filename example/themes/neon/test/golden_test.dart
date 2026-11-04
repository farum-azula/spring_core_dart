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

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';

import 'support/app.dart';

/// Decodes the images on screen for real: the test's fake clock never
/// finishes an image decode, so screenshots would show none. The theme's
/// background is an Image too.
Future<void> loadImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
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
  for (final theme in showcaseThemes) {
    goldenTest('overview in $theme', (tester) async {
      await startApp(tester, theme: theme);
      await loadImages(tester);
      await matchesScreen(tester, 'overview_$theme');
    });
  }

  goldenTest('components in neon', (tester) async {
    await startApp(tester, page: 1);
    await loadImages(tester);
    await matchesScreen(tester, 'components_neon');
  });

  goldenTest('the glow modal in neon-ice', (tester) async {
    await startApp(tester, theme: AppThemes.neonIce, page: 3);
    await loadImages(tester);
    await tester.tap(find.widgetWithText(NeonButton, 'OPEN THE MODAL'));
    await settle(tester);
    await matchesScreen(tester, 'modal_neon-ice');
  });

  goldenTest('the background page in neon', (tester) async {
    await startApp(tester, page: 5);
    await loadImages(tester);
    await matchesScreen(tester, 'background_neon');
  });

  goldenTest('themes in neon-ice', (tester) async {
    await startApp(tester, theme: AppThemes.neonIce, page: 8);
    await loadImages(tester);
    await matchesScreen(tester, 'themes_neon-ice');
  });
}
