// Screenshots of the app, compared with the PNGs in test/goldens/: a
// change to a screen fails here, and test/failures/ shows the difference.
//
//   flutter test test/golden_test.dart                    # compare
//   flutter test test/golden_test.dart --update-goldens   # accept the new look
//
// The PNGs are made on macOS and only match there (Linux and Windows draw
// the letters differently), so CI runs this file on a macOS runner; the
// `golden` tag keeps it out of the other runs (`--exclude-tags golden`).
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_counter/main.spring.dart';
import 'package:flutter_counter/src/about/about_page.dart';
import 'package:flutter_counter/src/counter_app.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Starts the app with SpringApplicationWidget on a [size] screen, as `flutter run` does.
Future<void> startApp(
  WidgetTester tester, {
  Size size = const Size(390, 844), // a phone
  List<String> args = const [],
}) async {
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => springApplication,
      args: args,
      child: const CounterApp(),
    ),
  );
  await tester.pumpAndSettle();
  await loadImages(tester);
}

/// Decodes the images on screen (the asset logo) for real: the test's fake
/// clock never finishes an image decode, so screenshots would show none.
Future<void> loadImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
}

/// Opens the About page with the app bar's button.
Future<void> openAbout(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.info_outline));
  await tester.pumpAndSettle();
  await loadImages(tester);
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
    }
  });
}

Future<void> tapPlus(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
  }
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  goldenTest('start screen (mobile profile)', (tester) async {
    await startApp(tester);
    await expectLater(
      find.byType(CounterApp),
      matchesGoldenFile('goldens/start_mobile.png'),
    );
  });

  goldenTest('after three taps with counter.step=2', (tester) async {
    await startApp(tester, args: ['--counter.step=2']);
    await tapPlus(tester, 3);
    expect(find.text('6'), findsOneWidget);
    await expectLater(
      find.byType(CounterApp),
      matchesGoldenFile('goldens/three_taps_step_2.png'),
    );
  });

  goldenTest('Japanese texts', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await startApp(tester);
    await tapPlus(tester, 1);
    await expectLater(
      find.byType(CounterApp),
      matchesGoldenFile('goldens/japanese.png'),
    );
  });

  goldenTest('About page: assets injected into a bean', (tester) async {
    await startApp(tester);
    await openAbout(tester);
    expect(find.byType(AboutPage), findsOneWidget);
    await expectLater(
      find.byType(CounterApp),
      matchesGoldenFile('goldens/about.png'),
    );
  });

  goldenTest('About page in Japanese: about_ja.txt', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await startApp(tester);
    await openAbout(tester);
    await expectLater(
      find.byType(CounterApp),
      matchesGoldenFile('goldens/about_japanese.png'),
    );
  });

  goldenTest('desktop profile on a desktop window', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await startApp(tester, size: const Size(1024, 640));
    await expectLater(
      find.byType(CounterApp),
      matchesGoldenFile('goldens/desktop.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
