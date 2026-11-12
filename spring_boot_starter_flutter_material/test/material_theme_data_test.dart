// A theme read from properties as Material's ThemeData: every color
// role and text style, the density, tap targets, ink splash and page
// transitions, a sample of components, and the SpringThemeData it carries.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

import 'support/themes.dart';

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
      expect(transition('content'), ContentPageTransitionsBuilder);
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
    });
  });

  group('components', () {
    test('app bar', () {
      final t = material({
        'components.app-bar.center-title': 'true',
        'components.app-bar.elevation': '2',
        'components.app-bar.scrolled-under-elevation': 'level3',
        'components.app-bar.background': r'$colors.surface-container',
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
        'components.filled-button.background': r'$colors.tertiary',
        'components.filled-button.foreground': r'$colors.on-tertiary',
        'components.elevated-button.elevation': 'level2',
        'components.outlined-button.border-color': r'$colors.outline',
        'components.outlined-button.padding': '8',
        'components.text-button.padding': '1, 2, 3, 4',
        'components.text-button.foreground': r'$colors.secondary',
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
        'components.card.color': r'$colors.surface-container-low',
        'components.card.margin': '4, 8',
        'components.chip.shape': 'full',
        'components.chip.background': r'$colors.secondary-container',
        'components.chip.label-style': 'label-small',
        'components.dialog.shape': 'large',
        'components.dialog.background': r'$colors.surface',
        'components.dialog.elevation': '9',
        'components.popup-menu.shape': 'small',
        'components.popup-menu.elevation': 'level2',
        'components.popup-menu.color': r'$colors.surface-container-high',
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
        'components.bottom-sheet.background': r'$colors.surface-container-low',
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
        'components.navigation-bar.background': r'$colors.surface',
        'components.navigation-bar.indicator-color':
            r'$colors.primary-container',
        'components.navigation-bar.indicator-shape': 'medium',
        'components.navigation-bar.label-behavior': 'alwaysHide',
        'components.navigation-bar.elevation': 'level0',
        'components.tab-bar.indicator-color': r'$colors.tertiary',
        'components.tab-bar.label-style': 'title-small',
        'components.tab-bar.label-color': r'$colors.primary',
        'components.tab-bar.unselected-label-color': r'$colors.outline',
        'components.floating-action-button.shape': 'full',
        'components.floating-action-button.elevation': '2',
        'components.floating-action-button.background':
            r'$colors.tertiary-container',
        'components.floating-action-button.foreground':
            r'$colors.on-tertiary-container',
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
        'components.snack-bar.background': r'$colors.inverse-surface',
        'components.snack-bar.elevation': 'level3',
        'components.tooltip.background': r'$colors.primary',
        'components.tooltip.text-style': 'body-small',
        'components.list-tile.dense': 'true',
        'components.list-tile.shape': 'medium',
        'components.list-tile.tile-color': r'$colors.surface-container',
        'components.divider.thickness': '2',
        'components.divider.color': r'$colors.outline',
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
        'components.input.fill-color': r'$colors.surface-container',
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
