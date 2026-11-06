---
title: "Input theme in YAML — Spring for Dart"
description: "Style the input in YAML: 38 properties such as style, shape and border, set under input."
slug: /docs/flutter/theme/components/input
section: Flutter / Theme / Components
order: 30
keywords: [flutter, theme, yaml, input, InputDecorationThemeData]
---

# Input theme in YAML

Text fields: the border, fill, labels and hints. It configures Flutter's `InputDecorationThemeData`. Set it under `spring.flutter.theme.components.input`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.input`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        input:
          style: outline
          shape: large
          border: outline
          filled: true
          fill-color: $colors.primary
          content-padding: { horizontal: 16, vertical: 8 }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field | Default |
|---|---|---|---|---|---|---|
| `style` | choice | `outline`, `underline`, `filled` | no | The look of the field: outline draws a box around it, underline a line below it and filled paints the field with a fill color and a line below it. It sets the border and the fill together. | `InputDecorationThemeData.border` | Flutter's Material 3 default |
| `shape` | shape | a token (`small`), a radius, or a map | no | The corner shape of the field border. A rounded shape rounds the corners of an outline field and the top corners of a filled one. | `InputDecorationThemeData.border` | Flutter's Material 3 default |
| `border` | input border | `outline`, `underline`, or a map | no | The shape of the border to draw around the decoration's container. The decoration's container is the area which is filled if filled is true and bordered per the border. | `InputDecorationThemeData.border` | Flutter's Material 3 default |
| `filled` | true / false | `true`, `false` | no | If true the decoration's container is filled with fill color. Typically this field set to true if border is an underline input border. | `InputDecorationThemeData.filled` | Flutter's Material 3 default |
| `fill-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color to fill the decoration's container with, if filled is true. The decoration's container is the area, defined by the border's get outer path, which is filled if filled is true and bordered per the border. | `InputDecorationThemeData.fillColor` | Flutter's Material 3 default |
| `content-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding for the input decoration's container. The decoration's container is the area which is filled if filled is true and bordered per the border. | `InputDecorationThemeData.contentPadding` | Flutter's Material 3 default |
| `label-style` | text style | a style name (`title-large`) or a map | no | The style to use for label text when the label is on top of the input field. When the label text is above (that is, vertically adjacent to) the input field, the text uses the floating label style instead. | `InputDecorationThemeData.labelStyle` | Flutter's Material 3 default |
| `floating-label-style` | text style | a style name (`title-large`) or a map | no | The style to use for label text when the label is above (that is, vertically adjacent to) the input field. When the label text is on top of the input field, the text uses the label style instead. | `InputDecorationThemeData.floatingLabelStyle` | Flutter's Material 3 default |
| `helper-style` | text style | a style name (`title-large`) or a map | no | The style to use for helper text. | `InputDecorationThemeData.helperStyle` | Flutter's Material 3 default |
| `helper-max-lines` | whole number | a whole number | no | The maximum number of lines the helper text can occupy. This value is passed along to the max lines attribute of the text widget used to display the helper. | `InputDecorationThemeData.helperMaxLines` | Flutter's Material 3 default |
| `hint-style` | text style | a style name (`title-large`) or a map | no | The style to use for the hint text. Also used for the label text when the label text is displayed on top of the input field (that is, at the same location on the screen where text may be entered in the input field). | `InputDecorationThemeData.hintStyle` | Flutter's Material 3 default |
| `hint-fade-duration` | duration | `250ms`, `1s` | no | The duration of the hint text fade in and fade out animations. | `InputDecorationThemeData.hintFadeDuration` | Flutter's Material 3 default |
| `hint-max-lines` | whole number | a whole number | no | The maximum number of lines the hint text can occupy. This value is passed along to the max lines attribute of the text widget used to display the hint text. | `InputDecorationThemeData.hintMaxLines` | Flutter's Material 3 default |
| `error-style` | text style | a style name (`title-large`) or a map | no | The style to use for the error text. | `InputDecorationThemeData.errorStyle` | Flutter's Material 3 default |
| `error-max-lines` | whole number | a whole number | no | The maximum number of lines the error text can occupy. This value is passed along to the max lines attribute of the text widget used to display the error. | `InputDecorationThemeData.errorMaxLines` | Flutter's Material 3 default |
| `floating-label-behavior` | choice | `never`, `auto`, `always` | no | Defines **how** the floating label should behave. When auto the label will float to the top only when the field is focused or has some text content, otherwise it will appear in the field in place of the content. | `InputDecorationThemeData.floatingLabelBehavior` | Flutter's Material 3 default |
| `is-dense` | true / false | `true`, `false` | no | Whether the input decorator's child is part of a dense form (that is, uses less vertical space). | `InputDecorationThemeData.isDense` | Flutter default: false |
| `is-collapsed` | true / false | `true`, `false` | no | Whether the decoration is the same size as the input field. A collapsed decoration cannot have label text, error text, or an icon. | `InputDecorationThemeData.isCollapsed` | Flutter's Material 3 default |
| `icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The Color to use for the icon. | `InputDecorationThemeData.iconColor` | Flutter's Material 3 default |
| `prefix-style` | text style | a style name (`title-large`) or a map | no | The style to use for the prefix text. | `InputDecorationThemeData.prefixStyle` | Flutter's Material 3 default |
| `prefix-icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The Color to use for the prefix icon. | `InputDecorationThemeData.prefixIconColor` | Flutter's Material 3 default |
| `prefix-icon-constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | The constraints to use for prefix icon constraints. This can be used to modify the box constraints surrounding prefix icon. | `InputDecorationThemeData.prefixIconConstraints` | Flutter's Material 3 default |
| `suffix-style` | text style | a style name (`title-large`) or a map | no | The style to use for the suffix text. | `InputDecorationThemeData.suffixStyle` | Flutter's Material 3 default |
| `suffix-icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The Color to use for the suffix icon. | `InputDecorationThemeData.suffixIconColor` | Flutter's Material 3 default |
| `suffix-icon-constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | The constraints to use for suffix icon constraints. This can be used to modify the box constraints surrounding suffix icon. | `InputDecorationThemeData.suffixIconConstraints` | Flutter's Material 3 default |
| `counter-style` | text style | a style name (`title-large`) or a map | no | The style to use for the counter text. | `InputDecorationThemeData.counterStyle` | Flutter's Material 3 default |
| `outline-border` | border side | `none`, or a map of `color`, `width`, `style` | no | The color and width of the border of an outline field. | `InputDecorationThemeData.outlineBorder` | Flutter's Material 3 default |
| `active-indicator-border` | border side | `none`, or a map of `color`, `width`, `style` | no | The color and width of the line of an underline field. | `InputDecorationThemeData.activeIndicatorBorder` | Flutter's Material 3 default |
| `focus-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color blended with the fill color while the field has focus. | `InputDecorationThemeData.focusColor` | Flutter's Material 3 default |
| `hover-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color blended with the fill color while the pointer is over the field. | `InputDecorationThemeData.hoverColor` | Flutter's Material 3 default |
| `error-border` | input border | `outline`, `underline`, or a map | no | The border to display when the input decorator does not have the focus and is showing an error. | `InputDecorationThemeData.errorBorder` | Flutter's Material 3 default |
| `focused-border` | input border | `outline`, `underline`, or a map | no | The border to display when the input decorator has the focus and is not showing an error. | `InputDecorationThemeData.focusedBorder` | Flutter's Material 3 default |
| `focused-error-border` | input border | `outline`, `underline`, or a map | no | The border to display when the input decorator has the focus and is showing an error. | `InputDecorationThemeData.focusedErrorBorder` | Flutter's Material 3 default |
| `disabled-border` | input border | `outline`, `underline`, or a map | no | The border to display when the input decorator is disabled and is not showing an error. | `InputDecorationThemeData.disabledBorder` | Flutter's Material 3 default |
| `enabled-border` | input border | `outline`, `underline`, or a map | no | The border to display when the input decorator is enabled and is not showing an error. | `InputDecorationThemeData.enabledBorder` | Flutter's Material 3 default |
| `align-label-with-hint` | true / false | `true`, `false` | no | Aligns the label with the hint at the top of the field instead of the center. Use it for fields with several lines. | `InputDecorationThemeData.alignLabelWithHint` | Flutter's Material 3 default |
| `constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | Defines minimum and maximum sizes for the input decorator. Typically the decorator will fill the horizontal space it is given. | `InputDecorationThemeData.constraints` | Flutter's Material 3 default |
| `visual-density` | visual density | `standard`, `compact`, `comfortable`, `adaptive`, or `h, v` | no | Defines how compact the decoration's layout will be. When the visual density is compact, the vertical aspect of content padding is reduced by 8 pixels. | `InputDecorationThemeData.visualDensity` | Flutter's Material 3 default |

## Read it in Dart

The starter sets `ThemeData.inputDecorationTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).inputDecorationTheme;
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
