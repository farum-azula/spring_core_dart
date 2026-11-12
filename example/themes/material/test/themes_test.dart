// What the YAML says is what the app shows: the themes, the references, the
// typed keys, the switcher, the states, the motion, the backgrounds and the
// images (without the network).
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart'
    show CupertinoThemes;
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/app/shell.dart';
import 'package:theme_showcase_material/src/widgets/styled_widgets.dart';

import 'support/app.dart';

void main() {
  testWidgets('six themes: light and dark, then by name', (tester) async {
    final context = await startApp(tester);
    final themes = context.getBean<SpringThemes>();
    expect(themes.names, [
      'light',
      'dark',
      'high-contrast',
      'neon',
      'ocean',
      'ocean-night',
    ]);
    expect(allThemes.toSet(), themes.names.toSet());
    await stopApp(tester);
  });

  testWidgets('extends: ocean-night is ocean, dark', (tester) async {
    final context = await startApp(tester);
    final themes = context.getBean<SpringThemes>();
    final ocean = themes.data(AppThemes.ocean);
    final night = themes.data(AppThemes.oceanNight);
    expect(ocean.brightness, Brightness.light);
    expect(night.brightness, Brightness.dark);
    expect(night.shape('large'), ocean.shape('large'));
    expect(night.shape('large'), 28);
    expect(night.token('brand.name'), 'Ocean at night');
    await stopApp(tester);
  });

  testWidgets('references and expressions follow each theme', (tester) async {
    for (final theme in [AppThemes.light, AppThemes.neon]) {
      await startApp(tester, theme: theme, page: 2);
      final element = tester.element(find.byType(Shell));
      final colors = element.theme.colors;
      final palette = element.theme.tokens.palette;
      final scheme = Theme.of(element).colorScheme;
      // $colors.primary alpha 12%
      expect(
        palette.soft.toARGB32(),
        scheme.primary.withValues(alpha: 0.12).toARGB32(),
        reason: theme,
      );
      // $colors.outline: a role nobody declared (light) or declared (neon).
      expect(palette.edge, scheme.outline, reason: theme);
      // outline-variant: $colors.outline alpha 50%
      expect(
        colors.outlineVariant.toARGB32(),
        scheme.outline.withValues(alpha: 0.5).toARGB32(),
        reason: theme,
      );
      // $shape.extra-small
      expect(
        element.theme.tokens.corner.tiny,
        SpringTheme.of(element).shape('extra-small'),
      );
      // A chain: deep refers to hover, which refers to primary.
      expect(palette.deep, isNot(palette.hover));
      await stopApp(tester);
    }
  });

  testWidgets('tokens: lists, durations, nested groups, an image', (
    tester,
  ) async {
    await startApp(tester, page: 2);
    final element = tester.element(find.byType(Shell));
    final tokens = element.theme.tokens;
    expect(tokens.chart.bars, [4, 9, 6, 11, 7]);
    expect(tokens.chart.days, ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']);
    expect(tokens.chart.colors, hasLength(4));
    expect(tokens.timing.intro, const Duration(milliseconds: 600));
    expect(tokens.timing.stagger, const Duration(milliseconds: 120));
    expect(tokens.layout.card.padding, 20);
    expect(tokens.brand.badge.source, 'assets/images/badge.png');
    expect(tokens.brand.badge.isNetwork, isFalse);
    await stopApp(tester);
  });

  testWidgets('the menu switches the theme at once', (tester) async {
    await startApp(tester, theme: AppThemes.light);
    expect(
      Theme.of(tester.element(find.byType(Shell))).brightness,
      Brightness.light,
    );
    await tester.tap(find.text('Active theme: light'));
    await settle(tester);
    await tester.tap(find.text('dark').last);
    await settle(tester);
    expect(shownTheme(tester), 'dark');
    expect(
      Theme.of(tester.element(find.byType(Shell))).brightness,
      Brightness.dark,
    );
    expect(find.text('Active theme: dark'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('the themes page selects with the generated names', (
    tester,
  ) async {
    final context = await startApp(tester);
    await openPage(tester, 'Themes');
    await tester.tap(find.text('high-contrast').first);
    await settle(tester);
    expect(context.getBean<ThemeSelection>().active, AppThemes.highContrast);
    expect(shownTheme(tester), 'high-contrast');
    await stopApp(tester);
  });

  testWidgets('components: states come from the YAML', (tester) async {
    await startApp(tester, theme: AppThemes.light, page: 3);
    final element = tester.element(find.byType(Shell));
    final button = Theme.of(element).filledButtonTheme.style!;
    final scheme = Theme.of(element).colorScheme;
    expect(button.backgroundColor!.resolve({}), scheme.primary);
    expect(
      button.backgroundColor!.resolve({WidgetState.pressed}),
      isSameColorAs(element.theme.colors.tertiary),
    );
    expect(
      button.backgroundColor!.resolve({WidgetState.hovered}),
      scheme.primary.withValues(alpha: 0.85),
    );
    expect(Theme.of(element).cardTheme.shape, isA<RoundedRectangleBorder>());
    await stopApp(tester);
  });

  testWidgets('the Cupertino theme comes from cupertino.*', (tester) async {
    final context = await startApp(tester, theme: AppThemes.light);
    final themes = context.getBean<CupertinoThemes>();
    final element = tester.element(find.byType(Shell));
    expect(
      themes.theme(AppThemes.light).primaryColor,
      Theme.of(element).colorScheme.primary,
    );
    await stopApp(tester);
  });

  testWidgets('ThemeStates: hover, press, selected, disabled', (tester) async {
    await startApp(tester, theme: AppThemes.light, page: 4);
    final chip = find.widgetWithText(PillChip, 'Hover me');
    Color border() =>
        (tester
                    .widget<Container>(
                      find
                          .descendant(
                            of: chip,
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .border!
            .top
            .color;
    final element = tester.element(find.byType(Shell));
    final outline = element.theme.colors.outline;
    final primary = Theme.of(element).colorScheme.primary;
    expect(border(), outline);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.ensureVisible(chip);
    await settle(tester);
    await mouse.moveTo(tester.getCenter(chip));
    await settle(tester);
    expect(border(), primary);

    await mouse.moveTo(Offset.zero);
    await settle(tester);
    expect(border(), outline);

    // Selecting changes the fill and the border; a second tap undoes it.
    await tester.tap(chip);
    await settle(tester);
    expect(border(), primary);
    await tester.tap(chip);
    await settle(tester);
    expect(border(), outline);

    // No onPressed: disabled, and a tap does nothing.
    final disabled = find.widgetWithText(PillChip, 'Disabled');
    await tester.tap(disabled);
    await settle(tester);
    expect(find.byType(PillChip), findsWidgets);
    await stopApp(tester);
  });

  testWidgets('the button counts presses; Enter works with focus', (
    tester,
  ) async {
    await startApp(tester, theme: AppThemes.light, page: 4);
    await tester.ensureVisible(find.text('Pressed 0 times'));
    await tester.tap(find.text('Pressed 0 times'));
    await settle(tester);
    expect(find.text('Pressed 1 times'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('reduce motion stops the animations', (tester) async {
    await startApp(tester, theme: AppThemes.light, page: 5);
    expect(find.textContaining('disableAnimations: false'), findsOneWidget);
    final off = find.text('Pretend the device asks for less motion');
    await tester.ensureVisible(off);
    await tester.tap(off);
    await settle(tester);
    expect(find.textContaining('disableAnimations: true'), findsOneWidget);
    expect(find.textContaining('motion.fast: 0 ms'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('a page opens with the theme\'s page transition', (tester) async {
    await startApp(tester, theme: AppThemes.neon, page: 5);
    final element = tester.element(find.byType(Shell));
    final builders = Theme.of(element).pageTransitionsTheme.builders;
    expect(builders.values.first, isA<ZoomPageTransitionsBuilder>());
    await tester.ensureVisible(find.text('Open a page'));
    await tester.tap(find.text('Open a page'));
    await settle(tester);
    expect(find.text('A page'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('backgrounds: neon has an image, ocean-night a gradient, '
      'light none', (tester) async {
    for (final (theme, image, gradient) in [
      (AppThemes.neon, true, true),
      (AppThemes.oceanNight, false, true),
      (AppThemes.light, false, false),
    ]) {
      await startApp(tester, theme: theme, page: 7);
      final background = tester.element(find.byType(Shell)).theme.background;
      expect(background == null, !gradient, reason: theme);
      expect(background?.image != null, image, reason: theme);
      expect(
        background?.overlay?.gradient != null,
        gradient,
        reason: theme,
      );
      expect(find.byType(ThemeBackground), findsWidgets);
      await stopApp(tester);
    }
  });

  testWidgets('a screen background only where the theme names it', (
    tester,
  ) async {
    await startApp(tester, theme: AppThemes.neon, page: 7);
    final background = tester.element(find.byType(Shell)).theme.background!;
    expect(background.screens.keys, ['showcase']);
    expect(background.effect, BackgroundEffect.drift);
    expect(background.animation, 'background-drift');
    await stopApp(tester);
  });

  testWidgets('images: assets by default, nothing from the network', (
    tester,
  ) async {
    await startApp(tester, page: 8);
    final element = tester.element(find.byType(Shell));
    final background = element.theme.background!.image!.image!;
    expect(background.isNetwork, isFalse);
    expect(element.theme.tokens.brand.badge.isNetwork, isFalse);
    expect(find.text('source: assets/images/badge.png'), findsOneWidget);
    await stopApp(tester);
  });

  group('the network profile', () {
    final http = MockHttpTransport();
    final app = springBootTest(
      springApplication,
      profiles: ['network'],
      overrides: [BeanOverride<HttpTransport>(http)],
    );

    test('points the images at https and keeps the assets as fallback', () {
      final themes = app.context.getBean<SpringThemes>();
      final neon = themes.data(AppThemes.neon);
      final image = neon.background!.image!.image!;
      expect(image.isNetwork, isTrue);
      expect(image.source, startsWith('https://'));
      expect(image.fallback, 'assets/images/neon-grid.png');
      final badge = neon.tokenImage('brand.badge')!;
      expect(badge.isNetwork, isTrue);
      expect(badge.fallback, 'assets/images/badge.png');
    });
  });

  group('the default profile', () {
    final app = springBootTest(springApplication);
    test('names no network image', () {
      expect(
        app.context
            .getBean<SpringThemes>()
            .data(AppThemes.neon)
            .background!
            .image!
            .image!
            .isNetwork,
        isFalse,
      );
    });
  });
}
