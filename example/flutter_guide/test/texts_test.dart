// Chapter 4, "Texts": messages*.properties in English and Japanese, read
// with context.message in the app's language; Settings switches it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

void main() {
  testWidgets('the locales are those of the messages files', (tester) async {
    final context = await startApp(tester, FakeServer());
    expect(FlutterAppSettings.of(context).supportedLocales, [
      const Locale('en'),
      const Locale('ja'),
    ]);
    await stopApp(tester);
  });

  testWidgets('a Japanese device gets the Japanese texts', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await startApp(tester, FakeServer());

    expect(find.text('カタログ'), findsOneWidget);
    expect(find.text('ログイン'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('Settings switches the language at once', (tester) async {
    await startApp(tester, FakeServer());
    await openMore(tester, 'Settings');

    await tester.ensureVisible(find.text('日本語'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();
    expect(find.text('設定'), findsOneWidget); // the app bar of Settings
    expect(find.text('言語'), findsOneWidget);

    await tester.tap(find.text('端末の設定に合わせる').last);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('arguments are formatted ({0})', (tester) async {
    await startApp(tester, FakeServer());
    final context = tester.element(find.text('Dune'));
    expect(context.message('catalog.page', args: [2, 5]), 'Page 2 of 5');
    expect(
      context.message('basket.added', args: ['Dune']),
      'Dune is in the basket',
    );
    await stopApp(tester);
  });
}
