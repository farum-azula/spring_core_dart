// Chapter 5, "Assets": files of the app's asset bundle injected into a
// bean with @Value('asset:...'), the Japanese text found next to the
// English one with createRelative.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/src/about/about_page.dart';
import 'package:neon_books_app/src/about/app_assets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

void main() {
  testWidgets("@Value('asset:...') injects the app's assets", (tester) async {
    final context = await startApp(tester, FakeServer());
    final assets = context.getBean<AppAssets>();

    expect(assets.logo, isA<AssetResource>());
    expect((assets.logo as AssetResource).key, 'assets/images/leaf.png');
    expect(assets.logo.exists(), isTrue); // in the app's asset manifest
    final (english, japanese, german, cover) = (await tester.runAsync(
      () async => (
        await assets.aboutText(const Locale('en')),
        await assets.aboutText(const Locale('ja')),
        await assets.aboutText(const Locale('de')),
        await assets.sampleCoverBytes(),
      ),
    ))!;
    expect(english, startsWith('NEON Books is the bookstore'));
    expect(japanese, contains('書店')); // about_ja.txt, next to about.txt
    expect(german, english); // no about_de.txt: the English text
    expect(cover.sublist(1, 4), 'PNG'.codeUnits);
    await stopApp(tester);
  });

  testWidgets('the About screen shows them', (tester) async {
    await startApp(tester, FakeServer());
    await openMore(tester, 'About');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
    expect(find.textContaining('NEON Books is the bookstore'), findsOneWidget);
    expect(
      find.text(
        'Loaded from asset [assets/images/leaf.png] and '
        'asset [assets/texts/about.txt]',
      ),
      findsOneWidget,
    );
    await stopApp(tester);
  });
}
