---
title: "Progress indicator theme in YAML — Spring for Dart"
description: "Style the progress indicator in YAML: 14 properties such as color, linear-track-color and linear-min-height, set under progress-indicator."
slug: /docs/flutter/theme/components/progress-indicator
section: Flutter / Theme / Components
order: 38
keywords: [flutter, theme, yaml, progress indicator, ProgressIndicatorThemeData]
---

# Progress indicator theme in YAML

The circular and linear bars that show progress or waiting. It configures Flutter's `ProgressIndicatorThemeData`. Set it under `spring.flutter.theme.components.progress-indicator`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.progress-indicator`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        progress-indicator:
          color: $colors.primary
          linear-min-height: 16
          border-radius: medium
          stroke-cap: butt
          constraints: { max-width: 640 }
          circular-track-padding: { horizontal: 16, vertical: 8 }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the progress indicator's indicator. | `ProgressIndicatorThemeData.color` |
| `linear-track-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Color of the track being filled by the linear indicator. | `ProgressIndicatorThemeData.linearTrackColor` |
| `linear-min-height` | number | a number | no | The minimum height of the line used to draw the linear indicator. | `ProgressIndicatorThemeData.linearMinHeight` |
| `circular-track-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Color of the circular track being filled by the circular indicator. | `ProgressIndicatorThemeData.circularTrackColor` |
| `refresh-background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Background color of that fills the circle under the refresh indicator. | `ProgressIndicatorThemeData.refreshBackgroundColor` |
| `border-radius` | corner radius | a token (`medium`) or a number | no | Sets the border radius of the progress indicator. | `ProgressIndicatorThemeData.borderRadius` |
| `stop-indicator-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Sets the stop indicator color of the linear progress indicator. | `ProgressIndicatorThemeData.stopIndicatorColor` |
| `stop-indicator-radius` | number | a number | no | Sets the stop indicator radius of the linear progress indicator. | `ProgressIndicatorThemeData.stopIndicatorRadius` |
| `stroke-width` | number | a number | no | Sets the stroke width of the circular progress indicator. | `ProgressIndicatorThemeData.strokeWidth` |
| `stroke-align` | number | a number | no | Sets the stroke align of the circular progress indicator. | `ProgressIndicatorThemeData.strokeAlign` |
| `stroke-cap` | choice | `butt`, `round`, `square` | no | Sets the stroke cap of the circular progress indicator. | `ProgressIndicatorThemeData.strokeCap` |
| `constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | Sets the constraints of the circular progress indicator. | `ProgressIndicatorThemeData.constraints` |
| `track-gap` | number | a number | no | The gap between the filled part and the track. | `ProgressIndicatorThemeData.trackGap` |
| `circular-track-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | Sets the padding of the circular progress indicator. | `ProgressIndicatorThemeData.circularTrackPadding` |

## Read it in Dart

The starter sets `ThemeData.progressIndicatorTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).progressIndicatorTheme;
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

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.7), copyright The Flutter Authors, BSD 3-Clause license.*
