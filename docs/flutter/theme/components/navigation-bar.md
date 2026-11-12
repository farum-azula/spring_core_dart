---
title: "Navigation bar theme in YAML — Spring for Dart"
description: "Style the navigation bar in YAML: 12 properties such as height, background-color and elevation, set under navigation-bar."
slug: /docs/flutter/theme/components/navigation-bar
section: Flutter / Theme / Components
order: 34
keywords: [flutter, theme, yaml, navigation bar, NavigationBarThemeData]
---

# Navigation bar theme in YAML

The Material 3 bar at the bottom of the screen to switch between pages. It configures Flutter's `NavigationBarThemeData`. Set it under `spring.flutter.theme.components.navigation-bar`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.navigation-bar`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        navigation-bar:
          height: 56
          elevation: level2
          indicator-shape: large
          label-text-style: { style: title-large, weight: bold }
          icon-theme: { color: $colors.primary, size: 24 }
          overlay-color:
            default: $colors.primary
            hovered:
              color: $colors.primary
              alpha: 90%
            disabled:
              color: $colors.on-surface
              alpha: 12%
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `height` | number | a number | no | The height of the navigation bar itself. If this is used in bottom navigation bar and the scaffold is full-screen, the safe area padding is also added to the height automatically. | `NavigationBarThemeData.height` |
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the navigation bar itself. | `NavigationBarThemeData.backgroundColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The elevation of the navigation bar itself. | `NavigationBarThemeData.elevation` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used for the drop shadow to indicate elevation. | `NavigationBarThemeData.shadowColor` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used as an overlay on background color to indicate elevation. This is not recommended for use. | `NavigationBarThemeData.surfaceTintColor` |
| `indicator-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the pill behind the selected destination. | `NavigationBarThemeData.indicatorColor` |
| `indicator-shape` | shape | a token (`small`), a radius, or a map | no | The shape of the pill behind the selected destination. | `NavigationBarThemeData.indicatorShape` |
| `label-text-style` | text style | a style name (`title-large`) or a map | yes | The text style of the destination labels. A value per state can give the selected label another style. | `NavigationBarThemeData.labelTextStyle` |
| `icon-theme` | icon theme | a color, or a map of `color`, `size`, ... | yes | The style of the destination icons. A value per state can give the selected icon another style. | `NavigationBarThemeData.iconTheme` |
| `label-behavior` | choice | `always-show`, `always-hide`, `only-show-selected` | no | Defines how the destinations' labels will be laid out and when they'll be displayed. Can be used to show all labels, show only the selected label, or hide all labels. | `NavigationBarThemeData.labelBehavior` |
| `overlay-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The highlight color that's typically used to indicate that the navigation destination is focused, hovered, or pressed. | `NavigationBarThemeData.overlayColor` |
| `label-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding around the label widget. | `NavigationBarThemeData.labelPadding` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The Material starter sets `ThemeData.navigationBarTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).navigationBarTheme;
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
