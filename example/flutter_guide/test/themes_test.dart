// Chapter 3, "Themes": every theme comes from the properties
// (application.yml and themes/*.yml), Settings switches them at run time,
// one more is loaded at run time, the fonts come from an asset folder.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/src/app/home_page.dart';
import 'package:neon_books_app/src/settings/settings_page.dart';
import 'package:neon_books_app/src/settings/theme_preview.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

Color primary(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(SettingsPage))).colorScheme.primary;

void main() {
  testWidgets('the themes of the properties: standard ones, then by name', (
    tester,
  ) async {
    final context = await startApp(tester, FakeServer());
    expect(context.getBean<SpringThemes>().names, [
      'light',
      'dark',
      'high-contrast',
      'neon',
      'neon-night',
      'sepia',
    ]);
    expect(context.getBean<ThemeSelection>().active, 'system');
    await stopApp(tester);
  });

  testWidgets('extends: neon-night is neon, dark', (tester) async {
    final context = await startApp(tester, FakeServer());
    final themes = context.getBean<SpringThemes>();
    final neon = themes.data('neon');
    final night = themes.data('neon-night');

    expect(night.brightness, Brightness.dark);
    expect(neon.brightness, Brightness.light);
    expect(night.shape('large'), neon.shape('large'));
    expect(night.shape('large'), 28);
    expect(night.tokenColor('brand.accent'), const Color(0xFF00E5FF));
    // The shared part: fonts from res/fonts/, loaded by family.
    expect(neon.fontFamily, 'Roboto');
    expect(
      themes.material('neon').textTheme.displaySmall!.fontFamily,
      'Roboto Condensed',
    );
    await stopApp(tester);
  });

  testWidgets('Settings switches the theme at once', (tester) async {
    final context = await startApp(tester, FakeServer());
    final themes = context.getBean<SpringThemes>();
    await openMore(tester, 'Settings');

    await tester.tap(find.text('Sepia'));
    await tester.pumpAndSettle();

    expect(context.getBean<ThemeSelection>().active, 'sepia');
    expect(primary(tester), themes.material('sepia').colorScheme.primary);
    // The banner: the theme's name on its own brand token.
    final banner = SpringTheme.of(tester.element(find.byType(ThemeBanner)));
    expect(banner.name, 'sepia');
    expect(banner.tokenColor('brand.accent'), const Color(0xFF8B4513));
    await stopApp(tester);
  });

  testWidgets('a theme loaded at run time (SpringThemes.loadYaml)', (
    tester,
  ) async {
    final context = await startApp(tester, FakeServer());
    await openMore(tester, 'Settings');

    await tester.ensureVisible(find.text('Load a theme from the server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load a theme from the server'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(context.getBean<SpringThemes>().names, contains('winter'));
    expect(context.getBean<ThemeSelection>().active, 'winter');
    expect(find.text('Theme winter loaded'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('a broken theme property stops the start', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: FakeServer().application,
        args: const ['--spring.flutter.theme.themes.neon.seed-color=pinc'],
        home: const HomePage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('themes.neon.seedcolor'), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
  });
}
