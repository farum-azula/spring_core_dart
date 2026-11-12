import 'package:flutter/widgets.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show
        DynamicColor,
        DynamicScheme,
        Hct,
        MaterialDynamicColors,
        SchemeContent,
        SchemeExpressive,
        SchemeFidelity,
        SchemeFruitSalad,
        SchemeMonochrome,
        SchemeNeutral,
        SchemeRainbow,
        SchemeTonalSpot,
        SchemeVibrant;
import 'package:spring_boot_starter_flutter/theme_design.dart';

typedef _SchemeOf = DynamicScheme Function({
  required Hct sourceColorHct,
  required bool isDark,
  required double contrastLevel,
});

/// The Material 3 palette of a seed color, made without Material's
/// widgets: the colors Flutter's `ColorScheme.fromSeed` gives, from the
/// same color math (`material_color_utilities`).
///
/// A theme of a Cupertino app has all the roles of a palette
/// (`SpringTheme.of(context).colorScheme.surfaceContainer`) from its
/// `seed-color`, and the same ones a Material app has from that seed.
abstract final class SeedColorScheme {
  /// The seed of a palette whose theme sets a variant or a contrast but
  /// no `seed-color`: the one of Material 3's baseline.
  static const defaultSeed = Color(0xFF6750A4);

  /// The variant of a palette whose theme sets none.
  static const defaultVariant = 'tonalSpot';

  // The algorithm of each variant, by the name Flutter's
  // `DynamicSchemeVariant` has for it.
  static const _variants = <String, _SchemeOf>{
    'tonalSpot': SchemeTonalSpot.new,
    'fidelity': SchemeFidelity.new,
    'monochrome': SchemeMonochrome.new,
    'neutral': SchemeNeutral.new,
    'vibrant': SchemeVibrant.new,
    'expressive': SchemeExpressive.new,
    'content': SchemeContent.new,
    'rainbow': SchemeRainbow.new,
    'fruitSalad': SchemeFruitSalad.new,
  };

  /// The names `scheme-variant` may have, in Flutter's spelling and
  /// order.
  static const variants = [
    'tonalSpot',
    'fidelity',
    'monochrome',
    'neutral',
    'vibrant',
    'expressive',
    'content',
    'rainbow',
    'fruitSalad',
  ];

  // The color of each role of a palette, as `ColorScheme.fromSeed` takes
  // them: its surface tint is the primary color.
  static final _roles = <String, DynamicColor>{
    'primary': MaterialDynamicColors.primary,
    'onPrimary': MaterialDynamicColors.onPrimary,
    'primaryContainer': MaterialDynamicColors.primaryContainer,
    'onPrimaryContainer': MaterialDynamicColors.onPrimaryContainer,
    'primaryFixed': MaterialDynamicColors.primaryFixed,
    'primaryFixedDim': MaterialDynamicColors.primaryFixedDim,
    'onPrimaryFixed': MaterialDynamicColors.onPrimaryFixed,
    'onPrimaryFixedVariant': MaterialDynamicColors.onPrimaryFixedVariant,
    'secondary': MaterialDynamicColors.secondary,
    'onSecondary': MaterialDynamicColors.onSecondary,
    'secondaryContainer': MaterialDynamicColors.secondaryContainer,
    'onSecondaryContainer': MaterialDynamicColors.onSecondaryContainer,
    'secondaryFixed': MaterialDynamicColors.secondaryFixed,
    'secondaryFixedDim': MaterialDynamicColors.secondaryFixedDim,
    'onSecondaryFixed': MaterialDynamicColors.onSecondaryFixed,
    'onSecondaryFixedVariant': MaterialDynamicColors.onSecondaryFixedVariant,
    'tertiary': MaterialDynamicColors.tertiary,
    'onTertiary': MaterialDynamicColors.onTertiary,
    'tertiaryContainer': MaterialDynamicColors.tertiaryContainer,
    'onTertiaryContainer': MaterialDynamicColors.onTertiaryContainer,
    'tertiaryFixed': MaterialDynamicColors.tertiaryFixed,
    'tertiaryFixedDim': MaterialDynamicColors.tertiaryFixedDim,
    'onTertiaryFixed': MaterialDynamicColors.onTertiaryFixed,
    'onTertiaryFixedVariant': MaterialDynamicColors.onTertiaryFixedVariant,
    'error': MaterialDynamicColors.error,
    'onError': MaterialDynamicColors.onError,
    'errorContainer': MaterialDynamicColors.errorContainer,
    'onErrorContainer': MaterialDynamicColors.onErrorContainer,
    'surface': MaterialDynamicColors.surface,
    'onSurface': MaterialDynamicColors.onSurface,
    'onSurfaceVariant': MaterialDynamicColors.onSurfaceVariant,
    'surfaceDim': MaterialDynamicColors.surfaceDim,
    'surfaceBright': MaterialDynamicColors.surfaceBright,
    'surfaceContainerLowest': MaterialDynamicColors.surfaceContainerLowest,
    'surfaceContainerLow': MaterialDynamicColors.surfaceContainerLow,
    'surfaceContainer': MaterialDynamicColors.surfaceContainer,
    'surfaceContainerHigh': MaterialDynamicColors.surfaceContainerHigh,
    'surfaceContainerHighest': MaterialDynamicColors.surfaceContainerHighest,
    'surfaceTint': MaterialDynamicColors.primary,
    'inverseSurface': MaterialDynamicColors.inverseSurface,
    'onInverseSurface': MaterialDynamicColors.inverseOnSurface,
    'inversePrimary': MaterialDynamicColors.inversePrimary,
    'outline': MaterialDynamicColors.outline,
    'outlineVariant': MaterialDynamicColors.outlineVariant,
    'shadow': MaterialDynamicColors.shadow,
    'scrim': MaterialDynamicColors.scrim,
  };

  /// The palette of [spec]: every role, from its seed color
  /// ([defaultSeed] when it has none), its variant ([defaultVariant]) and
  /// its contrast (0). Throws an `ArgumentError` for a variant that is not
  /// one of [variants].
  static SpringColorScheme of(ColorSchemeSpec spec) {
    final scheme = _schemeOf(spec.schemeVariant ?? defaultVariant)(
      sourceColorHct: Hct.fromInt((spec.seedColor ?? defaultSeed).toARGB32()),
      isDark: spec.brightness == Brightness.dark,
      contrastLevel: spec.contrast ?? 0,
    );
    return SpringColorScheme(spec.brightness, {
      for (final MapEntry(key: role, value: color) in _roles.entries)
        role: Color(color.getArgb(scheme)),
    });
  }

  static _SchemeOf _schemeOf(String variant) {
    final wanted = ThemeValues.canonical(variant);
    for (final MapEntry(key: name, value: scheme) in _variants.entries) {
      if (ThemeValues.canonical(name) == wanted) {
        return scheme;
      }
    }
    throw ArgumentError.value(
      variant,
      'schemeVariant',
      'one of ${variants.join(', ')}',
    );
  }
}
