import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';

/// Carries a [SpringThemeData] inside Material's `ThemeData`, among its
/// `extensions`.
///
/// Every `ThemeData` made from the properties has one, so code that has
/// only Material's theme at hand still reaches the values Material has no
/// place for (spacing, tokens, the `code` style). Inside the app,
/// `SpringTheme.of(context)` is shorter.
///
/// ```dart
/// // In a widget that only knows Material's theme.
/// final spring =
///     Theme.of(context).extension<SpringThemeExtension>()!.data;
/// final gap = spring.space('s');
/// ```
final class SpringThemeExtension extends ThemeExtension<SpringThemeExtension> {
  /// The extension carrying [data].
  SpringThemeExtension(this.data);

  /// The theme the `ThemeData` was made from.
  final SpringThemeData data;

  @override
  SpringThemeExtension copyWith() => this;

  @override
  SpringThemeExtension lerp(SpringThemeExtension? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
