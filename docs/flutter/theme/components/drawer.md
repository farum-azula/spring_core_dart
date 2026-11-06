---
title: "Drawer theme in YAML — Spring for Dart"
description: "Style the drawer in YAML: 9 properties such as background-color, scrim-color and elevation, set under drawer."
slug: /docs/flutter/theme/components/drawer
section: Flutter / Theme / Components
order: 25
keywords: [flutter, theme, yaml, drawer, DrawerThemeData]
---

# Drawer theme in YAML

A panel that slides in from the side of the screen. It configures Flutter's `DrawerThemeData`. Set it under `spring.flutter.theme.components.drawer`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.drawer`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        drawer:
          background-color: $colors.primary
          elevation: level2
          shape: large
          width: 16
          clip-behavior: none
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Sets the color of the material that holds all of the drawer's contents. | `DrawerThemeData.backgroundColor` |
| `scrim-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color to use for the scrim that obscures the underlying content while a drawer is open. | `DrawerThemeData.scrimColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate at which to place this drawer relative to its parent. This controls the size of the shadow below the drawer. | `DrawerThemeData.elevation` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used to paint a drop shadow under the drawer's material, which reflects the drawer's elevation. | `DrawerThemeData.shadowColor` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used as a surface tint overlay on the drawer's background color, which reflects the drawer's elevation. This is not recommended for use. | `DrawerThemeData.surfaceTintColor` |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of the drawer. Defines the drawer's shape. | `DrawerThemeData.shape` |
| `end-shape` | shape | a token (`small`), a radius, or a map | no | The shape of a drawer that opens from the end side (the right in left-to-right languages). | `DrawerThemeData.endShape` |
| `width` | number | a number | no | The width of the drawer. | `DrawerThemeData.width` |
| `clip-behavior` | choice | `none`, `hard-edge`, `anti-alias`, `anti-alias-with-save-layer` | no | The content will be clipped (or not) according to this option. The clip behavior argument specifies how to clip the drawer's shape. | `DrawerThemeData.clipBehavior` |

## Read it in Dart

The starter sets `ThemeData.drawerTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).drawerTheme;
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

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.9), copyright The Flutter Authors, BSD 3-Clause license.*
