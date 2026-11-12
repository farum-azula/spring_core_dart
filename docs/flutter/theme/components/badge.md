---
title: "Badge theme in YAML — Spring for Dart"
description: "Style the badge in YAML: 8 properties such as background-color, text-color and small-size, set under badge."
slug: /docs/flutter/theme/components/badge
section: Flutter / Theme / Components
order: 2
keywords: [flutter, theme, yaml, badge, BadgeThemeData]
---

# Badge theme in YAML

A small dot or number shown on top of another widget, such as an unread count on an icon. It configures Flutter's `BadgeThemeData`. Set it under `spring.flutter.theme.components.badge`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.badge`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        badge:
          background-color: $colors.primary
          small-size: 16
          text-style: { style: title-large, weight: bold }
          padding: { horizontal: 16, vertical: 8 }
          alignment: center
          offset: '4, -4'
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The badge's fill color. | `BadgeThemeData.backgroundColor` |
| `text-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the badge's label text. This color overrides the color of the label's text style. | `BadgeThemeData.textColor` |
| `small-size` | number | a number | no | The diameter of the badge when it is a plain dot, with no label. | `BadgeThemeData.smallSize` |
| `large-size` | number | a number | no | The height of the badge when it has a label. | `BadgeThemeData.largeSize` |
| `text-style` | text style | a style name (`title-large`) or a map | no | The default text style for the badge's label. The text style's color is overwritten by the text color. | `BadgeThemeData.textStyle` |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding added to the badge's label. | `BadgeThemeData.padding` |
| `alignment` | alignment | `center`, `top-left`, ..., or `x, y` | no | Combined with offset to determine the location of the label relative to the child. | `BadgeThemeData.alignment` |
| `offset` | offset | `x, y` | no | Combined with alignment to determine the location of the label relative to the child. | `BadgeThemeData.offset` |

## Read it in Dart

The Material starter sets `ThemeData.badgeTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).badgeTheme;
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
