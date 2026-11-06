---
title: "Switch theme in YAML — Spring for Dart"
description: "Style the switch in YAML: 9 properties such as thumb-color, track-color and track-outline-color, set under switch."
slug: /docs/flutter/theme/components/switch
section: Flutter / Theme / Components
order: 45
keywords: [flutter, theme, yaml, switch, SwitchThemeData]
---

# Switch theme in YAML

An on and off toggle. It configures Flutter's `SwitchThemeData`. Set it under `spring.flutter.theme.components.switch`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.switch`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        switch:
          thumb-color:
            default: $colors.primary
            hovered:
              color: $colors.primary
              alpha: 90%
            disabled:
              color: $colors.on-surface
              alpha: 12%
          track-outline-width: 16
          material-tap-target-size: padded
          mouse-cursor: click
          padding: { horizontal: 16, vertical: 8 }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `thumb-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The color of this switch's thumb. | `SwitchThemeData.thumbColor` |
| `track-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The color of this switch's track. | `SwitchThemeData.trackColor` |
| `track-outline-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The outline color of this switch's track. | `SwitchThemeData.trackOutlineColor` |
| `track-outline-width` | number | a number | yes | The outline width of this switch's track. | `SwitchThemeData.trackOutlineWidth` |
| `material-tap-target-size` | choice | `padded`, `shrink-wrap` | no | Configures the minimum size of the tap target. | `SwitchThemeData.materialTapTargetSize` |
| `mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over the widget. | `SwitchThemeData.mouseCursor` |
| `overlay-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The highlight color when the switch is hovered, focused or pressed. | `SwitchThemeData.overlayColor` |
| `splash-radius` | number | a number | no | The splash radius of the circular material ink response. | `SwitchThemeData.splashRadius` |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The amount of space to surround the child inside the bounds of the switch. | `SwitchThemeData.padding` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.switchTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).switchTheme;
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

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.9), copyright The Flutter Authors, BSD 3-Clause license.*
