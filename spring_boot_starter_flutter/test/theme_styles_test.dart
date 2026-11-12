// `styles.*`: states, precedence, types, lerp, and ThemeStates.
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';

SpringThemeData theme(Map<String, String> properties) =>
    SpringThemeData.of(ThemeConfig(properties), 'light');

const _props = {
  'colors.primary': '#FF0000',
  'styles.chip.padding.0': '12',
  'styles.chip.padding.1': '6',
  'styles.chip.radius': '8',
  'styles.chip.label': 'Hello, world',
  'styles.chip.delay': '50ms',
  'styles.chip.border.default': '#000000',
  'styles.chip.border.hovered': r'$colors.primary',
  'styles.chip.border.focused': '#00FF00',
  'styles.chip.border.pressed': '#0000FF',
  'styles.chip.border.disabled': '#888888',
  'styles.chip.border.selected': '#FFFF00',
  'styles.chip.fill.default': 'transparent',
  'styles.chip.fill.selected.color': r'$colors.primary',
  'styles.chip.fill.selected.alpha': '12%',
  'styles.chip.transition': '120ms ease-out',
};

StateStyle chip() =>
    ThemeKeyReader(theme(_props)).style('neon-chip'.replaceAll('neon-', ''));

void main() {
  group('StateStyle', () {
    test('types by value', () {
      final v = chip().resolve({});
      expect(
        v.insets('padding'),
        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      );
      expect(v.number('radius'), 8);
      expect(v.text('label'), 'Hello, world');
      expect(v.duration('delay'), const Duration(milliseconds: 50));
      expect(v.color('border'), const Color(0xFF000000));
      expect(v.color('fill'), const Color(0x00000000));
      expect(v.insets('radius'), const EdgeInsets.all(8));
    });

    test('insets forms', () {
      StyleValues v(String key, Map<String, String> items) => theme({
        for (final e in items.entries) 'styles.s.$key${e.key}': e.value,
      }).styles['s']!.resolve({});
      expect(
        v('p', {'': '1, 2, 3, 4'}).insets('p'),
        const EdgeInsets.fromLTRB(1, 2, 3, 4),
      );
      expect(v('p', {'.0': '5'}).insets('p'), const EdgeInsets.all(5));
      expect(
        v('p', {'.0': '1', '.1': '2', '.2': '3', '.3': '4'}).insets('p'),
        const EdgeInsets.fromLTRB(1, 2, 3, 4),
      );
    });

    test('transition and properties', () {
      final s = chip();
      expect(s.transition, const Duration(milliseconds: 120));
      expect(s.transitionCurve, Curves.easeOut);
      expect(s.properties, containsAll(['padding', 'border', 'fill']));
      expect(s.properties, isNot(contains('transition')));
      expect(s.style, same(s));
    });

    test('precedence: disabled > pressed > hovered > focused > selected', () {
      final s = chip();
      Color border(Set<WidgetState> states) =>
          s.resolve(states).color('border');
      expect(border({}), const Color(0xFF000000));
      expect(border({WidgetState.selected}), const Color(0xFFFFFF00));
      expect(
        border({WidgetState.selected, WidgetState.focused}),
        const Color(0xFF00FF00),
      );
      expect(
        border({WidgetState.focused, WidgetState.hovered}),
        const Color(0xFFFF0000),
      );
      expect(
        border({WidgetState.hovered, WidgetState.pressed}),
        const Color(0xFF0000FF),
      );
      expect(
        border({
          WidgetState.pressed,
          WidgetState.disabled,
          WidgetState.hovered,
        }),
        const Color(0xFF888888),
      );
      // A state without its own value falls back to the default.
      expect(border({WidgetState.error}), const Color(0xFF000000));
      expect(
        s.resolve({WidgetState.selected}).color('fill').a,
        closeTo(0.12, 0.01),
      );
    });

    test('a missing property or a wrong type is a StateError', () {
      final v = chip().resolve({});
      expect(() => v.color('nope'), throwsStateError);
      expect(() => v.color('radius'), throwsStateError);
      expect(() => v.number('border'), throwsStateError);
      expect(() => v.text('radius'), throwsStateError);
      expect(() => theme(_props).styles['x'], returnsNormally);
      expect(
        () => ThemeKeyReader(theme(_props)).style('nope'),
        throwsStateError,
      );
    });

    test('lerp keeps insets from going negative when a curve overshoots', () {
      final style = theme({
        'styles.s.pad.default': '0, 0',
        'styles.s.pad.hovered': '10, 10',
      }).styles['s']!;
      final a = style.resolve(const {});
      final b = style.resolve({WidgetState.hovered});
      final under = StyleValues.lerp(a, b, -0.5).insets('pad');
      expect(under.left, 0);
      expect(under.top, 0);
      expect(StyleValues.lerp(a, b, 1.5).insets('pad').left, 15);
    });

    test('lerp', () {
      final s = chip();
      final a = s.resolve({});
      final b = s.resolve({WidgetState.hovered});
      final mid = StyleValues.lerp(a, b, 0.5);
      expect(
        mid.color('border'),
        Color.lerp(const Color(0xFF000000), const Color(0xFFFF0000), 0.5),
      );
      expect(StyleValues.lerp(a, b, 0).color('border'), a.color('border'));
      expect(StyleValues.lerp(a, b, 1).color('border'), b.color('border'));
      expect(mid.number('radius'), 8);
      expect(a, equals(s.resolve({})));
      expect(a.hashCode, s.resolve({}).hashCode);
    });

    test('invalid styles stop the start', () {
      void bad(Map<String, String> p, [String? contains]) => expect(
        () => theme(p),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.toString(),
            'message',
            contains == null ? isNotEmpty : stringContainsInOrder([contains]),
          ),
        ),
      );
      bad({
        'styles.a.fill.hoverd': '#000000',
        'styles.a.fill.default': '#000',
      }, 'did you mean');
      bad({'styles.a.fill.hovered': '#000000'}, 'default');
      bad({
        'styles.a.fill.default': '#000000',
        'styles.a.fill.hovered': '4',
      }, 'same kind');
      bad({
        'styles.a.padding.0': '1',
        'styles.a.padding.1': '2',
        'styles.a.padding.2': '3',
      }, 'insets');
      bad({'styles.a.padding.0': 'x'}, 'insets');
      bad({'styles.a.transition': 'quick'}, 'duration');
      bad({'styles.a.transition': '1s wobbly'}, 'curve');
      bad({
        'colors.primary': '#000',
        'styles.a.fill': r'$colors.primry',
      }, 'did you mean');
    });
  });

  group('ThemeStates', () {
    Future<void> pumpChip(
      WidgetTester tester, {
      VoidCallback? onPressed,
      bool selected = false,
      bool error = false,
      bool reduce = false,
      FocusNode? focusNode,
      List<StyleValues>? seen,
      MouseCursor? cursor,
      bool showFocusAlways = false,
    }) => tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ThemeStates<StyleValues>(
              style: chip(),
              selected: selected,
              error: error,
              onPressed: onPressed,
              focusNode: focusNode,
              mouseCursor: cursor,
              showFocusAlways: showFocusAlways,
              builder: (context, values) {
                seen?.add(values);
                return SizedBox(
                  key: const Key('box'),
                  width: 100,
                  height: 40,
                  child: ColoredBox(color: values.color('border')),
                );
              },
            ),
          ),
        ),
      ),
    );

    Color shown(WidgetTester tester) => tester
        .widget<ColoredBox>(
          find.descendant(
            of: find.byKey(const Key('box')),
            matching: find.byType(ColoredBox),
          ),
        )
        .color;

    testWidgets('disabled without onPressed', (tester) async {
      await pumpChip(tester);
      expect(shown(tester), const Color(0xFF888888));
    });

    testWidgets('hover, press and release', (tester) async {
      var taps = 0;
      await pumpChip(tester, onPressed: () => taps++);
      await tester.pumpAndSettle();
      expect(shown(tester), const Color(0xFF000000));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(const Key('box'))));
      await tester.pumpAndSettle();
      expect(shown(tester), const Color(0xFFFF0000));
      await mouse.down(tester.getCenter(find.byKey(const Key('box'))));
      await tester.pumpAndSettle();
      expect(shown(tester), const Color(0xFF0000FF));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(shown(tester), const Color(0xFFFF0000));
      expect(taps, 1);
      await mouse.moveTo(const Offset(500, 500));
      await tester.pumpAndSettle();
      expect(shown(tester), const Color(0xFF000000));
    });

    testWidgets('selected, error and the cursor', (tester) async {
      await pumpChip(tester, onPressed: () {}, selected: true);
      await tester.pumpAndSettle();
      expect(shown(tester), const Color(0xFFFFFF00));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: tester.getCenter(find.byKey(const Key('box'))),
      );
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
    });

    testWidgets('keyboard: focus, then enter and space', (tester) async {
      var taps = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpChip(tester, onPressed: () => taps++, focusNode: node);
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(taps, 2);
    });

    testWidgets('focus after a touch: shown only with showFocusAlways', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      for (final always in [false, true]) {
        final node = FocusNode();
        addTearDown(node.dispose);
        await pumpChip(
          tester,
          onPressed: () {},
          focusNode: node,
          showFocusAlways: always,
        );
        node.requestFocus();
        await tester.pumpAndSettle();
        expect(node.hasFocus, isTrue);
        // `border.focused` is green; `default` is black.
        expect(
          shown(tester),
          always ? const Color(0xFF00FF00) : const Color(0xFF000000),
          reason: 'showFocusAlways: $always',
        );
        node.unfocus();
        await tester.pumpAndSettle();
        expect(shown(tester), const Color(0xFF000000));
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a disabled chip ignores taps and keys', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpChip(tester, focusNode: node);
      await tester.tap(find.byKey(const Key('box')));
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });

    testWidgets('animates over the transition', (tester) async {
      await pumpChip(tester, onPressed: () {});
      await tester.pumpAndSettle();
      await pumpChip(tester, onPressed: () {}, selected: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = shown(tester);
      expect(mid, isNot(const Color(0xFF000000)));
      expect(mid, isNot(const Color(0xFFFFFF00)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(shown(tester), const Color(0xFFFFFF00));
    });

    testWidgets('no animation with disableAnimations', (tester) async {
      await pumpChip(tester, onPressed: () {}, reduce: true);
      await pumpChip(tester, onPressed: () {}, selected: true, reduce: true);
      await tester.pump();
      expect(shown(tester), const Color(0xFFFFFF00));
    });
  });
}
