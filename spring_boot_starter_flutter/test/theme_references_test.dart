// References (`$colors.primary`), color objects and nested tokens.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show ColorScheme, DynamicSchemeVariant;
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';

import 'support/designs.dart' show testDesigns;

SpringThemeData theme(
  Map<String, String> properties, [
  String name = 'light',
]) => SpringThemeData.of(ThemeConfig(properties), name);

Map<String, String> resolved(Map<String, String> properties) =>
    ThemeConfig(properties).resolve('light');

/// [theme] in an app with a design library, which makes the palette of a
/// seed color.
SpringThemeData seeded(Map<String, String> properties) =>
    SpringThemeData.of(ThemeConfig(properties, designs: testDesigns), 'light');

void main() {
  group('references', () {
    test('a path from the root, a token path without tokens.', () {
      final values = resolved({
        'colors.primary': '#112233',
        'spacing.m': '12',
        'tokens.neon.yellow': r'$colors.primary',
        'tokens.neon.pad': r'$spacing.m',
        'tokens.neon.same': r'$neon.yellow',
        'tokens.neon.full': r'$tokens.neon.yellow',
      });
      expect(values['tokens.neon.yellow'], '#112233');
      expect(values['tokens.neon.pad'], '12');
      expect(values['tokens.neon.same'], '#112233');
      expect(values['tokens.neon.full'], '#112233');
    });

    test(r'a $path inside longer text is replaced too', () {
      final values = resolved({
        'colors.primary': '#112233',
        'tokens.neon.note': r'Accent is $colors.primary today',
      });
      expect(values['tokens.neon.note'], 'Accent is #112233 today');
    });

    test('seed-color can be a reference; chains resolve', () {
      final data = seeded({
        'colors.secondary': '#00FF00',
        'colors.tertiary': r'$colors.secondary',
        'seed-color': r'$colors.tertiary',
      });
      expect(data.seedColor, const Color(0xFF00FF00));
      expect(data.colors['tertiary'], const Color(0xFF00FF00));
    });

    test('a reference inside a color object', () {
      final data = theme({
        'colors.primary': '#FF0000',
        'tokens.a.fill.color': r'$colors.primary',
        'tokens.a.fill.alpha': '50%',
        'tokens.a.hover.color': r'$colors.primary',
        'tokens.a.hover.mix.with': 'white',
        'tokens.a.hover.mix.amount': '100%',
      });
      expect(data.tokenColor('a.fill')!.a, closeTo(0.5, 0.01));
      expect(data.tokenColor('a.hover'), const Color(0xFFFFFFFF));
    });

    test(r'$$ is a literal $, ${...} and $5 are left alone', () {
      final values = resolved({
        'tokens.a.price': r'$$5',
        'tokens.a.cdn': r'Bearer ${cdn.token}',
        'tokens.a.cost': r'costs $5',
        'tokens.a.text': r'a $$colors.primary',
      });
      expect(values['tokens.a.price'], r'$5');
      expect(values['tokens.a.cdn'], r'Bearer ${cdn.token}');
      expect(values['tokens.a.cost'], r'costs $5');
      expect(values['tokens.a.text'], r'a $colors.primary');
    });

    test('resolved after extends: the child changes what refers to it', () {
      final config = ThemeConfig({
        'colors.primary': '#111111',
        'tokens.a.fill': r'$colors.primary',
        'themes.ocean.colors.primary': '#222222',
      });
      expect(config.resolve('light')['tokens.a.fill'], '#111111');
      expect(config.resolve('ocean')['tokens.a.fill'], '#222222');
      expect(config.resolve('dark')['tokens.a.fill'], '#111111');
    });

    test('a reference to a list joins its items', () {
      final data = theme({
        'tokens.a.one': '#FF0000',
        'tokens.a.two': '#00FF00',
        'tokens.b.colors.0': r'$a.one',
        'tokens.b.colors.1': r'$a.two',
        'tokens.b.again': r'$b.colors',
      });
      expect(data.tokenColors('b.again'), [
        const Color(0xFFFF0000),
        const Color(0xFF00FF00),
      ]);
    });

    test('a cycle stops with the chain', () {
      expect(
        () => theme({
          'tokens.a.x': r'$a.y',
          'tokens.a.y': r'$a.z',
          'tokens.a.z': r'$a.x',
        }),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.expected,
            'expected',
            allOf(contains('cycle'), contains('tokens.a.x'), contains('→')),
          ),
        ),
      );
    });

    test('an unknown path names the property and suggests', () {
      expect(
        () => theme({
          'colors.primary': '#112233',
          'tokens.a.x': r'$colors.primry',
        }),
        throwsA(
          isA<ThemePropertyException>()
              .having((e) => e.key, 'key', contains('tokens.a.x'))
              .having(
                (e) => e.expected,
                'expected',
                contains("did you mean 'colors.primary'"),
              ),
        ),
      );
    });

    test('an undeclared Material role or shape is computed', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF008080),
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
        contrastLevel: 0.5,
      );
      String hex(Color c) =>
          '#${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
      final values = ThemeConfig({
        'brightness': 'dark',
        'seed-color': '#008080',
        'scheme-variant': 'vibrant',
        'contrast': '0.5',
        'colors.primary': '#112233',
        'tokens.a.outline': r'$colors.outline',
        'tokens.a.lowest': r'$colors.surface-container-lowest',
        'tokens.a.primary': r'$colors.primary',
        'tokens.a.soft.color': r'$colors.outline',
        'tokens.a.soft.alpha': '50%',
        'tokens.a.small': r'$shape.extra-small',
        'tokens.a.full': r'$shape.full',
      }, designs: testDesigns).resolve('light');
      expect(values['tokens.a.outline'], hex(scheme.outline));
      expect(
        values['tokens.a.lowest'],
        hex(scheme.surfaceContainerLowest),
      );
      // A declared role wins over the computed one.
      expect(values['tokens.a.primary'], '#112233');
      expect(values['tokens.a.soft.color'], hex(scheme.outline));
      expect(values['tokens.a.small'], '4');
      expect(values['tokens.a.full'], 'Infinity');
    });

    test('the computed role follows the theme it is read in', () {
      final config = ThemeConfig({
        'seed-color': '#008080',
        'tokens.a.outline': r'$colors.outline',
        'themes.dark.seed-color': '#AA0000',
      }, designs: testDesigns);
      expect(
        config.resolve('light')['tokens.a.outline'],
        isNot(config.resolve('dark')['tokens.a.outline']),
      );
    });

    test('a seed that needs an undeclared role is an error, not a loop', () {
      expect(
        () => seeded({'seed-color': r'$colors.outline'}),
        throwsA(isA<ThemePropertyException>()),
      );
    });

    test('an unknown role or shape still asks "did you mean"', () {
      expect(
        () => theme({'tokens.a.x': r'$colors.surfce'}),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.expected,
            'expected',
            contains('surface'),
          ),
        ),
      );
      expect(
        () => theme({'tokens.a.x': r'$shape.extra-smal'}),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.expected,
            'expected',
            contains('extrasmall'),
          ),
        ),
      );
    });

    test('headers and image sources are left as they are', () {
      final values = resolved({
        'background.image.source': r'https://x.test/a$abc.png',
        'background.image.fallback': r'assets/a$$b.png',
        'background.image.source-sha256': r'$abc',
        'background.image.headers.authorization': r'Bearer $abc',
        'background.image.headers.x-key': r'pa$$word',
        'tokens.a.b': r'$$ok',
      });
      expect(values['background.image.source'], r'https://x.test/a$abc.png');
      expect(values['background.image.fallback'], r'assets/a$$b.png');
      expect(values['background.image.sourcesha256'], r'$abc');
      expect(values['background.image.headers.authorization'], r'Bearer $abc');
      expect(values['background.image.headers.x-key'], r'pa$$word');
      expect(values['tokens.a.b'], r'$ok');
    });
  });

  group('color objects', () {
    test('plain colors are names and hex only', () {
      expect(ThemeValues.color('white'), const Color(0xFFFFFFFF));
      expect(ThemeValues.color('black'), const Color(0xFF000000));
      expect(ThemeValues.color('transparent'), const Color(0x00000000));
      for (final old in [
        '#FF0000 alpha 0.5',
        '#FF0000 mix white 50%',
        'primary@38%',
        'primary',
      ]) {
        expect(ThemeValues.color(old), isNull, reason: old);
      }
    });

    ThemeProperties props(Map<String, String> values) =>
        ThemeProperties('light', values);

    test('color, then mix, then alpha', () {
      final p = props({
        'a.color': '#FF0000',
        'a.mix.with': 'white',
        'a.mix.amount': '50%',
        'a.alpha': '80%',
      });
      final expected = Color.lerp(
        const Color(0xFFFF0000),
        const Color(0xFFFFFFFF),
        0.5,
      )!.withValues(alpha: 0.8);
      expect(p.color('a'), expected);
    });

    test('percent is 0% to 100% or 0 to 1', () {
      for (final amount in ['12%', '0.12']) {
        expect(
          props({'a.color': '#FF0000', 'a.alpha': amount}).color('a')!.a,
          closeTo(0.12, 0.01),
        );
      }
    });

    test('a color may be an object too, so objects nest', () {
      final p = props({
        'a.color.color': '#FF0000',
        'a.color.alpha': '50%',
        'a.mix.with.color': '#0000FF',
        'a.mix.with.alpha': '100%',
        'a.mix.amount': '0',
      });
      expect(p.color('a')!.a, closeTo(0.5, 0.01));
      expect(p.color('a')!.r, 1);
    });

    test('a color object in colors.* and seed-color', () {
      final data = seeded({
        'colors.primary.color': '#FF0000',
        'colors.primary.alpha': '50%',
        'seed-color.color': '#0000FF',
        'seed-color.mix.with': '#FFFFFF',
        'seed-color.mix.amount': '0',
      });
      expect(data.colors['primary']!.a, closeTo(0.5, 0.01));
      expect(data.seedColor, const Color(0xFF0000FF));
    });

    test('a reference to a color object is the color it makes', () {
      final values = resolved({
        'colors.primary.color': '#FF0000',
        'colors.primary.alpha': '50%',
        'tokens.a.x': r'$colors.primary',
        'tokens.a.y.color': r'$colors.primary',
        'tokens.a.y.mix.with': 'black',
        'tokens.a.y.mix.amount': '0',
      });
      expect(values['tokens.a.x'], '#80ff0000');
      expect(values['tokens.a.y.color'], '#80ff0000');
    });

    final bad = <String, (Map<String, String>, String)>{
      'an unknown key, with a hint': (
        {'a.color': '#F00', 'a.alfa': '10%'},
        "did you mean 'alpha'",
      ),
      'no color': ({'a.alpha': '10%'}, "object with a 'color'"),
      'a percent out of range': ({'a.color': '#F00', 'a.alpha': '120%'}, '0%'),
      'a mix as a one-liner': (
        {'a.color': '#F00', 'a.mix': 'white 10%'},
        'with',
      ),
      'a mix without an amount': (
        {'a.color': '#F00', 'a.mix.with': 'white'},
        "'amount'",
      ),
      'an unknown mix key': (
        {'a.color': '#F00', 'a.mix.with': 'white', 'a.mix.amout': '1'},
        "did you mean 'amount'",
      ),
      'a bad color': ({'a.color': 'nope'}, 'a color'),
    };
    for (final MapEntry(key: name, value: (values, hint)) in bad.entries) {
      test('is an error: $name', () {
        expect(
          () => props(values).color('a'),
          throwsA(
            isA<ThemePropertyException>().having(
              (e) => e.toString(),
              'message',
              contains(hint),
            ),
          ),
        );
      });
    }

    test('a token that is a map with color and other keys is an error', () {
      expect(
        () => theme({
          'tokens.brand.color': '#FF0000',
          'tokens.brand.size': '4',
        }),
        throwsA(isA<ThemePropertyException>()),
      );
    });

    test('a later layer replaces a color object whole', () {
      final config = ThemeConfig({
        'colors.primary.color': '#FF0000',
        'colors.primary.alpha': '50%',
        'themes.ocean.colors.primary': '#0000FF',
        'themes.dark.colors.primary.color': '#00FF00',
        'themes.dark.colors.primary.mix.with': 'white',
        'themes.dark.colors.primary.mix.amount': '10%',
      });
      expect(config.resolve('ocean')['colors.primary'], '#0000FF');
      expect(
        config
            .resolve('ocean')
            .keys
            .where((k) => k.startsWith('colors.primary.')),
        isEmpty,
      );
      expect(
        config.resolve('dark').containsKey('colors.primary.alpha'),
        isFalse,
      );
    });
  });

  group('nested tokens', () {
    final data = theme({
      'tokens.neon.modal.width': '460',
      'tokens.neon.modal.barrier': 'transparent',
      'tokens.neon.modal.open': '250ms',
      'tokens.neon.modal.border.width': '1',
      'tokens.neon.modal.border.colors.0': '#FF0000',
      'tokens.neon.modal.border.colors.1': '#00FF00',
      'tokens.neon.modal.border.sizes': '1, 2.5',
      'tokens.neon.modal.border.names.0': 'a',
      'tokens.neon.modal.border.names.1': 'b',
      'tokens.brand.accent': '#0000FF',
    });

    test('any depth, keyed by the full canonical path', () {
      expect(data.tokenNumber('neon.modal.width'), 460);
      expect(data.tokenNumber('neon.modal.border.width'), 1);
      expect(data.tokenColor('neon.modal.barrier'), const Color(0x00000000));
      expect(data.tokens['neon.modal.border.colors.0'], '#FF0000');
      expect(data.tokenColor('brand.accent'), const Color(0xFF0000FF));
    });

    test('durations and lists', () {
      expect(
        data.tokenDuration('neon.modal.open'),
        const Duration(milliseconds: 250),
      );
      expect(data.tokenColors('neon.modal.border.colors'), [
        const Color(0xFFFF0000),
        const Color(0xFF00FF00),
      ]);
      expect(data.tokenNumbers('neon.modal.border.sizes'), [1, 2.5]);
      expect(data.tokenTexts('neon.modal.border.names'), ['a', 'b']);
      expect(data.tokenColors('neon.modal.border.names'), isNull);
      expect(data.tokenTexts('neon.nothing'), isNull);
    });

    test('the reader reads them, missing ones throw', () {
      final reader = ThemeKeyReader(data);
      expect(reader.tokenColors('neon.modal.border.colors'), hasLength(2));
      expect(reader.tokenNumbers('neon.modal.border.sizes'), [1, 2.5]);
      expect(reader.tokenTexts('neon.modal.border.names'), ['a', 'b']);
      expect(
        reader.tokenDuration('neon.modal.open'),
        const Duration(milliseconds: 250),
      );
      expect(() => reader.tokenColors('nope'), throwsStateError);
      expect(() => reader.tokenDuration('nope'), throwsStateError);
    });
  });

  group('motion and animations', () {
    final data = theme({
      'motion.durations.fast': '120ms',
      'motion.curves.out': 'ease-out',
      'motion.curves.emphasized': '0.2, 0, 0, 1',
      'motion.durations.slow': '600ms',
      'motion.curves.old': 'linear',
      'motion.page-transition': 'fade-upwards',
      'animations.border-spin.duration': '4s',
      'animations.border-spin.curve': 'linear',
      'animations.border-spin.repeat': 'loop',
      'animations.glow.duration': '1.6s',
    });

    test('durations and curves', () {
      final reader = ThemeKeyReader(data);
      expect(
        reader.motionDuration('fast'),
        const Duration(milliseconds: 120),
      );
      expect(
        reader.motionDuration('slow'),
        const Duration(milliseconds: 600),
      );
      expect(reader.motionCurve('out'), Curves.easeOut);
      expect(reader.motionCurve('old'), Curves.linear);
      final emphasized = reader.motionCurve('emphasized') as Cubic;
      expect(
        [emphasized.a, emphasized.b, emphasized.c, emphasized.d],
        [0.2, 0, 0, 1],
      );
      expect(data.pageTransition, isA<FadeUpwardsPageTransitionsBuilder>());
      expect(() => reader.motionDuration('nope'), throwsStateError);
      expect(() => reader.motionCurve('nope'), throwsStateError);
    });

    test('a cubic curve as a YAML list, and a wrong one fails clearly', () {
      final listed = theme({
        'motion.curves.emphasized.0': '0.2',
        'motion.curves.emphasized.1': '0',
        'motion.curves.emphasized.2': '0',
        'motion.curves.emphasized.3': '1',
      });
      final cubic = ThemeKeyReader(listed).motionCurve('emphasized') as Cubic;
      expect([cubic.a, cubic.b, cubic.c, cubic.d], [0.2, 0, 0, 1]);
      expect(
        () => theme({
          'motion.curves.emphasized.0': '0.2',
          'motion.curves.emphasized.1': '0',
        }),
        throwsA(isA<ThemePropertyException>()),
      );
    });

    test('reduce motion gives zero durations', () {
      final reader = ThemeKeyReader(data, reduceMotion: true);
      expect(reader.motionDuration('fast'), Duration.zero);
      expect(reader.motionDuration('medium'), Duration.zero);
    });

    test('animations', () {
      final reader = ThemeKeyReader(data);
      final spin = reader.animation('border-spin');
      expect(spin.duration, const Duration(seconds: 4));
      expect(spin.repeat, AnimationRepeat.loop);
      final glow = reader.animation('glow');
      expect(glow.repeat, AnimationRepeat.none);
      expect(glow.curve, Curves.linear);
      expect(() => reader.animation('nope'), throwsStateError);
    });

    test('invalid animations and curves stop the start', () {
      expect(
        () =>
            theme({'animations.a.duration': '1s', 'animations.a.repeat': 'x'}),
        throwsA(isA<ThemePropertyException>()),
      );
      expect(
        () => theme({'animations.a.curve': 'linear'}),
        throwsA(isA<ThemePropertyException>()),
      );
      expect(
        () =>
            theme({'animations.a.duration': '1s', 'animations.a.duraton': '1'}),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.expected,
            'expected',
            contains('did you mean'),
          ),
        ),
      );
      expect(
        () => theme({'motion.curves.a': 'wobbly'}),
        throwsA(isA<ThemePropertyException>()),
      );
    });
  });
}
