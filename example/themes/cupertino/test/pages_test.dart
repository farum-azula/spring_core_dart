// Every page in every theme: the app starts from the properties, each page
// builds without an error (a layout overflow is one) and has its title.
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_showcase_cupertino/src/app/shell.dart';

import 'support/app.dart';

const _titles = {
  'colors': 'Colors',
  'type': 'Typography',
  'tokens': 'Tokens',
  'styles': 'Own widgets',
  'controls': 'Controls',
  'motion': 'Motion',
  'loaders': 'Loaders',
  'background': 'Background',
  'images': 'Images',
  'themes': 'Themes',
};

void main() {
  test('the pages of the navigation and their titles', () {
    expect([for (final page in pages) page.id], _titles.keys);
  });

  for (final theme in allThemes) {
    testWidgets('every page in $theme', (tester) async {
      await startApp(tester, theme: theme);
      expect(shownTheme(tester), theme);
      for (final title in _titles.values) {
        await openPage(tester, title);
        expect(
          find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.text(title),
          ),
          findsWidgets,
          reason: '$title in $theme',
        );
        expect(tester.takeException(), isNull, reason: '$title in $theme');
      }
      await stopApp(tester);
    });

    testWidgets('every page on a phone in $theme', (tester) async {
      await startApp(tester, theme: theme, size: phoneSize);
      for (final title in _titles.values) {
        await openPage(tester, title);
        expect(
          find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.text(title),
          ),
          findsWidgets,
          reason: '$title on a phone in $theme',
        );
        expect(tester.takeException(), isNull, reason: title);
        // A page behind "More" has a back button; go back to the tabs.
        if (!tabIds.contains(_idOf(title))) {
          await tester.tap(find.byType(CupertinoNavigationBarBackButton));
          await settle(tester);
        }
      }
      await stopApp(tester);
    });
  }

  // On desktop the scroll behavior adds the scrollbars to every list.
  testWidgets('every page on desktop, scrolled', (tester) async {
    await startApp(tester);
    for (final title in _titles.values) {
      await openPage(tester, title);
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -300),
      );
      // Not pumpAndSettle: some pages loop their animations.
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: title);
    }
    await stopApp(tester);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('a narrow window has a tab bar, not a sidebar', (tester) async {
    await startApp(tester, size: phoneSize);
    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byKey(const Key('sidebar')), findsNothing);
    await stopApp(tester);
  });

  testWidgets('a wide window has a sidebar, not a tab bar', (tester) async {
    await startApp(tester);
    expect(find.byType(CupertinoTabBar), findsNothing);
    expect(find.byKey(const Key('sidebar')), findsOneWidget);
    await stopApp(tester);
  });
}

String _idOf(String title) =>
    _titles.entries.firstWhere((e) => e.value == title).key;
