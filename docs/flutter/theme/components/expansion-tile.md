---
title: "Expansion tile theme in YAML — Spring for Dart"
description: "Style the expansion tile in YAML: 13 properties such as background-color, collapsed-background-color and tile-padding, set under expansion-tile."
slug: /docs/flutter/theme/components/expansion-tile
section: Flutter / Theme / Components
order: 27
keywords: [flutter, theme, yaml, expansion tile, ExpansionTileThemeData]
---

# Expansion tile theme in YAML

A list row that opens to show more content. It configures Flutter's `ExpansionTileThemeData`. Set it under `spring.flutter.theme.components.expansion-tile`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.expansion-tile`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        expansion-tile:
          background-color: $colors.primary
          tile-padding: { horizontal: 16, vertical: 8 }
          expanded-alignment: center
          shape: large
          clip-behavior: none
          expansion-animation-style: { duration: 250ms }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color to display behind the sublist when expanded. | `ExpansionTileThemeData.backgroundColor` |
| `collapsed-background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The background color of the tile when it is collapsed. | `ExpansionTileThemeData.collapsedBackgroundColor` |
| `tile-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | Specifies padding for the list tile. Analogous to content padding, this property defines the insets for the leading, title, subtitle and trailing widgets. | `ExpansionTileThemeData.tilePadding` |
| `expanded-alignment` | alignment | `center`, `top-left`, ..., or `x, y` | no | Specifies the alignment of children, which are arranged in a column when the tile is expanded. The internals of the expanded tile make use of a column widget for children, and align widget to align the column. | `ExpansionTileThemeData.expandedAlignment` |
| `children-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | Specifies padding for children. | `ExpansionTileThemeData.childrenPadding` |
| `icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The icon color of tile's expansion arrow icon when the sublist is expanded. | `ExpansionTileThemeData.iconColor` |
| `collapsed-icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The icon color of tile's expansion arrow icon when the sublist is collapsed. | `ExpansionTileThemeData.collapsedIconColor` |
| `text-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the tile's titles when the sublist is expanded. | `ExpansionTileThemeData.textColor` |
| `collapsed-text-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the tile's titles when the sublist is collapsed. | `ExpansionTileThemeData.collapsedTextColor` |
| `shape` | shape | a token (`small`), a radius, or a map | no | The tile's border shape when the sublist is expanded. | `ExpansionTileThemeData.shape` |
| `collapsed-shape` | shape | a token (`small`), a radius, or a map | no | The tile's border shape when the sublist is collapsed. | `ExpansionTileThemeData.collapsedShape` |
| `clip-behavior` | choice | `none`, `hard-edge`, `anti-alias`, `anti-alias-with-save-layer` | no | The content will be clipped (or not) according to this option. | `ExpansionTileThemeData.clipBehavior` |
| `expansion-animation-style` | animation | a map of `duration`, `reverse-duration` | no | Used to override the expansion animation curve and duration. If duration is provided, it will be used to override the expansion animation duration. | `ExpansionTileThemeData.expansionAnimationStyle` |

## Read it in Dart

The Material starter sets `ThemeData.expansionTileTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).expansionTileTheme;
```

## See also

- [All component themes](index.md)
- [Theme overview](../index.md)
- [Colors](../colors.md)
- [Shape, spacing and elevation](../shape-spacing-elevation.md)
- [Styles and states](../styles-and-states.md)
- [Tokens and references](../tokens-and-references.md)
- [Root theme properties](../properties.md)
- [Configuration reference](../../../configuration.md) (all properties of the framework)

---

*Property descriptions are adapted from the documentation of the Flutter SDK (3.50.0), copyright The Flutter Authors, BSD 3-Clause license.*
