import 'package:spring_core_dart_generator/src/material_color/dynamiccolor/dynamic_color.dart';
import 'package:spring_core_dart_generator/src/material_color/dynamiccolor/dynamic_scheme.dart';
import 'package:spring_core_dart_generator/src/material_color/dynamiccolor/material_dynamic_colors.dart';
import 'package:spring_core_dart_generator/src/material_color/hct/hct.dart';
import 'package:spring_core_dart_generator/src/material_color/scheme/scheme_content.dart';
import 'package:spring_core_dart_generator/src/material_color/scheme/scheme_expressive.dart';
import 'package:spring_core_dart_generator/src/material_color/scheme/scheme_fidelity.dart';
import 'package:spring_core_dart_generator/src/material_color/scheme/scheme_fruit_salad.dart';
import 'package:spring_core_dart_generator/src/material_color/scheme/scheme_monochrome.dart';
import 'package:spring_core_dart_generator/src/material_color/scheme/scheme_neutral.dart';
import 'package:spring_core_dart_generator/src/material_color/scheme/scheme_rainbow.dart';
import 'package:spring_core_dart_generator/src/material_color/scheme/scheme_tonal_spot.dart';
import 'package:spring_core_dart_generator/src/material_color/scheme/scheme_vibrant.dart';
import 'package:spring_core_dart_generator/src/material_color_values.dart';
import 'package:spring_core_dart_generator/src/theme_references.dart';
import 'package:spring_core_dart_generator/src/theme_value_syntax.dart';

/// Reads the values of one theme as the runtime does, but at build time:
/// colors (plain, `$` references, color objects, Material roles computed
/// from the seed), numbers, durations and texts. A value it cannot read
/// is `null`; the type checks of the typed keys have reported it already.
///
/// The page loader uses it, since the page is written before Flutter runs.
final class ThemeValueResolver {
  /// A resolver for [scope]; [dark] is the brightness the theme has.
  ThemeValueResolver(this.scope, {required this.dark});

  /// The theme.
  final ThemeScope scope;

  /// Whether the theme is dark.
  final bool dark;

  final _stack = <ThemeNode>[];
  DynamicScheme? _scheme;

  /// The color of [node] as `0xAARRGGBB`, or `null`.
  int? color(ThemeNode? node) {
    if (node == null || _stack.contains(node)) {
      return null;
    }
    _stack.add(node);
    try {
      if (node.entry != null && node.children.isEmpty) {
        return _colorText(node.entry!.value.trim());
      }
      final base = node.children['color'];
      if (node.entry == null && base != null) {
        var result = color(base);
        if (result == null) {
          return null;
        }
        if (node.children['mix'] case final mix?) {
          final other = color(mix.children['with']);
          final amount = percent(mix.children['amount']);
          if (other == null || amount == null) {
            return null;
          }
          result = _lerp(result, other, amount);
        }
        if (node.children['alpha'] case final alpha?) {
          final share = percent(alpha);
          if (share == null) {
            return null;
          }
          result = (result & 0x00FFFFFF) | ((share * 255).round() << 24);
        }
        return result;
      }
    } finally {
      _stack.removeLast();
    }
    return null;
  }

  int? _colorText(String value) {
    if (value.startsWith(r'$')) {
      final target = _lookup(value.substring(1));
      if (target != null) {
        return color(target);
      }
      final path = _canonicalPath(value.substring(1));
      return path.length == 2 && path[0] == 'colors' ? _role(path[1]) : null;
    }
    if (!ThemeValueSyntax.isPlainColor(value)) {
      return null;
    }
    if (value.startsWith('#')) {
      var hex = value.substring(1);
      if (hex.length == 3) {
        hex = hex.split('').map((c) => '$c$c').join();
      }
      if (hex.length == 6) {
        hex = 'FF$hex';
      }
      return int.tryParse(hex, radix: 16);
    }
    final camel = value.replaceAllMapped(
      RegExp('[-_]([a-z])'),
      (m) => m[1]!.toUpperCase(),
    );
    return materialColorValues[value] ?? materialColorValues[camel];
  }

  static List<String> _canonicalPath(String path) {
    final canon = path.split('.').map(canonicalName).toList();
    return ThemeValueSyntax.rootSections.contains(canon.first)
        ? canon
        : ['tokens', ...canon];
  }

  ThemeNode? _lookup(String path) => scope.node(_canonicalPath(path));

