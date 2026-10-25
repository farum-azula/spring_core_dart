// A theme read from properties: every color role, text style and
// component property, the Cupertino and Widgets forms, the accessors for
// the app's own widgets, and every kind of invalid value.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';

SpringThemeData theme(
  Map<String, String> properties, [
  String name = 'light',
]) => SpringThemeData.of(ThemeConfig(properties), name);

ThemeData material(Map<String, String> properties) =>
    theme(properties).toMaterial();

Matcher invalid(String key) => throwsA(
  isA<ThemePropertyException>().having((e) => e.key, 'key', contains(key)),
);

void main() {
  group('colors', () {
    test('every role can be set and read back', () {
      final properties = {
        for (final (i, role) in colorRoles.indexed)
          'colors.$role':
              '#${(0x101010 + i * 0x010203).toRadixString(16).padLeft(6, '0')}',
      };
      final t = theme(properties);
      final scheme = t.toMaterial().colorScheme;
      for (final (i, role) in colorRoles.indexed) {
        final expected = Color(0xFF000000 | (0x101010 + i * 0x010203));
        expect(t.role(role), expected, reason: role);
      }
      expect(
        scheme.surfaceContainerHighest,
        t.role('surface-container-highest'),
      );
      expect(t.role('unknown'), isNull);
    });

    test('every scheme variant and a contrast', () {
      for (final variant in DynamicSchemeVariant.values) {
        final scheme = theme({
          'scheme-variant': variant.name,
          'contrast': '0.5',
        }).colorScheme;
        expect(
          scheme.primary,
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            dynamicSchemeVariant: variant,
            contrastLevel: 0.5,
          ).primary,
          reason: variant.name,
        );
      }
    });

    test('dark: the seed\'s dark palette', () {
      final dark = theme({'seed-color': 'teal'}, 'dark');
      expect(dark.brightness, Brightness.dark);
      expect(
        dark.colorScheme.primary,
        ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ).primary,
      );
    });

    test('invalid values', () {
      expect(
        () => theme({'colors.primary': 'nope'}),
        invalid('colors.primary'),
      );
      expect(
        () => theme({'scheme-variant': 'rainbowish'}),
        invalid('schemevariant'),
      );
      expect(() => theme({'contrast': 'high'}), invalid('contrast'));
      expect(() => theme({'brightness': 'grey'}), invalid('brightness'));
    });
  });

  group('typography', () {
    test(
      'every TextTheme style: size, weight, height, letter spacing, family',
      () {
        final properties = {
          for (final style in textStyleNames) ...{
            'typography.$style.size': '${textStyleNames.indexOf(style) + 10}',
            'typography.$style.weight': 'medium',
            'typography.$style.height': '1.4',
            'typography.$style.letter-spacing': '0.3',
            'typography.$style.font-family': 'F$style',
          },
        };
        final t = theme(properties);
        final text = t.toMaterial().textTheme;
        for (final style in textStyleNames) {
          final s = t.textStyle(style);
          expect(s.fontSize, textStyleNames.indexOf(style) + 10, reason: style);
          expect(s.fontWeight, FontWeight.w500, reason: style);
          expect(s.height, 1.4, reason: style);
          expect(s.letterSpacing, 0.3, reason: style);
          expect(s.fontFamily, 'F$style', reason: style);
        }
        expect(text.labelSmall!.fontSize, 24);
      },
    );

    test('defaults, then a group, then a single style', () {
      final t = theme({
        'typography.defaults.weight': '300',
        'typography.defaults.letter-spacing': '0.1',
        'typography.title.weight': '500',
        'typography.title-large.weight': '700',
      });
      expect(t.textStyle('bodyMedium').fontWeight, FontWeight.w300);
      expect(t.textStyle('titleSmall').fontWeight, FontWeight.w500);
      expect(t.textStyle('titleLarge').fontWeight, FontWeight.w700);
      expect(t.textStyle('titleLarge').letterSpacing, 0.1);
    });

    test('code: monospace by default, the theme\'s fonts as fallback', () {
      final t = theme({
        'typography.font-family': 'Inter',
        'typography.font-family-fallback': 'Noto Sans JP',
      });
      final code = t.textStyle('code');
      expect(code.fontFamily, 'monospace');
      expect(code.fontSize, 14);
      expect(code.fontFamilyFallback, ['Inter', 'Noto Sans JP']);
      expect(t.fontFamilies, {'Inter', 'Noto Sans JP', 'monospace'});
      expect(() => t.textStyle('huge'), throwsArgumentError);
    });

    test('invalid values', () {
      expect(
        () => theme({'typography.body.size': 'big'}),
        invalid('typography.body.size'),
      );
      expect(
        () => theme({'typography.body.weight': '450'}),
        invalid('typography.body.weight'),
      );
      expect(
        () => theme({'typography.body.height': 'x'}),
        invalid('typography.body.height'),
      );
      expect(
        () => theme({'typography.code.letter-spacing': 'x'}),
        invalid('letterspacing'),
      );
    });
  });

  group('shapes, elevations, spacing, motion', () {
    test('the scale, the levels, spacing: defaults and set values', () {
      final t = theme({
        'shape.medium': '20',
        'elevation.level2': '4',
        'spacing.m': '18',
        'spacing.xxl': '64',
      });
      expect(t.shape('medium'), 20);
      expect(t.shape('extra-large'), 28);
      expect(t.shape('full'), double.infinity);
      expect(t.elevation('level2'), 4);
      expect(t.elevation('level5'), 12);
      expect(t.space('m'), 18);
      expect(t.space('xs'), 4);
      expect(t.space('xxl'), 64);
      expect(() => t.shape('huge'), throwsArgumentError);
      expect(() => t.elevation('level9'), throwsArgumentError);
      expect(() => t.space('xxxl'), throwsArgumentError);
    });

    test('motion: durations and curves, defaults and set', () {
      final defaults = theme(const {});
      expect(defaults.duration('short'), const Duration(milliseconds: 100));
      expect(defaults.duration('medium'), const Duration(milliseconds: 250));
      expect(defaults.duration('long'), const Duration(milliseconds: 450));
      expect(defaults.curve('standard'), Easing.standard);
      final t = theme({
        'motion.duration-medium': '300ms',
        'motion.easing-emphasized': '0.3, 0, 0, 1',
      });
      expect(t.duration('medium'), const Duration(milliseconds: 300));
      expect((t.curve('emphasized') as Cubic).a, 0.3);
      expect(
        () => theme({'motion.duration-medium': 'slow'}),
        invalid('durationmedium'),
      );
      expect(
        () => theme({'motion.easing-standard': '1, 2'}),
        invalid('easingstandard'),
      );
    });

    test('invalid shape, elevation and spacing', () {
      expect(() => theme({'shape.huge': '40'}), invalid('shape.huge'));
      expect(() => theme({'shape.medium': 'round'}), invalid('shape.medium'));
      expect(
        () => theme({'elevation.level9': '40'}),
        invalid('elevation.level9'),
      );
      expect(
        () => theme({'elevation.level1': 'high'}),
        invalid('elevation.level1'),
      );
      expect(() => theme({'spacing.m': 'wide'}), invalid('spacing.m'));
    });
  });

  group('density, tap targets, splash, page transitions', () {
    test('every value', () {
      expect(
        material({'visual-density': 'adaptive'}).visualDensity,
        VisualDensity.adaptivePlatformDensity,
      );
      expect(
        material({'visual-density': 'standard'}).visualDensity,
        VisualDensity.standard,
      );
      expect(
        material({'visual-density': 'comfortable'}).visualDensity,
        VisualDensity.comfortable,
      );
      expect(
        material({'visual-density': 'compact'}).visualDensity,
        VisualDensity.compact,
      );
      expect(
        material({'tap-target-size': 'shrinkWrap'}).materialTapTargetSize,
        MaterialTapTargetSize.shrinkWrap,
      );
      expect(
        material({'tap-target-size': 'padded'}).materialTapTargetSize,
        MaterialTapTargetSize.padded,
      );
      expect(
        material({'splash': 'ripple'}).splashFactory,
        InkRipple.splashFactory,
      );
      expect(
        material({'splash': 'sparkle'}).splashFactory,
        InkSparkle.splashFactory,
      );
      expect(
        material({'splash': 'none'}).splashFactory,
        NoSplash.splashFactory,
      );
      Type transition(String value) =>
          material({'motion.page-transition': value})
              .pageTransitionsTheme
              .builders[TargetPlatform.android]
              .runtimeType;
      expect(transition('fadeUpwards'), FadeUpwardsPageTransitionsBuilder);
      expect(transition('zoom'), ZoomPageTransitionsBuilder);
      expect(transition('cupertino'), CupertinoPageTransitionsBuilder);
      expect(transition('none').toString(), '_NoTransition');
      // platform: Flutter's own per platform.
      expect(
        material({'motion.page-transition': 'platform'}).pageTransitionsTheme,
        ThemeData().pageTransitionsTheme,
      );
    });

    test('a page transition of platform is Flutter\'s own, as it is', () {
      final builder = theme({'motion.page-transition': 'platform'})
          .pageTransition!;
      const child = SizedBox();
      final route = MaterialPageRoute<void>(builder: (_) => child);
      expect(
        builder.buildTransitions(
          route,
          _FakeContext(),
          kAlwaysCompleteAnimation,
          kAlwaysDismissedAnimation,
          child,
        ),
        same(child),
      );
    });

    test('a page transition of none shows the page as it is', () {
      final builder = material({'motion.page-transition': 'none'})
          .pageTransitionsTheme
          .builders[TargetPlatform.iOS]!;
      const child = SizedBox();
      final route = MaterialPageRoute<void>(builder: (_) => child);
      expect(
        builder.buildTransitions(
          route,
          _FakeContext(),
          kAlwaysCompleteAnimation,
          kAlwaysDismissedAnimation,
          child,
        ),
        same(child),
      );
    });

    test('invalid values', () {
      expect(
        () => theme({'visual-density': 'tight'}),
        invalid('visualdensity'),
      );
      expect(() => theme({'tap-target-size': 'big'}), invalid('taptargetsize'));
      expect(() => theme({'splash': 'wave'}), invalid('splash'));
      expect(
        () => theme({'motion.page-transition': 'slide'}),
        invalid('pagetransition'),
      );
    });
  });

  group('components', () {
    test('app bar', () {
      final t = material({
        'components.app-bar.center-title': 'true',
        'components.app-bar.elevation': '2',
        'components.app-bar.scrolled-under-elevation': 'level3',
        'components.app-bar.background': 'surface-container',
        'components.app-bar.foreground': '#112233',
        'components.app-bar.title-style': 'headline-small',
        'components.app-bar.toolbar-height': '72',
      });
      final a = t.appBarTheme;
      expect(a.centerTitle, isTrue);
      expect(a.elevation, 2);
      expect(a.scrolledUnderElevation, 6);
      expect(a.backgroundColor, t.colorScheme.surfaceContainer);
      expect(a.foregroundColor, const Color(0xFF112233));
      expect(a.titleTextStyle!.fontSize, t.textTheme.headlineSmall!.fontSize);
      expect(a.toolbarHeight, 72);
    });

    test('buttons: the shared button style under each kind\'s own', () {
      final t = material({
        'components.button.shape': 'small',
        'components.button.min-height': '44',
        'components.button.text-style': 'label-medium',
        'components.filled-button.background': 'tertiary',
        'components.filled-button.foreground': 'on-tertiary',
        'components.elevated-button.elevation': 'level2',
        'components.outlined-button.border-color': 'outline',
        'components.outlined-button.padding': '8',
        'components.text-button.padding': '1, 2, 3, 4',
        'components.text-button.foreground': 'secondary',
      });
      final filled = t.filledButtonTheme.style!;
      expect(
        filled.shape!.resolve({}),
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
      expect(filled.minimumSize!.resolve({}), const Size(0, 44));
      expect(filled.backgroundColor!.resolve({}), t.colorScheme.tertiary);
      expect(filled.foregroundColor!.resolve({}), t.colorScheme.onTertiary);
      expect(
        filled.textStyle!.resolve({})!.fontSize,
        t.textTheme.labelMedium!.fontSize,
      );
      expect(t.elevatedButtonTheme.style!.elevation!.resolve({}), 3);
      expect(
        t.elevatedButtonTheme.style!.shape!.resolve({}),
        filled.shape!.resolve({}),
      );
      expect(
        t.outlinedButtonTheme.style!.side!.resolve({}),
        BorderSide(color: t.colorScheme.outline),
      );
      expect(
        t.outlinedButtonTheme.style!.padding!.resolve({}),
        const EdgeInsets.all(8),
      );
      expect(
        t.textButtonTheme.style!.padding!.resolve({}),
        const EdgeInsets.fromLTRB(1, 2, 3, 4),
      );
      expect(
        t.textButtonTheme.style!.foregroundColor!.resolve({}),
        t.colorScheme.secondary,
      );
    });

    test('a kind alone, and no button themes without properties', () {
      final t = material({'components.text-button.shape': 'none'});
      expect(
        t.textButtonTheme.style!.shape!.resolve({}),
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      );
      expect(t.filledButtonTheme, ThemeData().filledButtonTheme);
      expect(material(const {}).textButtonTheme, ThemeData().textButtonTheme);
    });

    test('card, chip, dialog, popup menu', () {
      final t = material({
        'components.card.shape': '10',
        'components.card.elevation': 'level0',
        'components.card.color': 'surface-container-low',
        'components.card.margin': '4, 8',
        'components.chip.shape': 'full',
        'components.chip.background': 'secondary-container',
        'components.chip.label-style': 'label-small',
        'components.dialog.shape': 'large',
        'components.dialog.background': 'surface',
        'components.dialog.elevation': '9',
        'components.popup-menu.shape': 'small',
        'components.popup-menu.elevation': 'level2',
        'components.popup-menu.color': 'surface-container-high',
      });
      expect(
        t.cardTheme.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );
      expect(t.cardTheme.elevation, 0);
      expect(t.cardTheme.color, t.colorScheme.surfaceContainerLow);
      expect(
        t.cardTheme.margin,
        const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      );
      expect(t.chipTheme.shape, const StadiumBorder());
      expect(t.chipTheme.backgroundColor, t.colorScheme.secondaryContainer);
      expect(
        t.chipTheme.labelStyle!.fontSize,
        t.textTheme.labelSmall!.fontSize,
      );
      expect(
        t.dialogTheme.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
      expect(t.dialogTheme.backgroundColor, t.colorScheme.surface);
      expect(t.dialogTheme.elevation, 9);
      expect(
        t.popupMenuTheme.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
      expect(t.popupMenuTheme.elevation, 3);
      expect(t.popupMenuTheme.color, t.colorScheme.surfaceContainerHigh);
    });

    test('bottom sheet: top corners only', () {
      final t = material({
        'components.bottom-sheet.shape': 'extra-large',
        'components.bottom-sheet.show-drag-handle': 'true',
        'components.bottom-sheet.background': 'surface-container-low',
        'components.bottom-sheet.elevation': '1',
      });
      expect(
        t.bottomSheetTheme.shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      );
      expect(t.bottomSheetTheme.showDragHandle, isTrue);
      expect(
        t.bottomSheetTheme.backgroundColor,
        t.colorScheme.surfaceContainerLow,
      );
      expect(t.bottomSheetTheme.elevation, 1);
    });

    test('navigation bar, tab bar, FAB', () {
      final t = material({
        'components.navigation-bar.height': '64',
        'components.navigation-bar.background': 'surface',
        'components.navigation-bar.indicator-color': 'primary-container',
        'components.navigation-bar.indicator-shape': 'medium',
        'components.navigation-bar.label-behavior': 'alwaysHide',
        'components.navigation-bar.elevation': 'level0',
        'components.tab-bar.indicator-color': 'tertiary',
        'components.tab-bar.label-style': 'title-small',
        'components.tab-bar.label-color': 'primary',
        'components.tab-bar.unselected-label-color': 'outline',
        'components.floating-action-button.shape': 'full',
        'components.floating-action-button.elevation': '2',
        'components.floating-action-button.background': 'tertiary-container',
        'components.floating-action-button.foreground': 'on-tertiary-container',
      });
      final n = t.navigationBarTheme;
      expect(n.height, 64);
      expect(n.backgroundColor, t.colorScheme.surface);
      expect(n.indicatorColor, t.colorScheme.primaryContainer);
      expect(
        n.indicatorShape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
      expect(n.labelBehavior, NavigationDestinationLabelBehavior.alwaysHide);
      expect(n.elevation, 0);
      expect(t.tabBarTheme.indicatorColor, t.colorScheme.tertiary);
      expect(
        t.tabBarTheme.labelStyle!.fontSize,
        t.textTheme.titleSmall!.fontSize,
      );
      expect(t.tabBarTheme.labelColor, t.colorScheme.primary);
      expect(t.tabBarTheme.unselectedLabelColor, t.colorScheme.outline);
      final fab = t.floatingActionButtonTheme;
      expect(fab.shape, const StadiumBorder());
      expect(fab.elevation, 2);
      expect(fab.backgroundColor, t.colorScheme.tertiaryContainer);
      expect(fab.foregroundColor, t.colorScheme.onTertiaryContainer);
    });

    test('snack bar, tooltip, list tile, divider', () {
      final t = material({
        'components.snack-bar.behavior': 'floating',
        'components.snack-bar.shape': 'small',
        'components.snack-bar.background': 'inverse-surface',
        'components.snack-bar.elevation': 'level3',
        'components.tooltip.background': 'primary',
        'components.tooltip.text-style': 'body-small',
        'components.list-tile.dense': 'true',
        'components.list-tile.shape': 'medium',
        'components.list-tile.tile-color': 'surface-container',
        'components.divider.thickness': '2',
        'components.divider.color': 'outline',
        'components.divider.space': '24',
      });
      expect(t.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(
        t.snackBarTheme.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
      expect(t.snackBarTheme.backgroundColor, t.colorScheme.inverseSurface);
      expect(t.snackBarTheme.elevation, 6);
      final tooltip = t.tooltipTheme.decoration! as ShapeDecoration;
      expect(tooltip.color, t.colorScheme.primary);
      expect(
        tooltip.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      );
      expect(
        t.tooltipTheme.textStyle!.fontSize,
        t.textTheme.bodySmall!.fontSize,
      );
      expect(t.listTileTheme.dense, isTrue);
      expect(
        t.listTileTheme.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
      expect(t.listTileTheme.tileColor, t.colorScheme.surfaceContainer);
      expect(t.dividerTheme.thickness, 2);
      expect(t.dividerTheme.color, t.colorScheme.outline);
      expect(t.dividerTheme.space, 24);
    });

    test('tooltip: a shape without background, a text style alone', () {
      final shaped = material({'components.tooltip.shape': 'medium'});
      final decoration = shaped.tooltipTheme.decoration! as ShapeDecoration;
      expect(decoration.color, shaped.colorScheme.inverseSurface);
      expect(
        material({'components.tooltip.text-style': 'body-small'})
            .tooltipTheme
            .decoration,
        isNull,
      );
    });

    test('input: outline, underline, filled, a shape alone', () {
      final outline = material({
        'components.input.style': 'outline',
        'components.input.shape': 'small',
        'components.input.content-padding': '12, 8',
        'components.input.fill-color': 'surface-container',
      }).inputDecorationTheme;
      expect(outline.border, isA<OutlineInputBorder>());
      expect(
        (outline.border! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(8),
      );
      expect(
        outline.contentPadding,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      );
      expect(outline.filled, isFalse);
      expect(outline.fillColor, isNotNull);

      final underline = material({'components.input.style': 'underline'})
          .inputDecorationTheme;
      expect(underline.border, isA<UnderlineInputBorder>());
      expect(
        (underline.border! as UnderlineInputBorder).borderRadius,
        BorderRadius.zero,
      );

      final filled = material({'components.input.style': 'filled'})
          .inputDecorationTheme;
      expect(filled.filled, isTrue);
      expect(
        (filled.border! as UnderlineInputBorder).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(4)),
      );

      final full = material({'components.input.shape': 'full'})
          .inputDecorationTheme;
      expect(
        (full.border! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(999),
      );
      expect(
        material({'components.input.filled': 'true'})
            .inputDecorationTheme
            .filled,
        isTrue,
      );
    });

    test('a changed scale value reaches each component using it', () {
      final t = material({
        'shape.extra-small': '2',
        'shape.small': '6',
        'shape.medium': '14',
        'shape.large': '18',
        'shape.extra-large': '30',
        'shape.full': '20',
      });
      RoundedRectangleBorder r(double radius) =>
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
      expect(t.cardTheme.shape, r(14));
      expect(t.chipTheme.shape, r(6));
      expect(t.dialogTheme.shape, r(30));
      expect(
        t.bottomSheetTheme.shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      );
      expect(t.floatingActionButtonTheme.shape, r(18));
      expect(t.snackBarTheme.shape, r(2));
      expect((t.tooltipTheme.decoration! as ShapeDecoration).shape, r(2));
      expect(t.popupMenuTheme.shape, r(2));
      expect(
        (t.inputDecorationTheme.border! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(2),
      );
      expect(t.filledButtonTheme.style!.shape!.resolve({}), r(20));
      // An explicit component shape wins over the scale.
      expect(
        material({'shape.medium': '14', 'components.card.shape': 'none'})
            .cardTheme
            .shape,
        r(0),
      );
    });

    test('unknown components and properties, invalid values', () {
      expect(
        () => theme({'components.carrd.shape': 'large'}),
        invalid('components.carrd'),
      );
      expect(
        () => theme({'components.card.radius': '4'}),
        invalid('components.card.radius'),
      );
      for (final (key, value) in [
        ('components.card.shape', 'hugee'),
        ('components.card.color', 'surfase'),
        ('components.card.elevation', 'level9'),
        ('components.card.margin', '1, 2, 3'),
        ('components.card.margin', 'x'),
        ('components.app-bar.center-title', 'yes'),
        ('components.app-bar.toolbar-height', 'tall'),
        ('components.app-bar.title-style', 'title-huge'),
        ('components.snack-bar.behavior', 'flying'),
        ('components.input.style', 'boxed'),
      ]) {
        expect(
          () => theme({key: value}),
          invalid(key.replaceAll('-', '')),
          reason: '$key: $value',
        );
      }
    });
  });

  group('misspelled keys fail like wrong values', () {
    test('every kind of key', () {
      for (final (key, expected) in [
        ('seed-colour', 'a theme property'),
        ('themes', 'a theme is themes.<name>.<property>'),
        ('motion.speed', 'motion.page-transition'),
        ('cupertino.primary', 'cupertino.primary-color'),
        ('typography.body.colour', 'a text style property'),
        ('typography.code', 'typography.code.<font-family'),
      ]) {
        expect(
          () => theme({key: 'x'}),
          throwsA(
            isA<ThemePropertyException>()
                .having(
                  (e) => e.key,
                  'key',
                  contains(key.replaceAll('-', '').toLowerCase()),
                )
                .having((e) => e.expected, 'expected', contains(expected)),
          ),
          reason: key,
        );
      }
    });

    test('in a named theme too, with its name', () {
      expect(
        () => SpringThemes(const {'themes.ocean.seed-colour': 'teal'}),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.key,
            'key',
            'spring.flutter.theme.themes.ocean.seedcolour',
          ),
        ),
      );
    });

    test('the known keys are accepted', () {
      expect(
        () => theme({
          'brightness': 'light',
          'typography.font-family': 'Inter',
          'typography.font-family-fallback.0': 'A',
          'typography.body.letter-spacing': '0.2',
          'motion.page-transition': 'zoom',
          'motion.duration-short': '50ms',
          'motion.easing-standard': '0, 0, 1, 1',
          'cupertino.primary-color': 'blue',
          'tokens.anything.at-all': 'x',
        }),
        returnsNormally,
      );
    });
  });

  group('tokens', () {
    test('as color, number and text; missing ones are null', () {
      final t = theme({
        'tokens.brand.accent': '#FF6B00',
        'tokens.brand.hero-height': '240',
        'tokens.brand.name': 'NEON',
      });
      expect(t.tokenColor('brand.accent'), const Color(0xFFFF6B00));
      expect(t.tokenNumber('brand.heroHeight'), 240);
      expect(t.token('Brand.Name'), 'NEON');
      expect(t.tokenColor('brand.missing'), isNull);
      expect(t.tokenNumber('brand.missing'), isNull);
      expect(t.tokenColor('brand.name'), isNull); // not a color
    });
  });

  group('Cupertino', () {
    test('without properties: iOS\'s defaults, the theme\'s brightness', () {
      final c = theme(const {}, 'dark').toCupertino();
      expect(c.brightness, Brightness.dark);
      expect(c.primaryColor, CupertinoColors.systemBlue);
      expect(
        c.textTheme.textStyle,
        const CupertinoThemeData().textTheme.textStyle,
      );
    });

    test(
      'primary: cupertino.primary-color, else colors.primary, else the seed',
      () {
        expect(
          theme({
            'cupertino.primary-color': '#0057B8',
            'colors.primary': '#111111',
          }).toCupertino().primaryColor,
          const Color(0xFF0057B8),
        );
        expect(
          theme({'colors.primary': '#111111'}).toCupertino().primaryColor,
          const Color(0xFF111111),
        );
        final seeded = theme({'seed-color': 'teal'});
        expect(seeded.toCupertino().primaryColor, seeded.colorScheme.primary);
      },
    );

    test('backgrounds and text styles', () {
      final t = theme({
        'colors.surface': '#FAFAFA',
        'components.app-bar.background': '#EEEEEE',
        'typography.font-family': 'Inter',
        'typography.title-large.weight': 'bold',
        'typography.display-small.size': '40',
        'typography.font-family-fallback': 'Noto Sans JP',
      });
      final c = t.toCupertino();
      expect(c.scaffoldBackgroundColor, const Color(0xFFFAFAFA));
      expect(c.barBackgroundColor, const Color(0xFFEEEEEE));
      expect(c.textTheme.textStyle.fontFamily, 'Inter');
      expect(c.textTheme.textStyle.fontFamilyFallback, ['Noto Sans JP']);
      expect(c.textTheme.navTitleTextStyle.fontWeight, FontWeight.w700);
      expect(c.textTheme.navLargeTitleTextStyle.fontSize, 40);
      expect(c.textTheme.actionTextStyle.fontFamily, 'Inter');
      expect(t.toCupertino(), same(c)); // made once
    });
  });

  group('Widgets and the app\'s own widgets', () {
    test('app color and text style', () {
      final t = theme({
        'seed-color': 'teal',
        'typography.font-family': 'Inter',
      });
      expect(t.appColor, t.colorScheme.primary);
      expect(t.widgetsTextStyle.fontFamily, 'Inter');
      expect(t.widgetsTextStyle.color, t.colorScheme.onSurface);
    });

    test('the Material theme carries the SpringThemeData', () {
      final t = theme(const {});
      final extension = t.toMaterial().extension<SpringThemeExtension>()!;
      expect(extension.data, same(t));
      expect(extension.copyWith(), same(extension));
      final other = SpringThemeExtension(theme(const {}, 'dark'));
      expect(extension.lerp(other, 0.4), same(extension));
      expect(extension.lerp(other, 0.6), same(other));
      expect(extension.lerp(null, 0.9), same(extension));
    });
  });
}

class _FakeContext extends Fake implements BuildContext {}
