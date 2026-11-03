---
title: "Menu theme in YAML — Spring for Dart"
description: "Style the menu in YAML: 13 properties such as background-color, shadow-color and surface-tint-color, set under menu."
slug: /docs/flutter/theme/components/menu
section: Flutter / Theme / Components
order: 32
keywords: [flutter, theme, yaml, menu, MenuThemeData]
---

# Menu theme in YAML

The panel of a menu that opens from a button. It configures Flutter's `MenuThemeData`. Set it under `spring.flutter.theme.components.menu`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.menu`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        menu:
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
          side: { color: $colors.outline, width: 1 }
          shape: large
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The menu's background fill color. | `MenuStyle.backgroundColor` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The shadow color of the menu's material. | `MenuStyle.shadowColor` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The surface tint color of the menu's material. | `MenuStyle.surfaceTintColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | yes | The elevation of the menu's material. | `MenuStyle.elevation` |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | yes | The padding between the menu's boundary and its child. | `MenuStyle.padding` |
| `minimum-size` | size | `width, height`, one number, or a map | yes | The minimum size of the menu itself. This value must be less than or equal to maximum size. | `MenuStyle.minimumSize` |
| `fixed-size` | size | `width, height`, one number, or a map | yes | The menu's size. This size is still constrained by the style's minimum size and maximum size. | `MenuStyle.fixedSize` |
| `maximum-size` | size | `width, height`, one number, or a map | yes | The maximum size of the menu itself. This value must be greater than or equal to minimum size. | `MenuStyle.maximumSize` |
| `side` | border side | `none`, or a map of `color`, `width`, `style` | yes | The color and weight of the menu's outline. This value is combined with shape to create a shape decorated with an outline. | `MenuStyle.side` |
| `shape` | shape | a token (`small`), a radius, or a map | yes | The shape of the menu's underlying material. This shape is combined with side to create a shape decorated with an outline. | `MenuStyle.shape` |
| `mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over this menu's ink well. | `MenuStyle.mouseCursor` |
| `visual-density` | visual density | `standard`, `compact`, `comfortable`, `adaptive`, or `h, v` | no | Defines how compact the menu's layout will be. Density, in the context of a UI, is the vertical and horizontal "compactness" of the elements in the UI. | `MenuStyle.visualDensity` |
| `alignment` | alignment | `center`, `top-left`, ..., or `x, y` | no | Determines the desired alignment of the submenu when opened relative to the button that opens it. | `MenuStyle.alignment` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.menuTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).menuTheme;
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
