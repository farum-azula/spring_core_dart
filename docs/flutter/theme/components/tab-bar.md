---
title: "Tab bar theme in YAML — Spring for Dart"
description: "Style the tab bar in YAML: 16 properties such as indicator, indicator-color and indicator-size, set under tab-bar."
slug: /docs/flutter/theme/components/tab-bar
section: Flutter / Theme / Components
order: 46
keywords: [flutter, theme, yaml, tab bar, TabBarThemeData]
---

# Tab bar theme in YAML

The row of tabs to switch between pages of content. It configures Flutter's `TabBarThemeData`. Set it under `spring.flutter.theme.components.tab-bar`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.tab-bar`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        tab-bar:
          indicator: { color: $colors.surface-container, radius: medium }
          indicator-size: tab
          divider-height: 16
          label-padding: { horizontal: 16, vertical: 8 }
          label-style: { style: title-large, weight: bold }
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
| `indicator` | decoration | a color, or a map of `color`, `radius`, `border`, `shape` | no | Defines the appearance of the selected tab indicator. The indicator's size is based on the tab's bounds. | `TabBarThemeData.indicator` |
| `indicator-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the line that appears below the selected tab. | `TabBarThemeData.indicatorColor` |
| `indicator-size` | choice | `tab`, `label` | no | Defines how the selected tab indicator's size is computed. The selected tab's location appearance can be refined further with the indicator color, indicator weight, indicator padding, and indicator properties. | `TabBarThemeData.indicatorSize` |
| `divider-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the divider. If the divider color is transparent, then the divider will not be drawn. | `TabBarThemeData.dividerColor` |
| `divider-height` | number | a number | no | The height of the divider. If the divider height is zero or negative, then the divider will not be drawn. | `TabBarThemeData.dividerHeight` |
| `label-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of selected tab labels. | `TabBarThemeData.labelColor` |
| `label-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding added to each of the tab labels. If there are few tabs with both icon and text and few tabs with only icon or text, this padding is vertically adjusted to provide uniform padding to all tabs. | `TabBarThemeData.labelPadding` |
| `label-style` | text style | a style name (`title-large`) or a map | no | The text style of the selected tab labels. | `TabBarThemeData.labelStyle` |
| `unselected-label-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of unselected tab labels. | `TabBarThemeData.unselectedLabelColor` |
| `unselected-label-style` | text style | a style name (`title-large`) or a map | no | The text style of the unselected tab labels. | `TabBarThemeData.unselectedLabelStyle` |
| `overlay-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | Defines the ink response focus, hover, and splash colors. | `TabBarThemeData.overlayColor` |
| `splash-factory` | choice | `ripple`, `sparkle`, `none` | no | Creates the tab bar's ink well splash factory, which defines the appearance of "ink" splashes that occur in response to taps. Use splash factory to defeat ink splash rendering. | `TabBarThemeData.splashFactory` |
| `mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over the individual tab widgets. | `TabBarThemeData.mouseCursor` |
| `tab-alignment` | choice | `start`, `start-offset`, `fill`, `center` | no | Specifies the horizontal alignment of the tabs within a tab bar. If is scrollable is false, only fill and center are supported. | `TabBarThemeData.tabAlignment` |
| `indicator-animation` | choice | `linear`, `elastic` | no | Specifies the animation behavior of the tab indicator. | `TabBarThemeData.indicatorAnimation` |
| `splash-border-radius` | corner radius | a token (`medium`) or a number | no | Defines the clipping radius of splashes that extend outside the bounds of the tab. | `TabBarThemeData.splashBorderRadius` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.tabBarTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).tabBarTheme;
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
