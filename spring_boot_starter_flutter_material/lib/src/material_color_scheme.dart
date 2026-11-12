import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';

/// Material's palette as the starter's own [SpringColorScheme], which
/// knows no design library: the same 46 roles under the same names.
///
/// ```dart
/// final palette = ColorScheme.fromSeed(seedColor: Colors.teal).toSpring();
/// ```
extension SpringColorSchemeOfMaterial on ColorScheme {
  /// The roles of this palette as a [SpringColorScheme].
  SpringColorScheme toSpring() => SpringColorScheme(brightness, {
    'primary': primary,
    'onprimary': onPrimary,
    'primarycontainer': primaryContainer,
    'onprimarycontainer': onPrimaryContainer,
    'primaryfixed': primaryFixed,
    'primaryfixeddim': primaryFixedDim,
    'onprimaryfixed': onPrimaryFixed,
    'onprimaryfixedvariant': onPrimaryFixedVariant,
    'secondary': secondary,
    'onsecondary': onSecondary,
    'secondarycontainer': secondaryContainer,
    'onsecondarycontainer': onSecondaryContainer,
    'secondaryfixed': secondaryFixed,
    'secondaryfixeddim': secondaryFixedDim,
    'onsecondaryfixed': onSecondaryFixed,
    'onsecondaryfixedvariant': onSecondaryFixedVariant,
    'tertiary': tertiary,
    'ontertiary': onTertiary,
    'tertiarycontainer': tertiaryContainer,
    'ontertiarycontainer': onTertiaryContainer,
    'tertiaryfixed': tertiaryFixed,
    'tertiaryfixeddim': tertiaryFixedDim,
    'ontertiaryfixed': onTertiaryFixed,
    'ontertiaryfixedvariant': onTertiaryFixedVariant,
    'error': error,
    'onerror': onError,
    'errorcontainer': errorContainer,
    'onerrorcontainer': onErrorContainer,
    'surface': surface,
    'onsurface': onSurface,
    'onsurfacevariant': onSurfaceVariant,
    'surfacedim': surfaceDim,
    'surfacebright': surfaceBright,
    'surfacecontainerlowest': surfaceContainerLowest,
    'surfacecontainerlow': surfaceContainerLow,
    'surfacecontainer': surfaceContainer,
    'surfacecontainerhigh': surfaceContainerHigh,
    'surfacecontainerhighest': surfaceContainerHighest,
    'surfacetint': surfaceTint,
    'inversesurface': inverseSurface,
    'oninversesurface': onInverseSurface,
    'inverseprimary': inversePrimary,
    'outline': outline,
    'outlinevariant': outlineVariant,
    'shadow': shadow,
    'scrim': scrim,
  });

  /// This palette with every role of [roles] in place of its own. What
  /// Material's palette has besides the 46 roles (the colors it keeps for
  /// older code) stays.
  ColorScheme withRolesOf(SpringColorScheme roles) => copyWith(
    brightness: roles.brightness,
    primary: roles.primary,
    onPrimary: roles.onPrimary,
    primaryContainer: roles.primaryContainer,
    onPrimaryContainer: roles.onPrimaryContainer,
    primaryFixed: roles.primaryFixed,
    primaryFixedDim: roles.primaryFixedDim,
    onPrimaryFixed: roles.onPrimaryFixed,
    onPrimaryFixedVariant: roles.onPrimaryFixedVariant,
    secondary: roles.secondary,
    onSecondary: roles.onSecondary,
    secondaryContainer: roles.secondaryContainer,
    onSecondaryContainer: roles.onSecondaryContainer,
    secondaryFixed: roles.secondaryFixed,
    secondaryFixedDim: roles.secondaryFixedDim,
    onSecondaryFixed: roles.onSecondaryFixed,
    onSecondaryFixedVariant: roles.onSecondaryFixedVariant,
    tertiary: roles.tertiary,
    onTertiary: roles.onTertiary,
    tertiaryContainer: roles.tertiaryContainer,
    onTertiaryContainer: roles.onTertiaryContainer,
    tertiaryFixed: roles.tertiaryFixed,
    tertiaryFixedDim: roles.tertiaryFixedDim,
    onTertiaryFixed: roles.onTertiaryFixed,
    onTertiaryFixedVariant: roles.onTertiaryFixedVariant,
    error: roles.error,
    onError: roles.onError,
    errorContainer: roles.errorContainer,
    onErrorContainer: roles.onErrorContainer,
    surface: roles.surface,
    onSurface: roles.onSurface,
    onSurfaceVariant: roles.onSurfaceVariant,
    surfaceDim: roles.surfaceDim,
    surfaceBright: roles.surfaceBright,
    surfaceContainerLowest: roles.surfaceContainerLowest,
    surfaceContainerLow: roles.surfaceContainerLow,
    surfaceContainer: roles.surfaceContainer,
    surfaceContainerHigh: roles.surfaceContainerHigh,
    surfaceContainerHighest: roles.surfaceContainerHighest,
    surfaceTint: roles.surfaceTint,
    inverseSurface: roles.inverseSurface,
    onInverseSurface: roles.onInverseSurface,
    inversePrimary: roles.inversePrimary,
    outline: roles.outline,
    outlineVariant: roles.outlineVariant,
    shadow: roles.shadow,
    scrim: roles.scrim,
  );
}

/// The palettes Material makes: its baseline, and the one of a seed color.
abstract final class MaterialColorSchemes {
  /// The seed of a palette whose theme sets a variant or a contrast and no
  /// `seed-color`: the purple Material 3's baseline is made from.
  static const defaultSeed = Color(0xFF6750A4);

  /// The palette [spec] describes, made by Material 3's algorithm
  /// (`ColorScheme.fromSeed`); the seed is [defaultSeed], the variant
  /// `tonalSpot` and the contrast 0 where [spec] sets none.
  static ColorScheme fromSeed(ColorSchemeSpec spec) => ColorScheme.fromSeed(
    seedColor: spec.seedColor ?? defaultSeed,
    brightness: spec.brightness,
    dynamicSchemeVariant: switch (spec.schemeVariant) {
      final variant? =>
        ThemeValues.enumValue(DynamicSchemeVariant.values, variant) ??
            DynamicSchemeVariant.tonalSpot,
      null => DynamicSchemeVariant.tonalSpot,
    },
    contrastLevel: spec.contrast ?? 0,
  );

  /// The palette of [spec] before any role is set on it: Flutter's own
  /// Material 3 baseline (the one of `ThemeData()`, not quite the default
  /// seed's) when [spec] sets nothing, else [fromSeed].
  static ColorScheme of(ColorSchemeSpec spec) => spec.isBaseline
      ? ThemeData(brightness: spec.brightness).colorScheme
      : fromSeed(spec);
}
