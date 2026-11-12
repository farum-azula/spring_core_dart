// What the YAML says is what the app shows: the themes, the Cupertino
// theme, the references, the typed keys, the switcher, the states, the
// motion, the backgrounds and the images (without the network).
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/app/shell.dart';
import 'package:theme_showcase_cupertino/src/widgets/ios_widgets.dart';

import 'support/app.dart';

void main() {
  testWidgets('the app is a CupertinoApp', (tester) async {
    await startApp(tester);
    expect(find.byType(CupertinoApp), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('four themes, by the generated names', (tester) async {
    final context = await startApp(tester);
    final themes = context.getBean<SpringThemes>();
    expect(themes.names.toSet(), allThemes.toSet());
    await stopApp(tester);
  });

  testWidgets('extends: dark is light turned around, graphite is dark', (
    tester,
  ) async {
    final context = await startApp(tester);
    final themes = context.getBean<SpringThemes>();
    expect(themes.data(AppThemes.light).brightness, Brightness.light);
    expect(themes.data(AppThemes.dark).brightness, Brightness.dark);
    expect(themes.data(AppThemes.graphite).brightness, Brightness.dark);
    expect(themes.data(AppThemes.sunset).brightness, Brightness.light);
    // dark keeps what it does not change: the shape scale and the tokens.
    expect(themes.data(AppThemes.dark).shape('large'), 14);
    expect(themes.data(AppThemes.graphite).shape('large'), 14);
    expect(themes.data(AppThemes.graphite).token('brand.name'), 'Graphite');
    await stopApp(tester);
  });

  testWidgets('cupertino.*: the CupertinoThemeData of each theme', (
    tester,
  ) async {
    for (final (theme, primary, brightness) in [
      (AppThemes.light, const Color(0xFF007AFF), Brightness.light),
      (AppThemes.dark, const Color(0xFF0A84FF), Brightness.dark),
      (AppThemes.graphite, const Color(0xFFFF9F0A), Brightness.dark),
      (AppThemes.sunset, const Color(0xFFFF5E3A), Brightness.light),
    ]) {
      await startApp(tester, theme: theme);
      final cupertino = CupertinoTheme.of(tester.element(find.byType(Shell)));
      expect(cupertino.primaryColor, primary, reason: theme);
      expect(cupertino.brightness, brightness, reason: theme);
      // The action text styles carry the primary color.
      expect(cupertino.textTheme.actionTextStyle.color, primary);
      expect(cupertino.textTheme.navTitleTextStyle.fontSize, 17);
      expect(cupertino.textTheme.pickerTextStyle.fontSize, 21);
      expect(cupertino.textTheme.navLargeTitleTextStyle.fontSize, 34);
      await stopApp(tester);
    }
  });

  testWidgets('a theme with a background has see-through scaffolds', (
    tester,
  ) async {
    await startApp(tester, theme: AppThemes.light);
    var cupertino = CupertinoTheme.of(tester.element(find.byType(Shell)));
    expect(cupertino.scaffoldBackgroundColor, const Color(0xFFF2F2F7));
    await stopApp(tester);
    await startApp(tester, theme: AppThemes.sunset);
    cupertino = CupertinoTheme.of(tester.element(find.byType(Shell)));
    expect(cupertino.scaffoldBackgroundColor.a, 0);
    await stopApp(tester);
  });

  testWidgets('references and expressions follow each theme', (tester) async {
    for (final theme in allThemes) {
      await startApp(tester, theme: theme, page: 2);
      final element = tester.element(find.byType(Shell));
      final colors = element.theme.colors;
      final palette = element.theme.tokens.palette;
      // $colors.primary alpha 12%
      expect(
        palette.soft.toARGB32(),
        colors.primary.withValues(alpha: 0.12).toARGB32(),
        reason: theme,
      );
      // $colors.outline alpha 50%
      expect(
        colors.outlineVariant.toARGB32(),
        colors.outline.withValues(alpha: 0.5).toARGB32(),
        reason: theme,
      );
      expect(palette.edge, colors.outline, reason: theme);
      // $shape.small
      expect(
        element.theme.tokens.corner.tiny,
        SpringTheme.of(element).shape('small'),
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
    final tokens = tester.element(find.byType(Shell)).theme.tokens;
    expect(tokens.chart.bars, [4, 9, 6, 11, 7]);
    expect(tokens.chart.days, ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']);
    expect(tokens.chart.colors, hasLength(4));
    expect(tokens.timing.intro, const Duration(milliseconds: 600));
    expect(tokens.timing.stagger, const Duration(milliseconds: 120));
    expect(tokens.layout.card.padding, 16);
    expect(tokens.layout.card.radius, 14);
    expect(tokens.brand.badge.source, 'assets/images/badge.png');
    expect(tokens.brand.badge.isNetwork, isFalse);
    await stopApp(tester);
  });

  testWidgets('the theme menu switches the theme at once', (tester) async {
    await startApp(tester);
    expect(
      CupertinoTheme.of(tester.element(find.byType(Shell))).brightness,
      Brightness.light,
    );
    await tester.tap(find.text('Theme: light'));
    await settle(tester);
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('dark'));
    await settle(tester);
    expect(shownTheme(tester), 'dark');
    expect(
      CupertinoTheme.of(tester.element(find.byType(Shell))).brightness,
      Brightness.dark,
    );
    expect(find.text('Theme: dark'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('the themes page selects with the generated names', (
    tester,
  ) async {
    final context = await startApp(tester);
    await openPage(tester, 'Themes');
    await tester.tap(find.text('graphite').first);
    await settle(tester);
    expect(context.getBean<ThemeSelection>().active, AppThemes.graphite);
    expect(shownTheme(tester), 'graphite');
    await tester.tap(find.text('sunset').first);
    await settle(tester);
    expect(shownTheme(tester), 'sunset');
    await stopApp(tester);
  });

  testWidgets('the page opened is logged and kept when the theme changes', (
    tester,
  ) async {
    final context = await startApp(tester);
    await openPage(tester, 'Motion');
    context.getBean<ThemeSelection>().select(AppThemes.dark);
    await settle(tester);
    expect(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.text('Motion'),
      ),
      findsWidgets,
    );
    await stopApp(tester);
  });

  testWidgets('ThemeStates: hover, press, selected, disabled', (tester) async {
    await startApp(tester, page: 3);
    final chip = find.widgetWithText(IosChip, 'Hover me');
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
    final primary = element.theme.colors.primary;
    expect(border(), outline);

    await tester.ensureVisible(chip);
    await settle(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(chip));
    await settle(tester);
    expect(border(), primary);

    await mouse.moveTo(Offset.zero);
    await settle(tester);
    expect(border(), outline);

    // Selecting changes the border; a second tap undoes it.
    await tester.tap(chip);
    await settle(tester);
    expect(border(), primary);
    await tester.tap(chip);
    await settle(tester);
    expect(border(), outline);

    // No onPressed: disabled, and a tap does nothing.
    await tester.tap(find.widgetWithText(IosChip, 'Disabled'));
    await settle(tester);
    expect(find.byType(IosChip), findsWidgets);
    await stopApp(tester);
  });

  testWidgets('a press fades the button: the opacity of the style', (
    tester,
  ) async {
    await startApp(tester, page: 3);
    final button = find.text('Pressed 0 times');
    // Scroll it into the middle: at the top it would sit under the bar.
    await tester.ensureVisible(button);
    await settle(tester);
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 300),
    );
    await settle(tester);
    double opacity() => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.textContaining('Pressed '),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    expect(opacity(), 1);
    // A mouse button: the style's `pressed` state is the primary button.
    final press = await tester.startGesture(
      tester.getCenter(button),
      kind: PointerDeviceKind.mouse,
    );
    // One frame starts the transition, the next ends it.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(opacity(), closeTo(0.55, 0.01));
    await press.up();
    await settle(tester);
    expect(find.text('Pressed 1 times'), findsOneWidget);
    // Released, the mouse is still over it: the hovered value.
    expect(opacity(), closeTo(0.9, 0.01));
    await stopApp(tester);
  });

  testWidgets('reduce motion stops the animations', (tester) async {
    await startApp(tester, page: 5);
    expect(find.textContaining('disableAnimations: false'), findsOneWidget);
    final off = find.byType(CupertinoSwitch);
    await tester.ensureVisible(off);
    await settle(tester);
    await tester.tap(off);
    await settle(tester);
    expect(find.textContaining('disableAnimations: true'), findsOneWidget);
    expect(find.textContaining('motion.fast: 0 ms'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('a page opens with the iOS slide', (tester) async {
    await startApp(tester, page: 5);
    await tester.ensureVisible(find.text('Open a page'));
    await settle(tester);
    await tester.tap(find.text('Open a page'));
    await settle(tester);
    expect(find.text('A page'), findsWidgets);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('the controls: switch, sheet and dialog', (tester) async {
    await startApp(tester, page: 4);
    final sheet = find.text('Action sheet');
    await tester.ensureVisible(sheet);
    await settle(tester);
    await tester.tap(sheet);
    await settle(tester);
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('Send a link'));
    await settle(tester);
    expect(find.textContaining('action sheet: Send a link'), findsOneWidget);
    final alert = find.text('Alert dialog');
    await tester.tap(alert);
    await settle(tester);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await settle(tester);
    expect(find.textContaining('alert dialog: Switch'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('backgrounds: sunset has an image, graphite a gradient, '
      'light none', (tester) async {
    for (final (theme, image, gradient) in [
      (AppThemes.sunset, true, true),
      (AppThemes.graphite, false, true),
      (AppThemes.light, false, false),
    ]) {
      await startApp(tester, theme: theme, page: 7);
      final background = tester.element(find.byType(Shell)).theme.background;
      expect(background == null, !gradient, reason: theme);
      expect(background?.image != null, image, reason: theme);
      expect(background?.overlay?.gradient != null, gradient, reason: theme);
      expect(find.byType(ThemeBackground), findsWidgets);
      await stopApp(tester);
    }
  });

  testWidgets('a screen background only where the theme names it', (
    tester,
  ) async {
    await startApp(tester, theme: AppThemes.sunset, page: 7);
    final background = tester.element(find.byType(Shell)).theme.background!;
    expect(background.screens.keys, ['showcase']);
    expect(background.effect, BackgroundEffect.drift);
    expect(background.animation, 'background-drift');
    await stopApp(tester);
  });

  testWidgets('images: assets by default, nothing from the network', (
    tester,
  ) async {
    await startApp(tester, theme: AppThemes.sunset, page: 8);
    final element = tester.element(find.byType(Shell));
    final background = element.theme.background!.image!.image!;
    expect(background.isNetwork, isFalse);
    expect(element.theme.tokens.brand.badge.isNetwork, isFalse);
    expect(find.text('source: assets/images/badge.png'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('a phone: the More tab opens the pages without a tab', (
    tester,
  ) async {
    await startApp(tester, size: phoneSize);
    await openPage(tester, 'Tokens');
    expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget);
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
      final image = themes.data(AppThemes.sunset).background!.image!.image!;
      expect(image.isNetwork, isTrue);
      expect(image.source, startsWith('https://'));
      expect(image.fallback, 'assets/images/sunset-sky.png');
      final badge = themes.data(AppThemes.sunset).tokenImage('brand.badge')!;
      expect(badge.isNetwork, isTrue);
      expect(badge.fallback, 'assets/images/badge.png');
    });
  });

  group('the default profile', () {
    final app = springBootTest(springApplication);

    test('names no network image', () {
      final sunset = app.context.getBean<SpringThemes>().data(AppThemes.sunset);
      expect(sunset.background!.image!.image!.isNetwork, isFalse);
      expect(sunset.tokenImage('brand.badge')!.isNetwork, isFalse);
    });
  });
}
