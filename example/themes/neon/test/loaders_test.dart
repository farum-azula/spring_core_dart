// The splash flow and the loaders of the app: the splash shows the gate
// while the app starts, parts over the app, and the Loaders page shows it
// with a slider, the built-in kinds and a skeleton. No
// network; time moves by pumping durations (the loaders loop, so not
// pumpAndSettle).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_neon/src/app/shell.dart';

import 'support/app.dart';

ThemeLoaderSpec _specOf(WidgetTester tester, Finder loader) =>
    tester.widget<ThemeLoader>(loader).spec;

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  for (var left = total; left > Duration.zero;) {
    const step = Duration(milliseconds: 50);
    await tester.pump(step);
    left -= step;
  }
}

void main() {
  group('the splash', () {
    testWidgets('shows the gate, then parts over the app', (tester) async {
      await startApp(tester, keepSplash: true);
      final splash = find.byType(ThemeSplash);
      expect(splash, findsOneWidget);
      await _pumpFor(tester, const Duration(milliseconds: 300));
      // The loader draws everything itself; the splash has no image.
      expect(
        find.descendant(of: splash, matching: find.byType(Image)),
        findsNothing,
      );
      final loader = find.descendant(
        of: splash,
        matching: find.byType(ThemeLoader),
      );
      expect(_specOf(tester, loader).kind, 'neongate');
      // The app is built under it, behind the splash's background.
      expect(find.byType(Shell), findsOneWidget);
      bool backgroundShown() => tester
          .widgetList<Visibility>(
            find.descendant(of: splash, matching: find.byType(Visibility)),
          )
          .every((v) => v.visible);
      expect(backgroundShown(), isTrue);
      // The panels slide in (2 s), the box fills in 2.5 s at least: the
      // splash is still there after 4 s.
      await _pumpFor(tester, const Duration(milliseconds: 3700));
      expect(splash, findsOneWidget);
      expect(backgroundShown(), isTrue);
      // Then the panels part (1.4 s) over the app: the background is gone
      // while they go (exit.reveal).
      await _pumpFor(tester, const Duration(milliseconds: 1400));
      expect(splash, findsOneWidget);
      expect(backgroundShown(), isFalse);
      await endSplash(tester);
      expect(splash, findsNothing);
      expect(find.byType(Shell), findsOneWidget);
      await stopApp(tester);
    });

    testWidgets('reduce motion: every phase is at its end, no fade', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await startApp(tester, keepSplash: true);
      // Every phase is at its end: nothing to wait for, it goes at once.
      await _pumpFor(tester, const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ThemeSplash), findsNothing);
      await stopApp(tester);
    });
  });

  group('the Loaders page', () {
    testWidgets('the slider sets the progress the gate gets', (
      tester,
    ) async {
      await startApp(tester);
      await openPage(tester, 'Loaders');
      final stage = find.byKey(const Key('gate-stage'));
      final gate = find.descendant(
        of: stage,
        matching: find.byType(ThemeLoader),
      );
      expect(_specOf(tester, gate).kind, 'neongate');
      expect(tester.widget<ThemeLoader>(gate).progress, 0.4);
      await tester.ensureVisible(find.byKey(const Key('progress-slider')));
      final slider = find.byKey(const Key('progress-slider'));
      final box = tester.getRect(slider);
      await tester.tapAt(Offset(box.left + box.width * 0.75, box.center.dy));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<ThemeLoader>(gate).progress,
        closeTo(0.75, 0.01),
      );
      expect(find.text('PROGRESS 75 %'), findsOneWidget);
      await stopApp(tester);
    });

    testWidgets('a fake load runs to 100 % and the panels part', (
      tester,
    ) async {
      await startApp(tester);
      await openPage(tester, 'Loaders');
      final run = find.text('RUN A FAKE LOAD');
      await tester.ensureVisible(run);
      await tester.tap(run);
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('PROGRESS 100 %'), findsNothing);
      await _pumpFor(tester, const Duration(seconds: 3));
      expect(find.text('PROGRESS 100 %'), findsOneWidget);
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await stopApp(tester);
    });

    testWidgets('the built-in kinds: spinner, dots and a bar with progress', (
      tester,
    ) async {
      await startApp(tester);
      await openPage(tester, 'Loaders');
      final kinds = {
        for (final loader in tester.widgetList<ThemeLoader>(
          find.byType(ThemeLoader),
        ))
          loader.spec.kind: loader.progress,
      };
      expect(kinds.keys, containsAll(['neongate', 'spinner', 'dots', 'bar']));
      expect(kinds['bar'], 0);
      final upload = find.text('FAKE UPLOAD');
      await tester.ensureVisible(upload);
      await tester.tap(upload);
      await _pumpFor(tester, const Duration(milliseconds: 1600));
      final bar = tester
          .widgetList<ThemeLoader>(find.byType(ThemeLoader))
          .firstWhere((loader) => loader.spec.kind == 'bar');
      expect(bar.progress, inInclusiveRange(0.4, 0.7));
      await stopApp(tester);
    });

    testWidgets('the skeleton shows until the list is there', (tester) async {
      await startApp(tester);
      await openPage(tester, 'Loaders');
      final loaded = find.byKey(const Key('books-loaded'));
      // The first load is over by now; "Load again" starts one.
      expect(loaded, findsOneWidget);
      final again = find.text('LOAD AGAIN');
      await tester.ensureVisible(again);
      await tester.tap(again);
      await tester.pump();
      expect(loaded, findsNothing);
      expect(find.byType(ThemeSkeleton), findsOneWidget);
      await _pumpFor(tester, const Duration(milliseconds: 1000));
      expect(loaded, findsNothing);
      await _pumpFor(tester, const Duration(milliseconds: 800));
      expect(loaded, findsOneWidget);
      expect(find.text('First volume'), findsOneWidget);
      await stopApp(tester);
    });
  });
}
