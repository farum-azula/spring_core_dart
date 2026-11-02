import 'package:flutter/painting.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';

/// Reads the values of the keys that the generated `context.theme` fixes
/// (`lib/spring_keys.dart`), from a [SpringThemeData] at the moment of the
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
  /// A reader of [theme].
  const ThemeKeyReader(this.theme);

  /// The theme the values come from.
  final SpringThemeData theme;

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

  Never _missing(String path, String kind) => throw StateError(
    "Theme '${theme.name}' has no token '$path' as $kind "
    '(spring.flutter.theme.tokens.$path).',
  );

  static String _canonical(String name) =>
      name.toLowerCase().replaceAll('-', '').replaceAll('_', '');
}
