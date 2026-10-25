// The template's smoke test, against the Spring application: once with
// the context of a springBootTest (properties and beans replaceable), once
// started by SpringApplicationWidget itself as `flutter run` does.
import 'package:flutter/material.dart';
import 'package:flutter_counter/main.spring.dart';
import 'package:flutter_counter/src/about/app_assets.dart';
import 'package:flutter_counter/src/counter/counter.dart';
import 'package:flutter_counter/src/counter_app.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

void main() {
  group('springBootTest', () {
    final app = springBootTest(
      springApplication,
      properties: {'counter.step': 2},
    );

    setUp(app.markDirty); // a fresh Counter for every test

    testWidgets('a tap adds counter.step', (tester) async {
      await tester.pumpWidget(
        SpringScope(applicationContext: app.context, child: const CounterApp()),
      );

      expect(find.text('0'), findsOneWidget);
      expect(
        find.text('You have pushed the button this many times:'),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(app.context.getBean<Counter>().value, 2);
    });
  });

  testWidgets('SpringApplicationWidget starts the application', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => springApplication,
        child: const CounterApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The test runs as Android: the mobile profile's title.
    expect(find.text('Flutter Demo Home Page (mobile)'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // closes the context
  });

  testWidgets('@Value(asset:...) injects the app\'s assets', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => springApplication,
        child: const CounterApp(),
      ),
    );
    await tester.pumpAndSettle();
    final assets = SpringScope.of(tester.element(find.byType(Scaffold)))
        .getBean<AppAssets>();

    expect(assets.logo, isA<AssetResource>());
    expect((assets.logo as AssetResource).key, 'assets/images/leaf.png');
    expect(assets.logo.exists(), isTrue); // in the app's asset manifest
    final (english, japanese) = await tester.runAsync(
      () async => (
        await assets.aboutText(const Locale('en')),
        await assets.aboutText(const Locale('ja')),
      ),
    ) as (String, String);
    expect(english, startsWith('The counter app'));
    expect(japanese, contains('カウンターアプリ'));
    // No about_de.txt: the English text.
    expect(
      await tester.runAsync(() => assets.aboutText(const Locale('de'))),
      english,
    );

    await tester.pumpWidget(const SizedBox()); // closes the context
  });

  testWidgets('a counter.step below 1 fails the start', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => springApplication,
        args: const ['--counter.step=0'],
        child: const CounterApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('The application failed to start'),
      findsOneWidget,
    );
    expect(find.textContaining('counter.step'), findsOneWidget);
  });
}
