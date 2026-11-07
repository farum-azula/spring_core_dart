import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart'
    show textStyleNames;
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// How the frame meter looks, the theme's `frame-meter` (the meter is on
/// with `spring.flutter.frame-meter.enabled`). A value the theme does not
/// set comes from its colors and typography.
///
/// ```yaml
/// frame-meter:
///   background: { color: $colors.surface, alpha: 85% }
///   foreground: $colors.on-surface
///   good: $neon.green
///   warning: $neon.yellow
///   bad: $colors.error
///   text-style: label-small
/// ```
@immutable
final class FrameMeterTheme {
  /// A look of these values; `null` ones come from the theme.
  const FrameMeterTheme({
    this.background,
    this.foreground,
    this.good,
    this.warning,
    this.bad,
    this.textStyle,
  });

  /// The panel's fill; the surface at 85% by default.
  final Color? background;

  /// The text; the color on the surface by default.
  final Color? foreground;

  /// A frame within the budget; the primary color by default.
  final Color? good;

  /// A frame up to twice the budget; the tertiary color by default.
  final Color? warning;

  /// A frame over twice the budget; the error color by default.
  final Color? bad;

  /// The typography style of the text (`label-small`), by canonical name;
  /// `label-small` by default.
  final String? textStyle;

  static const _keys = [
    'background',
    'foreground',
    'good',
    'warning',
    'bad',
    'text-style',
  ];

  /// Reads `frame-meter` of [p]; every value `null` when there is none.
  static FrameMeterTheme parse(ThemeProperties p) {
    const path = 'framemeter';
    if (p.children(path).isEmpty) {
      return const FrameMeterTheme();
    }
    checkThemeKeys(p, path, _keys, 'the frame meter');
    return FrameMeterTheme(
      background: p.color('$path.background'),
      foreground: p.color('$path.foreground'),
      good: p.color('$path.good'),
      warning: p.color('$path.warning'),
      bad: p.color('$path.bad'),
      textStyle: p.read(
        '$path.textstyle',
        (v) => switch (ThemeValues.canonical(v)) {
          final name when name == 'code' || textStyleNames.contains(name) =>
            name,
          _ => null,
        },
        'a text style of the typography (label-small, body-medium...) '
            'or code',
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FrameMeterTheme &&
      other.background == background &&
      other.foreground == foreground &&
      other.good == good &&
      other.warning == warning &&
      other.bad == bad &&
      other.textStyle == textStyle;

  @override
  int get hashCode =>
      Object.hash(background, foreground, good, warning, bad, textStyle);
}
