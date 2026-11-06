---
title: "Navigation rail theme in YAML — Spring for Dart"
description: "Style the navigation rail in YAML: 13 properties such as background-color, elevation and unselected-label-text-style, set under navigation-rail."
slug: /docs/flutter/theme/components/navigation-rail
section: Flutter / Theme / Components
order: 36
keywords: [flutter, theme, yaml, navigation rail, NavigationRailThemeData]
---

# Navigation rail theme in YAML

A narrow bar at the side of the screen to switch between pages. It configures Flutter's `NavigationRailThemeData`. Set it under `spring.flutter.theme.components.navigation-rail`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.navigation-rail`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        navigation-rail:
          background-color: $colors.primary
          elevation: level2
          unselected-label-text-style: { style: title-large, weight: bold }
          unselected-icon-theme: { color: $colors.primary, size: 24 }
          group-alignment: 16
          label-type: none
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Color to be used for the navigation rail's background. | `NavigationRailThemeData.backgroundColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate to be used for the navigation rail's elevation. | `NavigationRailThemeData.elevation` |
| `unselected-label-text-style` | text style | a style name (`title-large`) or a map | no | The style to merge with the default text style for navigation rail destination labels, when the destination is not selected. | `NavigationRailThemeData.unselectedLabelTextStyle` |
| `selected-label-text-style` | text style | a style name (`title-large`) or a map | no | The style to merge with the default text style for navigation rail destination labels, when the destination is selected. | `NavigationRailThemeData.selectedLabelTextStyle` |
| `unselected-icon-theme` | icon theme | a color, or a map of `color`, `size`, ... | no | The theme to merge with the default icon theme for navigation rail destination icons, when the destination is not selected. | `NavigationRailThemeData.unselectedIconTheme` |
| `selected-icon-theme` | icon theme | a color, or a map of `color`, `size`, ... | no | The theme to merge with the default icon theme for navigation rail destination icons, when the destination is selected. | `NavigationRailThemeData.selectedIconTheme` |
| `group-alignment` | number | a number | no | The alignment for the navigation rail destinations as they are positioned within the navigation rail. | `NavigationRailThemeData.groupAlignment` |
| `label-type` | choice | `none`, `selected`, `all` | no | The type that defines the layout and behavior of the labels in the navigation rail. | `NavigationRailThemeData.labelType` |
| `use-indicator` | true / false | `true`, `false` | no | Whether or not the selected navigation rail destination should include a navigation indicator. | `NavigationRailThemeData.useIndicator` |
| `indicator-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the pill behind the selected destination, when use-indicator is on. | `NavigationRailThemeData.indicatorColor` |
| `indicator-shape` | shape | a token (`small`), a radius, or a map | no | The shape of the pill behind the selected destination. | `NavigationRailThemeData.indicatorShape` |
| `min-width` | number | a number | no | The least width of the rail when it is not extended. | `NavigationRailThemeData.minWidth` |
| `min-extended-width` | number | a number | no | The least width of the rail when it is extended, with the labels beside the icons. | `NavigationRailThemeData.minExtendedWidth` |

## Read it in Dart

The starter sets `ThemeData.navigationRailTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).navigationRailTheme;
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

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.9), copyright The Flutter Authors, BSD 3-Clause license.*
