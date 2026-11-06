---
title: "Outlined button theme in YAML — Spring for Dart"
description: "Style the outlined button in YAML: 25 properties such as min-height, border-color and text-style, set under outlined-button."
slug: /docs/flutter/theme/components/outlined-button
section: Flutter / Theme / Components
order: 10
keywords: [flutter, theme, yaml, outlined button, OutlinedButtonThemeData]
---

# Outlined button theme in YAML

A button with a border and no fill. It configures Flutter's `OutlinedButtonThemeData`, whose `style` is a `ButtonStyle`. It starts from [button](button.md): a value set here wins over the one of `button`. Set it under `spring.flutter.theme.components.outlined-button`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.outlined-button`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        outlined-button:
          min-height: 40
          text-style: { style: title-large, weight: bold }
          background-color:
            default: $colors.primary
            hovered:
              color: $colors.primary
              alpha: 90%
            disabled:
              color: $colors.on-surface
              alpha: 12%
          elevation: level2
          padding: { horizontal: 16, vertical: 8 }
          minimum-size: { width: 48, height: 48 }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `min-height` | number | a number | no | The least height of the button. A shortcut for the height of minimum-size, with no minimum width. | `ButtonStyle.minimumSize` |
| `border-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the button border, with the default border width. A shortcut for the color of side. | `ButtonStyle.side` |
| `text-style` | text style | a style name (`title-large`) or a map | yes | The style for a button's text widget descendants. The color of the text style is typically not used directly, the foreground color is used instead. | `ButtonStyle.textStyle` |
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The button's background fill color. | `ButtonStyle.backgroundColor` |
| `foreground-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The color for the button's text widget descendants. This color is typically used instead of the color of the text style. | `ButtonStyle.foregroundColor` |
| `overlay-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The highlight color that's typically used to indicate that the button is focused, hovered, or pressed. | `ButtonStyle.overlayColor` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The shadow color of the button's material. | `ButtonStyle.shadowColor` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The surface tint color of the button's material. | `ButtonStyle.surfaceTintColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | yes | The elevation of the button's material. | `ButtonStyle.elevation` |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | yes | The padding between the button's boundary and its child. When the visual density is compact, the top and bottom insets are reduced by 8 pixels or set to 0 pixels if the result of the reduced padding is negative. | `ButtonStyle.padding` |
| `minimum-size` | size | `width, height`, one number, or a map | yes | The minimum size of the button itself before applying visual density. The size of the rectangle the button lies within may be larger per tap target size. | `ButtonStyle.minimumSize` |
| `fixed-size` | size | `width, height`, one number, or a map | yes | The button's size. This size is still constrained by the style's minimum size and maximum size. | `ButtonStyle.fixedSize` |
| `maximum-size` | size | `width, height`, one number, or a map | yes | The maximum size of the button itself. This value must be greater than or equal to minimum size. | `ButtonStyle.maximumSize` |
| `icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The icon's color inside of the button. | `ButtonStyle.iconColor` |
| `icon-size` | number | a number | yes | The icon's size inside of the button. | `ButtonStyle.iconSize` |
| `icon-alignment` | choice | `start`, `end` | no | Whether the icon of a button that has an icon and a label sits before (start) or after (end) the label. | `ButtonStyle.iconAlignment` |
| `side` | border side | `none`, or a map of `color`, `width`, `style` | yes | The color and weight of the button's outline. This value is combined with shape to create a shape decorated with an outline. | `ButtonStyle.side` |
| `shape` | shape | a token (`small`), a radius, or a map | yes | The shape of the button's underlying material. This shape is combined with side to create a shape decorated with an outline. | `ButtonStyle.shape` |
| `mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over this button's ink well. | `ButtonStyle.mouseCursor` |
| `visual-density` | visual density | `standard`, `compact`, `comfortable`, `adaptive`, or `h, v` | no | Defines how compact the button's layout will be. Density, in the context of a UI, is the vertical and horizontal "compactness" of the elements in the UI. | `ButtonStyle.visualDensity` |
| `tap-target-size` | choice | `padded`, `shrink-wrap` | no | Configures the minimum size of the area within which the button may be pressed. If the tap target size is larger than minimum size, the button will include a transparent margin that responds to taps. | `ButtonStyle.tapTargetSize` |
| `animation-duration` | duration | `250ms`, `1s` | no | Defines the duration of animated changes for shape and elevation. | `ButtonStyle.animationDuration` |
| `enable-feedback` | true / false | `true`, `false` | no | Whether a tap or a long press gives a sound or a vibration. | `ButtonStyle.enableFeedback` |
| `alignment` | alignment | `center`, `top-left`, ..., or `x, y` | no | The alignment of the button's child. Typically buttons are sized to be just big enough to contain the child and its padding. | `ButtonStyle.alignment` |
| `splash-factory` | choice | `ripple`, `sparkle`, `none` | no | Creates the ink well splash factory, which defines the appearance of "ink" splashes that occur in response to taps. Use splash factory to defeat ink splash rendering. | `ButtonStyle.splashFactory` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.outlinedButtonTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).outlinedButtonTheme.style;
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
