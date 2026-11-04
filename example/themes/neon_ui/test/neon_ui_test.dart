import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'support.dart';

const _yellow = Color(0xFFF2E35B);
const _cyan = Color(0xFF4FD8E8);

void main() {
  testWidgets('every widget builds in the theme, without an error', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);
    await pumpNeon(
      tester,
      SizedBox(
        width: 600,
        height: 700,
        child: Column(
          children: [
            const NeonLogo(text: 'NEON'),
            const NeonLabel('label'),
            const NeonBadge('ok', tone: NeonTone.green),
            NeonButton(label: 'Go', onPressed: () {}),
            NeonButton(label: 'Outline', filled: false, onPressed: () {}),
            NeonChip(label: 'chip', selected: true, onPressed: () {}),
            NeonField(
              label: 'Name',
              child: NeonTextField(controller: controller),
            ),
            const NeonCode('a: b'),
            NeonResizeHandle(onDrag: (_) {}),
            const SizedBox(
              height: 100,
              child: NeonPanel(title: 'Panel', child: SizedBox()),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('GO'), findsOneWidget);
    expect(find.text('NEON'), findsWidgets);
  });

  group('NeonButton', () {
    testWidgets('hover lights it, press calls back, Enter too', (tester) async {
      var pressed = 0;
      await pumpNeon(
        tester,
        NeonButton(label: 'Go', onPressed: () => pressed++),
      );
      final button = find.byType(NeonButton);
      expect(decorationOf(tester, button).color, _yellow);
      await hover(tester, button);
      // `colors.primary` mixed with white 14%: lighter than the primary.
      final hovered = decorationOf(tester, button).color!;
      expect(hovered, isNot(_yellow));
      expect(
        hovered.computeLuminance(),
        greaterThan(_yellow.computeLuminance()),
      );
      await tester.tap(button);
      expect(pressed, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(pressed, 2);
    });

    testWidgets('without onPressed it is disabled and does not react', (
      tester,
    ) async {
      await pumpNeon(tester, const NeonButton(label: 'Go', onPressed: null));
      final fill = decorationOf(tester, find.byType(NeonButton)).color!;
      // `colors.primary` with alpha 40%
      expect(fill.a, closeTo(0.4, 0.01));
      expect(fill.r, closeTo(_yellow.r, 0.01));
    });

    testWidgets('the outlined one gets a primary border on hover', (
      tester,
    ) async {
      await pumpNeon(
        tester,
        NeonButton(label: 'Go', filled: false, onPressed: () {}),
      );
      final button = find.byType(NeonButton);
      Color border() =>
          (decorationOf(tester, button).border! as Border).top.color;
      expect(border(), const Color(0xFF343A48));
      await hover(tester, button);
      expect(border(), _yellow);
    });
  });

  testWidgets('NeonChip: selected has a soft fill and a primary border', (
    tester,
  ) async {
    await pumpNeon(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeonChip(label: 'one', selected: true, onPressed: () {}),
          const SizedBox(width: 8),
          NeonChip(label: 'two', selected: false, onPressed: () {}),
        ],
      ),
    );
    final chips = find.byType(NeonChip);
    final on = decorationOf(tester, chips.first);
    final off = decorationOf(tester, chips.last);
    expect(on.color!.a, closeTo(0.12, 0.01));
    expect((on.border! as Border).top.color, _yellow);
    expect(off.color, const Color(0x00000000));
  });

  testWidgets('NeonBadge: the soft fill is a color object of the tone', (
    tester,
  ) async {
    await pumpNeon(tester, const NeonBadge('x', tone: NeonTone.cyan));
    final box = decorationOf(tester, find.byType(NeonBadge));
    expect(box.color!.a, closeTo(0.12, 0.01));
    expect((box.border! as Border).top.color, _cyan);
  });

  group('NeonTextField', () {
    testWidgets('typing, focus lights the frame, error turns it red', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var error = false;
      late StateSetter update;
      await pumpNeon(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SizedBox(
              width: 300,
              child: NeonTextField(controller: controller, error: error),
            );
          },
        ),
      );
      final field = find.byType(NeonTextField);
      Color border() =>
          (decorationOf(tester, field).border! as Border).top.color;
      expect(border(), const Color(0xFF343A48));
      await tester.tap(field);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(border(), _yellow);
      await tester.enterText(find.byType(EditableText), 'a b');
      expect(controller.text, 'a b');
      update(() => error = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(border(), const Color(0xFFFF5C7A));
    });
  });

  group('NeonGlowBorder', () {
    double turn(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(NeonGlowBorder),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      return (paint.foregroundPainter! as dynamic).turn.value as double;
    }

    testWidgets('turns with animations.border-spin (4s, loop)', (
      tester,
    ) async {
      await pumpNeon(tester, const NeonGlowBorder(child: SizedBox(width: 50)));
      final before = turn(tester);
      await tester.pump(const Duration(seconds: 1));
      final after = turn(tester);
      expect(after, isNot(before));
      // A quarter of the four seconds later: about a quarter further.
      expect((after - before).abs(), closeTo(0.25, 0.05));
    });

    testWidgets('stands still when the system asks for less motion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpNeon(tester, const NeonGlowBorder(child: SizedBox(width: 50)));
      await tester.pump(const Duration(seconds: 2));
      expect(turn(tester), 0);
    });
  });

  testWidgets('showNeonModal: width and turning border from the theme', (
    tester,
  ) async {
    await pumpNeon(
      tester,
      Builder(
        builder: (context) => NeonButton(
          label: 'Open',
          onPressed: () => showNeonModal<void>(
            context,
            builder: (_) => const SizedBox(height: 80, child: NeonLabel('hi')),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(NeonButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('HI'), findsOneWidget);
    expect(tester.getSize(find.byType(NeonGlowBorder)).width, 460);
    // The barrier is `transparent`; a tap on it closes the modal.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('HI'), findsNothing);
  });

  testWidgets('a theme that extends neon and changes one color follows', (
    tester,
  ) async {
    await pumpNeon(
      tester,
      NeonButton(label: 'Go', onPressed: () {}),
      properties: const {
        'spring.flutter.theme.active': 'ice',
        'spring.flutter.theme.themes.ice.extends': 'neon',
        'spring.flutter.theme.themes.ice.colors.primary': r'$neon.cyan',
      },
    );
    // The button's fill, the accent and the border colors all refer to
    // `colors.primary`.
    expect(decorationOf(tester, find.byType(NeonButton)).color, _cyan);
  });

  testWidgets('NeonLogsPanel shows the records of a LogBuffer', (
    tester,
  ) async {
    final buffer = LogBuffer();
    addTearDown(buffer.clear);
    await pumpNeon(
      tester,
      SizedBox(
        width: 700,
        height: 300,
        child: NeonLogsPanel(buffer: buffer, emptyMessage: 'nothing yet'),
      ),
    );
    expect(find.text('NOTHING YET'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
