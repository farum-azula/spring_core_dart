---
title: "Bottom app bar theme in YAML — Spring for Dart"
description: "Style the bottom app bar in YAML: 6 properties such as color, elevation and height, set under bottom-app-bar."
slug: /docs/flutter/theme/components/bottom-app-bar
section: Flutter / Theme / Components
order: 4
keywords: [flutter, theme, yaml, bottom app bar, BottomAppBarThemeData]
---

# Bottom app bar theme in YAML

The bar at the bottom of a screen that can hold actions and a floating action button. It configures Flutter's `BottomAppBarThemeData`. Set it under `spring.flutter.theme.components.bottom-app-bar`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.bottom-app-bar`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        bottom-app-bar:
          color: $colors.primary
          elevation: level2
          height: 56
          surface-tint-color: $colors.on-primary
          padding: { horizontal: 16, vertical: 8 }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The bottom app bar's background color. | `BottomAppBarThemeData.color` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate at which to place this bottom app bar relative to its parent. This controls the size of the shadow below the bottom app bar. | `BottomAppBarThemeData.elevation` |
| `height` | number | a number | no | The double value used to indicate the height of the bottom app bar. | `BottomAppBarThemeData.height` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | A custom color for the Material 3 surface-tint elevation effect. This is not recommended for use. | `BottomAppBarThemeData.surfaceTintColor` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the shadow below the app bar. | `BottomAppBarThemeData.shadowColor` |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The amount of space to surround the child inside the bounds of the bottom app bar. | `BottomAppBarThemeData.padding` |

## Read it in Dart

The starter sets `ThemeData.bottomAppBarTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).bottomAppBarTheme;
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
