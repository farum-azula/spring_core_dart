// The site's pages: Markdown with links between them, the server's
// /api/info on the page's origin, an address the app does not know.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:static_site_app/src/pages.dart';

import 'support/app.dart';

void main() {
  testWidgets('home, then the guide through a link of its Markdown', (
    tester,
  ) async {
    final context = await startSite(tester, MockHttpTransport());
    expect(find.text('A Flutter site on a Spring server'), findsOneWidget);

    await tester.tapOnText(find.textRange.ofSubstring('the guide'));
    await tester.pumpAndSettle();
    expect(find.byType(GuidePage), findsOneWidget);
    expect(find.text('How it is served'), findsOneWidget);
    expect(context.getBean<RouteTemplate>().uri.path, '/guide');

    await tester.tapOnText(find.textRange.ofSubstring('the start'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    await stopSite(tester);
  });

  testWidgets('the server page asks /api/info of its own origin', (
    tester,
  ) async {
    final http = MockHttpTransport();
    http
        .when(HttpMethod.get, '/api/info')
        .respond(
          200,
          json: {'name': 'static-site', 'time': '2026-11-05T12:00:00Z'},
        );
    await startSite(tester, http);

    await tester.tap(find.widgetWithText(TextButton, 'Server'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Served by static-site'), findsOneWidget);
    expect(http.requests.single.url.path, '/api/info');
    await stopSite(tester);
  });

  testWidgets('no answer from the server is shown on the page', (
    tester,
  ) async {
    final http = MockHttpTransport();
    http.when(HttpMethod.get, '/api/info').respond(503);
    await startSite(tester, http);

    await tester.tap(find.widgetWithText(TextButton, 'Server'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.textContaining('No answer'), findsOneWidget);
    await stopSite(tester);
  });

  testWidgets('an address the app does not know: its not-found page', (
    tester,
  ) async {
    final context = await startSite(tester, MockHttpTransport());
    await context.getBean<RouteTemplate>().go('/nope');
    await tester.pumpAndSettle();
    expect(find.text('No page at /nope'), findsOneWidget);
    await stopSite(tester);
  });
}
