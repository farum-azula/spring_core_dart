import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/app/shell.dart';

/// The four themes of the app, by the generated names.
const allThemes = [
  AppThemes.light,
  AppThemes.dark,
  AppThemes.graphite,
  AppThemes.sunset,
];

/// A wide window (a sidebar) and a phone (a tab bar).
const wideSize = Size(1280, 800);
const phoneSize = Size(390, 844);

/// Starts the app with `SpringApplicationWidget`, as `flutter run` does, on a
/// [size] screen (a wide window by default) with [theme] active. Close it
/// with [stopApp] at the end.
Future<ConfigurableApplicationContext> startApp(
  WidgetTester tester, {
  String theme = AppThemes.light,
  Size size = wideSize,
  int page = 0,
  List<String> args = const [],
  bool keepSplash = false,
}) async {
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  // The desktop profile sets the window; no window plugin runs in a widget
  // test, so the platform side is a fake.
  const windowChannel = MethodChannel(DesktopWindowChannel.name);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    windowChannel,
    (call) async =>
        call.method == 'apply' ? {'insets': <String, Object?>{}} : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      null,
    ),
  );
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => springApplication,
      args: ['--spring.flutter.theme.active=$theme', ...args],
      home: Shell(initialPage: page),
    ),
  );
  // Fonts and assets are read for real before the first frame.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  if (keepSplash) {
    await tester.pump();
  } else {
    await settle(tester);
    await endSplash(tester);
  }
  return SpringScope.of(tester.element(find.byType(Shell)))
      as ConfigurableApplicationContext;
}

/// Lets the splash of the theme finish: at least its `min-duration`, then
/// the fade out. [startApp] waits for it, so tests can tap the app.
Future<void> endSplash(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    if (find.byType(ThemeSplash).evaluate().isEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('The splash is still on screen after 10 seconds.');
}

/// Closes the context of [startApp] (its timers end with it).
Future<void> stopApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

/// Opens the page called [label]: in the sidebar of a wide window, in a tab
/// of a phone, or behind the "More" tab.
Future<void> openPage(WidgetTester tester, String label) async {
  final sidebar = find.byKey(const Key('sidebar'));
  if (sidebar.evaluate().isNotEmpty) {
    await tester.tap(find.descendant(of: sidebar, matching: find.text(label)));
    await settle(tester);
    return;
  }
  final bar = find.byType(CupertinoTabBar);
  final tab = find.descendant(of: bar, matching: find.text(label));
  if (tab.evaluate().isNotEmpty) {
    await tester.tap(tab);
  } else {
    await tester.tap(find.descendant(of: bar, matching: find.text('More')));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoListTile),
        matching: find.text(label),
      ),
    );
  }
  await settle(tester);
}

/// Lets transitions end. `pumpAndSettle` never returns while an animation
/// repeats (the sunset background drifts, the spinners turn).
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// The theme shown now.
String shownTheme(WidgetTester tester) =>
    SpringTheme.of(tester.element(find.byType(Shell))).name;