  /// The number of [node]: a number or a reference to one (`$spacing.m`,
  /// `$shape.medium`); `null` otherwise.
  double? number(ThemeNode? node) {
    if (node?.entry == null || node!.children.isNotEmpty) {
      return null;
    }
    if (_stack.contains(node)) {
      return null;
    }
    final value = node.entry!.value.trim();
    if (value.startsWith(r'$')) {
      final target = _lookup(value.substring(1));
      if (target != null) {
        _stack.add(node);
        try {
          return number(target);
        } finally {
          _stack.removeLast();
        }
      }
      final path = _canonicalPath(value.substring(1));
      return path.length == 2 && path[0] == 'shape' ? _shape[path[1]] : null;
    }
    return ThemeValueSyntax.isNumber(value)
        ? double.tryParse(value.toLowerCase().replaceFirst('infinity', 'inf'))
        : null;
  }

  /// A share from 0 to 1 (`12%` or `0.12`) of [node], or `null`.
  double? percent(ThemeNode? node) {
    final value = node?.entry?.value.trim();
    if (value == null || !ThemeValueSyntax.isPercent(value)) {
      return null;
    }
    return value.endsWith('%')
        ? double.parse(value.substring(0, value.length - 1)) / 100
        : double.parse(value);
  }

  /// The duration of [node] in milliseconds, or `null`.
  double? milliseconds(ThemeNode? node) {
    var value = node?.entry?.value.trim();
    if (value == null) {
      return null;
    }
    if (value.startsWith(r'$')) {
      return milliseconds(_lookup(value.substring(1)));
    }
    if (!ThemeValueSyntax.isDuration(value)) {
      return null;
    }
    value = value.toLowerCase().replaceAll(RegExp(r'\s'), '');
    const units = {'ms': 1.0, 's': 1000.0, 'm': 60000.0, 'h': 3600000.0};
    const days = 86400000.0;
    for (final unit in ['ms', 's', 'm', 'h']) {
      if (value.endsWith(unit)) {
        return double.parse(value.substring(0, value.length - unit.length)) *
            units[unit]!;
      }
    }
    return double.parse(value.substring(0, value.length - 1)) * days;
  }

  /// The text of [node]: the value with `$$` read as `$`; a reference to a
  /// value stands for that value's text.
  String? text(ThemeNode? node) {
    final value = node?.entry?.value.trim();
    if (value == null || node!.children.isNotEmpty) {
      return null;
    }
    if (_stack.contains(node)) {
      return null;
    }
    if (RegExp(r'^\$[A-Za-z][\w.\-]*$').hasMatch(value)) {
      final target = _lookup(value.substring(1));
      if (target != null) {
        _stack.add(node);
        try {
          return text(target);
        } finally {
          _stack.removeLast();
        }
      }
    }
    return value.replaceAll(r'$$', r'$');
  }

  static final Map<String, double> _shape = {
    'none': 0,
    'extrasmall': 4,
    'small': 8,
    'medium': 12,
    'large': 16,
    'largeincreased': 20,
    'extralarge': 28,
    'extralargeincreased': 32,
    'extraextralarge': 48,
    'full': 9999,
  };

  static int _lerp(int a, int b, double t) {
    int channel(int shift) {
      final from = (a >> shift) & 0xFF;
      final to = (b >> shift) & 0xFF;
      return (from + (to - from) * t).round().clamp(0, 255);
    }

    return (channel(24) << 24) |
        (channel(16) << 16) |
        (channel(8) << 8) |
        channel(0);
  }

  // The value of a Material role of the palette the seed makes.
  int? _role(String canon) {
    return materialRole(_palette(), canon);
  }

  DynamicScheme _palette() {
    final seed = scope.node(const ['seedcolor']);
    final seedColor = seed == null ? null : color(seed);
    final variant = scope.node(const ['schemevariant'])?.entry?.value;
    final contrast = number(scope.node(const ['contrast'])) ?? 0;
    return _scheme ??= materialScheme(
      seedColor ?? 0xFF6750A4,
      variant ?? 'tonalspot',
      dark: dark,
      contrast: contrast,
    );
  }
}

