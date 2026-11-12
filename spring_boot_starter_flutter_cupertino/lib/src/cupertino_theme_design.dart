import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';
import 'package:spring_boot_starter_flutter_cupertino/src/cupertino_theme_data.dart';
import 'package:spring_boot_starter_flutter_cupertino/src/seed_color_scheme.dart';

/// Cupertino's part of the themes of `spring.flutter.theme.*`: the
/// `cupertino.*` properties, the palette a seed color makes, and the iOS
/// page transition.
///
/// The starter lists it in the factories of its module, so the themes are
/// read with it from the start (the splash shows before any bean exists).
/// A test that reads themes by hand passes it:
///
/// ```dart
/// final themes = SpringThemes(
///   const {'seed-color': 'teal', 'cupertino.primary-color': '#00897B'},
///   designs: const ThemeDesigns(
///     all: [CupertinoThemeDesign()],
///     appType: 'cupertino',
///   ),
/// );
/// final ios = themes.data('light').toCupertino();
/// ```
final class CupertinoThemeDesign implements ThemeDesign {
  /// The design.
  const CupertinoThemeDesign();

  /// `cupertino`: the value of `spring.flutter.app.type` and the root of
  /// the design's theme properties.
  static const typeName = 'cupertino';

  @override
  String get appType => typeName;

  @override
  List<String> get themeProperties => const [typeName];

  /// The variants of Material 3's palettes, as Flutter names them:
  /// `tonalSpot`, `fidelity`, `monochrome`, `neutral`, `vibrant`,
  /// `expressive`, `content`, `rainbow`, `fruitSalad`.
  @override
  List<String> get schemeVariants => SeedColorScheme.variants;

  /// The Material 3 palette of [spec]'s seed color, the one a Material
  /// app has from the same properties.
  @override
  SpringColorScheme colorScheme(ColorSchemeSpec spec) =>
      SeedColorScheme.of(spec);

  /// The iOS slide for `cupertino`; `null` for the others.
  @override
  PageTransitionsBuilder? pageTransition(PageTransitionType type) =>
      type == PageTransitionType.cupertino
      ? const CupertinoPageTransitionsBuilder()
      : null;

  /// Makes the `CupertinoThemeData` of [theme], which reads every
  /// `cupertino.*` value and refuses a key it does not know.
  @override
  void check(SpringThemeData theme) => theme.toCupertino();
}
