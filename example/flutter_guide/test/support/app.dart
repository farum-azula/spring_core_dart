import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/src/app/home_page.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_security_core/spring_security_core.dart'
    show SecurityContextHolder;

import 'fake_server.dart';

/// Starts the app with `SpringApplicationWidget`, as `flutter run` does,
/// against [server], on a [size] screen (a phone by default) of
/// [platform] (Android by default: the `mobile` and `android` profiles).
/// Returns the running context. Close it at the end with [stopApp].
Future<ConfigurableApplicationContext> startApp(
  WidgetTester tester,
  FakeServer server, {
  List<String> args = const [],
  Size size = const Size(390, 844),
  TargetPlatform? platform,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  // The logged-in user is the program's (SecurityContextHolder), not the
  // context's: each test starts logged out.
  addTearDown(SecurityContextHolder.clearContext);
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: server.application,
      args: args,
      home: const HomePage(),
    ),
  );
  // Fonts and assets are read for real before the first frame.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pumpAndSettle();
  return SpringScope.of(tester.element(find.byType(HomePage)))
      as ConfigurableApplicationContext;
}

/// Closes the context of [startApp] (its timers end with it).
Future<void> stopApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  debugDefaultTargetPlatformOverride = null;
}

/// The widget [page] in the app widget of [context] (the theme, texts and
/// locales of the properties), as `springBootTest` tests show a screen.
Future<void> showPage(
  WidgetTester tester,
  ApplicationContext context,
  Widget page,
) async {
  await tester.pumpWidget(
    SpringScope(
      applicationContext: context,
      child: SpringApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

/// Records which widgets rebuild while [action] runs (Flutter's
/// `debugOnRebuildDirtyWidget` hook), by type.
Future<List<Type>> rebuiltBy(Future<void> Function() action) async {
  final rebuilt = <Type>[];
  debugOnRebuildDirtyWidget = (element, builtOnce) =>
      rebuilt.add(element.widget.runtimeType);
  try {
    await action();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return rebuilt;
}

/// Opens the More section's entry [title] ([more]: the section's label).
Future<void> openMore(
  WidgetTester tester,
  String title, {
  String more = 'More',
}) async {
  await tester.tap(find.text(more));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// Logs in through the Login screen (the app bar's button).
Future<void> logIn(WidgetTester tester, String user, String password) async {
  await tester.tap(find.widgetWithText(TextButton, 'Log in'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('login-username')), user);
  await tester.enterText(find.byKey(const Key('login-password')), password);
  await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
  await tester.pumpAndSettle();
}
