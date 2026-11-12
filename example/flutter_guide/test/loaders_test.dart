// The splash flow and the loaders of the app: the splash shows the logo and
// a bar while the app starts and hands over to it; the catalog shows a
// skeleton while the server has not answered; Settings shows the loaders
// with the YAML that makes them. No network (the fake server); time moves by
// pumping durations, not pumpAndSettle (the loaders loop).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neon_books_app/src/settings/loaders_preview.dart';
import 'package:neon_books_app/src/settings/settings_page.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  for (var left = total; left > Duration.zero;) {
    const step = Duration(milliseconds: 50);
    await tester.pump(step);
    left -= step;
  }
}

/// A line without its indentation, with one space between words.
String _normal(String line) => line.trim().replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('the splash', () {
    testWidgets('shows the logo, the title and a bar, then the app', (
      tester,
    ) async {
      await startApp(tester, FakeServer(), keepSplash: true);
      final splash = find.byType(ThemeSplash);
      expect(splash, findsOneWidget);
      expect(
        find.descendant(of: splash, matching: find.text('NEON Books')),
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
      // At least min-duration (1 s), then it fades out.
      await _pumpFor(tester, const Duration(milliseconds: 800));
      expect(splash, findsOneWidget);
      await endSplash(tester);
      expect(splash, findsNothing);
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
      await startApp(tester, FakeServer(), keepSplash: true);
      await _pumpFor(tester, const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ThemeSplash), findsNothing);
      await stopApp(tester);
    });
  });

  group('in the app', () {
    testWidgets('the catalog shows a skeleton until the server answers', (
      tester,
    ) async {
      final server = FakeServer();
      final gate = Completer<void>();
      // The books wait for the gate.
      server.http
        ..reset()
        ..when(HttpMethod.get, '/api/books').respondWith((request) async {
          await gate.future;
          return HttpResponse(
            200,
            headers: HttpHeaders({'Content-Type': 'application/json'}),
            body: utf8.encode(
              jsonEncode({
                'items': books,
                'page': 0,
                'size': 20,
                'total': books.length,
              }),
            ),
          );
        })
        ..when(
          HttpMethod.get,
          '/api/stock/events',
        ).respondEvents(const [], keepOpen: true);
      await startApp(tester, server, keepSplash: true);
      await endSplash(tester, settle: false);
      expect(find.byType(ThemeSkeleton), findsOneWidget);
      expect(find.text('Dune'), findsNothing);
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.byType(ThemeSkeleton), findsOneWidget);

      gate.complete();
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.byType(ThemeSkeleton), findsNothing);
      expect(find.text('Dune'), findsOneWidget);
      await stopApp(tester);
    });

    testWidgets('Settings shows the loaders: a skeleton, then the content, a '
        'bar with progress', (tester) async {
      await startApp(tester, FakeServer());
      await openMore(tester, 'Settings');
      final preview = find.byType(LoadersPreview);
      await tester.dragUntilVisible(
        preview,
        find.byType(ListView).first,
        const Offset(0, -300),
      );
      // The fake download runs for three seconds from the first build.
      final skeleton = find.descendant(
        of: preview,
        matching: find.byType(ThemeSkeleton),
      );
      expect(skeleton, findsOneWidget);
      double? progress() => tester
          .widgetList<ThemeLoader>(
            find.descendant(of: preview, matching: find.byType(ThemeLoader)),
          )
          .map((loader) => loader.progress)
          .whereType<double>()
          .first;
      expect(progress(), lessThan(1));
      await _pumpFor(tester, const Duration(seconds: 4));
      expect(progress(), 1);
      expect(find.text('Loaded'), findsOneWidget);
      expect(find.byType(SettingsPage), findsOneWidget);
      // "Run again" starts over.
      await tester.tap(find.text('Run again'));
      await tester.pump();
      expect(progress(), 0);
      await _pumpFor(tester, const Duration(seconds: 4));
      await stopApp(tester);
    });
  });

  test('every line of the YAML boxes is in lib/resources/', () {
    final known = <String>{
      for (final file in [
        File('lib/resources/application.yml'),
        ...Directory('lib/resources/themes').listSync().whereType<File>(),
      ])
        for (final line in file.readAsLinesSync()) _normal(line),
    };
    final source = File(
      'lib/src/settings/loaders_preview.dart',
    ).readAsStringSync();
    // The text of each r'''...''' string is a box.
    final boxes = RegExp(r"r'''\n(.*?)'''", dotAll: true).allMatches(source);
    expect(boxes.length, 2);
    final missing = <String>[];
    for (final box in boxes) {
      for (final line in box.group(1)!.split('\n')) {
        if (_normal(line).isNotEmpty && !known.contains(_normal(line))) {
          missing.add(line.trim());
        }
      }
    }
    expect(missing, isEmpty);
  });
}
