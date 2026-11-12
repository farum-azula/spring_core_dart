---
title: "Navigation drawer theme in YAML — Spring for Dart"
description: "Style the navigation drawer in YAML: 10 properties such as tile-height, background-color and elevation, set under navigation-drawer."
slug: /docs/flutter/theme/components/navigation-drawer
section: Flutter / Theme / Components
order: 35
keywords: [flutter, theme, yaml, navigation drawer, NavigationDrawerThemeData]
---

# Navigation drawer theme in YAML

The Material 3 side panel with the destinations of the app. It configures Flutter's `NavigationDrawerThemeData`. Set it under `spring.flutter.theme.components.navigation-drawer`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.navigation-drawer`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        navigation-drawer:
          tile-height: 16
          background-color: $colors.primary
          elevation: level2
          indicator-shape: large
          indicator-size: { width: 48, height: 48 }
          label-text-style:
            default: { style: title-large, weight: bold }
            hovered: { style: title-large, weight: bold }
            disabled: { style: title-large, weight: bold }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `tile-height` | number | a number | no | The height of each destination. | `NavigationDrawerThemeData.tileHeight` |
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The background color of the material that holds the navigation drawer's contents. | `NavigationDrawerThemeData.backgroundColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The elevation of the navigation drawer itself. | `NavigationDrawerThemeData.elevation` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used for the drop shadow to indicate elevation. | `NavigationDrawerThemeData.shadowColor` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The surface tint of the material that holds the navigation drawer's contents. This is not recommended for use. | `NavigationDrawerThemeData.surfaceTintColor` |
| `indicator-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the pill behind the selected destination. | `NavigationDrawerThemeData.indicatorColor` |
| `indicator-shape` | shape | a token (`small`), a radius, or a map | no | The shape of the pill behind the selected destination. | `NavigationDrawerThemeData.indicatorShape` |
| `indicator-size` | size | `width, height`, one number, or a map | no | The size of the pill behind the selected destination. | `NavigationDrawerThemeData.indicatorSize` |
| `label-text-style` | text style | a style name (`title-large`) or a map | yes | The text style of the destination labels. A value per state can give the selected label another style. | `NavigationDrawerThemeData.labelTextStyle` |
| `icon-theme` | icon theme | a color, or a map of `color`, `size`, ... | yes | The style of the destination icons. A value per state can give the selected icon another style. | `NavigationDrawerThemeData.iconTheme` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The Material starter sets `ThemeData.navigationDrawerTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).navigationDrawerTheme;
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
