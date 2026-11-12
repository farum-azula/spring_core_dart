---
title: "Scrollbar theme in YAML — Spring for Dart"
description: "Style the scrollbar in YAML: 11 properties such as thumb-visibility, thickness and track-visibility, set under scrollbar."
slug: /docs/flutter/theme/components/scrollbar
section: Flutter / Theme / Components
order: 40
keywords: [flutter, theme, yaml, scrollbar, ScrollbarThemeData]
---

# Scrollbar theme in YAML

The bar that shows where you are in a scrolling list. It configures Flutter's `ScrollbarThemeData`. Set it under `spring.flutter.theme.components.scrollbar`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.scrollbar`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        scrollbar:
          thumb-visibility: true
          thickness: 16
          track-visibility: true
          radius: medium
          thumb-color:
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

| Property | Type | Values | States | What it does | Flutter field | Default |
|---|---|---|---|---|---|---|
| `thumb-visibility` | true / false | `true`, `false` | yes | Indicates that the scrollbar thumb should be visible, even when a scroll is not underway. When false, the scrollbar will be shown during scrolling and will fade out otherwise. | `ScrollbarThemeData.thumbVisibility` | Flutter's Material 3 default |
| `thickness` | number | a number | yes | The thickness of the scrollbar in the cross axis of the scrollable. On iOS, default thickness is used. | `ScrollbarThemeData.thickness` | Flutter's Material 3 default |
| `track-visibility` | true / false | `true`, `false` | yes | Indicates that the scrollbar track should be visible. When true, the scrollbar track will always be visible so long as the thumb is visible. | `ScrollbarThemeData.trackVisibility` | Flutter default: false |
| `interactive` | true / false | `true`, `false` | no | Whether the Scrollbar should be interactive and respond to dragging on the thumb, or tapping in the track area. Does not apply to the cupertino scrollbar, which is always interactive to match native behavior. | `ScrollbarThemeData.interactive` | Flutter's Material 3 default |
| `radius` | corner radius | a token (`medium`) or a number | no | The radius of the scrollbar thumb's rounded rectangle corners. On android, no radius is applied to the scrollbar thumb. | `ScrollbarThemeData.radius` | Flutter's Material 3 default |
| `thumb-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | Sets the color of the scrollbar thumb. | `ScrollbarThemeData.thumbColor` | Flutter's Material 3 default |
| `track-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | Sets the color of the scrollbar track when track visibility is true. | `ScrollbarThemeData.trackColor` | Flutter's Material 3 default |
| `track-border-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | Sets the color of the scrollbar track border when track visibility is true. | `ScrollbarThemeData.trackBorderColor` | Flutter's Material 3 default |
| `cross-axis-margin` | number | a number | no | Distance from the scrollbar thumb to the nearest cross axis edge in logical pixels. The scrollbar track consumes this space. | `ScrollbarThemeData.crossAxisMargin` | Flutter's Material 3 default |
| `main-axis-margin` | number | a number | no | Distance from the scrollbar thumb's start and end to the edge of the viewport in logical pixels. It affects the amount of available paint area. | `ScrollbarThemeData.mainAxisMargin` | Flutter's Material 3 default |
| `min-thumb-length` | number | a number | no | The preferred smallest size the scrollbar thumb can shrink to when the total scrollable extent is large, the current visible viewport is small, and the viewport is not overscrolled. | `ScrollbarThemeData.minThumbLength` | Flutter's Material 3 default |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The Material starter sets `ThemeData.scrollbarTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).scrollbarTheme;
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

*Property descriptions are adapted from the documentation of the Flutter SDK (3.50.0), copyright The Flutter Authors, BSD 3-Clause license.*
