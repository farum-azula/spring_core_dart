// Screenshots of the gallery in every theme of the properties, compared
// with the PNGs in test/goldens/ (made on macOS; see the README).
//
//   flutter test test/golden_test.dart                    # compare
//   flutter test test/golden_test.dart --update-goldens   # accept the new look
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_themes/main.spring.dart';
import 'package:flutter_themes/src/gallery_page.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The app with theme [theme] on a phone screen, as `flutter run` starts it.
Future<void> startApp(WidgetTester tester, String theme) async {
  tester.view
    ..physicalSize = const Size(390, 1500) * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => springApplication,
      args: ['--spring.flutter.theme.active=$theme'],
      home: const GalleryPage(),
    ),
  );
  // The fonts are read from the assets for real before the first frame.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final theme in [
    'light',
    'dark',
    'ocean',
    'ocean-night',
    'sepia',
    'high-contrast',
  ]) {
    testWidgets('the gallery in $theme', (tester) async {
      debugDisableShadows = false;
      try {
        await startApp(tester, theme);
        expect(find.byType(GalleryPage), findsOneWidget);
        await expectLater(
          find.byType(SpringApp),
          matchesGoldenFile('goldens/$theme.png'),
        );
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
