---
title: "Radio theme in YAML — Spring for Dart"
description: "Style the radio in YAML: 9 properties such as mouse-cursor, fill-color and overlay-color, set under radio."
slug: /docs/flutter/theme/components/radio
section: Flutter / Theme / Components
order: 39
keywords: [flutter, theme, yaml, radio, RadioThemeData]
---

# Radio theme in YAML

A round button to pick one option out of several. It configures Flutter's `RadioThemeData`. Set it under `spring.flutter.theme.components.radio`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.radio`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        radio:
          mouse-cursor: click
          fill-color:
            default: $colors.primary
            hovered:
              color: $colors.primary
              alpha: 90%
            disabled:
              color: $colors.on-surface
              alpha: 12%
          splash-radius: 16
          material-tap-target-size: padded
          visual-density: compact
          side: { color: $colors.outline, width: 1 }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over the widget. | `RadioThemeData.mouseCursor` |
| `fill-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The color that fills the radio button. | `RadioThemeData.fillColor` |
| `overlay-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The highlight color when the radio button is hovered, focused or pressed. | `RadioThemeData.overlayColor` |
| `splash-radius` | number | a number | no | The splash radius of the circular material ink response. | `RadioThemeData.splashRadius` |
| `material-tap-target-size` | choice | `padded`, `shrink-wrap` | no | Configures the minimum size of the tap target. | `RadioThemeData.materialTapTargetSize` |
| `visual-density` | visual density | `standard`, `compact`, `comfortable`, `adaptive`, or `h, v` | no | Defines how compact the radio's layout will be. Density, in the context of a UI, is the vertical and horizontal "compactness" of the elements in the UI. | `RadioThemeData.visualDensity` |
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The color of the background of the radio button. | `RadioThemeData.backgroundColor` |
| `side` | border side | `none`, or a map of `color`, `width`, `style` | no | The side for the circular border of the radio button. | `RadioThemeData.side` |
| `inner-radius` | number | a number | yes | The radius of the inner circle of the radio button. | `RadioThemeData.innerRadius` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The Material starter sets `ThemeData.radioTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).radioTheme;
```

## See also

- [All component themes](index.md)
- [Theme overview](../index.md)
- [Colors](../colors.md)
- [Styles and states](../styles-and-states.md)
- [Tokens and references](../tokens-and-references.md)
- [Root theme properties](../properties.md)
- [Configuration reference](../../../configuration.md) (all properties of the framework)

---

*Property descriptions are adapted from the documentation of the Flutter SDK (3.50.0), copyright The Flutter Authors, BSD 3-Clause license.*
