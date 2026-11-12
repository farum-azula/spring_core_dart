---
title: "Bottom navigation bar theme in YAML — Spring for Dart"
description: "Style the bottom navigation bar in YAML: 14 properties such as background-color, elevation and selected-icon-theme, set under bottom-navigation-bar."
slug: /docs/flutter/theme/components/bottom-navigation-bar
section: Flutter / Theme / Components
order: 5
keywords: [flutter, theme, yaml, bottom navigation bar, BottomNavigationBarThemeData]
---

# Bottom navigation bar theme in YAML

The bar at the bottom of a screen to switch between a few top-level pages. It configures Flutter's `BottomNavigationBarThemeData`. Set it under `spring.flutter.theme.components.bottom-navigation-bar`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.bottom-navigation-bar`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        bottom-navigation-bar:
          background-color: $colors.primary
          elevation: level2
          selected-icon-theme: { color: $colors.primary, size: 24 }
          selected-label-style: { style: title-large, weight: bold }
          show-selected-labels: true
          mouse-cursor:
            default: click
            hovered: click
            disabled: click
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the bottom navigation bar itself. | `BottomNavigationBarThemeData.backgroundColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate of the bottom navigation bar. | `BottomNavigationBarThemeData.elevation` |
| `selected-icon-theme` | icon theme | a color, or a map of `color`, `size`, ... | no | The size, opacity, and color of the icon in the currently selected icon. | `BottomNavigationBarThemeData.selectedIconTheme` |
| `unselected-icon-theme` | icon theme | a color, or a map of `color`, `size`, ... | no | The size, opacity, and color of the icon in the currently unselected icons. | `BottomNavigationBarThemeData.unselectedIconTheme` |
| `selected-item-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the selected icon and label. | `BottomNavigationBarThemeData.selectedItemColor` |
| `unselected-item-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the unselected icon and labels. | `BottomNavigationBarThemeData.unselectedItemColor` |
| `selected-label-style` | text style | a style name (`title-large`) or a map | no | The text style of the bottom navigation bar item labels when they are selected. | `BottomNavigationBarThemeData.selectedLabelStyle` |
| `unselected-label-style` | text style | a style name (`title-large`) or a map | no | The text style of the bottom navigation bar item labels when they are not selected. | `BottomNavigationBarThemeData.unselectedLabelStyle` |
| `show-selected-labels` | true / false | `true`, `false` | no | Whether the labels are shown for the selected bottom navigation bar item. | `BottomNavigationBarThemeData.showSelectedLabels` |
| `show-unselected-labels` | true / false | `true`, `false` | no | Whether the labels are shown for the unselected bottom navigation bar items. | `BottomNavigationBarThemeData.showUnselectedLabels` |
| `type` | choice | `fixed`, `shifting` | no | Defines the layout and behavior of a bottom navigation bar. | `BottomNavigationBarThemeData.type` |
| `enable-feedback` | true / false | `true`, `false` | no | Whether a tap or a long press gives a sound or a vibration. | `BottomNavigationBarThemeData.enableFeedback` |
| `landscape-layout` | choice | `spread`, `centered`, `linear` | no | How the items are laid out when the screen is wide: spread across the bar, centered, or in a line. | `BottomNavigationBarThemeData.landscapeLayout` |
| `mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over the items. | `BottomNavigationBarThemeData.mouseCursor` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The Material starter sets `ThemeData.bottomNavigationBarTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).bottomNavigationBarTheme;
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
