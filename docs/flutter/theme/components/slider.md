---
title: "Slider theme in YAML — Spring for Dart"
description: "Style the slider in YAML: 25 properties such as track-height, active-track-color and inactive-track-color, set under slider."
slug: /docs/flutter/theme/components/slider
section: Flutter / Theme / Components
order: 43
keywords: [flutter, theme, yaml, slider, SliderThemeData]
---

# Slider theme in YAML

A control to pick a value by dragging a thumb along a track. It configures Flutter's `SliderThemeData`. Set it under `spring.flutter.theme.components.slider`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.slider`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        slider:
          track-height: 16
          active-track-color: $colors.primary
          show-value-indicator: only-for-discrete
          value-indicator-text-style: { style: title-large, weight: bold }
          mouse-cursor:
            default: click
            hovered: click
            disabled: click
          padding: { horizontal: 16, vertical: 8 }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `track-height` | number | a number | no | The height of the slider track. | `SliderThemeData.trackHeight` |
| `active-track-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the slider track between the min position and the current thumb position. | `SliderThemeData.activeTrackColor` |
| `inactive-track-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the slider track between the current thumb position and the max position. | `SliderThemeData.inactiveTrackColor` |
| `secondary-active-track-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the slider track between the current thumb position and the secondary track value position. | `SliderThemeData.secondaryActiveTrackColor` |
| `disabled-active-track-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the slider track between the min position and the current thumb position when the slider is disabled. | `SliderThemeData.disabledActiveTrackColor` |
| `disabled-secondary-active-track-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the slider track between the current thumb position and the secondary track value position when the slider is disabled. | `SliderThemeData.disabledSecondaryActiveTrackColor` |
| `disabled-inactive-track-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the slider track between the current thumb position and the max position when the slider is disabled. | `SliderThemeData.disabledInactiveTrackColor` |
| `active-tick-mark-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the track's tick marks that are drawn between the min position and the current thumb position. | `SliderThemeData.activeTickMarkColor` |
| `inactive-tick-mark-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the track's tick marks that are drawn between the current thumb position and the max position. | `SliderThemeData.inactiveTickMarkColor` |
| `disabled-active-tick-mark-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the track's tick marks that are drawn between the min position and the current thumb position when the slider is disabled. | `SliderThemeData.disabledActiveTickMarkColor` |
| `disabled-inactive-tick-mark-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the track's tick marks that are drawn between the current thumb position and the max position when the slider is disabled. | `SliderThemeData.disabledInactiveTickMarkColor` |
| `thumb-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color given to the thumb shape to draw itself with. | `SliderThemeData.thumbColor` |
| `overlapping-shape-stroke-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color given to the perimeter of the top range thumb shape when the thumbs are overlapping and the top range value indicator shape when the value indicators are overlapping. | `SliderThemeData.overlappingShapeStrokeColor` |
| `disabled-thumb-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color given to the thumb shape to draw itself with when the slider is disabled. | `SliderThemeData.disabledThumbColor` |
| `overlay-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the overlay drawn around the slider thumb when it is pressed, focused, or hovered. This is typically a semi-transparent color. | `SliderThemeData.overlayColor` |
| `value-indicator-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color given to the value indicator shape to draw itself with. | `SliderThemeData.valueIndicatorColor` |
| `value-indicator-stroke-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color given to the value indicator shape stroke. | `SliderThemeData.valueIndicatorStrokeColor` |
| `show-value-indicator` | choice | `only-for-discrete`, `only-for-continuous`, `always`, `on-drag`, `always-visible`, `never` | no | Whether the value indicator should be shown for different types of sliders. The value indicator is only shown when the thumb is being touched. | `SliderThemeData.showValueIndicator` |
| `value-indicator-text-style` | text style | a style name (`title-large`) or a map | no | The text style for the text on the value indicator. | `SliderThemeData.valueIndicatorTextStyle` |
| `min-thumb-separation` | number | a number | no | Limits the thumb's separation distance. Use this only if you want to control the visual appearance of the thumbs in terms of a logical pixel value. | `SliderThemeData.minThumbSeparation` |
| `mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over the widget. | `SliderThemeData.mouseCursor` |
| `allowed-interaction` | choice | `tap-and-slide`, `tap-only`, `slide-only`, `slide-thumb` | no | Allowed way for the user to interact with the slider. For example, if this is set to tap only, the user can interact with the slider only by tapping anywhere on the track. | `SliderThemeData.allowedInteraction` |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | Determines the padding around the slider. | `SliderThemeData.padding` |
| `thumb-size` | size | `width, height`, one number, or a map | yes | The size of the handle thumb shape thumb. | `SliderThemeData.thumbSize` |
| `track-gap` | number | a number | no | The size of the gap between the active and inactive tracks of the gapped slider track shape. In this case, set the track shape to gapped slider track shape to use the track gap. | `SliderThemeData.trackGap` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.sliderTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).sliderTheme;
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

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.7), copyright The Flutter Authors, BSD 3-Clause license.*
