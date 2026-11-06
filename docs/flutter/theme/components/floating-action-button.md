---
title: "Floating action button theme in YAML — Spring for Dart"
description: "Style the floating action button in YAML: 21 properties such as foreground-color, background-color and focus-color, set under floating-action-button."
slug: /docs/flutter/theme/components/floating-action-button
section: Flutter / Theme / Components
order: 16
keywords: [flutter, theme, yaml, floating action button, FloatingActionButtonThemeData]
---

# Floating action button theme in YAML

The round button floating over the content for the main action of a screen. It configures Flutter's `FloatingActionButtonThemeData`, whose `style` is a `ButtonStyle`. It starts from [button](button.md): a value set here wins over the one of `button`. Set it under `spring.flutter.theme.components.floating-action-button`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.floating-action-button`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        floating-action-button:
          foreground-color: $colors.primary
          elevation: level2
          shape: large
          enable-feedback: true
          icon-size: 16
          mouse-cursor:
            default: click
            hovered: click
            disabled: click
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `foreground-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Color to be used for the unselected, enabled floating action button's foreground. | `FloatingActionButtonThemeData.foregroundColor` |
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Color to be used for the unselected, enabled floating action button's background. | `FloatingActionButtonThemeData.backgroundColor` |
| `focus-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color to use for filling the button when the button has input focus. | `FloatingActionButtonThemeData.focusColor` |
| `hover-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color to use for filling the button when the button has a pointer hovering over it. | `FloatingActionButtonThemeData.hoverColor` |
| `splash-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The splash color for this floating action button's ink well. | `FloatingActionButtonThemeData.splashColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate to be used for the unselected, enabled floating action button's elevation foreground. | `FloatingActionButtonThemeData.elevation` |
| `focus-elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate at which to place this button relative to its parent when the button has the input focus. This controls the size of the shadow below the floating action button. | `FloatingActionButtonThemeData.focusElevation` |
| `hover-elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate at which to place this button relative to its parent when the button is enabled and has a pointer hovering over it. This controls the size of the shadow below the floating action button. | `FloatingActionButtonThemeData.hoverElevation` |
| `disabled-elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate to be used for the disabled floating action button's elevation foreground. | `FloatingActionButtonThemeData.disabledElevation` |
| `highlight-elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate to be used for the selected, enabled floating action button's elevation foreground. | `FloatingActionButtonThemeData.highlightElevation` |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape to be used for the floating action button's material. | `FloatingActionButtonThemeData.shape` |
| `enable-feedback` | true / false | `true`, `false` | no | Whether a tap or a long press gives a sound or a vibration. | `FloatingActionButtonThemeData.enableFeedback` |
| `icon-size` | number | a number | no | The size of the icon inside the floating action button. | `FloatingActionButtonThemeData.iconSize` |
| `size-constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | The size limits of the regular floating action button. | `FloatingActionButtonThemeData.sizeConstraints` |
| `small-size-constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | The size limits of the small floating action button. | `FloatingActionButtonThemeData.smallSizeConstraints` |
| `large-size-constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | The size limits of the large floating action button. | `FloatingActionButtonThemeData.largeSizeConstraints` |
| `extended-size-constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | The size limits of the extended floating action button, the one with a label. | `FloatingActionButtonThemeData.extendedSizeConstraints` |
| `extended-icon-label-spacing` | number | a number | no | The spacing between the icon and the label for an extended floating action button. | `FloatingActionButtonThemeData.extendedIconLabelSpacing` |
| `extended-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding for an extended floating action button's content. | `FloatingActionButtonThemeData.extendedPadding` |
| `extended-text-style` | text style | a style name (`title-large`) or a map | no | The text style for an extended floating action button's label. | `FloatingActionButtonThemeData.extendedTextStyle` |
| `mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over the button. | `FloatingActionButtonThemeData.mouseCursor` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.floatingActionButtonTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).floatingActionButtonTheme.style;
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

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.9), copyright The Flutter Authors, BSD 3-Clause license.*
