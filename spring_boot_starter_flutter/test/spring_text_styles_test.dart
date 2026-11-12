// The text styles of a theme in an app without a design library:
// SpringThemeData.textStyle (the platform's font, the palette's on-surface
// color, what typography.* sets), localizedTextStyle (the sizes of the
// Material 3 type scale for a script) and the table itself,
// SpringTypeScale.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

// The 15 styles as apps write them, in the order of the scale.
const _styles = [
  'displayLarge', 'displayMedium', 'displaySmall', //
  'headlineLarge', 'headlineMedium', 'headlineSmall', //
  'titleLarge', 'titleMedium', 'titleSmall', //
  'bodyLarge', 'bodyMedium', 'bodySmall', //
  'labelLarge', 'labelMedium', 'labelSmall',
];

// The Material 3 type scale: size, weight, letter spacing, line height.
const _scale = <String, (double, FontWeight, double, double)>{
  'displayLarge': (57, FontWeight.w400, -0.25, 1.12),
  'displayMedium': (45, FontWeight.w400, 0, 1.16),
  'displaySmall': (36, FontWeight.w400, 0, 1.22),
  'headlineLarge': (32, FontWeight.w400, 0, 1.25),
  'headlineMedium': (28, FontWeight.w400, 0, 1.29),
  'headlineSmall': (24, FontWeight.w400, 0, 1.33),
  'titleLarge': (22, FontWeight.w400, 0, 1.27),
  'titleMedium': (16, FontWeight.w500, 0.15, 1.5),
  'titleSmall': (14, FontWeight.w500, 0.1, 1.43),
  'bodyLarge': (16, FontWeight.w400, 0.5, 1.5),
  'bodyMedium': (14, FontWeight.w400, 0.25, 1.43),
  'bodySmall': (12, FontWeight.w400, 0.4, 1.33),
  'labelLarge': (14, FontWeight.w500, 0.1, 1.43),
  'labelMedium': (12, FontWeight.w500, 0.5, 1.33),
  'labelSmall': (11, FontWeight.w500, 0.5, 1.45),
};

// The styles Apple's display font is for on iOS; the text font the rest.
const _iosDisplay = {
  'displayLarge', 'displayMedium', 'displaySmall', //
  'headlineLarge', 'headlineMedium', 'headlineSmall', //
  'titleLarge',
};

const _linuxFallback = [
  'Ubuntu',
  'Adwaita Sans',
  'Cantarell',
  'DejaVu Sans',
  'Liberation Sans',
  'Arial',
];

String _family(TargetPlatform platform, String style) => switch (platform) {
  TargetPlatform.android ||
  TargetPlatform.fuchsia ||
  TargetPlatform.linux => 'Roboto',
  TargetPlatform.windows => 'Segoe UI',
  TargetPlatform.macOS => '.AppleSystemUIFont',
  TargetPlatform.iOS =>
    _iosDisplay.contains(style)
        ? 'CupertinoSystemDisplay'
        : 'CupertinoSystemText',
};

