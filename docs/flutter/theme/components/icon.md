---
title: "Icon theme in YAML — Spring for Dart"
description: "Style the icon in YAML: 7 properties such as color, size and fill, set under icon."
slug: /docs/flutter/theme/components/icon
section: Flutter / Theme / Components
order: 28
keywords: [flutter, theme, yaml, icon, IconThemeData]
---

# Icon theme in YAML

The default look of every icon. It configures Flutter's `IconThemeData`. Set it under `spring.flutter.theme.components.icon`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.icon`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        icon:
          color: $colors.primary
          size: 16
          fill: 16
          weight: 16
          grade: 16
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field | Default |
|---|---|---|---|---|---|---|
| `color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of icons. | `IconThemeData.color` | Flutter's Material 3 default |
| `size` | number | a number | no | The width and height of icons, in logical pixels. | `IconThemeData.size` | Flutter default: 24 |
| `fill` | number | a number | no | How filled in the icon is, from 0 (outlined) to 1 (filled). Only for icon fonts with variable axes, such as Material Symbols. | `IconThemeData.fill` | Flutter default: 0 |
| `weight` | number | a number | no | The stroke weight of the icon, from 100 (thin) to 700 (bold). Only for icon fonts with variable axes. | `IconThemeData.weight` | Flutter default: 400 |
| `grade` | number | a number | no | A fine adjustment of the stroke thickness, from -25 to 200, without changing the size of the icon. Only for icon fonts with variable axes. | `IconThemeData.grade` | Flutter default: 0 |
| `optical-size` | number | a number | no | The size the icon design is tuned for, from 20 to 48. Only for icon fonts with variable axes. | `IconThemeData.opticalSize` | Flutter default: 48 |
| `opacity` | number | a number | no | How see-through icons are, from 0 (invisible) to 1 (opaque). It applies to the color you set and to the default one. | `IconThemeData.opacity` | Flutter default: 1 |

## Read it in Dart

The starter sets `ThemeData.iconTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).iconTheme;
```

## See also

- [All component themes](index.md)
- [Theme overview](../index.md)
- [Colors](../colors.md)
- [Styles and states](../styles-and-states.md)
- [Tokens and references](../tokens-and-references.md)
- [Root theme properties](../properties.md)
- [Configuration reference](../../../configuration.md) (all properties of the framework)

---

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.7), copyright The Flutter Authors, BSD 3-Clause license.*
