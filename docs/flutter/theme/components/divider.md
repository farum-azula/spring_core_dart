---
title: "Divider theme in YAML — Spring for Dart"
description: "Style the divider in YAML: 6 properties such as color, space and thickness, set under divider."
slug: /docs/flutter/theme/components/divider
section: Flutter / Theme / Components
order: 24
keywords: [flutter, theme, yaml, divider, DividerThemeData]
---

# Divider theme in YAML

A thin line between two pieces of content. It configures Flutter's `DividerThemeData`. Set it under `spring.flutter.theme.components.divider`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.divider`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        divider:
          color: $colors.primary
          space: 16
          thickness: 16
          indent: 16
          radius: medium
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of dividers and vertical dividers, also used between list tiles, between rows in data tables, and so forth. | `DividerThemeData.color` |
| `space` | number | a number | no | The divider's height or the vertical divider's width. This represents the amount of horizontal or vertical space the divider takes up. | `DividerThemeData.space` |
| `thickness` | number | a number | no | The thickness of the line drawn within the divider. | `DividerThemeData.thickness` |
| `indent` | number | a number | no | The amount of empty space at the leading edge of divider or top edge of vertical divider. | `DividerThemeData.indent` |
| `end-indent` | number | a number | no | The amount of empty space at the trailing edge of divider or bottom edge of vertical divider. | `DividerThemeData.endIndent` |
| `radius` | corner radius | a token (`medium`) or a number | no | The border radius applied to the divider or vertical divider. | `DividerThemeData.radius` |

## Read it in Dart

The Material starter sets `ThemeData.dividerTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).dividerTheme;
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
