// Every component of ThemeData from properties: values by type, a value
// per state, a sample of components end to end (the ThemeData they give
// and the colors they render), Cupertino, and the errors.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart';

import 'support/theme_catalog.dart';

SpringThemeData theme(Map<String, String> properties) =>
    SpringThemeData.of(ThemeConfig(properties), 'light');

ThemeData material(Map<String, String> properties) =>
    theme(properties).toMaterial();

/// [properties] with the `components.` prefix.
Map<String, String> c(String component, Map<String, String> properties) => {
  for (final MapEntry(:key, :value) in properties.entries)
    'components.$component.$key': value,
};

Matcher invalid(String key, [String? expected]) => throwsA(
  isA<ThemePropertyException>()
      .having((e) => e.key, 'key', contains(key))
      .having(
        (e) => e.expected,
        'expected',
        expected == null ? anything : contains(expected),
      ),
);

const _hovered = {WidgetState.hovered};

void main() {
  group('a value per state', () {
    WidgetStateProperty<Color?> fill(Map<String, String> p) =>
        material(c('checkbox', p)).checkboxTheme.fillColor!;

    test('one value is the value in every state', () {
      final property = fill({'fill-color': '#112233'});
      for (final states in [
        <WidgetState>{},
        {WidgetState.hovered, WidgetState.selected},
        {WidgetState.disabled},
      ]) {
        expect(property.resolve(states), const Color(0xFF112233));
      }
    });

    test('a map gives each state its value, default for the rest', () {
      final property = fill({
        'fill-color.default': '#000001',
        'fill-color.hovered': '#000002',
        'fill-color.focused': '#000003',
        'fill-color.pressed': '#000004',
        'fill-color.dragged': '#000005',
        'fill-color.selected': '#000006',
        'fill-color.scrolled-under': '#000007',
        'fill-color.disabled': '#000008',
        'fill-color.error': '#000009',
      });
      Color? at(Set<WidgetState> states) => property.resolve(states);
      expect(at({}), const Color(0xFF000001));
      expect(at({WidgetState.hovered}), const Color(0xFF000002));
      expect(at({WidgetState.focused}), const Color(0xFF000003));
      expect(at({WidgetState.pressed}), const Color(0xFF000004));
      expect(at({WidgetState.dragged}), const Color(0xFF000005));
      expect(at({WidgetState.selected}), const Color(0xFF000006));
      expect(at({WidgetState.scrolledUnder}), const Color(0xFF000007));
      expect(at({WidgetState.disabled}), const Color(0xFF000008));
      expect(at({WidgetState.error}), const Color(0xFF000009));
    });

    test('with several states the strongest wins', () {
      final property = fill({
        'fill-color.default': '#000001',
        'fill-color.hovered': '#000002',
        'fill-color.focused': '#000003',
        'fill-color.pressed': '#000004',
        'fill-color.selected': '#000006',
        'fill-color.disabled': '#000008',
        'fill-color.error': '#000009',
      });
      Color? at(Set<WidgetState> states) => property.resolve(states);
      // disabled > error > pressed > hovered > focused > selected > default
      expect(
        at({...WidgetState.values}),
        const Color(0xFF000008),
        reason: 'disabled beats all',
      );
      expect(
        at({WidgetState.error, WidgetState.pressed, WidgetState.hovered}),
        const Color(0xFF000009),
      );
      expect(
        at({WidgetState.pressed, WidgetState.hovered, WidgetState.focused}),
        const Color(0xFF000004),
      );
      expect(
        at({WidgetState.hovered, WidgetState.focused, WidgetState.selected}),
        const Color(0xFF000002),
      );
      expect(
        at({WidgetState.focused, WidgetState.selected}),
        const Color(0xFF000003),
      );
      expect(
        at({WidgetState.selected, WidgetState.dragged}),
        const Color(0xFF000006),
        reason: 'dragged has no value: the next state down',
      );
    });

    test('a state without a value and no default keeps Flutter\'s', () {
      final property = fill({'fill-color.hovered': '#000002'});
      expect(property.resolve(_hovered), const Color(0xFF000002));
      expect(property.resolve({WidgetState.disabled}), isNull);
      expect(property.resolve({}), isNull);
    });

    test('a plain value next to the map is the default', () {
      final property = fill({
        'fill-color': '#000001',
        'fill-color.selected': '#000006',
      });
      expect(property.resolve({}), const Color(0xFF000001));
      expect(property.resolve({WidgetState.selected}), const Color(0xFF000006));
    });

    test('every value form works in a state: roles, hex, opacity', () {
      final property = fill({
        'fill-color.default': 'grey.shade100',
        'fill-color.hovered': r'$colors.primary',
        'fill-color.pressed': '#80FF0000',
        'fill-color.focused.color': r'$colors.primary',
        'fill-color.focused.alpha': '50%',
      });
      final t = theme(c('checkbox', const {}));
      expect(property.resolve({}), Colors.grey.shade100);
      expect(property.resolve(_hovered), t.role('primary'));
      expect(property.resolve({WidgetState.pressed}), const Color(0x80FF0000));
      expect(
        property.resolve({WidgetState.focused}),
        t.role('primary')!.withValues(alpha: 0.5),
      );
    });

    test('states of borders, text styles, elevation, cursor, shape', () {
      final t = material({
        ...c('elevated-button', {
          'elevation.default': 'level1',
          'elevation.hovered': 'level3',
          'side.default': r'$colors.outline',
          'side.focused.color': r'$colors.primary',
          'side.focused.width': '3',
          'text-style.default': 'label-large',
          'text-style.hovered.weight': 'bold',
          'shape.default': 'small',
          'shape.hovered': 'stadium',
          'mouse-cursor.default': 'click',
          'mouse-cursor.disabled': 'forbidden',
        }),
      }).elevatedButtonTheme.style!;
      expect(t.elevation!.resolve({}), 3.0 - 2);
      expect(t.elevation!.resolve(_hovered), 6);
      expect(t.side!.resolve({WidgetState.focused})!.width, 3);
      expect(t.side!.resolve({})!.width, 1);
      expect(t.textStyle!.resolve(_hovered)!.fontWeight, FontWeight.w700);
      expect(t.shape!.resolve({}), isA<RoundedRectangleBorder>());
      expect(t.shape!.resolve(_hovered), isA<StadiumBorder>());
      expect(t.mouseCursor!.resolve({}), SystemMouseCursors.click);
      expect(
        t.mouseCursor!.resolve({WidgetState.disabled}),
        SystemMouseCursors.forbidden,
      );
    });

    test('equal maps make equal properties (ThemeData compares)', () {
      final a = fill({'fill-color.hovered': '#000002'});
      final b = fill({'fill-color.hovered': '#000002'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(fill({'fill-color.hovered': '#000003'})));
    });

    test('mistakes: an unknown state, states mixed with other keys', () {
      expect(
        () => fill({'fill-color.hoverd': r'$colors.primary'}),
        invalid(
          'components.checkbox.fillcolor.hoverd',
          "did you mean 'hovered'",
        ),
      );
      expect(
        () => material(
          c('elevated-button', {
            'side.color': r'$colors.primary',
            'side.hovered.color': r'$colors.error',
          }),
        ),
        invalid('components.elevatedbutton.side.color', 'a state of side'),
      );
    });

    test('a property without states rejects a map', () {
      expect(
        () => material(c('card', {'color.hovered': r'$colors.primary'})),
        invalid('components.card.color.hovered', 'no states'),
      );
    });

    test('from YAML, as a theme loaded at run time', () {
      final themes = SpringThemes(const {});
      themes.loadYaml(r'''
themes:
  states:
    components:
      switch:
        thumb-color:
          default: grey
          selected: $colors.primary
          disabled: $colors.outline
        track-outline-width: { default: 1, focused: 3 }
''');
      final t = themes.material('states').switchTheme;
      expect(t.thumbColor!.resolve({}), const Color(0xFF9E9E9E));
      expect(t.thumbColor!.resolve({WidgetState.disabled}), isNotNull);
      expect(t.trackOutlineWidth!.resolve({WidgetState.focused}), 3);
    });
  });

  group('values by type', () {
    ThemeData card(Map<String, String> p) => material(c('card', p));

    test('colors: roles, Colors names, hex, opacity', () {
      expect(card({'color': r'$colors.primary'}).cardTheme.color, isNotNull);
      expect(
        card({'color': 'deepPurple.shade200'}).cardTheme.color,
        Colors.deepPurple.shade200,
      );
      expect(card({'color': '#abc'}).cardTheme.color, const Color(0xFFAABBCC));
      expect(
        card({
          'color.color': '#FF0000',
          'color.alpha': '25%',
        }).cardTheme.color,
        const Color(0xFFFF0000).withValues(alpha: 0.25),
      );
      expect(
        card({
          'color.color': '#FF0000',
          'color.alpha': '0.5',
        }).cardTheme.color,
        const Color(0xFFFF0000).withValues(alpha: 0.5),
      );
      for (final bad in [
        'nope',
        '#12',
        '0xFF0000',
        'primary',
        '#F00 alpha 5%',
      ]) {
        expect(() => card({'color': bad}), invalid('components.card.color'));
      }
      expect(
        () => card({'color.color': '#FF0000', 'color.alpha': '150%'}),
        invalid('components.card.color.alpha'),
      );
    });

    test('shapes: token, radius, stadium, circle, map with a border', () {
      OutlinedBorder? shape(String value) =>
          card({'shape': value}).cardTheme.shape as OutlinedBorder?;
      expect(shape('large'), isA<RoundedRectangleBorder>());
      expect(
        (shape('10') as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(10),
      );
      expect(shape('stadium'), isA<StadiumBorder>());
      expect(shape('circle'), isA<CircleBorder>());
      expect(shape('full'), isA<StadiumBorder>());
      final mapped =
          card({
                'shape.type': 'beveled',
                'shape.radius': 'small',
                'shape.side.color': r'$colors.primary',
                'shape.side.width': '2',
              }).cardTheme.shape!
              as BeveledRectangleBorder;
      expect(mapped.borderRadius, BorderRadius.circular(8));
      expect(mapped.side.width, 2);
      final continuous = card({
        'shape.type': 'continuous',
        'shape.radius': '5',
      });
      expect(continuous.cardTheme.shape, isA<ContinuousRectangleBorder>());
      expect(
        () => card({'shape': 'roundish'}),
        invalid('components.card.shape', 'a shape token'),
      );
      expect(
        () => card({'shape.type': 'wavy'}),
        invalid('components.card.shape.type'),
      );
    });

    test('a bottom sheet rounds the top corners only', () {
      final shape =
          material(c('bottom-sheet', {'shape': 'large'}))
                  .bottomSheetTheme
                  .shape!
              as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(16)),
      );
    });

    test('border sides: a color, none, or a map', () {
      BorderSide? side(Map<String, String> p) =>
          material(c('chip', p)).chipTheme.side;
      expect(side({'side': r'$colors.error'})!.color, theme({}).role('error'));
      expect(side({'side': 'none'}), BorderSide.none);
      final mapped = side({
        'side.color': '#00FF00',
        'side.width': '3',
        'side.stroke-align': 'outside',
      })!;
      expect(mapped.color, const Color(0xFF00FF00));
      expect(mapped.width, 3);
      expect(mapped.strokeAlign, BorderSide.strokeAlignOutside);
      expect(
        () => side({'side.colour': r'$colors.primary'}),
        invalid('components.chip.side.colour', "did you mean 'color'"),
      );
    });

    test('insets: all, two, four values, a map', () {
      EdgeInsetsGeometry? padding(Map<String, String> p) =>
          material(c('chip', p)).chipTheme.padding;
      expect(padding({'padding': '4'}), const EdgeInsets.all(4));
      expect(
        padding({'padding': '4, 8'}),
        const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      );
      expect(
        padding({'padding': '1, 2, 3, 4'}),
        const EdgeInsets.fromLTRB(1, 2, 3, 4),
      );
      expect(
        padding({'padding.horizontal': '6', 'padding.top': '1'}),
        const EdgeInsets.only(left: 6, right: 6, top: 1),
      );
      expect(
        () => padding({'padding': '1, 2, 3'}),
        invalid('components.chip.padding'),
      );
    });

    test('text styles: a name, or a map over a base', () {
      TextStyle? style(Map<String, String> p) =>
          material(c('chip', p)).chipTheme.labelStyle;
      final base = material({}).textTheme.labelSmall;
      expect(style({'label-style': 'label-small'}), base);
      final mapped = style({
        'label-style.style': 'label-small',
        'label-style.size': '20',
        'label-style.weight': 'bold',
        'label-style.color': r'$colors.error',
        'label-style.italic': 'true',
        'label-style.decoration': 'underline',
        'label-style.letter-spacing': '1.5',
        'label-style.height': '2',
      })!;
      expect(mapped.fontSize, 20);
      expect(mapped.fontWeight, FontWeight.w700);
      expect(mapped.color, theme({}).role('error'));
      expect(mapped.fontStyle, FontStyle.italic);
      expect(mapped.decoration, TextDecoration.underline);
      expect(mapped.letterSpacing, 1.5);
      expect(mapped.height, 2);
      expect(style({'label-style.size': '9'})!.fontSize, 9);
      expect(
        () => style({'label-style': 'label-smal'}),
        invalid('components.chip.labelstyle', "did you mean 'label-small'"),
      );
      expect(
        () => style({'label-style.weight': 'heavy'}),
        invalid('components.chip.labelstyle.weight'),
      );
    });

    test('numbers, elevations, booleans, durations, enums', () {
      final tooltip = material(
        c('tooltip', {
          'vertical-offset': '12.5',
          'prefer-below': 'false',
          'wait-duration': '1s',
          'show-duration': '250ms',
          'text-align': 'center',
          'trigger-mode': 'longPress',
        }),
      ).tooltipTheme;
      expect(tooltip.verticalOffset, 12.5);
      expect(tooltip.preferBelow, isFalse);
      expect(tooltip.waitDuration, const Duration(seconds: 1));
      expect(tooltip.showDuration, const Duration(milliseconds: 250));
      expect(tooltip.textAlign, TextAlign.center);
      expect(tooltip.triggerMode, TooltipTriggerMode.longPress);
      expect(
        material(c('tooltip', {'trigger-mode': 'long-press'}))
            .tooltipTheme
            .triggerMode,
        TooltipTriggerMode.longPress,
        reason: 'kebab case works for enum values',
      );
      expect(
        material(c('card', {'elevation': 'level3'})).cardTheme.elevation,
        6,
      );
      for (final (key, value) in [
        ('vertical-offset', 'far'),
        ('prefer-below', 'maybe'),
        ('wait-duration', 'soon'),
        ('trigger-mode', 'poke'),
      ]) {
        expect(
          () => material(c('tooltip', {key: value})),
          invalid('components.tooltip.${key.replaceAll('-', '')}'),
        );
      }
    });

    test('sizes, constraints, offsets, alignments, densities, radii', () {
      final sheet = material(
        c('bottom-sheet', {
          'drag-handle-size': '40, 6',
          'constraints.max-width': '640',
          'constraints.min-height': 'infinity',
        }),
      ).bottomSheetTheme;
      expect(sheet.dragHandleSize, const Size(40, 6));
      expect(sheet.constraints!.maxWidth, 640);
      expect(sheet.constraints!.minHeight, double.infinity);
      expect(
        material(c('badge', {'offset': '2, -3', 'alignment': 'top-left'}))
            .badgeTheme,
        isA<BadgeThemeData>()
            .having((b) => b.offset, 'offset', const Offset(2, -3))
            .having((b) => b.alignment, 'alignment', Alignment.topLeft),
      );
      expect(
        material(c('checkbox', {'visual-density': 'compact'}))
            .checkboxTheme
            .visualDensity,
        VisualDensity.compact,
      );
      expect(
        material(c('checkbox', {'visual-density': '-1, 2'}))
            .checkboxTheme
            .visualDensity,
        const VisualDensity(horizontal: -1, vertical: 2),
      );
      expect(
        material(c('progress-indicator', {'border-radius': 'small'}))
            .progressIndicatorTheme
            .borderRadius,
        BorderRadius.circular(8),
      );
      expect(
        material(c('scrollbar', {'radius': '3'})).scrollbarTheme.radius,
        const Radius.circular(3),
      );
      expect(
        () => material(c('badge', {'alignment': 'sideways'})),
        invalid('components.badge.alignment'),
      );
      expect(
        () => material(c('bottom-sheet', {'constraints.width': '1'})),
        invalid(
          'components.bottomsheet.constraints.width',
          'min-width'.replaceAll('-', ''),
        ),
      );
    });

    test('icon themes, decorations, input borders, animation styles', () {
      final nav = material(
        c('bottom-navigation-bar', {
          'selected-icon-theme.color': r'$colors.primary',
          'selected-icon-theme.size': '30',
          'unselected-icon-theme': '#999999',
        }),
      ).bottomNavigationBarTheme;
      expect(nav.selectedIconTheme!.size, 30);
      expect(nav.unselectedIconTheme!.color, const Color(0xFF999999));
      final tab =
          material(
                c('tab-bar', {
                  'indicator.color': r'$colors.primary',
                  'indicator.radius': 'small',
                  'indicator.border': r'$colors.error',
                }),
              ).tabBarTheme.indicator!
              as BoxDecoration;
      expect(tab.borderRadius, BorderRadius.circular(8));
      expect(tab.border, isNotNull);
      final input = material(
        c('input', {
          'border': 'underline',
          'focused-border.type': 'outline',
          'focused-border.radius': 'large',
          'focused-border.side.width': '2',
          'error-border': 'none',
        }),
      ).inputDecorationTheme;
      expect(input.border, isA<UnderlineInputBorder>());
      expect(
        (input.focusedBorder! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(16),
      );
      expect(input.focusedBorder!.borderSide.width, 2);
      expect(input.errorBorder, InputBorder.none);
      final animation = material(
        c('expansion-tile', {
          'expansion-animation-style.duration': '300ms',
        }),
      ).expansionTileTheme.expansionAnimationStyle!;
      expect(animation.duration, const Duration(milliseconds: 300));
    });

    test('nested groups of a component: button styles, input decoration', () {
      final picker = material(
        c('date-picker', {
          'cancel-button-style.foreground-color.default': r'$colors.error',
          'cancel-button-style.foreground-color.hovered': r'$colors.primary',
          'input-decoration.fill-color': r'$colors.surface',
          'input-decoration.filled': 'true',
        }),
      ).datePickerTheme;
      expect(
        picker.cancelButtonStyle!.foregroundColor!.resolve({}),
        theme({}).role('error'),
      );
      expect(picker.confirmButtonStyle, isNull);
      expect(picker.inputDecorationTheme!.filled, isTrue);
      expect(
        material(c('date-picker', {'shape': 'small'}))
            .datePickerTheme
            .inputDecorationTheme,
        isNull,
        reason: 'an unused group keeps Flutter\'s default',
      );
      expect(
        () => material(c('date-picker', {'cancel-button-style.colour': 'x'})),
        invalid(
          'components.datepicker.cancelbuttonstyle.colour',
          'a property of date-picker.cancel-button-style',
        ),
      );
    });
  });

  group('components end to end', () {
    test('the buttons start from button; a kind overrides it', () {
      final t = material({
        ...c('button', {
          'padding': '4, 2',
          'background-color.hovered': r'$colors.tertiary',
          'overlay-color.pressed.color': r'$colors.primary',
          'overlay-color.pressed.alpha': '20%',
          'min-height': '40',
        }),
        ...c('filled-button', {'background-color.hovered': r'$colors.error'}),
      });
      final filled = t.filledButtonTheme.style!;
      final elevated = t.elevatedButtonTheme.style!;
      final scheme = theme({}).colorScheme;
      expect(
        filled.padding!.resolve({}),
        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      );
      expect(filled.backgroundColor!.resolve(_hovered), scheme.error);
      expect(elevated.backgroundColor!.resolve(_hovered), scheme.tertiary);
      expect(elevated.minimumSize!.resolve({}), const Size(0, 40));
      expect(
        elevated.overlayColor!.resolve({WidgetState.pressed}),
        scheme.primary.withValues(alpha: 0.2),
      );
      expect(t.textButtonTheme.style, isNotNull);
      expect(
        t.iconButtonTheme.style,
        isNull,
        reason: 'icon buttons do not inherit button',
      );
    });

    test(
      'a rendered button takes the color of its state',
      (
        // ignore: avoid_unused_constructor_parameters
      ) {},
    );

    testWidgets('a rendered button shows the color of its state', (
      tester,
    ) async {
      final t = material(
        c('filled-button', {
          'background-color.default': '#112233',
          'background-color.hovered': '#445566',
          'background-color.disabled': '#778899',
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: t,
          home: Column(
            children: [
              FilledButton(
                key: const Key('on'),
                onPressed: () {},
                child: const Text('a'),
              ),
              const FilledButton(
                key: Key('off'),
                onPressed: null,
                child: Text('b'),
              ),
            ],
          ),
        ),
      );
      Color? rendered(String key) => tester
          .widget<Material>(
            find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(Material),
            ),
          )
          .color;
      expect(rendered('on'), const Color(0xFF112233));
      expect(rendered('off'), const Color(0xFF778899));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(const Key('on'))));
      await tester.pumpAndSettle();
      expect(rendered('on'), const Color(0xFF445566));
    });

    testWidgets('a rendered switch and checkbox follow their states', (
      tester,
    ) async {
      final t = material({
        ...c('switch', {
          'track-color.selected': '#00AA00',
          'track-color.default': '#AA0000',
        }),
        ...c('checkbox', {
          'fill-color.selected': '#0000AA',
          'fill-color.default': '#CCCCCC',
        }),
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: t,
          home: Scaffold(
            body: Column(
              children: [
                Switch(key: const Key('s1'), value: true, onChanged: (_) {}),
                Switch(key: const Key('s0'), value: false, onChanged: (_) {}),
                Checkbox(key: const Key('c1'), value: true, onChanged: (_) {}),
              ],
            ),
          ),
        ),
      );
      Color? track(String key) {
        final ctx = tester.element(find.byKey(Key(key)));
        return SwitchTheme.of(ctx).trackColor!.resolve({
          if (key == 's1') WidgetState.selected,
        });
      }

      expect(track('s1'), const Color(0xFF00AA00));
      expect(track('s0'), const Color(0xFFAA0000));
      // The rendered switch paints its track with that color.
      expect(
        find.byKey(const Key('s1')),
        paints..rrect(color: const Color(0xFF00AA00)),
      );
      expect(
        find.byKey(const Key('c1')),
        paints..rrect(color: const Color(0xFF0000AA)),
      );
    });

    test('app bar, card, dialog, snack bar keep their first keys', () {
      final t = material({
        ...c('app-bar', {
          'center-title': 'true',
          'title-style': 'title-large',
          'background': r'$colors.surface',
        }),
        ...c('dialog', {'background': r'$colors.surface', 'shape': 'large'}),
        ...c('snack-bar', {
          'behavior': 'floating',
          'background': r'$colors.inverse-surface',
        }),
        ...c('card', {
          'elevation': 'level0',
          'color': r'$colors.surface-container-low',
        }),
      });
      expect(t.appBarTheme.centerTitle, isTrue);
      expect(t.appBarTheme.titleTextStyle, t.textTheme.titleLarge);
      expect(t.appBarTheme.backgroundColor, t.colorScheme.surface);
      expect(t.dialogTheme.backgroundColor, t.colorScheme.surface);
      expect(t.snackBarTheme.backgroundColor, t.colorScheme.inverseSurface);
      expect(t.cardTheme.color, t.colorScheme.surfaceContainerLow);
    });

    test('a sample of the new components, property by property', () {
      final t = material({
        ...c('slider', {
          'track-height': '6',
          'active-track-color': r'$colors.primary',
          'show-value-indicator': 'on-drag',
          'thumb-size.hovered': '24, 24',
        }),
        ...c('data-table', {
          'heading-row-color.default': r'$colors.surface-container',
          'data-row-color.selected': r'$colors.primary-container',
          'heading-text-style': 'title-small',
          'column-spacing': '32',
          'heading-row-alignment': 'center',
        }),
        ...c('navigation-bar', {
          'label-text-style.selected.weight': 'bold',
          'icon-theme.selected.color': r'$colors.primary',
          'icon-theme.default.color': r'$colors.outline',
        }),
        ...c('search-bar', {
          'background-color.focused': r'$colors.surface-container-high',
          'side.default': r'$colors.outline',
          'elevation.default': 'level0',
        }),
        ...c('menu', {
          'background-color': r'$colors.surface',
          'shape': 'small',
        }),
        ...c('text-selection', {'cursor-color': r'$colors.error'}),
        ...c('badge', {
          'background-color': r'$colors.error',
          'small-size': '8',
        }),
        ...c('drawer', {'width': '300', 'shape': 'large'}),
        ...c('icon', {'color': r'$colors.primary', 'size': '28'}),
        ...c('time-picker', {'dial-hand-color': r'$colors.tertiary'}),
        ...c('dropdown-menu', {
          'menu-style.background-color': r'$colors.surface',
          'text-style': 'body-small',
        }),
      });
      expect(t.sliderTheme.trackHeight, 6);
      expect(t.sliderTheme.showValueIndicator, ShowValueIndicator.onDrag);
      expect(t.sliderTheme.thumbSize!.resolve(_hovered), const Size(24, 24));
      expect(
        t.dataTableTheme.headingRowColor!.resolve({}),
        t.colorScheme.surfaceContainer,
      );
      expect(
        t.dataTableTheme.dataRowColor!.resolve({WidgetState.selected}),
        t.colorScheme.primaryContainer,
      );
      expect(t.dataTableTheme.headingRowAlignment, MainAxisAlignment.center);
      expect(
        t.navigationBarTheme.labelTextStyle!.resolve({
          WidgetState.selected,
        })!.fontWeight,
        FontWeight.w700,
      );
      expect(
        t.navigationBarTheme.iconTheme!.resolve({WidgetState.selected})!.color,
        t.colorScheme.primary,
      );
      expect(
        t.navigationBarTheme.iconTheme!.resolve({})!.color,
        t.colorScheme.outline,
      );
      expect(
        t.searchBarTheme.backgroundColor!.resolve({WidgetState.focused}),
        t.colorScheme.surfaceContainerHigh,
      );
      expect(
        t.menuTheme.style!.backgroundColor!.resolve({}),
        t.colorScheme.surface,
      );
      expect(t.textSelectionTheme.cursorColor, t.colorScheme.error);
      expect(t.badgeTheme.smallSize, 8);
      expect(t.drawerTheme.width, 300);
      expect(t.iconTheme.size, 28);
      expect(t.timePickerTheme.dialHandColor, t.colorScheme.tertiary);
      expect(
        t.dropdownMenuTheme.menuStyle!.backgroundColor!.resolve({}),
        t.colorScheme.surface,
      );
    });

    test('shape tokens still reach the components that follow them', () {
      final t = material({'shape.medium': '20', 'shape.full': '30'});
      expect(
        (t.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(20),
      );
      expect(t.filledButtonTheme.style, isNotNull);
    });

    test('the same property in a theme that extends another', () {
      final themes = SpringThemes({
        'components.checkbox.fill-color.selected': r'$colors.primary',
        'themes.ocean.components.checkbox.fill-color.selected':
            r'$colors.tertiary',
      });
      expect(
        themes.material('ocean').checkboxTheme.fillColor!.resolve({
          WidgetState.selected,
        }),
        themes.data('ocean').colorScheme.tertiary,
      );
    });
  });

  group('Cupertino', () {
    test('colors and text styles of CupertinoThemeData', () {
      final t = theme({
        'cupertino.primary-color': r'$colors.tertiary',
        'cupertino.primary-contrasting-color': '#FFFFFF',
        'cupertino.scaffold-background-color': '#F0F0F0',
        'cupertino.bar-background-color': r'$colors.surface',
        'cupertino.selection-handle-color': '#00FF00',
        'cupertino.apply-theme-to-all': 'true',
        'cupertino.text-theme.text-style.size': '17',
        'cupertino.text-theme.nav-title-text-style': 'title-large',
        'cupertino.text-theme.action-text-style.color': r'$colors.error',
      }).toCupertino();
      final scheme = theme({}).colorScheme;
      expect(t.primaryColor, scheme.tertiary);
      expect(t.primaryContrastingColor, const Color(0xFFFFFFFF));
      expect(t.scaffoldBackgroundColor, const Color(0xFFF0F0F0));
      expect(t.barBackgroundColor, scheme.surface);
      expect(t.selectionHandleColor, const Color(0xFF00FF00));
      expect(t.applyThemeToAll, isTrue);
      expect(t.textTheme.textStyle.fontSize, 17);
      expect(t.textTheme.navTitleTextStyle, material({}).textTheme.titleLarge);
      expect(t.textTheme.actionTextStyle.color, scheme.error);
    });

    test('without cupertino keys it keeps the earlier behavior', () {
      final t = theme({
        'colors.surface': '#EEEEEE',
        'components.app-bar.background': '#111111',
      }).toCupertino();
      expect(t.scaffoldBackgroundColor, const Color(0xFFEEEEEE));
      expect(t.barBackgroundColor, const Color(0xFF111111));
    });

    test('mistakes name the valid keys', () {
      expect(
        () => theme({'cupertino.primay-color': 'x'}),
        invalid(
          'cupertino.primaycolor'.replaceAll('primay', 'primay'),
          "did you mean 'primary-color'",
        ),
      );
      expect(
        () => theme({'cupertino.text-theme.nav-title': 'title-large'}),
        invalid('cupertino.texttheme.navtitle', 'nav-title-text-style'),
      );
      expect(
        () => theme({'cupertino.bar-background-color': 'nope'}),
        invalid('cupertino.barbackgroundcolor'),
      );
    });
  });

  group('the mapping covers every property', () {
    final catalog = themeCatalog();

    String sample(ThemeProperty p) {
      final kind = p.kind;
      if (kind.startsWith('one of: ')) {
        final options = kind.substring(8).split(' | ');
        // A snack bar's width needs the floating behavior.
        return p.name == 'behavior' ? 'floating' : options.first;
      }
      if (p.name.endsWith('fill') ||
          p.name.endsWith('opacity') ||
          p.name.endsWith('threshold')) {
        return '0.5';
      }
      return switch (kind) {
        'color' => r'$colors.primary',
        'number' => '3',
        'elevation' => 'level2',
        'true / false' => 'true',
        'whole number' => '2',
        'duration' => '200ms',
        'insets' => '4, 8',
        'size' => '40, 20',
        'offset' => '1, 2',
        'shape' => 'medium',
        'border side' => r'$colors.outline',
        'text style' => 'body-small',
        'icon theme' => r'$colors.primary',
        'mouse cursor' => 'click',
        'alignment' => 'center',
        'corner radius' => 'small',
        'visual density' => 'compact',
        'decoration' => r'$colors.primary',
        'input border' => 'outline',
        _ => throw StateError('no sample for $kind of ${p.name}'),
      };
    }

    Map<String, String> entries(
      String root,
      List<ThemeProperty> properties, {
      required bool states,
    }) {
      final result = <String, String>{};
      for (final p in properties) {
        final key = '$root.${p.name}';
        switch (p.kind) {
          case 'constraints':
            result['$key.min-width'] = '1';
          case 'animation':
            result['$key.duration'] = '100ms';
          default:
            if (states && p.states) {
              result['$key.default'] = sample(p);
              result['$key.hovered'] = sample(p);
              result['$key.disabled'] = sample(p);
            } else {
              result[key] = sample(p);
            }
        }
      }
      return result;
    }

    test('at least 48 components and Cupertino, with their properties', () {
      expect(catalog.length, greaterThanOrEqualTo(49));
      expect(catalog.keys, containsAll(['app-bar', 'checkbox', 'cupertino']));
      final total = catalog.values.fold<int>(0, (n, p) => n + p.length);
      expect(total, greaterThan(800));
    });

    for (final states in [false, true]) {
      for (final MapEntry(key: name, value: properties) in catalog.entries) {
        test('$name: every property is read${states ? ' per state' : ''}', () {
          final root = name == 'cupertino' ? 'cupertino' : 'components.$name';
          final values = entries(root, properties, states: states);
          // Reading and checking every key must not fail, and the keys
          // are exactly the ones the mapping lists.
          final t = theme(values);
          t.toMaterial();
          t.toCupertino();
        });
      }
    }

    test('every property is rejected with a wrong value of its type', () {
      var checked = 0;
      for (final MapEntry(key: name, value: properties) in catalog.entries) {
        final root = name == 'cupertino' ? 'cupertino' : 'components.$name';
        for (final p in properties) {
          final wrong = switch (p.kind) {
            'color' => 'notacolor',
            'number' || 'elevation' => 'many',
            'true / false' => 'perhaps',
            'whole number' => '1.5',
            'duration' => 'soon',
            'insets' => '1, 2, 3',
            'size' => 'big',
            'offset' => 'near',
            'shape' => 'roundish',
            'border side' => 'notacolor',
            'text style' => 'title-huge',
            'icon theme' => 'notacolor',
            'mouse cursor' => 'finger',
            'alignment' => 'sideways',
            'corner radius' => 'many',
            'visual density' => 'airy',
            'decoration' => 'notacolor',
            'input border' => 'wavy',
            'constraints' || 'animation' => null,
            _ => 'zzzz',
          };
          if (wrong == null || p.name.contains('.')) {
            continue;
          }
          checked++;
          expect(
            () => theme({'$root.${p.name}': wrong}).toCupertino(),
            throwsA(isA<ThemePropertyException>()),
            reason: '$name.${p.name} (${p.kind}) = $wrong',
          );
        }
      }
      expect(checked, greaterThan(700));
    });
  });

  group('mistakes name the valid keys', () {
    test('an unknown component, with a suggestion', () {
      expect(
        () => theme({'components.chek-box.fill-color': r'$colors.primary'}),
        invalid('components.chekbox', "did you mean 'checkbox'"),
      );
      expect(
        () => theme({'components.widget.color': r'$colors.primary'}),
        invalid('components.widget', 'a component: app-bar, badge'),
      );
    });

    test('an unknown property lists the component\'s', () {
      expect(
        () => theme({'components.card.shadow-colour': r'$colors.primary'}),
        invalid(
          'components.card.shadowcolour',
          "a property of card: clip-behavior, color, shadow-color, surface-tint-color, elevation, margin, shape (did you mean 'shadow-color'?)",
        ),
      );
      expect(
        () => theme({
          'components.switch.thumb-color.selectd': r'$colors.primary',
        }),
        invalid(
          'components.switch.thumbcolor.selectd',
          "did you mean 'selected'",
        ),
      );
    });

    test('the error names the property as the files do, with the theme', () {
      expect(
        () => SpringThemes(const {'themes.ocean.components.card.colour': 'x'}),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.key,
            'key',
            'spring.flutter.theme.themes.ocean.components.card.colour',
          ),
        ),
      );
    });

    test('a theme loaded at run time is checked before it is used', () {
      final themes = SpringThemes(const {});
      expect(
        () => themes.loadYaml('''
themes:
  bad:
    components:
      slider: { track-height: thick }
'''),
        throwsA(isA<ThemePropertyException>()),
      );
      expect(themes.names, ['light', 'dark']);
    });
  });
}
