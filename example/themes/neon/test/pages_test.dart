// Every page in every theme: the app starts from the properties, each page
// builds without an error (a layout overflow is one) and has its title.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_showcase_neon/src/app/shell.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';

import 'support/app.dart';

Finder _title(String title) =>
    find.descendant(of: find.byType(PageFrame), matching: find.text(title));

void main() {
  test('the pages of the navigation and their titles', () {
    expect([for (final page in pages) page.id], pageTitles.keys);
  });

  for (final theme in showcaseThemes) {
    testWidgets('every page in $theme', (tester) async {
      await startApp(tester, theme: theme);
      expect(shownTheme(tester), theme);
      for (final (label, title) in pageTitles.values) {
        await openPage(tester, label);
        expect(_title(title), findsOneWidget, reason: '$title in $theme');
        expect(tester.takeException(), isNull, reason: '$title in $theme');
      }
      await stopApp(tester);
    });
  }

  // On desktop: scroll every page, with the pointer. Not pumpAndSettle:
  // the background drifts and the borders turn for ever.
  testWidgets('every page on desktop, scrolled', (tester) async {
    await startApp(tester);
    for (final (label, title) in pageTitles.values) {
      await openPage(tester, label);
      expect(_title(title), findsOneWidget, reason: title);
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

  testWidgets('a narrow window has a strip of chips on top', (tester) async {
    await startApp(tester, size: const Size(390, 844));
    for (final (label, title) in pageTitles.values) {
      await openPage(tester, label);
      expect(_title(title), findsOneWidget, reason: title);
      expect(tester.takeException(), isNull, reason: title);
    }
    await stopApp(tester);
  });

  testWidgets('there is no Material, Cupertino or Scaffold on screen', (
    tester,
  ) async {
    await startApp(tester);
    final types = {
      for (final element in find.byWidgetPredicate((_) => true).evaluate())
        element.widget.runtimeType.toString(),
    };
    for (final name in const [
      'MaterialApp',
      'Scaffold',
      'Material',
      'InkWell',
      'CupertinoApp',
      'Theme',
    ]) {
      expect(types, isNot(contains(name)), reason: name);
    }
    expect(types, contains('WidgetsApp'));
    await stopApp(tester);
  });
}
