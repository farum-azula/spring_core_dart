// The splash flow and the loaders of the app: the splash shows the logo and
// the bar while the app starts and hands over to it; the Loaders page shows
// a spinner, a bar with progress and a skeleton. No network; time moves by
// pumping durations (the loaders loop, so not pumpAndSettle).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_material/src/app/shell.dart';

import 'support/app.dart';

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  for (var left = total; left > Duration.zero;) {
    const step = Duration(milliseconds: 50);
    await tester.pump(step);
    left -= step;
  }
}

Iterable<ThemeLoader> _loaders(WidgetTester tester) =>
    tester.widgetList<ThemeLoader>(find.byType(ThemeLoader));

void main() {
  group('the splash', () {
    testWidgets('shows the logo, the title and a bar, then the app', (
      tester,
    ) async {
      await startApp(tester, keepSplash: true);
      final splash = find.byType(ThemeSplash);
      expect(splash, findsOneWidget);
      expect(
        find.descendant(of: splash, matching: find.text('Theme Showcase')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: splash, matching: find.byType(Image)),
        findsOneWidget,
      );
      final loader = tester.widget<ThemeLoader>(
        find.descendant(of: splash, matching: find.byType(ThemeLoader)),
      );
      expect(loader.spec.kind, 'bar');
      // The app is built under it; the splash stays for min-duration.
      expect(find.byType(Shell), findsOneWidget);
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(splash, findsOneWidget);
      await endSplash(tester);
      expect(splash, findsNothing);
      await stopApp(tester);
    });

    testWidgets('every theme has the splash of the root', (tester) async {
      await startApp(tester, keepSplash: true);
      final themes = SpringScope.of(
        tester.element(find.byType(Shell)),
      ).getBean<SpringThemes>();
      for (final name in themes.names) {
        expect(themes.data(name).splash?.title, 'Theme Showcase', reason: name);
        expect(themes.data(name).splash?.loader, 'bar', reason: name);
      }
      await endSplash(tester);
      await stopApp(tester);
    });

    testWidgets('reduce motion: it goes without a fade after min-duration', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await startApp(tester, keepSplash: true);
      await _pumpFor(tester, const Duration(milliseconds: 1300));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ThemeSplash), findsNothing);
      await stopApp(tester);
    });
  });

  group('the Loaders page', () {
    testWidgets('a refresh shows the spinner until it is done', (
      tester,
    ) async {
      await startApp(tester);
      await openPage(tester, 'Loaders');
      expect(
        _loaders(tester).where((loader) => loader.spec.kind == 'spinner'),
        isEmpty,
      );
      final refresh = find.text('Refresh');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pump();
      expect(
        _loaders(tester).where((loader) => loader.spec.kind == 'spinner'),
        hasLength(1),
      );
      await _pumpFor(tester, const Duration(milliseconds: 1600));
      expect(find.text('Up to date'), findsOneWidget);
      await stopApp(tester);
    });

    testWidgets('a fake upload fills the bar from 0 to 100 %', (tester) async {
      await startApp(tester);
      await openPage(tester, 'Loaders');
      double? progress() => _loaders(
        tester,
      ).where((l) => l.spec.kind == 'bar' && l.progress != null).first.progress;
      expect(progress(), 0);
      final upload = find.text('Fake upload');
      await tester.ensureVisible(upload);
      await tester.tap(upload);
      await _pumpFor(tester, const Duration(milliseconds: 1500));
      expect(progress(), inInclusiveRange(0.4, 0.6));
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(progress(), 1);
      expect(find.text('Upload: 100 %'), findsOneWidget);
      await stopApp(tester);
    });

    testWidgets('a skeleton shows until the list is there', (tester) async {
      await startApp(tester);
      await openPage(tester, 'Loaders');
      final loaded = find.byKey(const Key('books-loaded'));
      expect(loaded, findsOneWidget);
      final again = find.text('Load again');
      await tester.ensureVisible(again);
      await tester.tap(again);
      await tester.pump();
      expect(loaded, findsNothing);
      expect(find.byType(ThemeSkeleton), findsOneWidget);
      await _pumpFor(tester, const Duration(milliseconds: 1000));
      expect(loaded, findsNothing);
      await _pumpFor(tester, const Duration(milliseconds: 700));
      expect(loaded, findsOneWidget);
      expect(find.text('First volume'), findsOneWidget);
      await stopApp(tester);
    });

    testWidgets('the skeleton stands still with reduce motion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await startApp(tester);
      await openPage(tester, 'Loaders');
      final again = find.text('Load again');
      await tester.ensureVisible(again);
      await tester.tap(again);
      await tester.pump();
      expect(find.byType(ThemeSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);
      await stopApp(tester);
    });
  });
}
