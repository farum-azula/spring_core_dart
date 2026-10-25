// Switching themes at run time, a theme loaded from a "server", and a
// broken theme property failing the start.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_themes/main.spring.dart';
import 'package:flutter_themes/src/gallery_page.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

Future<ApplicationContext> startApp(
  WidgetTester tester, [
  List<String> args = const [],
]) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => springApplication,
      args: args,
      home: const GalleryPage(),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pumpAndSettle();
  return SpringScope.of(tester.element(find.byType(GalleryPage)));
}

Color primary(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(GalleryPage))).colorScheme.primary;

void main() {
  testWidgets('every theme of the properties: standard ones, then by name', (
    tester,
  ) async {
    final context = await startApp(tester);
    expect(context.getBean<SpringThemes>().names, [
      'light',
      'dark',
      'high-contrast',
      'ocean',
      'ocean-night',
      'sepia',
    ]);
    expect(context.getBean<ThemeSelection>().active, 'system');
  });

  testWidgets('the menu switches the theme at once', (tester) async {
    final context = await startApp(tester);
    final themes = context.getBean<SpringThemes>();

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ocean').last);
    await tester.pumpAndSettle();

    expect(context.getBean<ThemeSelection>().active, 'ocean');
    expect(primary(tester), themes.material('ocean').colorScheme.primary);
    expect(find.text('Ocean'), findsOneWidget); // the banner
  });

  testWidgets('a theme loaded from the server', (tester) async {
    final context = await startApp(tester);

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load a theme from the server'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(context.getBean<SpringThemes>().names, contains('winter'));
    expect(context.getBean<ThemeSelection>().active, 'winter');
    expect(find.text('Theme winter loaded'), findsOneWidget);
  });

  testWidgets('the shared part and the theme\'s own properties', (
    tester,
  ) async {
    final context = await startApp(tester, [
      '--spring.flutter.theme.active=sepia',
    ]);
    final sepia = context.getBean<SpringThemes>().data('sepia');
    expect(sepia.colorScheme.surface, const Color(0xFFF4ECD8));
    expect(sepia.shape('medium'), 4);
    expect(sepia.fontFamily, 'Roboto'); // shared
    expect(sepia.tokenColor('brand.accent'), const Color(0xFF8B4513));
    final display = Theme.of(tester.element(find.byType(GalleryPage)))
        .textTheme
        .displaySmall!;
    expect(display.fontFamily, 'Roboto Condensed');
  });

  testWidgets('a broken theme property fails the start', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => springApplication,
        args: const ['--spring.flutter.theme.themes.sepia.seed-color=browm'],
        home: const GalleryPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('themes.sepia.seedcolor'), findsOneWidget);
    expect(find.byType(GalleryPage), findsNothing);
  });
}
