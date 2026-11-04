---
title: "Popup menu theme in YAML — Spring for Dart"
description: "Style the popup menu in YAML: 13 properties such as color, shape and menu-padding, set under popup-menu."
slug: /docs/flutter/theme/components/popup-menu
section: Flutter / Theme / Components
order: 37
keywords: [flutter, theme, yaml, popup menu, PopupMenuThemeData]
---

# Popup menu theme in YAML

The small menu that pops up from a button or a tap. It configures Flutter's `PopupMenuThemeData`. Set it under `spring.flutter.theme.components.popup-menu`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.popup-menu`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        popup-menu:
          color: $colors.primary
          shape: large
          menu-padding: { horizontal: 16, vertical: 8 }
          elevation: level2
          label-text-style:
            default: { style: title-large, weight: bold }
            hovered: { style: title-large, weight: bold }
            disabled: { style: title-large, weight: bold }
          enable-feedback: true
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The background color of the popup menu. | `PopupMenuThemeData.color` |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of the popup menu. | `PopupMenuThemeData.shape` |
| `menu-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding around the items of the popup menu. | `PopupMenuThemeData.menuPadding` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The elevation of the popup menu. | `PopupMenuThemeData.elevation` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used to paint shadow below the popup menu. | `PopupMenuThemeData.shadowColor` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used as an overlay on color of the popup menu. | `PopupMenuThemeData.surfaceTintColor` |
| `text-style` | text style | a style name (`title-large`) or a map | no | The text style of items in the popup menu. | `PopupMenuThemeData.textStyle` |
| `label-text-style` | text style | a style name (`title-large`) or a map | yes | The text style of the item labels. A value per state can style enabled and disabled items differently. | `PopupMenuThemeData.labelTextStyle` |
| `enable-feedback` | true / false | `true`, `false` | no | Whether a tap or a long press gives a sound or a vibration. | `PopupMenuThemeData.enableFeedback` |
| `mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over the widget. | `PopupMenuThemeData.mouseCursor` |
| `position` | choice | `over`, `under` | no | Whether the popup menu is positioned over or under the popup menu button. | `PopupMenuThemeData.position` |
| `icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the icon in the popup menu button. | `PopupMenuThemeData.iconColor` |
| `icon-size` | number | a number | no | The size of the icon in the popup menu button. | `PopupMenuThemeData.iconSize` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.popupMenuTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).popupMenuTheme;
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