final Map<String, DynamicColor> _dynamicColors = {
  'primary': MaterialDynamicColors.primary,
  'onprimary': MaterialDynamicColors.onPrimary,
  'primarycontainer': MaterialDynamicColors.primaryContainer,
  'onprimarycontainer': MaterialDynamicColors.onPrimaryContainer,
  'primaryfixed': MaterialDynamicColors.primaryFixed,
  'primaryfixeddim': MaterialDynamicColors.primaryFixedDim,
  'onprimaryfixed': MaterialDynamicColors.onPrimaryFixed,
  'onprimaryfixedvariant': MaterialDynamicColors.onPrimaryFixedVariant,
  'secondary': MaterialDynamicColors.secondary,
  'onsecondary': MaterialDynamicColors.onSecondary,
  'secondarycontainer': MaterialDynamicColors.secondaryContainer,
  'onsecondarycontainer': MaterialDynamicColors.onSecondaryContainer,
  'secondaryfixed': MaterialDynamicColors.secondaryFixed,
  'secondaryfixeddim': MaterialDynamicColors.secondaryFixedDim,
  'onsecondaryfixed': MaterialDynamicColors.onSecondaryFixed,
  'onsecondaryfixedvariant': MaterialDynamicColors.onSecondaryFixedVariant,
  'tertiary': MaterialDynamicColors.tertiary,
  'ontertiary': MaterialDynamicColors.onTertiary,
  'tertiarycontainer': MaterialDynamicColors.tertiaryContainer,
  'ontertiarycontainer': MaterialDynamicColors.onTertiaryContainer,
  'tertiaryfixed': MaterialDynamicColors.tertiaryFixed,
  'tertiaryfixeddim': MaterialDynamicColors.tertiaryFixedDim,
  'ontertiaryfixed': MaterialDynamicColors.onTertiaryFixed,
  'ontertiaryfixedvariant': MaterialDynamicColors.onTertiaryFixedVariant,
  'error': MaterialDynamicColors.error,
  'onerror': MaterialDynamicColors.onError,
  'errorcontainer': MaterialDynamicColors.errorContainer,
  'onerrorcontainer': MaterialDynamicColors.onErrorContainer,
  'surface': MaterialDynamicColors.surface,
  'onsurface': MaterialDynamicColors.onSurface,
  'onsurfacevariant': MaterialDynamicColors.onSurfaceVariant,
  'surfacedim': MaterialDynamicColors.surfaceDim,
  'surfacebright': MaterialDynamicColors.surfaceBright,
  'surfacecontainerlowest': MaterialDynamicColors.surfaceContainerLowest,
  'surfacecontainerlow': MaterialDynamicColors.surfaceContainerLow,
  'surfacecontainer': MaterialDynamicColors.surfaceContainer,
  'surfacecontainerhigh': MaterialDynamicColors.surfaceContainerHigh,
  'surfacecontainerhighest': MaterialDynamicColors.surfaceContainerHighest,
  'surfacetint': MaterialDynamicColors.primary,
  'inversesurface': MaterialDynamicColors.inverseSurface,
  'oninversesurface': MaterialDynamicColors.inverseOnSurface,
  'inverseprimary': MaterialDynamicColors.inversePrimary,
  'outline': MaterialDynamicColors.outline,
  'outlinevariant': MaterialDynamicColors.outlineVariant,
  'shadow': MaterialDynamicColors.shadow,
  'scrim': MaterialDynamicColors.scrim,
};

/// The Material 3 colour scheme of [seed] (`0xAARRGGBB`) as Flutter's
/// `ColorScheme.fromSeed` makes it. [variant] is a `scheme-variant` name
/// (any spelling); an unknown one is `tonalSpot`. [contrast] is from -1 to 1.
DynamicScheme materialScheme(
  int seed,
  String variant, {
  required bool dark,
  double contrast = 0,
}) {
  final source = Hct.fromInt(seed);
  final level = contrast.clamp(-1.0, 1.0);
  DynamicScheme make(
    DynamicScheme Function({
      required Hct sourceColorHct,
      required bool isDark,
      required double contrastLevel,
    })
    build,
  ) => build(sourceColorHct: source, isDark: dark, contrastLevel: level);
  return switch (canonicalName(variant)) {
    'fidelity' => make(SchemeFidelity.new),
    'monochrome' => make(SchemeMonochrome.new),
    'neutral' => make(SchemeNeutral.new),
    'vibrant' => make(SchemeVibrant.new),
    'expressive' => make(SchemeExpressive.new),
    'content' => make(SchemeContent.new),
    'rainbow' => make(SchemeRainbow.new),
    'fruitsalad' => make(SchemeFruitSalad.new),
    _ => make(SchemeTonalSpot.new),
  };
}

/// The colour of Material role [canon] (canonical name, e.g.
/// `primarycontainer`) in [scheme]; `null` for an unknown role.
int? materialRole(DynamicScheme scheme, String canon) =>
    _dynamicColors[canon]?.getArgb(scheme);

/// CSS text of an `0xAARRGGBB` color: `#rrggbb`, or `rgba(...)` when it is
/// not opaque.
String cssColor(int argb) {
  final alpha = (argb >> 24) & 0xFF;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  if (alpha == 255) {
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${hex(r)}${hex(g)}${hex(b)}';
  }
  final share = (alpha / 255 * 1000).round() / 1000;
  return 'rgba($r, $g, $b, $share)';
}

/// A number as CSS text without trailing zeros (`6`, `0.5`).
String cssNumber(double value) {
  if (value.isNaN) {
    return '0';
  }
  if (value.isInfinite) {
    return value.isNegative ? '-9999' : '9999';
  }
  final rounded = (value * 1000).round() / 1000;
  return rounded == rounded.roundToDouble() ? '${rounded.round()}' : '$rounded';
}
