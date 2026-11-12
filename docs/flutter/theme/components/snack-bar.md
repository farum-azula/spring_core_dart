---
title: "Snack bar theme in YAML — Spring for Dart"
description: "Style the snack bar in YAML: 15 properties such as background-color, action-text-color and disabled-action-text-color, set under snack-bar."
slug: /docs/flutter/theme/components/snack-bar
section: Flutter / Theme / Components
order: 44
keywords: [flutter, theme, yaml, snack bar, SnackBarThemeData]
---

# Snack bar theme in YAML

A short message that appears at the bottom of the screen. It configures Flutter's `SnackBarThemeData`. Set it under `spring.flutter.theme.components.snack-bar`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.snack-bar`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        snack-bar:
          background-color: $colors.primary
          content-text-style: { style: title-large, weight: bold }
          elevation: level2
          shape: large
          behavior: fixed
          width: 16
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The snack bar's background color. | `SnackBarThemeData.backgroundColor` |
| `action-text-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The button label color. | `SnackBarThemeData.actionTextColor` |
| `disabled-action-text-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The button disabled label color. This color is shown after the snack bar action is dismissed. | `SnackBarThemeData.disabledActionTextColor` |
| `content-text-style` | text style | a style name (`title-large`) or a map | no | Used to configure the default text style for the content widget. | `SnackBarThemeData.contentTextStyle` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate at which to place the snack bar. This controls the size of the shadow below the snack bar. | `SnackBarThemeData.elevation` |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of the snack bar's material. Defines the snack bar's shape. | `SnackBarThemeData.shape` |
| `behavior` | choice | `fixed`, `floating` | no | Where the snack bar appears: fixed at the bottom of the screen, or floating above it. | `SnackBarThemeData.behavior` |
| `width` | number | a number | no | The width of the snack bar. If width is specified, the snack bar will be centered horizontally in the available space. | `SnackBarThemeData.width` |
| `inset-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | Empty space to surround the snack bar. This property is only used when behavior is floating. | `SnackBarThemeData.insetPadding` |
| `show-close-icon` | true / false | `true`, `false` | no | Whether the snack bar shows a close icon. Tapping it closes the snack bar. | `SnackBarThemeData.showCloseIcon` |
| `close-icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | An optional color for the close icon, if show close icon is true. | `SnackBarThemeData.closeIconColor` |
| `action-overflow-threshold` | number | a number | no | The share of the snack bar width the action may take before it moves to its own line, from 0 to 1. | `SnackBarThemeData.actionOverflowThreshold` |
| `action-background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The button background fill color. | `SnackBarThemeData.actionBackgroundColor` |
| `disabled-action-background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The button disabled background color. This color is shown after the snack bar action is dismissed. | `SnackBarThemeData.disabledActionBackgroundColor` |
| `dismiss-direction` | choice | `vertical`, `horizontal`, `end-to-start`, `start-to-end`, `up`, `down`, `none` | no | The direction in which the SnackBar can be dismissed. | `SnackBarThemeData.dismissDirection` |

## Read it in Dart

The Material starter sets `ThemeData.snackBarTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).snackBarTheme;
```

## See also

- [All component themes](index.md)
- [Theme overview](../index.md)
- [Colors](../colors.md)
- [Typography](../typography.md)
- [Shape, spacing and elevation](../shape-spacing-elevation.md)
- [Styles and states](../styles-and-states.md)
- [Tokens and references](../tokens-and-references.md)
- [Root theme properties](../properties.md)
- [Configuration reference](../../../configuration.md) (all properties of the framework)

---

*Property descriptions are adapted from the documentation of the Flutter SDK (3.50.0), copyright The Flutter Authors, BSD 3-Clause license.*
