// Every page in every theme: the app starts from the properties, each page
// builds without an error (a layout overflow is one) and has its title.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_showcase_material/src/app/shell.dart';
import 'package:theme_showcase_material/src/widgets/page_frame.dart';

import 'support/app.dart';

const _titles = {
  'colors': 'Colors',
  'type': 'Type and space',
  'tokens': 'Tokens',
  'components': 'Components',
  'states': 'Own widgets',
  'motion': 'Motion',
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
            of: find.byType(PageFrame),
            matching: find.text(title),
          ),
          findsOneWidget,
          reason: '$title in $theme',
        );
      }
      await stopApp(tester);
    });
  }

  // On desktop: scroll every page with the pointer. Not pumpAndSettle: the
  // neon background drifts for ever.
  testWidgets('every page on desktop, scrolled', (tester) async {
    await startApp(tester);
    for (final title in _titles.values) {
      await openPage(tester, title);
      await tester.drag(
        find
            .descendant(
              of: find.byType(PageFrame),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
        const Offset(0, -300),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: title);
    }
    await stopApp(tester);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('a narrow window has a drawer, not a rail', (tester) async {
    await startApp(tester, size: const Size(390, 844));
    expect(find.byType(NavigationRail), findsNothing);
    await openPage(tester, 'Themes');
    expect(
      find.text('Six themes, one set of widgets.', findRichText: true),
      findsNothing,
    );
    expect(find.text('Themes'), findsWidgets);
    await stopApp(tester);
  });
}
