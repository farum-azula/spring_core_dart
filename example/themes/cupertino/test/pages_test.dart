// Every page in every theme: the app starts from the properties, each page
// builds without an error (a layout overflow is one) and has its title.
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
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
  'transitions': 'Transitions',
  'themes': 'Themes',
};

void main() {
  _addresses();

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

// The pages are routes: an address opens its page in its tab, with the
// pages of its path below it.
void _addresses() {
  testWidgets('an address of "More" opens in the More tab, over its list', (
    tester,
  ) async {
    final context = await startApp(
      tester,
      size: phoneSize,
      page: pages.indexWhere((p) => p.id == 'motion'),
    );
    final route = context.getBean<RouteTemplate>();
    // A flat address, in the More tab (`branch: '/more'`).
    expect(route.uri.path, '/motion');
    expect(route.stack.map((s) => s.uri.path), ['/more', '/motion']);
    expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget);
    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await settle(tester);
    expect(route.uri.path, '/more');
    await stopApp(tester);
  });

  testWidgets('the sidebar opens a page at once, without a transition', (
    tester,
  ) async {
    await startApp(tester);
    await openPage(tester, 'Motion');
    final title = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.text('Motion'),
    );
    final route = ModalRoute.of(tester.element(title.first))! as PageRoute;
    expect(route.transitionDuration, Duration.zero);
    await stopApp(tester);
  });

  testWidgets("the Transitions page: the platform's by default, the "
      "platform's for a screen, a fade", (tester) async {
    await startApp(tester, size: phoneSize);
    await openPage(tester, 'Transitions');
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
                        of: find.byType(CustomScrollView),
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

    // The default: the platform's (the theme sets no transition): the iOS
    // slide, as a screen that asks for the platform's.
    final (theme, themeDuration) = await open(
      'Open with the default',
      'With the default',
    );
    expect(theme, isA<CupertinoRouteTransitionMixin<Object?>>());
    final (platform, platformDuration) = await open(
      "Open with the platform's",
      "With the platform's",
    );
    expect(platform, isA<CupertinoRouteTransitionMixin<Object?>>());
    expect(platformDuration, greaterThan(Duration.zero));
    expect(themeDuration, platformDuration);
    final (_, fade) = await open('Open with a fade', 'With a fade');
    expect(fade, const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    await stopApp(tester);
  });

  testWidgets('an unknown address shows the not-found screen', (tester) async {
    final context = await startApp(tester);
    await context.getBean<RouteTemplate>().go('/nowhere');
    await settle(tester);
    expect(find.text('No page at /nowhere'), findsOneWidget);
    await stopApp(tester);
  });
}

String _idOf(String title) =>
    _titles.entries.firstWhere((e) => e.value == title).key;
