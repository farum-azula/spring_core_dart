// The theme at work: the switch between neon and neon-ice, states, the glow
// modal, reduce motion, the log page.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/app/shell.dart';
import 'package:theme_showcase_neon/src/widgets/state_tile.dart';

import 'support/app.dart';

const _yellow = Color(0xFFF2E35B);
const _cyan = Color(0xFF4FD8E8);

Color _fill(WidgetTester tester, Finder button) =>
    (tester
                .widget<Container>(
                  find
                      .descendant(of: button, matching: find.byType(Container))
                      .first,
                )
                .decoration!
            as BoxDecoration)
        .color!;

Finder _button(String label) =>
    find.widgetWithText(NeonButton, label.toUpperCase());

void main() {
  testWidgets('the generated names of the themes', (tester) async {
    await startApp(tester);
    final element = tester.element(find.byType(Shell));
    expect(showcaseThemes, [AppThemes.neon, AppThemes.neonIce]);
    expect(AppThemes.neonIce, 'neon-ice');
    // The library's theme and ours are both known to the app.
    expect(
      SpringThemes.of(SpringScope.of(element)).names,
      containsAll(['neon', 'neon-ice']),
    );
    await stopApp(tester);
  });

  testWidgets('the switcher changes the theme: yellow becomes cyan', (
    tester,
  ) async {
    await startApp(tester, page: 1);
    final button = _button('Save');
    expect(shownTheme(tester), 'neon');
    expect(_fill(tester, button), _yellow);
    final element = tester.element(find.byType(Shell));
    expect(element.theme.colors.primary, _yellow);

    await tester.tap(find.widgetWithText(NeonChip, 'neon-ice'));
    await settle(tester);
    expect(shownTheme(tester), 'neon-ice');
    expect(_fill(tester, button), _cyan);
    expect(element.theme.colors.primary, _cyan);
    // Everything that says $neon.accent follows: the modal's first color.
    expect(element.theme.tokens.neon.modal.border.colors.first, _cyan);
    // And back.
    await tester.tap(find.widgetWithText(NeonChip, 'neon'));
    await settle(tester);
    expect(_fill(tester, button), _yellow);
    await stopApp(tester);
  });

  testWidgets('the theme switch is in the log', (tester) async {
    await startApp(tester);
    await tester.tap(find.widgetWithText(NeonChip, 'neon-ice'));
    await settle(tester);
    await openPage(tester, 'Logs');
    // The buffer is the process's: lines of earlier tests may be there.
    expect(
      find.textContaining(
        'theme selected {theme: neon-ice}',
        findRichText: true,
      ),
      findsWidgets,
    );
    expect(
      find.textContaining('page opened {page: logs}', findRichText: true),
      findsWidgets,
    );
    await stopApp(tester);
  });

  testWidgets('the Logs page writes a line on request', (tester) async {
    await startApp(tester, page: 7);
    await tester.tap(_button('Warning'));
    await settle(tester);
    expect(
      find.textContaining('a line at warning', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(_button('Error'));
    await settle(tester);
    expect(
      find.textContaining('on request', findRichText: true),
      findsWidgets,
    );
    await stopApp(tester);
  });

  testWidgets('Components: a press is counted, a field takes text', (
    tester,
  ) async {
    await startApp(tester, page: 1);
    expect(find.text('Press one.'), findsOneWidget);
    await tester.tap(_button('Save'));
    await settle(tester);
    expect(find.text('Pressed 1 times.'), findsOneWidget);
    // A disabled button does nothing.
    await tester.tap(find.widgetWithText(NeonButton, 'DISABLED').first);
    await settle(tester);
    expect(find.text('Pressed 1 times.'), findsOneWidget);
    final field = find.descendant(
      of: find.widgetWithText(NeonField, 'NAME'),
      matching: find.byType(EditableText),
    );
    await tester.enterText(field, 'Grace');
    expect(find.text('Grace'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('States: disabled dims the button, error reddens the field', (
    tester,
  ) async {
    await startApp(tester, page: 2);
    final press = _button('Press me');
    expect(_fill(tester, press), _yellow);
    await tester.tap(find.widgetWithText(NeonChip, 'disabled'));
    await settle(tester);
    // `colors.primary` with alpha 40%
    expect(_fill(tester, press).a, closeTo(0.4, 0.01));
    await tester.tap(press);
    await settle(tester);
    expect(find.textContaining('Pressed 1 times'), findsNothing);

    await tester.tap(find.widgetWithText(NeonChip, 'disabled'));
    await settle(tester);
    await tester.tap(press);
    await settle(tester);
    expect(find.text('Pressed 1 times.'), findsOneWidget);

    final field = find.byType(NeonTextField);
    Color border() =>
        ((tester
                            .widget<Container>(
                              find
                                  .descendant(
                                    of: field,
                                    matching: find.byType(Container),
                                  )
                                  .first,
                            )
                            .decoration!
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .color;
    expect(border(), const Color(0xFF343A48));
    await tester.tap(find.widgetWithText(NeonChip, 'error'));
    await settle(tester);
    expect(border(), const Color(0xFFFF5C7A));
    await stopApp(tester);
  });

  testWidgets('a tile of the app\'s own style is selected by a tap', (
    tester,
  ) async {
    await startApp(tester, page: 8);
    final tiles = find.byType(StateTile);
    Color border(int i) =>
        ((tester
                            .widget<Container>(
                              find
                                  .descendant(
                                    of: tiles.at(i),
                                    matching: find.byType(Container),
                                  )
                                  .first,
                            )
                            .decoration!
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .color;
    expect(border(0), _yellow); // neon is selected
    expect(border(1), isNot(_cyan));
    await tester.tap(tiles.at(1));
    await settle(tester);
    expect(shownTheme(tester), 'neon-ice');
    expect(border(1), _cyan);
    await stopApp(tester);
  });

  group('the glow modal', () {
    testWidgets('opens, has the width and the colors of the theme, closes', (
      tester,
    ) async {
      await startApp(tester, page: 3);
      await tester.tap(_button('Open the modal'));
      await settle(tester);
      expect(find.text('Save the changes?'), findsOneWidget);
      expect(tester.getSize(find.byType(NeonGlowBorder).last).width, 460);
      await tester.tap(_button('Cancel'));
      await settle(tester);
      expect(find.text('Save the changes?'), findsNothing);
      // A tap on the (transparent) barrier closes it too.
      await tester.tap(_button('Open the modal'));
      await settle(tester);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      expect(find.text('Save the changes?'), findsNothing);
      await stopApp(tester);
    });

    testWidgets('the border turns, and stands still with reduce motion', (
      tester,
    ) async {
      await startApp(tester, page: 3);
      double turn() =>
          ((tester
                          .widget<CustomPaint>(
                            find
                                .descendant(
                                  of: find.byType(NeonGlowBorder),
                                  matching: find.byType(CustomPaint),
                                )
                                .first,
                          )
                          .foregroundPainter!)
                      as dynamic)
                  .turn
                  .value
              as double;
      final before = turn();
      await tester.pump(const Duration(seconds: 1));
      expect(turn(), isNot(before));
      expect(
        find.text('disableAnimations: false', findRichText: true),
        findsNothing,
      );
      await tester.tap(
        find.widgetWithText(
          NeonChip,
          'Pretend the device asks for less motion',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.textContaining('disableAnimations: true'),
        findsOneWidget,
      );
      expect(find.textContaining('motion.medium: 0 ms'), findsOneWidget);
      final still = turn();
      await tester.pump(const Duration(seconds: 1));
      expect(turn(), still);
      expect(still, 0);
      await stopApp(tester);
    });
  });

  testWidgets('Background: the theme\'s, a screen\'s and none', (tester) async {
    await startApp(tester, page: 5);
    // The one under the whole app and the three tiles.
    expect(find.byType(ThemeBackground), findsNWidgets(4));
    await stopApp(tester);
  });

  testWidgets('Tokens: the list of colors and the app\'s own token', (
    tester,
  ) async {
    await startApp(tester, page: 6);
    expect(find.text('colors[3]'), findsOneWidget);
    expect(find.text('showcase.content-width: 980'), findsOneWidget);
    await stopApp(tester);
  });
}
