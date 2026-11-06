// Every page in every theme: the app starts from the properties, each page
// builds without an error (a layout overflow is one) and has its title.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
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
  'loaders': 'Loaders',
  'background': 'Background',
  'images': 'Images',
  'transitions': 'Transitions',
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

  testWidgets('each page has its address; an unknown one, the not-found page', (
    tester,
  ) async {
    final context = await startApp(tester);
    final route = context.getBean<RouteTemplate>();
    expect(route.uri.path, '/colors');

    await route.go('/motion');
    await settle(tester);
    expect(
      find.descendant(
        of: find.byType(PageFrame),
        matching: find.text('Motion'),
      ),
      findsOneWidget,
    );
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, pages.indexWhere((p) => p.id == 'motion'));

    await openPage(tester, 'Themes');
    expect(route.uri.path, '/themes');

    await route.go('/nope');
    await settle(tester);
    expect(find.text('No page at /nope'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets("the Transitions page: none by default, the platform's, a fade", (
    tester,
  ) async {
    // The light theme sets no transition (neon zooms).
    await startApp(tester, theme: AppThemes.light);
    await openPage(tester, 'Transitions');
    Future<PageRoute<Object?>> open(String button, String title) async {
      await tester.ensureVisible(find.text(button));
      await settle(tester);
      await tester.tap(find.text(button));
      await settle(tester);
      final route =
          ModalRoute.of(
                tester.element(
                  find
                      .descendant(
                        of: find.byType(PageFrame),
                        matching: find.text(title),
                      )
                      .first,
                ),
              )!
              as PageRoute<Object?>;
      await tester.tap(find.text('Back'));
      await settle(tester);
      return route;
    }

    // The default: none (the light theme sets no transition).
    final theme = await open('Open with the default', 'With the default');
    expect(theme.transitionDuration, Duration.zero);
    final platform = await open(
      "Open with the platform's",
      "With the platform's",
    );
    expect(platform, isA<MaterialRouteTransitionMixin<Object?>>());
    final fade = await open('Open with a fade', 'With a fade');
    expect(fade.transitionDuration, const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    await stopApp(tester);
  });
}
