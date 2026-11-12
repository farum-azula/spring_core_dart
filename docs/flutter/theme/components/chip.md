---
title: "Chip theme in YAML — Spring for Dart"
description: "Style the chip in YAML: 22 properties such as color, background-color and delete-icon-color, set under chip."
slug: /docs/flutter/theme/components/chip
section: Flutter / Theme / Components
order: 20
keywords: [flutter, theme, yaml, chip, ChipThemeData]
---

# Chip theme in YAML

A small pill for a tag, a filter, a choice or an input. It configures Flutter's `ChipThemeData`. Set it under `spring.flutter.theme.components.chip`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.chip`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        chip:
          color:
            default: $colors.primary
            hovered:
              color: $colors.primary
              alpha: 90%
            disabled:
              color: $colors.on-surface
              alpha: 12%
          show-checkmark: true
          label-padding: { horizontal: 16, vertical: 8 }
          side: { color: $colors.outline, width: 1 }
          shape: large
          label-style: { style: title-large, weight: bold }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field | Default |
|---|---|---|---|---|---|---|
| `color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The color that fills the chip. | `ChipThemeData.color` | Flutter's Material 3 default |
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Color to be used for the unselected, enabled chip's background. | `ChipThemeData.backgroundColor` | Flutter's Material 3 default |
| `delete-icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the delete icon. | `ChipThemeData.deleteIconColor` | Flutter's Material 3 default |
| `disabled-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used for the chip's background to indicate that it is not enabled. | `ChipThemeData.disabledColor` | Flutter's Material 3 default |
| `selected-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Color to be used for the chip's background, indicating that it is selected. The chip is selected when selected is true. | `ChipThemeData.selectedColor` | Flutter's Material 3 default |
| `secondary-selected-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The fill color of the chip when it is selected. | `ChipThemeData.secondarySelectedColor` | Flutter's Material 3 default |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Color of the chip's shadow when the elevation is greater than 0. | `ChipThemeData.shadowColor` | Flutter's Material 3 default |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Color of the chip's surface tint overlay when its elevation is greater than 0. This is not recommended for use. | `ChipThemeData.surfaceTintColor` | Flutter's Material 3 default |
| `selected-shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Color of the chip's shadow when the elevation is greater than 0 and the chip is selected. | `ChipThemeData.selectedShadowColor` | Flutter's Material 3 default |
| `show-checkmark` | true / false | `true`, `false` | no | Whether or not to show a check mark when selected is true. | `ChipThemeData.showCheckmark` | Flutter default: true |
| `checkmark-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the check mark shown when the chip is selected. | `ChipThemeData.checkmarkColor` | Flutter's Material 3 default |
| `label-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding around the label widget. | `ChipThemeData.labelPadding` | Flutter's Material 3 default |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding between the contents of the chip and the outside shape. | `ChipThemeData.padding` | Flutter's Material 3 default |
| `side` | border side | `none`, or a map of `color`, `width`, `style` | no | The color and weight of the chip's outline. This value is combined with shape to create a shape decorated with an outline. | `ChipThemeData.side` | Flutter's Material 3 default |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of the chip border. | `ChipThemeData.shape` | Flutter's Material 3 default |
| `label-style` | text style | a style name (`title-large`) or a map | no | The text style of the chip label. | `ChipThemeData.labelStyle` | Flutter's Material 3 default |
| `secondary-label-style` | text style | a style name (`title-large`) or a map | no | The text style of the label when the chip is selected. | `ChipThemeData.secondaryLabelStyle` | Flutter's Material 3 default |
| `elevation` | elevation | `level0` to `level5`, or a number | no | Elevation to be applied on the chip relative to its parent. This controls the size of the shadow below the chip. | `ChipThemeData.elevation` | Flutter's Material 3 default |
| `press-elevation` | elevation | `level0` to `level5`, or a number | no | Elevation to be applied on the chip relative to its parent during the press motion. This controls the size of the shadow below the chip. | `ChipThemeData.pressElevation` | Flutter's Material 3 default |
| `icon-theme` | icon theme | a color, or a map of `color`, `size`, ... | no | Theme used for all icons in the chip. | `ChipThemeData.iconTheme` | Flutter's Material 3 default |
| `avatar-box-constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | Optional size constraints for the avatar. | `ChipThemeData.avatarBoxConstraints` | Flutter's Material 3 default |
| `delete-icon-box-constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | Optional size constraints for the delete icon. | `ChipThemeData.deleteIconBoxConstraints` | Flutter's Material 3 default |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The Material starter sets `ThemeData.chipTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).chipTheme;
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
