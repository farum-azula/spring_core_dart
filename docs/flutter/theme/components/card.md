---
title: "Card theme in YAML — Spring for Dart"
description: "Style the card in YAML: 7 properties such as clip-behavior, color and shadow-color, set under card."
slug: /docs/flutter/theme/components/card
section: Flutter / Theme / Components
order: 17
keywords: [flutter, theme, yaml, card, CardThemeData]
---

# Card theme in YAML

A rounded panel with a shadow that groups related content. It configures Flutter's `CardThemeData`. Set it under `spring.flutter.theme.components.card`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.card`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        card:
          clip-behavior: none
          color: $colors.primary
          elevation: level2
          margin: { horizontal: 16, vertical: 8 }
          shape: large
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `clip-behavior` | choice | `none`, `hard-edge`, `anti-alias`, `anti-alias-with-save-layer` | no | The content will be clipped (or not) according to this option. | `CardThemeData.clipBehavior` |
| `color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The card's background color. Defines the card's color. | `CardThemeData.color` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color to paint the shadow below the card. | `CardThemeData.shadowColor` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used as an overlay on color to indicate elevation. This is not recommended for use. | `CardThemeData.surfaceTintColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate at which to place this card. This controls the size of the shadow below the card. | `CardThemeData.elevation` |
| `margin` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The empty space that surrounds the card. Defines the card's outer margin. | `CardThemeData.margin` |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of the card's material. Defines the card's shape. | `CardThemeData.shape` |

## Read it in Dart

The starter sets `ThemeData.cardTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).cardTheme;
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

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.7), copyright The Flutter Authors, BSD 3-Clause license.*
