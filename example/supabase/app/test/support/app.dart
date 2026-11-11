// What the tests share: the app started as `flutter run` starts it, on a
// project played in memory.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:supabase_example_app/src/app/home_page.dart';

import 'fake_project.dart';

export 'fake_project.dart';

/// Starts the app with `SpringApplicationWidget` against [project], on a
/// phone-sized screen. Returns the running context; close it at the end
/// with [stopApp].
Future<ApplicationContext> startApp(
  WidgetTester tester,
  FakeProject project,
) async {
  // The signed-in user is the program's (SecurityContextHolder), not the
  // context's: each test starts signed out.
  addTearDown(SecurityContextHolder.clearContext);
  tester.view
    ..physicalSize = const Size(390, 844) * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SpringApplicationWidget(application: project.application),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await settle(tester);
  return SpringScope.of(tester.element(find.byType(HomePage)));
}

/// Lets the app finish what it started: the answers of the project, the
/// changes Realtime tells and the query that follows them.
///
/// Not `pumpAndSettle`: a list that waits shows a progress indicator,
/// which never settles. And with real time in between: Realtime reads the
/// key and the token of its connection outside the zone of whoever uses a
/// channel (so that a channel never acts as a passing caller), which is
/// also outside the fake clock of a widget test.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Closes the context of [startApp] (its timers and its connection end
/// with it).
Future<void> stopApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// Fills the starter's `LoginForm` (its fields by their labels) and
/// presses its button, [submit].
Future<void> fillLogin(
  WidgetTester tester,
  String email,
  String password, {
  String submit = 'Sign in',
}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
  await tester.enterText(find.widgetWithText(TextField, 'Password'), password);
  await tester.tap(find.widgetWithText(FilledButton, submit));
  await settle(tester);
}
