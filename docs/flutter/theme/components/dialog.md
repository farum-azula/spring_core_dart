---
title: "Dialog theme in YAML — Spring for Dart"
description: "Style the dialog in YAML: 14 properties such as background-color, elevation and shadow-color, set under dialog."
slug: /docs/flutter/theme/components/dialog
section: Flutter / Theme / Components
order: 23
keywords: [flutter, theme, yaml, dialog, DialogThemeData]
---

# Dialog theme in YAML

A window that appears over the content and asks for a decision. It configures Flutter's `DialogThemeData`. Set it under `spring.flutter.theme.components.dialog`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.dialog`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        dialog:
          background-color: $colors.primary
          elevation: level2
          shape: large
          alignment: center
          title-text-style: { style: title-large, weight: bold }
          actions-padding: { horizontal: 16, vertical: 8 }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The background color of the surface of this dialog. This sets the color on this dialog's material. | `DialogThemeData.backgroundColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate of this dialog. Controls how far above the parent the dialog will appear. | `DialogThemeData.elevation` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used to paint a drop shadow under the dialog's material, which reflects the dialog's elevation. | `DialogThemeData.shadowColor` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used as a surface tint overlay on the dialog's background color, which reflects the dialog's elevation. This is not recommended for use. | `DialogThemeData.surfaceTintColor` |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of this dialog's border. Defines the dialog's shape. | `DialogThemeData.shape` |
| `alignment` | alignment | `center`, `top-left`, ..., or `x, y` | no | How to align the dialog. | `DialogThemeData.alignment` |
| `title-text-style` | text style | a style name (`title-large`) or a map | no | The text style of the dialog title. | `DialogThemeData.titleTextStyle` |
| `content-text-style` | text style | a style name (`title-large`) or a map | no | The text style of the dialog content. | `DialogThemeData.contentTextStyle` |
| `actions-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | Padding around the set of actions at the bottom of the dialog. Typically used to provide padding to the button bar between the button bar and the edges of the dialog. | `DialogThemeData.actionsPadding` |
| `icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the icon at the top of the dialog. | `DialogThemeData.iconColor` |
| `barrier-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the dimmed layer behind the dialog. | `DialogThemeData.barrierColor` |
| `inset-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The amount of padding added to view insets on the outside of the dialog. This defines the minimum space between the screen's edges and the dialog. | `DialogThemeData.insetPadding` |
| `clip-behavior` | choice | `none`, `hard-edge`, `anti-alias`, `anti-alias-with-save-layer` | no | Controls how the contents of the dialog are clipped (or not) to the given shape. | `DialogThemeData.clipBehavior` |
| `constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | Constrains the size of the dialog. | `DialogThemeData.constraints` |

## Read it in Dart

The starter sets `ThemeData.dialogTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).dialogTheme;
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
