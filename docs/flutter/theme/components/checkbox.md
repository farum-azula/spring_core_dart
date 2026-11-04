---
title: "Checkbox theme in YAML — Spring for Dart"
description: "Style the checkbox in YAML: 9 properties such as mouse-cursor, fill-color and check-color, set under checkbox."
slug: /docs/flutter/theme/components/checkbox
section: Flutter / Theme / Components
order: 19
keywords: [flutter, theme, yaml, checkbox, CheckboxThemeData]
---

# Checkbox theme in YAML

A box that is ticked or cleared. It configures Flutter's `CheckboxThemeData`. Set it under `spring.flutter.theme.components.checkbox`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.checkbox`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        checkbox:
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
          shape: large
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over the widget. | `CheckboxThemeData.mouseCursor` |
| `fill-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The color that fills the checkbox. | `CheckboxThemeData.fillColor` |
| `check-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The color to use for the check icon when this checkbox is checked. | `CheckboxThemeData.checkColor` |
| `overlay-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The highlight color when the checkbox is hovered, focused or pressed. | `CheckboxThemeData.overlayColor` |
| `splash-radius` | number | a number | no | The splash radius of the circular material ink response. | `CheckboxThemeData.splashRadius` |
| `material-tap-target-size` | choice | `padded`, `shrink-wrap` | no | Configures the minimum size of the tap target. | `CheckboxThemeData.materialTapTargetSize` |
| `visual-density` | visual density | `standard`, `compact`, `comfortable`, `adaptive`, or `h, v` | no | Defines how compact the checkbox's layout will be. Density, in the context of a UI, is the vertical and horizontal "compactness" of the elements in the UI. | `CheckboxThemeData.visualDensity` |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of the checkbox's material. | `CheckboxThemeData.shape` |
| `side` | border side | `none`, or a map of `color`, `width`, `style` | no | The color and width of the checkbox border. | `CheckboxThemeData.side` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.checkboxTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).checkboxTheme;
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
