// A theme read from properties as a CupertinoThemeData: the primary
// color, the text styles, the backgrounds, the cupertino.* properties and
// every kind of wrong value.
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';

import 'support/themes.dart';

void main() {
  group('toCupertino', () {
    test('without properties: iOS\'s defaults, the theme\'s brightness', () {
      final c = theme(const {}, name: 'dark').toCupertino();
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

    test('action text styles carry the theme\'s primary color', () {
      final text = theme({
        'colors.primary': '#FF5E3A',
        'typography.body-large.size': '17',
      }).toCupertino().textTheme;
      expect(text.actionTextStyle.color, const Color(0xFFFF5E3A));
      expect(text.navActionTextStyle.color, const Color(0xFFFF5E3A));
    });

    test('backgrounds and text styles', () {
      final t = theme({
        'colors.surface': '#FAFAFA',
        'components.app-bar.background': '#EEEEEE',
        'typography.font-family': 'Inter',
        'typography.title-large.weight': 'bold',
        'typography.display-small.size': '40',
        'typography.font-family-fallback': 'Noto Sans JP',
      }, designs: bothDesigns);
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

    test('the bars: cupertino.bar-background-color, else the app bar\'s', () {
      expect(
        theme({
          'cupertino.bar-background-color': '#101010',
          'components.app-bar.background-color': '#EEEEEE',
        }, designs: bothDesigns).toCupertino().barBackgroundColor,
        const Color(0xFF101010),
      );
      expect(
        theme({
          'components.app-bar.background-color': '#EEEEEE',
        }, designs: bothDesigns).toCupertino().barBackgroundColor,
        const Color(0xFFEEEEEE),
      );
      // A color object, as every color of a theme may be.
      expect(
        theme({
          'components.app-bar.background-color.color': '#EEEEEE',
          'components.app-bar.background-color.alpha': '50%',
        }, designs: bothDesigns).toCupertino().barBackgroundColor,
        const Color(0xFFEEEEEE).withValues(alpha: 0.5),
      );
      // iOS's own without either.
      expect(
        theme(const {}).toCupertino().barBackgroundColor,
        const CupertinoThemeData().barBackgroundColor,
      );
    });

    test('a wrong color of the app bar names its property', () {
      expect(
        () => theme({
          'components.app-bar.background-color': 'no color',
        }, designs: bothDesigns),
        invalid('components.appbar.backgroundcolor'),
      );
    });

    test('the scaffold: its own color, else the surface, else clear over '
        'the theme\'s background', () {
      expect(
        theme({
          'cupertino.scaffold-background-color': '#202020',
          'colors.surface': '#FAFAFA',
        }).toCupertino().scaffoldBackgroundColor,
        const Color(0xFF202020),
      );
      expect(
        theme({
          'colors.surface': '#FAFAFA',
          'background.color': '#000000',
        }).toCupertino().scaffoldBackgroundColor,
        const Color(0x00000000),
      );
      // The palette's surface is not forced on iOS's own background.
      expect(
        theme({'seed-color': 'teal'}).toCupertino().scaffoldBackgroundColor,
        const CupertinoThemeData().scaffoldBackgroundColor,
      );
    });

    test('every cupertino property', () {
      final c = theme({
        'cupertino.primary-color': '#0057B8',
        'cupertino.primary-contrasting-color': '#FFFFFF',
        'cupertino.scaffold-background-color': '#F2F2F7',
        'cupertino.bar-background-color': '#E5E5EA',
        'cupertino.selection-handle-color': '#FF9500',
        'cupertino.apply-theme-to-all': 'true',
        'cupertino.text-theme.primary-color': '#34C759',
        'cupertino.text-theme.text-style.size': '18',
        'cupertino.text-theme.nav-title-text-style': 'title-large',
        'cupertino.text-theme.tab-label-text-style.weight': 'bold',
        'typography.title-large.size': '21',
      }).toCupertino();
      expect(c.primaryColor, const Color(0xFF0057B8));
      expect(c.primaryContrastingColor, const Color(0xFFFFFFFF));
      expect(c.scaffoldBackgroundColor, const Color(0xFFF2F2F7));
      expect(c.barBackgroundColor, const Color(0xFFE5E5EA));
      expect(c.selectionHandleColor, const Color(0xFFFF9500));
      expect(c.applyThemeToAll, isTrue);
      expect(c.textTheme.textStyle.fontSize, 18);
      expect(c.textTheme.tabLabelTextStyle.fontWeight, FontWeight.w700);
      // The actions carry the theme's primary color.
      expect(c.textTheme.actionTextStyle.color, const Color(0xFF0057B8));
    });

    test('a named text style is the theme\'s own', () {
      final t = theme({
        'cupertino.text-theme.nav-title-text-style': 'title-large',
        'cupertino.text-theme.picker-text-style': 'code',
        'typography.title-large.size': '21',
        'typography.title-large.weight': '600',
      });
      final text = t.toCupertino().textTheme;
      expect(text.navTitleTextStyle, t.textStyle('titleLarge'));
      expect(text.navTitleTextStyle.fontSize, 21);
      expect(text.pickerTextStyle, t.textStyle('code'));
    });

    test('text-theme alone makes a text theme; the rest stays iOS\'s', () {
      final text = theme({
        'cupertino.text-theme.text-style.size': '18',
      }).toCupertino().textTheme;
      const defaults = CupertinoTextThemeData();
      expect(text.textStyle.fontSize, 18);
      expect(text.navTitleTextStyle, defaults.navTitleTextStyle);
      expect(text.actionTextStyle, defaults.actionTextStyle);
    });
  });

  group('cupertinoPrimaryColor', () {
    test('the property; null when not set', () {
      expect(
        theme({'cupertino.primary-color': '#0057B8'}).cupertinoPrimaryColor,
        const Color(0xFF0057B8),
      );
      expect(
        theme({'colors.primary': '#111111'}).cupertinoPrimaryColor,
        isNull,
      );
    });
  });

  group('cupertinoProperties', () {
    test('lists what the theme reads, in the order of the reference', () {
      expect(
        [
          for (final p in theme(const {}).cupertinoProperties)
            '${p.name}: ${p.kind}',
        ],
        [
          'primary-color: color',
          'text-theme.primary-color: color',
          'text-theme.text-style: text style',
          'text-theme.action-text-style: text style',
          'text-theme.tab-label-text-style: text style',
          'text-theme.nav-title-text-style: text style',
          'text-theme.nav-large-title-text-style: text style',
          'text-theme.nav-action-text-style: text style',
          'text-theme.picker-text-style: text style',
          'text-theme.date-time-picker-text-style: text style',
          'primary-contrasting-color: color',
          'scaffold-background-color: color',
          'bar-background-color: color',
          'selection-handle-color: color',
          'apply-theme-to-all: true / false',
        ],
      );
      expect(
        theme(const {}).cupertinoProperties.any((p) => p.states),
        isFalse,
      );
    });
  });

  group('wrong keys and values fail the start', () {
    test('a misspelled key names the valid ones', () {
      expect(
        () => theme({'cupertino.primary': 'x'}),
        throwsA(
          isA<ThemePropertyException>()
              .having((e) => e.key, 'key', contains('cupertino.primary'))
              .having((e) => e.expected, 'expected', contains('primary-color')),
        ),
      );
      expect(
        () => theme({'cupertino.text-theme.title-style': 'title-large'}),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.expected,
            'expected',
            contains('nav-title-text-style'),
          ),
        ),
      );
    });

    test('a wrong value names its property', () {
      for (final (key, value) in [
        ('cupertino.primary-color', 'no color'),
        ('cupertino.apply-theme-to-all', 'maybe'),
        ('cupertino.text-theme.text-style', 'huge'),
        ('cupertino.text-theme.text-style.size', 'big'),
      ]) {
        expect(
          () => theme({key: value}),
          invalid(key.replaceAll('-', '')),
          reason: '$key: $value',
        );
      }
    });

    test('in a named theme too, with its name', () {
      expect(
        () => themes(const {'themes.ocean.cupertino.primary': 'blue'}),
        invalid('spring.flutter.theme.themes.ocean.cupertino.primary'),
      );
    });

    test('the known keys are accepted', () {
      expect(
        () => theme({
          'brightness': 'light',
          'typography.font-family': 'Inter',
          'motion.page-transition': 'cupertino',
          'cupertino.primary-color': 'blue',
          'tokens.anything.at-all': 'x',
        }),
        returnsNormally,
      );
    });

    test('cupertino.* without the design is accepted, not checked, and '
        'named with the starter that reads it', () {
      for (final (themes, name) in [
        (
          SpringThemes(const {'cupertino.primary-color': 'not a color'}),
          'light',
        ),
        (
          SpringThemes(const {
            'themes.ocean.cupertino.primary-color': 'not a color',
          }),
          'ocean',
        ),
        (
          SpringThemes(
            const {'cupertino.primary-color': 'not a color'},
            designs: const ThemeDesigns(all: [ComponentsDesign()]),
          ),
          'light',
        ),
      ]) {
        expect(themes.data(name).unreadDesignProperties, {
          'cupertino': 'spring_boot_starter_flutter_cupertino',
        });
      }
      // With the design the same value fails the start.
      expect(
        () => SpringThemes(
          const {'cupertino.primary-color': 'not a color'},
          designs: const ThemeDesigns(
            all: [CupertinoThemeDesign()],
            appType: 'cupertino',
          ),
        ),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.key,
            'key',
            contains('cupertino'),
          ),
        ),
      );
    });
  });
}
