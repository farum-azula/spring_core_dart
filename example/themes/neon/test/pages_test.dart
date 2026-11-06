// Every page in every theme: the app starts from the properties, each page
// builds without an error (a layout overflow is one) and has its title.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_neon/src/app/shell.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/tile_grid.dart';

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

  // The overview's tiles: as many columns as fit, each as tall as its
  // text, whatever the width.
  for (final width in [700.0, 1000.0, 1600.0]) {
    testWidgets('the pieces keep their whole text at width $width', (
      tester,
    ) async {
      await startApp(tester, size: Size(width, 2400));
      final grid = find.byType(TileGrid);
      final panels = find.descendant(
        of: grid,
        matching: find.byType(NeonPanel),
      );
      expect(panels, findsNWidgets(6));
      for (final panel in panels.evaluate()) {
        final box = tester.getRect(find.byWidget(panel.widget));
        final text = find.descendant(
          of: find.byWidget(panel.widget),
          matching: find.byType(RichText),
        );
        final body = tester.getRect(text.last);
        expect(body.bottom, lessThanOrEqualTo(box.bottom), reason: '$width');
        // Laid out as tall as its lines need: nothing cut off.
        final paragraph = tester.renderObject<RenderParagraph>(text.last);
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(
            paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5,
          ),
          reason: '$width',
        );
      }
      expect(tester.takeException(), isNull);
      await stopApp(tester);
    });
  }

  testWidgets('each page has its address; a chip goes there', (tester) async {
    final context = await startApp(tester);
    final route = context.getBean<RouteTemplate>();
    expect(route.uri.path, '/overview');
    for (final (label, title) in pageTitles.values.skip(1)) {
      await openPage(tester, label);
      expect(_title(title), findsOneWidget, reason: title);
    }
    expect(route.uri.path, '/themes');
    await route.go('/states');
    await settle(tester);
    expect(_title('States'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('an address that is no page: the not-found page', (
    tester,
  ) async {
    final context = await startApp(tester);
    await context.getBean<RouteTemplate>().go('/nope');
    await settle(tester);
    expect(find.text('No page here'), findsOneWidget);
    await tester.tap(find.text('TO THE OVERVIEW'));
    await settle(tester);
    expect(_title('A design system without Material'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets("the Transitions page: none by default, the platform's, a zoom", (
    tester,
  ) async {
    await startApp(tester);
    await openPage(tester, 'Transitions');
    Future<PageRoute<Object?>> open(String button, String title) async {
      await tester.ensureVisible(find.text(button));
      await settle(tester);
      await tester.tap(find.text(button));
      await settle(tester);
      final route =
          ModalRoute.of(tester.element(_title(title).first))!
              as PageRoute<Object?>;
      await tester.tap(find.text('BACK'));
      await settle(tester);
      return route;
    }

    // The default: none; the platform's: none too in a WidgetsApp.
    final theme = await open('OPEN WITH THE DEFAULT', 'With the default');
    expect(theme.transitionDuration, Duration.zero);
    final platform = await open(
      "OPEN WITH THE PLATFORM'S",
      "With the platform's",
    );
    expect(platform.transitionDuration, Duration.zero);
    final zoom = await open('OPEN WITH A ZOOM', 'With a zoom');
    expect(zoom.transitionDuration, const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await stopApp(tester);
  });
}
