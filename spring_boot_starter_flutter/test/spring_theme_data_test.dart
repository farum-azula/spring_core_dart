// A theme read from properties without a design library: the checks of
// its colors, the text styles, the scales, motion and page transitions,
// the accessors for the app's own widgets, and every kind of invalid value.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';

import 'support/designs.dart' show testDesigns;

SpringThemeData theme(
  Map<String, String> properties, [
  String name = 'light',
]) => SpringThemeData.of(ThemeConfig(properties), name);

Matcher invalid(String key) => throwsA(
  isA<ThemePropertyException>().having((e) => e.key, 'key', contains(key)),
);

void main() {
  group('colors', () {
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
      expect(() => theme({'contrast': '1.5'}), invalid('contrast'));
      expect(() => theme({'contrast': '-1.01'}), invalid('contrast'));
      // The limits are values: a design makes the palette of a contrast.
      double? contrast(String value) => SpringThemeData.of(
        ThemeConfig({'contrast': value}, designs: testDesigns),
        'light',
      ).contrast;
      expect(contrast('-1'), -1);
      expect(contrast('1'), 1);
      expect(() => theme({'brightness': 'grey'}), invalid('brightness'));
    });
  });

  group('typography', () {
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
      final defaults = ThemeKeyReader(theme(const {}));
      expect(
        defaults.motionDuration('short'),
        const Duration(milliseconds: 100),
      );
      expect(
        defaults.motionDuration('medium'),
        const Duration(milliseconds: 250),
      );
      expect(
        defaults.motionDuration('long'),
        const Duration(milliseconds: 450),
      );
      expect(
        () => defaults.motionDuration('mediun'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains("did you mean 'medium'"),
          ),
        ),
      );
      expect(
        ThemeKeyReader(theme(const {}), reduceMotion: true).motionDuration(
          'long',
        ),
        Duration.zero,
      );
      // Material 3's standard easing, as numbers.
      expect(theme(const {}).curve('standard'), const Cubic(0.2, 0, 0, 1));
      final t = theme({
        'motion.durations.medium': '300ms',
        'motion.curves.emphasized': '0.3, 0, 0, 1',
      });
      expect(
        ThemeKeyReader(t).motionDuration('medium'),
        const Duration(milliseconds: 300),
      );
      expect((t.curve('emphasized') as Cubic).a, 0.3);
      expect(
        () => theme({'motion.durations.medium': 'slow'}),
        invalid('motion.durations.medium'),
      );
      expect(
        () => theme({'motion.curves.standard': '1, 2'}),
        invalid('motion.curves.standard'),
      );
      expect(
        () => theme({'motion.duration-medium': '300ms'}),
        invalid('durationmedium'),
      );
      expect(
        () => theme({'motion.easing-standard': 'ease'}),
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

  group('page transitions', () {
    test('the page transition for the router: a kind, or a map', () {
      // Not set: the platform's, as in Flutter, for the router and
      // Material's page routes alike.
      expect(
        theme({}).pageTransitions,
        const PageTransitionSpec(type: PageTransitionType.platform),
      );
      expect(theme({}).isPlatformPageTransition, isTrue);
      expect(
        theme({'motion.page-transition': 'none'}).pageTransitions,
        const PageTransitionSpec(type: PageTransitionType.none),
      );
      expect(theme({}).motionEnabled, isTrue);
      expect(theme({'motion.enabled': 'false'}).motionEnabled, isFalse);
      expect(
        () => theme({'motion.speed': 'fast'}),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => '$e',
            'message',
            contains('motion.enabled, motion.page-transition'),
          ),
        ),
      );
      final map = theme({
        'motion.durations.fast': '140ms',
        'motion.page-transition.type': 'fade',
        'motion.page-transition.duration': r'$motion.durations.fast',
        'motion.page-transition.curve': 'ease-out',
      });
      expect(map.pageTransitions.type, PageTransitionType.fade);
      expect(
        map.pageTransitions.duration,
        const Duration(milliseconds: 140),
      );
      expect(map.pageTransitions.curve, Curves.easeOut);
      // The same for the page routes of a design.
      expect(
        theme({
          'motion.page-transition': 'fade',
        }).pageTransition.runtimeType.toString(),
        '_FadeTransition',
      );
    });

    test('a wrong page transition key or kind fails the start, named', () {
      expect(
        () => theme({'motion.page-transition.speed': 'fast'}),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.toString(),
            'message',
            contains('type, duration or curve'),
          ),
        ),
      );
      expect(
        () => theme({'motion.page-transition': 'slide'}),
        throwsA(isA<ThemePropertyException>()),
      );
      expect(
        () => theme({'motion.page-transition': 'slide'}),
        invalid('pagetransition'),
      );
    });
  });

  group('misspelled keys fail like wrong values', () {
    test('every kind of key', () {
      for (final (key, expected) in [
        ('seed-colour', 'a theme property'),
        ('themes', 'a theme is themes.<name>.<property>'),
        ('motion.speed', 'motion.page-transition'),
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
          'motion.page-transition': 'fade-upwards',
          'motion.durations.short': '50ms',
          'motion.curves.standard': '0, 0, 1, 1',
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
}
