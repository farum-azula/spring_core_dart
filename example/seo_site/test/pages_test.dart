// The site's screens: the Markdown pages with links between them, the
// pages of a path variable, the messages, the not-found page.
import 'package:flutter_test/flutter_test.dart';
import 'package:seo_site_app/src/pages.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

import 'support/app.dart';

void main() {
  testWidgets('the docs, and a link between two Markdown files', (
    tester,
  ) async {
    final context = await startSite(tester, '/docs');
    expect(find.text('Documentation'), findsOneWidget);

    await tester.tapOnText(find.textRange.ofSubstring('routing'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(context.getBean<RouteTemplate>().uri.path, '/docs/guides/routing');
    expect(find.text('Routing'), findsOneWidget);
    await stopSite(tester);
  });

  testWidgets('a blog post and a legal page', (tester) async {
    await startSite(tester, '/blog/hello');
    expect(find.text('Hello, Lumen'), findsOneWidget);
    await stopSite(tester);

    await startSite(tester, '/legal/terms');
    expect(find.text('Terms'), findsOneWidget);
    await stopSite(tester);
  });

  testWidgets('a book by its id, the about page from the messages', (
    tester,
  ) async {
    await startSite(tester, '/books/2');
    expect(find.text('Book 2'), findsOneWidget);
    await stopSite(tester);

    await startSite(tester, '/about');
    expect(
      find.text('Who writes Lumen, and how to reach them.'),
      findsOneWidget,
    );
    await stopSite(tester);
  });

  testWidgets('an address the app does not know', (tester) async {
    await startSite(tester, '/nope');
    expect(find.byType(NotFoundPage), findsOneWidget);
    expect(find.text('No page at /nope'), findsOneWidget);
    await stopSite(tester);
  });

  testWidgets('/ja: the same pages in Japanese, and the switch back', (
    tester,
  ) async {
    final context = await startSite(tester, '/ja/docs');
    final route = context.getBean<RouteTemplate>();
    expect(route.language, 'ja');
    expect(find.text('ドキュメント'), findsOneWidget);

    await tester.tap(find.text('EN'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(route.language, 'en');
    expect(find.text('Documentation'), findsOneWidget);
    await stopSite(tester);

    await startSite(tester, '/ja/about');
    expect(find.text('Lumen を書いている人と、連絡の方法。'), findsOneWidget);
    await stopSite(tester);
  });
}
