// Every page in every theme: the app starts from the properties, each page
// builds without an error (a layout overflow is one) and has its title.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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

  testWidgets("the Transitions page: the platform's by default, the "
      "platform's for a screen, a fade", (tester) async {
    // The light theme sets no transition (neon zooms, high-contrast none).
    final context = await startApp(tester, theme: AppThemes.light);
    await openPage(tester, 'Transitions');
    // Flutter's own transition on the test's platform.
    final flutters = const PageTransitionsTheme()
        .builders[Theme.of(tester.element(find.byType(Shell))).platform]!
        .transitionDuration;
    // The route of the screen, and its duration while it is open.
    Future<(PageRoute<Object?>, Duration)> open(
      String button,
      String title,
    ) async {
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
      final duration = route.transitionDuration;
      await tester.tap(find.text('Back'));
      await settle(tester);
      return (route, duration);
    }

    // The default: the platform's (the light theme sets no transition):
    // Material's route, with Flutter's duration.
    final (theme, themeDuration) = await open(
      'Open with the default',
      'With the default',
    );
    expect(theme, isA<MaterialRouteTransitionMixin<Object?>>());
    expect(themeDuration, flutters);
    final (platform, _) = await open(
      "Open with the platform's",
      "With the platform's",
    );
    expect(platform, isA<MaterialRouteTransitionMixin<Object?>>());
    final (_, fade) = await open('Open with a fade', 'With a fade');
    expect(fade, const Duration(milliseconds: 250));
    // High-contrast writes none: the screen is there at once.
    context.getBean<ThemeSelection>().select(AppThemes.highContrast);
    await settle(tester);
    final (_, instant) = await open(
      'Open with the default',
      'With the default',
    );
    expect(instant, Duration.zero);
    expect(tester.takeException(), isNull);
    await stopApp(tester);
  });
}
