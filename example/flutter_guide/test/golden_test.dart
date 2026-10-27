// Screenshots of the app, compared with the PNGs in test/goldens/: a
// change to a screen fails here, and test/failures/ shows the difference.
//
//   flutter test --tags golden                    # compare
//   flutter test --tags golden --update-goldens   # accept the new look
//
// The PNGs are made on macOS and only match there (Linux and Windows draw
// the letters differently), so CI runs this file on a macOS runner; the
// `golden` tag keeps it out of the other runs (`--exclude-tags golden`).
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart'
    show HttpMethod, ServerSentEvent;
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

/// Decodes the images on screen (the logo, a cover) for real: the test's
/// fake clock never finishes an image decode, so screenshots would show
/// none.
Future<void> loadImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
}

/// Lets real asynchronous work (asset reads) finish.
Future<void> settleForReal(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
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
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  goldenTest('the catalog (mobile profile)', (tester) async {
    await startApp(tester, FakeServer());
    await matchesScreen(tester, 'catalog');
  });

  goldenTest('a book with its cover and live stock', (tester) async {
    final server = FakeServer()
      ..http.reset()
      ..answerCatalog(
        stockEvents: [
          ServerSentEvent({'isbn': '9780441013593', 'available': 2}),
        ],
      );
    await startApp(tester, server);
    await tester.tap(find.text('Live stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catalog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    await loadImages(tester);
    await matchesScreen(tester, 'book');
  });

  goldenTest('the basket of a logged-in user', (tester) async {
    final server = FakeServer()..answerLogin('ada');
    server.http
        .when(HttpMethod.put, '/api/basket/items/9780441013593')
        .respond(204);
    server.http
        .when(HttpMethod.put, '/api/basket/items/9780345539434')
        .respond(204);
    await startApp(tester, server);
    await logIn(tester, 'ada', 'ada-secret');
    await tester.tap(find.byTooltip('Add to basket').first);
    await tester.tap(find.byTooltip('Add to basket').first);
    await tester.tap(find.byTooltip('Add to basket').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basket'));
    await tester.pumpAndSettle();
    await matchesScreen(tester, 'basket');
  });

  goldenTest('the live stock', (tester) async {
    final server = FakeServer()
      ..http.reset()
      ..answerCatalog(
        stockEvents: [
          ServerSentEvent({'isbn': '9780441013593', 'available': 2}),
          ServerSentEvent({'isbn': '9780345539434', 'available': 0}),
          ServerSentEvent({'isbn': '9780441013593', 'available': 1}),
        ],
      );
    await startApp(tester, server);
    await tester.tap(find.text('Live stock'));
    await tester.pumpAndSettle();
    await matchesScreen(tester, 'live_stock');
  });

  goldenTest('the support chat', (tester) async {
    final server = FakeServer()..answerLogin('ada');
    await startApp(tester, server);
    await logIn(tester, 'ada', 'ada-secret');
    await openMore(tester, 'Support');
    final socket = (await tester.runAsync(
      () => server.sockets.nextConnection,
    ))!;
    socket.pushJson({'from': 'neon-bot', 'text': 'Hello! How can I help?'});
    await settleForReal(tester);
    await tester.enterText(find.byKey(const Key('chat-text')), 'Is Dune back?');
    await tester.tap(find.byTooltip('Send'));
    await settleForReal(tester);
    socket.pushJson({
      'from': 'neon-bot',
      'text': 'Yes, 2 copies arrived today.',
    });
    await settleForReal(tester);
    await matchesScreen(tester, 'support');
    await tester.runAsync(() => socket.closeFromServer());
  });

  goldenTest('the Admin form with its errors', (tester) async {
    final server = FakeServer()..answerLogin('root', roles: ['USER', 'ADMIN']);
    await startApp(tester, server);
    await logIn(tester, 'root', 'root-secret');
    await openMore(tester, 'Admin');
    await tester.enterText(find.byKey(const Key('admin-isbn')), '978-0');
    await tester.enterText(find.byKey(const Key('admin-price')), 'twelve');
    await tester.tap(find.text('Add the book'));
    await tester.pumpAndSettle();
    await matchesScreen(tester, 'admin_errors');
  });

  goldenTest('the Login screen', (tester) async {
    await startApp(tester, FakeServer());
    await tester.tap(find.widgetWithText(TextButton, 'Log in'));
    await tester.pumpAndSettle();
    await matchesScreen(tester, 'login');
  });

  goldenTest('Japanese texts', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await startApp(tester, FakeServer());
    await matchesScreen(tester, 'japanese');
  });

  goldenTest('the About screen: assets injected into a bean', (tester) async {
    await startApp(tester, FakeServer());
    await openMore(tester, 'About');
    await settleForReal(tester);
    await loadImages(tester);
    await matchesScreen(tester, 'about');
  });

  goldenTest('the About screen in Japanese: about_ja.txt', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await startApp(tester, FakeServer());
    await openMore(tester, 'このアプリについて', more: 'その他');
    await settleForReal(tester);
    await loadImages(tester);
    await matchesScreen(tester, 'about_japanese');
  });

  goldenTest('the desktop profile on a desktop window', (tester) async {
    await startApp(
      tester,
      FakeServer(),
      platform: TargetPlatform.macOS,
      size: const Size(1024, 640),
    );
    await matchesScreen(tester, 'desktop');
  });

  // The themes gallery: Settings in every theme of the properties.
  for (final theme in [
    'light',
    'dark',
    'neon',
    'neon-night',
    'sepia',
    'high-contrast',
  ]) {
    goldenTest('Settings in the $theme theme', (tester) async {
      await startApp(
        tester,
        FakeServer(),
        args: ['--spring.flutter.theme.active=$theme'],
        size: const Size(390, 1500),
      );
      await openMore(tester, 'Settings');
      await matchesScreen(tester, 'settings_$theme');
    });
  }
}
