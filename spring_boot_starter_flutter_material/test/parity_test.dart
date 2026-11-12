// The Flutter starter knows no design library, and keeps Material 3's
// numbers as its own: the baseline palette, the type scale, the fonts per
// platform, the easings, two icons. Each must be what Material has, so an
// app without Material and a MaterialApp show the same theme.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

import 'support/color_roles.dart';
import 'support/themes.dart';

/// [roles] by canonical name, as `SpringColorScheme.roles` has them.
Map<String, Color> canonical(Map<String, Color> roles) => {
  for (final MapEntry(:key, :value) in roles.entries) key.toLowerCase(): value,
};

/// Runs [body] as on [platform].
void onPlatform(TargetPlatform platform, void Function() body) {
  debugDefaultTargetPlatformOverride = platform;
  try {
    body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

const _typography = <String, Map<String, String>>{
  'nothing set': {},
  'a font family': {'typography.font-family': 'Inter'},
  'a font family and fallbacks': {
    'typography.font-family': 'Inter',
    'typography.font-family-fallback': 'Noto Sans JP, Roboto',
  },
  'a style override': {
    'typography.title-large.size': '23',
    'typography.title-large.weight': '600',
    'typography.body.height': '1.6',
    'typography.defaults.letter-spacing': '0.2',
    'typography.display.font-family': 'Playfair Display',
  },
  'a seed color': {'seed-color': 'teal', 'colors.on-surface': '#102030'},
};

const _scripts = {
  TextScript.englishLike: ScriptCategory.englishLike,
  TextScript.dense: ScriptCategory.dense,
  TextScript.tall: ScriptCategory.tall,
};

void main() {
  group('the baseline palette', () {
    for (final brightness in Brightness.values) {
      test('${brightness.name}: the roles of ThemeData()', () {
        final material = ThemeData(brightness: brightness).colorScheme;
        final baseline = SpringColorScheme.baseline(brightness);
        expect(baseline.brightness, brightness);
        expect(baseline.roles.keys.toSet(), colorRoles.toSet());
        expect(baseline.roles, canonical(roleColors(material)));
      });

      test('${brightness.name}: a theme without properties has it, and '
          'its ThemeData has Flutter\'s own palette', () {
        final spring = theme(const {}, brightness.name);
        expect(spring.colorScheme, SpringColorScheme.baseline(brightness));
        expect(
          spring.toMaterial().colorScheme,
          ThemeData(brightness: brightness).colorScheme,
        );
        expect(
          spring.materialColorScheme,
          same(spring.toMaterial().colorScheme),
        );
      });
    }
  });

  group('a seed color', () {
    test('without a design: the start fails, naming the starter', () {
      expect(
        () => SpringThemes(const {'seed-color': 'teal'}),
        throwsA(
          isA<ThemePropertyException>()
              .having((e) => e.key, 'key', contains('seedcolor'))
              .having(
                (e) => e.expected,
                'expected',
                contains('spring_boot_starter_flutter_material'),
              ),
        ),
      );
    });

    for (final brightness in Brightness.values) {
      test('${brightness.name}: the roles of ColorScheme.fromSeed', () {
        final seeded = ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        );
        final spring = theme(const {'seed-color': 'teal'}, brightness.name);
        expect(spring.colorScheme.roles, canonical(roleColors(seeded)));
        // All of Material's palette, the colors it keeps for older code
        // (`surfaceVariant`, `background`) too.
        expect(spring.toMaterial().colorScheme, seeded);
      });
    }

    test('a variant, a contrast and roles of colors over them', () {
      final seeded = ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
        contrastLevel: 0.5,
      );
      final spring = theme(const {
        'seed-color': 'deepPurple',
        'scheme-variant': 'vibrant',
        'contrast': '0.5',
        'colors.error': '#B3261E',
      });
      expect(
        spring.toMaterial().colorScheme,
        seeded.copyWith(error: const Color(0xFFB3261E)),
      );
      expect(spring.colorScheme.roles, {
        ...canonical(roleColors(seeded)),
        'error': const Color(0xFFB3261E),
      });
    });

    test('a contrast alone: the default seed', () {
      expect(
        theme(const {'contrast': '1'}).toMaterial().colorScheme,
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          contrastLevel: 1,
        ),
      );
    });

    test('the palette of Material, there and back', () {
      final seeded = ColorScheme.fromSeed(seedColor: Colors.orange);
      expect(seeded.toSpring().roles, canonical(roleColors(seeded)));
      expect(
        const ColorScheme.light().withRolesOf(seeded.toSpring()).primary,
        seeded.primary,
      );
      expect(seeded.withRolesOf(seeded.toSpring()), seeded);
    });
  });

  group('the text styles', () {
    for (final platform in TargetPlatform.values) {
      for (final brightness in Brightness.values) {
        for (final MapEntry(key: what, value: properties)
            in _typography.entries) {
          test('${platform.name}, ${brightness.name}, $what: those of '
              'ThemeData.textTheme', () {
            onPlatform(platform, () {
              final spring = theme(properties, brightness.name);
              final text = spring.toMaterial().textTheme;
              for (final name in textStyleNames) {
                expect(
                  spring.textStyle(name),
                  text.styleNamed(name),
                  reason: '$name on ${platform.name}',
                );
              }
            });
          });

          test('${platform.name}, ${brightness.name}, $what: with the '
              'sizes of a script, those of Theme.of', () {
            onPlatform(platform, () {
              final spring = theme(properties, brightness.name);
              for (final MapEntry(key: script, value: category)
                  in _scripts.entries) {
                final text = ThemeData.localize(
                  spring.toMaterial(),
                  Typography.material2021(
                    platform: defaultTargetPlatform,
                  ).geometryThemeFor(category),
                ).textTheme;
                for (final name in textStyleNames) {
                  expect(
                    spring.localizedTextStyle(name, script),
                    text.styleNamed(name),
                    reason: '$name, ${script.name} on ${platform.name}',
                  );
                }
              }
            });
          });
        }
      }
    }

    test('code: over body medium, in a component as in the theme', () {
      final spring = theme(const {
        'typography.font-family': 'Inter',
        'typography.code.font-family': 'JetBrains Mono',
        'components.tooltip.text-style': 'code',
      });
      expect(
        spring.toMaterial().tooltipTheme.textStyle,
        spring.textStyle('code'),
      );
    });

    test('the scripts of the locales are Material\'s', () {
      for (final MapEntry(key: language, value: script) in const {
        'en': TextScript.englishLike,
        'ru': TextScript.englishLike,
        'ja': TextScript.dense,
        'zh': TextScript.dense,
        'ko': TextScript.dense,
        'ar': TextScript.tall,
        'hi': TextScript.tall,
        'th': TextScript.tall,
      }.entries) {
        expect(SpringTypeScale.scriptOf(Locale(language)), script);
      }
      expect(SpringTypeScale.scriptOf(null), TextScript.englishLike);
    });
  });

  group('the easings', () {
    Matcher sameCubic(Curve curve) {
      final cubic = curve as Cubic;
      return isA<Cubic>()
          .having((c) => c.a, 'a', cubic.a)
          .having((c) => c.b, 'b', cubic.b)
          .having((c) => c.c, 'c', cubic.c)
          .having((c) => c.d, 'd', cubic.d);
    }

    test('the Material 3 curves by name are those of Easing', () {
      for (final MapEntry(key: name, value: curve) in const {
        'standard': Easing.standard,
        'standard-accelerate': Easing.standardAccelerate,
        'standard-decelerate': Easing.standardDecelerate,
        'emphasized-accelerate': Easing.emphasizedAccelerate,
        'emphasized-decelerate': Easing.emphasizedDecelerate,
      }.entries) {
        expect(ThemeValues.curveNames, contains(name));
        expect(ThemeValues.anyCurve(name), sameCubic(curve), reason: name);
      }
      expect(ThemeValues.standardEasing, sameCubic(Easing.standard));
      expect(theme(const {}).curve('standard'), sameCubic(Easing.standard));
    });
  });

  group('the icons of the Markdown view', () {
    test('copy and check are the Material Icons font\'s', () {
      expect(Icons.copy_rounded.codePoint, 0xf66c);
      expect(Icons.check_rounded.codePoint, 0xf636);
      expect(Icons.copy_rounded.fontFamily, 'MaterialIcons');
      expect(Icons.check_rounded.fontFamily, 'MaterialIcons');
    });
  });

  group('the shape scale and the elevations', () {
    test('a theme without properties leaves every component to Flutter', () {
      final made = theme(const {}).toMaterial();
      final flutter = ThemeData();
      expect(made.cardTheme, flutter.cardTheme);
      expect(made.dialogTheme, flutter.dialogTheme);
      expect(made.filledButtonTheme, flutter.filledButtonTheme);
      expect(made.inputDecorationTheme, flutter.inputDecorationTheme);
      expect(made.textTheme, flutter.textTheme);
      // The page transitions too: Flutter's own per platform, unless the
      // theme names one.
      expect(made.pageTransitionsTheme, flutter.pageTransitionsTheme);
      expect(
        theme(const {
          'motion.page-transition': 'platform',
        }).toMaterial().pageTransitionsTheme,
        flutter.pageTransitionsTheme,
      );
      expect(
        theme(const {
          'motion.page-transition': 'none',
        }).toMaterial().pageTransitionsTheme,
        isNot(flutter.pageTransitionsTheme),
      );
    });
  });
}