/// The theme [name] of [properties], made on [platform].
SpringThemeData themeOn(
  TargetPlatform platform, [
  Map<String, String> properties = const {},
  String name = 'light',
]) {
  debugDefaultTargetPlatformOverride = platform;
  try {
    return SpringThemes(properties).data(name);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

SpringThemeData theme([
  Map<String, String> properties = const {},
  String name = 'light',
]) => themeOn(TargetPlatform.android, properties, name);

void main() {
  group('textStyle', () {
    test('the fonts of the platform the theme was made on', () {
      for (final platform in TargetPlatform.values) {
        final t = themeOn(platform);
        // Read later, on the platform of the test: the fonts stay those of
        // the platform the theme was made on.
        expect(debugDefaultTargetPlatformOverride, isNull);
        for (final style in _styles) {
          final made = t.textStyle(style);
          expect(
            made.fontFamily,
            _family(platform, style),
            reason: '${platform.name} $style',
          );
          expect(
            made.fontFamilyFallback,
            platform == TargetPlatform.linux ? _linuxFallback : isNull,
            reason: '${platform.name} $style',
          );
        }
      }
    });

    test('the on-surface color of the palette, and no size of its own', () {
      for (final (properties, name, color) in [
        (const <String, String>{}, 'light', const Color(0xFF1D1B20)),
        (const <String, String>{}, 'dark', const Color(0xFFE6E0E9)),
        (
          const {'colors.on-surface': '#112233'},
          'light',
          const Color(0xFF112233),
        ),
      ]) {
        final t = theme(properties, name);
        for (final style in _styles) {
          final made = t.textStyle(style);
          expect(made.color, color, reason: '$name $style');
          expect(made.color, t.colorScheme.onSurface);
          expect(made.decoration, TextDecoration.none, reason: style);
          expect(made.decorationColor, color, reason: style);
          expect(made.inherit, isTrue, reason: style);
          expect(made.fontSize, isNull, reason: style);
          expect(made.fontWeight, isNull, reason: style);
          expect(made.height, isNull, reason: style);
          expect(made.letterSpacing, isNull, reason: style);
        }
      }
    });

    test('a name in any spelling, made once; another name is refused', () {
      final t = theme();
      final title = t.textStyle('titleLarge');
      for (final name in ['titlelarge', 'title-large', 'TITLE_LARGE']) {
        expect(t.textStyle(name), same(title), reason: name);
      }
      for (final name in ['huge', 'title', 'titleHuge', '']) {
        expect(
          () => t.textStyle(name),
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.invalidValue, 'value', name)
                .having(
                  (e) => e.message,
                  'message',
                  'a TextTheme style or code',
                ),
          ),
          reason: name,
        );
      }
    });

    test('typography.*: every style\'s size, weight, height, letter '
        'spacing and family', () {
      final t = themeOn(TargetPlatform.iOS, {
        for (final (index, style) in _styles.indexed) ...{
          'typography.$style.size': '${index + 10}',
          'typography.$style.weight': 'medium',
          'typography.$style.height': '1.4',
          'typography.$style.letter-spacing': '0.3',
          'typography.$style.font-family': 'F$style',
        },
      });
      for (final (index, style) in _styles.indexed) {
        final made = t.textStyle(style);
        expect(made.fontSize, index + 10, reason: style);
        expect(made.fontWeight, FontWeight.w500, reason: style);
        expect(made.fontVariations, const [
          FontVariation('wght', 500),
        ], reason: style);
        expect(made.height, 1.4, reason: style);
        expect(made.letterSpacing, 0.3, reason: style);
        expect(made.fontFamily, 'F$style', reason: style);
        expect(made.color, const Color(0xFF1D1B20), reason: style);
      }
    });

    test('the theme\'s family and fallbacks in place of the platform\'s', () {
      final t = themeOn(TargetPlatform.linux, const {
        'typography.font-family': 'Inter',
        'typography.font-family-fallback': 'Noto Sans JP, Noto Color Emoji',
        'typography.display.font-family': 'Playfair Display',
        'typography.display.weight': 'bold',
        'typography.display-small.size': '30',
        'typography.title-large.weight': '600',
      });
      for (final style in _styles) {
        final made = t.textStyle(style);
        expect(
          made.fontFamily,
          style.startsWith('display') ? 'Playfair Display' : 'Inter',
          reason: style,
        );
        expect(made.fontFamilyFallback, [
          'Noto Sans JP',
          'Noto Color Emoji',
        ], reason: style);
      }
      expect(t.textStyle('displayLarge').fontWeight, FontWeight.w700);
      expect(t.textStyle('displayLarge').fontSize, isNull);
      expect(t.textStyle('displaySmall').fontSize, 30);
      expect(t.textStyle('titleLarge').fontWeight, FontWeight.w600);
      expect(t.textStyle('bodyMedium').fontWeight, isNull);
    });

    test('code: over body medium, with the palette\'s color', () {
      final t = themeOn(TargetPlatform.macOS, const {
        'typography.body-medium.letter-spacing': '0.4',
        'typography.code.size': '13',
        'typography.code.font-family': 'JetBrains Mono',
        'themes.night.brightness': 'dark',
      }, 'night');
      final code = t.textStyle('code');
      expect(code.fontFamily, 'JetBrains Mono');
      expect(code.fontSize, 13);
      expect(code.letterSpacing, 0.4);
      expect(code.color, const Color(0xFFE6E0E9));
      expect(code.fontFamilyFallback, isEmpty);
      expect(t.textStyle('CODE').fontFamily, 'JetBrains Mono');
    });
  });

  group('the app\'s own color and text style (a WidgetsApp\'s)', () {
    test('the primary color, and body medium on the surface', () {
      final plain = theme();
      expect(plain.appColor, const Color(0xFF6750A4));
      expect(plain.widgetsTextStyle.fontFamily, 'Roboto');
      expect(plain.widgetsTextStyle.color, const Color(0xFF1D1B20));

      final t = theme(const {
        'colors.primary': 'teal',
        'colors.on-surface': '#101010',
        'typography.font-family': 'Inter',
        'typography.body-medium.size': '15',
        'typography.body-large.size': '99',
      });
      expect(t.appColor, const Color(0xFF009688));
      expect(t.appColor, t.colorScheme.primary);
      expect(t.widgetsTextStyle.fontFamily, 'Inter');
      expect(t.widgetsTextStyle.fontSize, 15);
      expect(t.widgetsTextStyle.color, const Color(0xFF101010));
      expect(t.widgetsTextStyle.color, t.colorScheme.onSurface);
    });
  });

  group('localizedTextStyle', () {
    test('the sizes of the Material 3 type scale, in the theme\'s font and '
        'color', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        final t = themeOn(platform);
        for (final style in _styles) {
          final (size, weight, spacing, height) = _scale[style]!;
          final made = t.localizedTextStyle(style, TextScript.englishLike);
          final reason = '${platform.name} $style';
          expect(made.fontSize, size, reason: reason);
          expect(made.fontWeight, weight, reason: reason);
          expect(made.letterSpacing, spacing, reason: reason);
          expect(made.height, height, reason: reason);
          expect(made.textBaseline, TextBaseline.alphabetic, reason: reason);
          expect(
            made.leadingDistribution,
            TextLeadingDistribution.even,
            reason: reason,
          );
          expect(made.fontFamily, _family(platform, style), reason: reason);
          expect(made.color, const Color(0xFF1D1B20), reason: reason);
          expect(made.decoration, TextDecoration.none, reason: reason);
        }
      }
    });

    test('per script: the ideographic baseline for dense writing', () {
      final t = theme();
      for (final style in _styles) {
        final (size, weight, spacing, height) = _scale[style]!;
        for (final (script, baseline) in [
          (TextScript.englishLike, TextBaseline.alphabetic),
          (TextScript.dense, TextBaseline.ideographic),
          (TextScript.tall, TextBaseline.alphabetic),
        ]) {
          final made = t.localizedTextStyle(style, script);
          final reason = '${script.name} $style';
          expect(made.textBaseline, baseline, reason: reason);
          expect(made.fontSize, size, reason: reason);
          expect(made.fontWeight, weight, reason: reason);
          expect(made.letterSpacing, spacing, reason: reason);
          expect(made.height, height, reason: reason);
        }
      }
    });

    test('what typography.* sets wins over the scale, the rest is the '
        'scale\'s', () {
      final t = theme(const {
        'typography.title-large.size': '30',
        'typography.title-large.weight': 'bold',
        'typography.body.height': '1.8',
        'typography.label-small.letter-spacing': '1',
      });
      final title = t.localizedTextStyle('title-large', TextScript.dense);
      expect(title.fontSize, 30);
      expect(title.fontWeight, FontWeight.w700);
      expect(title.height, 1.27);
      expect(title.letterSpacing, 0);
      expect(title.textBaseline, TextBaseline.ideographic);
      final body = t.localizedTextStyle('bodyLarge', TextScript.englishLike);
      expect(body.fontSize, 16);
      expect(body.height, 1.8);
      final label = t.localizedTextStyle('labelSmall', TextScript.tall);
      expect(label.fontSize, 11);
      expect(label.letterSpacing, 1);
      expect(label.fontWeight, FontWeight.w500);
    });

    test('code has no place in the scale; another name is refused', () {
      final t = theme(const {'typography.code.size': '13'});
      for (final script in TextScript.values) {
        final code = t.localizedTextStyle('code', script);
        expect(code.fontSize, 13, reason: script.name);
        expect(code.fontFamily, 'monospace', reason: script.name);
        expect(code.height, isNull, reason: script.name);
      }
      expect(
        () => t.localizedTextStyle('huge', TextScript.englishLike),
        throwsArgumentError,
      );
    });
  });

  group('SpringTypeScale', () {
    test('scriptOf: dense and tall languages, Latin-like for the rest', () {
      for (final (languages, script) in [
        (['ja', 'zh', 'ko'], TextScript.dense),
        (['ar', 'fa', 'hi', 'th', 'bn', 'ur'], TextScript.tall),
        (['en', 'de', 'ru', 'el', 'he', 'pt'], TextScript.englishLike),
      ]) {
        for (final language in languages) {
          expect(
            SpringTypeScale.scriptOf(Locale(language)),
            script,
            reason: language,
          );
        }
      }
      expect(
        SpringTypeScale.scriptOf(const Locale('zh', 'TW')),
        TextScript.dense,
      );
      expect(
        SpringTypeScale.scriptOf(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        ),
        TextScript.dense,
      );
      expect(SpringTypeScale.scriptOf(null), TextScript.englishLike);
    });

    test('geometry: a style by its canonical name, for every script', () {
      for (final script in TextScript.values) {
        for (final style in _styles) {
          final (size, weight, spacing, height) = _scale[style]!;
          final geometry = SpringTypeScale.geometry(
            style.toLowerCase(),
            script,
          )!;
          final reason = '${script.name} $style';
          expect(geometry.inherit, isFalse, reason: reason);
          expect(geometry.fontSize, size, reason: reason);
          expect(geometry.fontWeight, weight, reason: reason);
          expect(geometry.letterSpacing, spacing, reason: reason);
          expect(geometry.height, height, reason: reason);
          // Sizes only: the font and the color are the theme's.
          expect(geometry.fontFamily, isNull, reason: reason);
          expect(geometry.color, isNull, reason: reason);
        }
        expect(SpringTypeScale.geometry('code', script), isNull);
        expect(SpringTypeScale.geometry('titleLarge', script), isNull);
        expect(SpringTypeScale.geometry('title-large', script), isNull);
      }
    });

    test('the default fonts of every platform', () {
      for (final platform in TargetPlatform.values) {
        for (final style in _styles) {
          expect(
            SpringTypeScale.fontFamily(platform, style.toLowerCase()),
            _family(platform, style),
            reason: '${platform.name} $style',
          );
        }
        expect(
          SpringTypeScale.fontFamilyFallback(platform),
          platform == TargetPlatform.linux ? _linuxFallback : isNull,
          reason: platform.name,
        );
      }
    });
  });
}
