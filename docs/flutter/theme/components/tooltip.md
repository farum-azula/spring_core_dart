---
title: "Tooltip theme in YAML — Spring for Dart"
description: "Style the tooltip in YAML: 16 properties such as shape, background and decoration, set under tooltip."
slug: /docs/flutter/theme/components/tooltip
section: Flutter / Theme / Components
order: 49
keywords: [flutter, theme, yaml, tooltip, TooltipThemeData]
---

# Tooltip theme in YAML

The small label that appears when you hover or long-press something. It configures Flutter's `TooltipThemeData`. Set it under `spring.flutter.theme.components.tooltip`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.tooltip`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        tooltip:
          shape: large
          background: $colors.primary
          decoration: { color: $colors.surface-container, radius: medium }
          constraints: { max-width: 640 }
          padding: { horizontal: 16, vertical: 8 }
          vertical-offset: 16
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field | Default |
|---|---|---|---|---|---|---|
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of the tooltip background. Together with background it replaces decoration. | `TooltipThemeData.decoration` | Flutter's Material 3 default |
| `background` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The fill color of the tooltip. Together with shape it replaces decoration. | `TooltipThemeData.decoration` | Flutter's Material 3 default |
| `decoration` | decoration | a color, or a map of `color`, `radius`, `border`, `shape` | no | The tooltip's shape and background color. | `TooltipThemeData.decoration` | Flutter's Material 3 default |
| `constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | Constrains the size of the tooltip's message. | `TooltipThemeData.constraints` | Flutter's Material 3 default |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The space between the tooltip text and the edge of the tooltip. | `TooltipThemeData.padding` | Flutter's Material 3 default |
| `margin` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The empty space around the tooltip. | `TooltipThemeData.margin` | Flutter's Material 3 default |
| `vertical-offset` | number | a number | no | The vertical gap between the widget and the displayed tooltip. | `TooltipThemeData.verticalOffset` | Flutter's Material 3 default |
| `prefer-below` | true / false | `true`, `false` | no | Whether the tooltip appears below the widget when there is room. Set it to false to show it above, so a finger or the cursor does not cover it. | `TooltipThemeData.preferBelow` | Flutter's Material 3 default |
| `exclude-from-semantics` | true / false | `true`, `false` | no | Whether the message should be excluded from the semantics tree. Set this property to true if the app is going to provide its own custom semantics label. | `TooltipThemeData.excludeFromSemantics` | Flutter's Material 3 default |
| `text-style` | text style | a style name (`title-large`) or a map | no | The style to use for the message of tooltips. | `TooltipThemeData.textStyle` | Flutter's Material 3 default |
| `text-align` | choice | `left`, `right`, `center`, `justify`, `start`, `end` | no | The text align to use for the message of tooltips. | `TooltipThemeData.textAlign` | Flutter's Material 3 default |
| `wait-duration` | duration | `250ms`, `1s` | no | The length of time that a pointer must hover over a tooltip's widget before the tooltip will be shown. | `TooltipThemeData.waitDuration` | Flutter's Material 3 default |
| `show-duration` | duration | `250ms`, `1s` | no | The length of time that the tooltip will be shown once it has appeared. | `TooltipThemeData.showDuration` | Flutter's Material 3 default |
| `exit-duration` | duration | `250ms`, `1s` | no | The length of time that a pointer must have stopped hovering over a tooltip's widget before the tooltip will be hidden. | `TooltipThemeData.exitDuration` | Flutter's Material 3 default |
| `trigger-mode` | choice | `manual`, `long-press`, `tap` | no | The tooltip trigger mode that will show the tooltip. | `TooltipThemeData.triggerMode` | Flutter's Material 3 default |
| `enable-feedback` | true / false | `true`, `false` | no | Whether a tap or a long press gives a sound or a vibration. | `TooltipThemeData.enableFeedback` | Flutter default: true |

## Read it in Dart

The Material starter sets `ThemeData.tooltipTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).tooltipTheme;
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
