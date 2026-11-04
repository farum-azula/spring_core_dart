import 'package:flutter/animation.dart' show Curve;
import 'package:flutter/painting.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_background.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_loader.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_splash.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_styles.dart';

/// Reads the values of the keys that the generated `context.theme` fixes
/// (`main.spring.dart`), from a [SpringThemeData] at the moment of the
/// call, so a switched or refreshed theme gives its own values.
///
/// Application code uses `context.theme.colors.surface`, not this class;
/// the key names are those of the properties (`surface-container-low`).
///
/// ```dart
/// final values = ThemeKeyReader(SpringTheme.of(context));
/// values.color('surface-container-low');
/// values.spacing('m');
/// values.tokenColor('brand.accent');
/// ```
final class ThemeKeyReader {
  /// A reader of [theme]. With [reduceMotion] (the system asks for less
  /// motion, `MediaQuery.disableAnimations`) every [motionDuration] is
  /// zero.
  const ThemeKeyReader(this.theme, {this.reduceMotion = false});

  /// The theme the values come from.
  final SpringThemeData theme;

  /// Whether the motion durations read as zero.
  final bool reduceMotion;

  /// The color `colors.<key>`: the theme's own value, else the Material
  /// role of that name from the theme's color scheme. Throws a
  /// [StateError] for a name that is neither declared in this theme nor a
  /// Material role.
  Color color(String key) =>
      theme.role(key) ??
      theme.colors[_canonical(key)] ??
      (throw StateError(
        "Theme '${theme.name}' has no color '$key' "
        '(spring.flutter.theme.colors.$key).',
      ));

  /// The size `spacing.<key>` of the theme.
  double spacing(String key) => theme.space(key);

  /// The text style `typography.<key>` of the theme.
  TextStyle textStyle(String key) => theme.textStyle(key);

  /// The color token `tokens.<group>.<key>`; [path] is `group.key`.
  Color tokenColor(String path) =>
      theme.tokenColor(path) ?? _missing(path, 'a color');

  /// The number token `tokens.<group>.<key>`.
  double tokenNumber(String path) =>
      theme.tokenNumber(path) ?? _missing(path, 'a number');

  /// The text token `tokens.<group>.<key>`.
  String token(String path) => theme.token(path) ?? _missing(path, 'a value');

  /// The color list token `tokens.<path>`.
  List<Color> tokenColors(String path) =>
      theme.tokenColors(path) ?? _missing(path, 'a list of colors');

  /// The number list token `tokens.<path>`.
  List<double> tokenNumbers(String path) =>
      theme.tokenNumbers(path) ?? _missing(path, 'a list of numbers');

  /// The text list token `tokens.<path>`.
  List<String> tokenTexts(String path) =>
      theme.tokenTexts(path) ?? _missing(path, 'a list');

  /// The duration token `tokens.<path>`.
  Duration tokenDuration(String path) =>
      theme.tokenDuration(path) ?? _missing(path, 'a duration');

  /// The style `styles.<name>`. Throws a [StateError] for a missing one.
  StateStyle style(String name) =>
      theme.styles[_canonical(name)] ??
      (throw StateError(
        "Theme '${theme.name}' has no style '$name' "
        '(spring.flutter.theme.styles.$name).',
      ));

  /// The duration `motion.durations.<name>`;
  /// zero when [reduceMotion]. `short`, `medium` and `long` have defaults.
  Duration motionDuration(String name) {
    final key = _canonical(name);
    final duration =
        theme.durations[key] ??
        (SpringThemeData.defaultDurations[key] ??
            (throw StateError(
              "Theme '${theme.name}' has no motion duration '$name' "
              '(spring.flutter.theme.motion.durations.$name)'
              '${didYouMean(name, [...theme.durations.keys, ...SpringThemeData.defaultDurations.keys])}.',
            )));
    return reduceMotion ? Duration.zero : duration;
  }

  /// The curve `motion.curves.<name>`.
  Curve motionCurve(String name) =>
      theme.curves[_canonical(name)] ??
      (throw StateError(
        "Theme '${theme.name}' has no motion curve '$name' "
        '(spring.flutter.theme.motion.curves.$name).',
      ));

  /// The animation `animations.<name>`.
  AnimationSpec animation(String name) =>
      theme.animations[_canonical(name)] ??
      (throw StateError(
        "Theme '${theme.name}' has no animation '$name' "
        '(spring.flutter.theme.animations.$name).',
      ));

  /// The theme's `background`. Throws a [StateError] when the theme has
  /// none.
  ThemeBackgroundData background() =>
      theme.background ??
      (throw StateError(
        "Theme '${theme.name}' has no background "
        '(spring.flutter.theme.background).',
      ));

  /// The loader `loaders.<name>` (`-`, `_` and case do not matter).
  /// Throws a [StateError] for a missing one.
  ThemeLoaderSpec loader(String name) =>
      theme.loaders[_canonical(name)] ??
      (throw StateError(
        "Theme '${theme.name}' has no loader '$name' "
        '(spring.flutter.theme.loaders.$name)'
        '${didYouMean(name, theme.loaders.keys.toList())}.',
      ));

  /// The theme's `splash` (a map). Throws a [StateError] when the theme
  /// has none.
  ThemeSplashData splash() =>
      theme.splash ??
      (throw StateError(
        "Theme '${theme.name}' has no splash "
        '(spring.flutter.theme.splash).',
      ));

  /// The image token `tokens.<group>.<key>`: a token that is a map with
  /// `source`.
  ThemeImage tokenImage(String path) =>
      theme.tokenImage(path) ?? _missing(path, 'an image (a map with source)');

  Never _missing(String path, String kind) => throw StateError(
    "Theme '${theme.name}' has no token '$path' as $kind "
    '(spring.flutter.theme.tokens.$path).',
  );

  static String _canonical(String name) =>
      name.toLowerCase().replaceAll('-', '').replaceAll('_', '');
}
