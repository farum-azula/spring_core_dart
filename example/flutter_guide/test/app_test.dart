// Chapter 1, "The application": SpringApplicationWidget starts the
// application as `flutter run` does; the platform is a profile; the app's
// lifecycle and its navigation arrive as events and in the log.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/src/app/home_page.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

List<String> logged(ApplicationContext context, String logger) => [
  for (final record in context.getBean<LogBuffer>().records)
    if (record.loggerName == logger) record.message,
];

void main() {
  testWidgets('on a phone: the mobile and android profiles', (tester) async {
    final server = FakeServer();
    final context = await startApp(tester, server);

    expect(context.environment.activeProfiles, ['mobile', 'android']);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('NEON Books'), findsOneWidget);
    // application-android.properties: the emulator's way to the computer.
    expect(server.http.requests.first.url.origin, 'http://10.0.2.2:8080');
    expect(find.text('Dune'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('on a desktop: the desktop and macos profiles', (tester) async {
    final server = FakeServer();
    final context = await startApp(
      tester,
      server,
      platform: TargetPlatform.macOS,
      size: const Size(1024, 640),
    );

    expect(context.environment.activeProfiles, ['desktop', 'macos']);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('NEON Books for desktop'), findsOneWidget);
    expect(server.http.requests.first.url.origin, 'http://localhost:8080');
    await stopApp(tester);
  });

  testWidgets('the app lifecycle: events, and the context paused', (
    tester,
  ) async {
    final context = await startApp(tester, FakeServer());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(
      logged(context, 'neon.lifecycle'),
      containsAllInOrder([
        'App inactive',
        'App hidden',
        'App paused',
        'In the background: scheduled tasks paused',
        'App resumed',
        'In the foreground again: scheduled tasks running',
      ]),
    );
    await stopApp(tester);
  });

  testWidgets('a NavigatorObserver bean sees the screens', (tester) async {
    final context = await startApp(tester, FakeServer());

    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      logged(context, 'neon.navigation'),
      containsAllInOrder([
        'open book/9780441013593',
        'close book/9780441013593',
      ]),
    );
    await stopApp(tester);
  });

  testWidgets('a bad property stops the start with a report', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: FakeServer().application,
        args: const ['--api.base-url=localhost:8080'],
        home: const HomePage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('The application failed to start'),
      findsOneWidget,
    );
    expect(find.textContaining('api.base-url'), findsWidgets);
    expect(find.byType(HomePage), findsNothing);
  });
}
