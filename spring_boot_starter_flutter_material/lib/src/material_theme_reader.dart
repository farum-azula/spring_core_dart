import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';

/// The values only Material's widgets have, read from a component's
/// properties: a visual density, the border of a text field, an ink
/// splash. The other kinds (colors, shapes, text styles) are the
/// [ThemeReader]'s own.
///
/// ```dart
/// // components.search-bar.visual-density: compact
/// final density = reader.density('visualDensity');
/// ```
extension MaterialThemeReader on ThemeReader {
  /// A visual density: `adaptive`, `standard`, `comfortable`, `compact`
  /// or two numbers (`horizontal, vertical`).
  VisualDensity? density(String name) =>
      custom(name, 'visual density', _densityAt);

  /// An input border: `outline`, `underline`, `none`, or a map of type,
  /// radius and side.
  InputBorder? inputBorder(String name) =>
      custom(name, 'input border', _inputBorderAt);

  /// An ink splash: `ripple`, `sparkle`, `none`.
  InteractiveInkFeatureFactory? splash(String name) => custom(
    name,
    'one of: ripple | sparkle | none',
    (path) => leaf(
      path,
      (raw) => switch (ThemeValues.canonical(raw)) {
        'ripple' => InkRipple.splashFactory,
        'sparkle' => InkSparkle.splashFactory,
        'none' => NoSplash.splashFactory,
        _ => null,
      },
      'ripple, sparkle or none',
    ),
  );

  VisualDensity? _densityAt(String path) => leaf(path, (raw) {
    switch (ThemeValues.canonical(raw)) {
      case 'adaptive':
        return VisualDensity.adaptivePlatformDensity;
      case 'standard':
        return VisualDensity.standard;
      case 'comfortable':
        return VisualDensity.comfortable;
      case 'compact':
        return VisualDensity.compact;
    }
    final parts = [
      for (final part in raw.split(',')) ThemeReader.parseNumber(part),
    ];
    return parts.length == 2 && !parts.contains(null)
        ? VisualDensity(horizontal: parts[0]!, vertical: parts[1]!)
        : null;
  }, "adaptive, standard, comfortable, compact or 'horizontal, vertical'");

  InputBorder? _inputBorderAt(String path) {
    final raw = properties[path];
    final children = kids(path);
    if (children.isEmpty && raw == null) {
      return null;
    }
    if (children.isNotEmpty) {
      keys(path, {'type', 'radius', 'side'}, 'an input border');
    }
    final type = children.isEmpty
        ? raw
        : (properties['$path.type'] ?? raw ?? 'outline');
    final side = children.isEmpty ? null : sideAt('$path.side');
    final radius = children.isEmpty ? null : borderRadiusAt('$path.radius');
    return switch (ThemeValues.canonical(type!)) {
      'outline' => OutlineInputBorder(
        borderSide: side ?? const BorderSide(),
        borderRadius: radius ?? const BorderRadius.all(Radius.circular(4)),
      ),
      'underline' => UnderlineInputBorder(
        borderSide: side ?? const BorderSide(),
        borderRadius:
            radius ??
            const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
      ),
      'none' => InputBorder.none,
      _ => throw ThemePropertyException(
        properties.propertyName(children.isEmpty ? path : '$path.type'),
        type,
        'outline, underline or none, or a map of type, radius and side',
      ),
    };
  }
}
