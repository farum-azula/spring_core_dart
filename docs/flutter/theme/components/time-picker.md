---
title: "Time picker theme in YAML — Spring for Dart"
description: "Style the time picker in YAML: 109 properties such as background-color, day-period-border-side and day-period-color, set under time-picker."
slug: /docs/flutter/theme/components/time-picker
section: Flutter / Theme / Components
order: 48
keywords: [flutter, theme, yaml, time picker, TimePickerThemeData]
---

# Time picker theme in YAML

The dialog to pick a time of day. It configures Flutter's `TimePickerThemeData`. Set it under `spring.flutter.theme.components.time-picker`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.time-picker`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        time-picker:
          day-period-border-side: { color: $colors.outline, width: 1 }
          day-period-shape: large
          day-period-text-style: { style: title-large, weight: bold }
          elevation: level2
          padding: { horizontal: 16, vertical: 8 }
          time-selector-separator-color:
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

A key with a dot, such as `cancel-button-style.min-height`, is inside a group: write it as a map under the first part.

| Property | Type | Values | States | What it does | Flutter field | Default |
|---|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The background color of a time picker. | `TimePickerThemeData.backgroundColor` | Flutter's Material 3 default |
| `cancel-button-style.min-height` | number | a number | no | The least height of the button. A shortcut for the height of minimum-size, with no minimum width. | `ButtonStyle.minimumSize` | Flutter's Material 3 default |
| `cancel-button-style.border-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the button border, with the default border width. A shortcut for the color of side. | `ButtonStyle.side` | Flutter's Material 3 default |
| `cancel-button-style.text-style` | text style | a style name (`title-large`) or a map | yes | The style for a button's text widget descendants. The color of the text style is typically not used directly, the foreground color is used instead. | `ButtonStyle.textStyle` | Flutter's Material 3 default |
| `cancel-button-style.background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The button's background fill color. | `ButtonStyle.backgroundColor` | Flutter's Material 3 default |
| `cancel-button-style.foreground-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The color for the button's text widget descendants. This color is typically used instead of the color of the text style. | `ButtonStyle.foregroundColor` | Flutter's Material 3 default |
| `cancel-button-style.overlay-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The highlight color that's typically used to indicate that the button is focused, hovered, or pressed. | `ButtonStyle.overlayColor` | Flutter's Material 3 default |
| `cancel-button-style.shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The shadow color of the button's material. | `ButtonStyle.shadowColor` | Flutter's Material 3 default |
| `cancel-button-style.surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The surface tint color of the button's material. | `ButtonStyle.surfaceTintColor` | Flutter's Material 3 default |
| `cancel-button-style.elevation` | elevation | `level0` to `level5`, or a number | yes | The elevation of the button's material. | `ButtonStyle.elevation` | Flutter's Material 3 default |
| `cancel-button-style.padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | yes | The padding between the button's boundary and its child. When the visual density is compact, the top and bottom insets are reduced by 8 pixels or set to 0 pixels if the result of the reduced padding is negative. | `ButtonStyle.padding` | Flutter's Material 3 default |
| `cancel-button-style.minimum-size` | size | `width, height`, one number, or a map | yes | The minimum size of the button itself before applying visual density. The size of the rectangle the button lies within may be larger per tap target size. | `ButtonStyle.minimumSize` | Flutter's Material 3 default |
| `cancel-button-style.fixed-size` | size | `width, height`, one number, or a map | yes | The button's size. This size is still constrained by the style's minimum size and maximum size. | `ButtonStyle.fixedSize` | Flutter's Material 3 default |
| `cancel-button-style.maximum-size` | size | `width, height`, one number, or a map | yes | The maximum size of the button itself. This value must be greater than or equal to minimum size. | `ButtonStyle.maximumSize` | Flutter's Material 3 default |
| `cancel-button-style.icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The icon's color inside of the button. | `ButtonStyle.iconColor` | Flutter's Material 3 default |
| `cancel-button-style.icon-size` | number | a number | yes | The icon's size inside of the button. | `ButtonStyle.iconSize` | Flutter's Material 3 default |
| `cancel-button-style.icon-alignment` | choice | `start`, `end` | no | Whether the icon of a button that has an icon and a label sits before (start) or after (end) the label. | `ButtonStyle.iconAlignment` | Flutter's Material 3 default |
| `cancel-button-style.side` | border side | `none`, or a map of `color`, `width`, `style` | yes | The color and weight of the button's outline. This value is combined with shape to create a shape decorated with an outline. | `ButtonStyle.side` | Flutter's Material 3 default |
| `cancel-button-style.shape` | shape | a token (`small`), a radius, or a map | yes | The shape of the button's underlying material. This shape is combined with side to create a shape decorated with an outline. | `ButtonStyle.shape` | Flutter's Material 3 default |
| `cancel-button-style.mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over this button's ink well. | `ButtonStyle.mouseCursor` | Flutter's Material 3 default |
| `cancel-button-style.visual-density` | visual density | `standard`, `compact`, `comfortable`, `adaptive`, or `h, v` | no | Defines how compact the button's layout will be. Density, in the context of a UI, is the vertical and horizontal "compactness" of the elements in the UI. | `ButtonStyle.visualDensity` | Flutter's Material 3 default |
| `cancel-button-style.tap-target-size` | choice | `padded`, `shrink-wrap` | no | Configures the minimum size of the area within which the button may be pressed. If the tap target size is larger than minimum size, the button will include a transparent margin that responds to taps. | `ButtonStyle.tapTargetSize` | Flutter's Material 3 default |
| `cancel-button-style.animation-duration` | duration | `250ms`, `1s` | no | Defines the duration of animated changes for shape and elevation. | `ButtonStyle.animationDuration` | Flutter's Material 3 default |
| `cancel-button-style.enable-feedback` | true / false | `true`, `false` | no | Whether a tap or a long press gives a sound or a vibration. | `ButtonStyle.enableFeedback` | Flutter's Material 3 default |
| `cancel-button-style.alignment` | alignment | `center`, `top-left`, ..., or `x, y` | no | The alignment of the button's child. Typically buttons are sized to be just big enough to contain the child and its padding. | `ButtonStyle.alignment` | Flutter's Material 3 default |
| `cancel-button-style.splash-factory` | choice | `ripple`, `sparkle`, `none` | no | Creates the ink well splash factory, which defines the appearance of "ink" splashes that occur in response to taps. Use splash factory to defeat ink splash rendering. | `ButtonStyle.splashFactory` | Flutter's Material 3 default |
| `confirm-button-style.min-height` | number | a number | no | The least height of the button. A shortcut for the height of minimum-size, with no minimum width. | `ButtonStyle.minimumSize` | Flutter's Material 3 default |
| `confirm-button-style.border-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the button border, with the default border width. A shortcut for the color of side. | `ButtonStyle.side` | Flutter's Material 3 default |
| `confirm-button-style.text-style` | text style | a style name (`title-large`) or a map | yes | The style for a button's text widget descendants. The color of the text style is typically not used directly, the foreground color is used instead. | `ButtonStyle.textStyle` | Flutter's Material 3 default |
| `confirm-button-style.background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The button's background fill color. | `ButtonStyle.backgroundColor` | Flutter's Material 3 default |
| `confirm-button-style.foreground-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The color for the button's text widget descendants. This color is typically used instead of the color of the text style. | `ButtonStyle.foregroundColor` | Flutter's Material 3 default |
| `confirm-button-style.overlay-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The highlight color that's typically used to indicate that the button is focused, hovered, or pressed. | `ButtonStyle.overlayColor` | Flutter's Material 3 default |
| `confirm-button-style.shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The shadow color of the button's material. | `ButtonStyle.shadowColor` | Flutter's Material 3 default |
| `confirm-button-style.surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The surface tint color of the button's material. | `ButtonStyle.surfaceTintColor` | Flutter's Material 3 default |
| `confirm-button-style.elevation` | elevation | `level0` to `level5`, or a number | yes | The elevation of the button's material. | `ButtonStyle.elevation` | Flutter's Material 3 default |
| `confirm-button-style.padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | yes | The padding between the button's boundary and its child. When the visual density is compact, the top and bottom insets are reduced by 8 pixels or set to 0 pixels if the result of the reduced padding is negative. | `ButtonStyle.padding` | Flutter's Material 3 default |
| `confirm-button-style.minimum-size` | size | `width, height`, one number, or a map | yes | The minimum size of the button itself before applying visual density. The size of the rectangle the button lies within may be larger per tap target size. | `ButtonStyle.minimumSize` | Flutter's Material 3 default |
| `confirm-button-style.fixed-size` | size | `width, height`, one number, or a map | yes | The button's size. This size is still constrained by the style's minimum size and maximum size. | `ButtonStyle.fixedSize` | Flutter's Material 3 default |
| `confirm-button-style.maximum-size` | size | `width, height`, one number, or a map | yes | The maximum size of the button itself. This value must be greater than or equal to minimum size. | `ButtonStyle.maximumSize` | Flutter's Material 3 default |
| `confirm-button-style.icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The icon's color inside of the button. | `ButtonStyle.iconColor` | Flutter's Material 3 default |
| `confirm-button-style.icon-size` | number | a number | yes | The icon's size inside of the button. | `ButtonStyle.iconSize` | Flutter's Material 3 default |
| `confirm-button-style.icon-alignment` | choice | `start`, `end` | no | Whether the icon of a button that has an icon and a label sits before (start) or after (end) the label. | `ButtonStyle.iconAlignment` | Flutter's Material 3 default |
| `confirm-button-style.side` | border side | `none`, or a map of `color`, `width`, `style` | yes | The color and weight of the button's outline. This value is combined with shape to create a shape decorated with an outline. | `ButtonStyle.side` | Flutter's Material 3 default |
| `confirm-button-style.shape` | shape | a token (`small`), a radius, or a map | yes | The shape of the button's underlying material. This shape is combined with side to create a shape decorated with an outline. | `ButtonStyle.shape` | Flutter's Material 3 default |
| `confirm-button-style.mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over this button's ink well. | `ButtonStyle.mouseCursor` | Flutter's Material 3 default |
| `confirm-button-style.visual-density` | visual density | `standard`, `compact`, `comfortable`, `adaptive`, or `h, v` | no | Defines how compact the button's layout will be. Density, in the context of a UI, is the vertical and horizontal "compactness" of the elements in the UI. | `ButtonStyle.visualDensity` | Flutter's Material 3 default |
| `confirm-button-style.tap-target-size` | choice | `padded`, `shrink-wrap` | no | Configures the minimum size of the area within which the button may be pressed. If the tap target size is larger than minimum size, the button will include a transparent margin that responds to taps. | `ButtonStyle.tapTargetSize` | Flutter's Material 3 default |
| `confirm-button-style.animation-duration` | duration | `250ms`, `1s` | no | Defines the duration of animated changes for shape and elevation. | `ButtonStyle.animationDuration` | Flutter's Material 3 default |
| `confirm-button-style.enable-feedback` | true / false | `true`, `false` | no | Whether a tap or a long press gives a sound or a vibration. | `ButtonStyle.enableFeedback` | Flutter's Material 3 default |
| `confirm-button-style.alignment` | alignment | `center`, `top-left`, ..., or `x, y` | no | The alignment of the button's child. Typically buttons are sized to be just big enough to contain the child and its padding. | `ButtonStyle.alignment` | Flutter's Material 3 default |
| `confirm-button-style.splash-factory` | choice | `ripple`, `sparkle`, `none` | no | Creates the ink well splash factory, which defines the appearance of "ink" splashes that occur in response to taps. Use splash factory to defeat ink splash rendering. | `ButtonStyle.splashFactory` | Flutter's Material 3 default |
| `day-period-border-side` | border side | `none`, or a map of `color`, `width`, `style` | no | The color and weight of the day period's outline. | `TimePickerThemeData.dayPeriodBorderSide` | Flutter's Material 3 default |
| `day-period-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The background color of the AM/PM toggle. If the segment is not selected, transparent is used to allow the dialog's color to be used. | `TimePickerThemeData.dayPeriodColor` | Flutter's Material 3 default |
| `day-period-shape` | shape | a token (`small`), a radius, or a map | no | The shape of the day period that the time picker uses. | `TimePickerThemeData.dayPeriodShape` | Flutter's Material 3 default |
| `day-period-text-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the day period text that represents AM/PM. | `TimePickerThemeData.dayPeriodTextColor` | Flutter's Material 3 default |
| `day-period-text-style` | text style | a style name (`title-large`) or a map | no | Used to configure the text styles for the day period control. | `TimePickerThemeData.dayPeriodTextStyle` | Flutter's Material 3 default |
| `dial-background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The background color of the time picker dial when the entry mode is dial or dial only. | `TimePickerThemeData.dialBackgroundColor` | Flutter's Material 3 default |
| `dial-hand-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the time picker dial's hand when the entry mode is dial or dial only. | `TimePickerThemeData.dialHandColor` | Flutter's Material 3 default |
| `dial-text-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the dial text that represents specific hours and minutes. | `TimePickerThemeData.dialTextColor` | Flutter's Material 3 default |
| `dial-text-style` | text style | a style name (`title-large`) or a map | no | The text style for the numbers on the time selection dial. | `TimePickerThemeData.dialTextStyle` | Flutter's Material 3 default |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The Material elevation for the time picker dialog. | `TimePickerThemeData.elevation` | Flutter's Material 3 default |
| `entry-mode-icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the entry mode icon button. | `TimePickerThemeData.entryModeIconColor` | Flutter's Material 3 default |
| `help-text-style` | text style | a style name (`title-large`) or a map | no | Used to configure the text styles for the helper text in the header. | `TimePickerThemeData.helpTextStyle` | Flutter's Material 3 default |
| `hour-minute-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The background color of the hour and minute boxes in the header. | `TimePickerThemeData.hourMinuteColor` | Flutter's Material 3 default |
| `hour-minute-shape` | shape | a token (`small`), a radius, or a map | no | The shape of the hour and minute controls that the time picker uses. | `TimePickerThemeData.hourMinuteShape` | Flutter's Material 3 default |
| `hour-minute-text-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the header text that represents hours and minutes. | `TimePickerThemeData.hourMinuteTextColor` | Flutter's Material 3 default |
| `hour-minute-text-style` | text style | a style name (`title-large`) or a map | no | Used to configure the text styles for the hour/minute controls. | `TimePickerThemeData.hourMinuteTextStyle` | Flutter's Material 3 default |
| `input-decoration.style` | choice | `outline`, `underline`, `filled` | no | The look of the field: outline draws a box around it, underline a line below it and filled paints the field with a fill color and a line below it. It sets the border and the fill together. | `InputDecorationThemeData.border` | Flutter's Material 3 default |
| `input-decoration.shape` | shape | a token (`small`), a radius, or a map | no | The corner shape of the field border. A rounded shape rounds the corners of an outline field and the top corners of a filled one. | `InputDecorationThemeData.border` | Flutter's Material 3 default |
| `input-decoration.border` | input border | `outline`, `underline`, or a map | no | The shape of the border to draw around the decoration's container. The decoration's container is the area which is filled if filled is true and bordered per the border. | `InputDecorationThemeData.border` | Flutter's Material 3 default |
| `input-decoration.filled` | true / false | `true`, `false` | no | If true the decoration's container is filled with fill color. Typically this field set to true if border is an underline input border. | `InputDecorationThemeData.filled` | Flutter's Material 3 default |
| `input-decoration.fill-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color to fill the decoration's container with, if filled is true. The decoration's container is the area, defined by the border's get outer path, which is filled if filled is true and bordered per the border. | `InputDecorationThemeData.fillColor` | Flutter's Material 3 default |
| `input-decoration.content-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding for the input decoration's container. The decoration's container is the area which is filled if filled is true and bordered per the border. | `InputDecorationThemeData.contentPadding` | Flutter's Material 3 default |
| `input-decoration.label-style` | text style | a style name (`title-large`) or a map | no | The style to use for label text when the label is on top of the input field. When the label text is above (that is, vertically adjacent to) the input field, the text uses the floating label style instead. | `InputDecorationThemeData.labelStyle` | Flutter's Material 3 default |
| `input-decoration.floating-label-style` | text style | a style name (`title-large`) or a map | no | The style to use for label text when the label is above (that is, vertically adjacent to) the input field. When the label text is on top of the input field, the text uses the label style instead. | `InputDecorationThemeData.floatingLabelStyle` | Flutter's Material 3 default |
| `input-decoration.helper-style` | text style | a style name (`title-large`) or a map | no | The style to use for helper text. | `InputDecorationThemeData.helperStyle` | Flutter's Material 3 default |
| `input-decoration.helper-max-lines` | whole number | a whole number | no | The maximum number of lines the helper text can occupy. This value is passed along to the max lines attribute of the text widget used to display the helper. | `InputDecorationThemeData.helperMaxLines` | Flutter's Material 3 default |
| `input-decoration.hint-style` | text style | a style name (`title-large`) or a map | no | The style to use for the hint text. Also used for the label text when the label text is displayed on top of the input field (that is, at the same location on the screen where text may be entered in the input field). | `InputDecorationThemeData.hintStyle` | Flutter's Material 3 default |
| `input-decoration.hint-fade-duration` | duration | `250ms`, `1s` | no | The duration of the hint text fade in and fade out animations. | `InputDecorationThemeData.hintFadeDuration` | Flutter's Material 3 default |
| `input-decoration.hint-max-lines` | whole number | a whole number | no | The maximum number of lines the hint text can occupy. This value is passed along to the max lines attribute of the text widget used to display the hint text. | `InputDecorationThemeData.hintMaxLines` | Flutter's Material 3 default |
| `input-decoration.error-style` | text style | a style name (`title-large`) or a map | no | The style to use for the error text. | `InputDecorationThemeData.errorStyle` | Flutter's Material 3 default |
| `input-decoration.error-max-lines` | whole number | a whole number | no | The maximum number of lines the error text can occupy. This value is passed along to the max lines attribute of the text widget used to display the error. | `InputDecorationThemeData.errorMaxLines` | Flutter's Material 3 default |
| `input-decoration.floating-label-behavior` | choice | `never`, `auto`, `always` | no | Defines **how** the floating label should behave. When auto the label will float to the top only when the field is focused or has some text content, otherwise it will appear in the field in place of the content. | `InputDecorationThemeData.floatingLabelBehavior` | Flutter's Material 3 default |
| `input-decoration.is-dense` | true / false | `true`, `false` | no | Whether the input decorator's child is part of a dense form (that is, uses less vertical space). | `InputDecorationThemeData.isDense` | Flutter default: false |
| `input-decoration.is-collapsed` | true / false | `true`, `false` | no | Whether the decoration is the same size as the input field. A collapsed decoration cannot have label text, error text, or an icon. | `InputDecorationThemeData.isCollapsed` | Flutter's Material 3 default |
| `input-decoration.icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The Color to use for the icon. | `InputDecorationThemeData.iconColor` | Flutter's Material 3 default |
| `input-decoration.prefix-style` | text style | a style name (`title-large`) or a map | no | The style to use for the prefix text. | `InputDecorationThemeData.prefixStyle` | Flutter's Material 3 default |
| `input-decoration.prefix-icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The Color to use for the prefix icon. | `InputDecorationThemeData.prefixIconColor` | Flutter's Material 3 default |
| `input-decoration.prefix-icon-constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | The constraints to use for prefix icon constraints. This can be used to modify the box constraints surrounding prefix icon. | `InputDecorationThemeData.prefixIconConstraints` | Flutter's Material 3 default |
| `input-decoration.suffix-style` | text style | a style name (`title-large`) or a map | no | The style to use for the suffix text. | `InputDecorationThemeData.suffixStyle` | Flutter's Material 3 default |
| `input-decoration.suffix-icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The Color to use for the suffix icon. | `InputDecorationThemeData.suffixIconColor` | Flutter's Material 3 default |
| `input-decoration.suffix-icon-constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | The constraints to use for suffix icon constraints. This can be used to modify the box constraints surrounding suffix icon. | `InputDecorationThemeData.suffixIconConstraints` | Flutter's Material 3 default |
| `input-decoration.counter-style` | text style | a style name (`title-large`) or a map | no | The style to use for the counter text. | `InputDecorationThemeData.counterStyle` | Flutter's Material 3 default |
| `input-decoration.outline-border` | border side | `none`, or a map of `color`, `width`, `style` | no | The color and width of the border of an outline field. | `InputDecorationThemeData.outlineBorder` | Flutter's Material 3 default |
| `input-decoration.active-indicator-border` | border side | `none`, or a map of `color`, `width`, `style` | no | The color and width of the line of an underline field. | `InputDecorationThemeData.activeIndicatorBorder` | Flutter's Material 3 default |
| `input-decoration.focus-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color blended with the fill color while the field has focus. | `InputDecorationThemeData.focusColor` | Flutter's Material 3 default |
| `input-decoration.hover-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color blended with the fill color while the pointer is over the field. | `InputDecorationThemeData.hoverColor` | Flutter's Material 3 default |
| `input-decoration.error-border` | input border | `outline`, `underline`, or a map | no | The border to display when the input decorator does not have the focus and is showing an error. | `InputDecorationThemeData.errorBorder` | Flutter's Material 3 default |
| `input-decoration.focused-border` | input border | `outline`, `underline`, or a map | no | The border to display when the input decorator has the focus and is not showing an error. | `InputDecorationThemeData.focusedBorder` | Flutter's Material 3 default |
| `input-decoration.focused-error-border` | input border | `outline`, `underline`, or a map | no | The border to display when the input decorator has the focus and is showing an error. | `InputDecorationThemeData.focusedErrorBorder` | Flutter's Material 3 default |
| `input-decoration.disabled-border` | input border | `outline`, `underline`, or a map | no | The border to display when the input decorator is disabled and is not showing an error. | `InputDecorationThemeData.disabledBorder` | Flutter's Material 3 default |
| `input-decoration.enabled-border` | input border | `outline`, `underline`, or a map | no | The border to display when the input decorator is enabled and is not showing an error. | `InputDecorationThemeData.enabledBorder` | Flutter's Material 3 default |
| `input-decoration.align-label-with-hint` | true / false | `true`, `false` | no | Aligns the label with the hint at the top of the field instead of the center. Use it for fields with several lines. | `InputDecorationThemeData.alignLabelWithHint` | Flutter's Material 3 default |
| `input-decoration.constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | Defines minimum and maximum sizes for the input decorator. Typically the decorator will fill the horizontal space it is given. | `InputDecorationThemeData.constraints` | Flutter's Material 3 default |
| `input-decoration.visual-density` | visual density | `standard`, `compact`, `comfortable`, `adaptive`, or `h, v` | no | Defines how compact the decoration's layout will be. When the visual density is compact, the vertical aspect of content padding is reduced by 8 pixels. | `InputDecorationThemeData.visualDensity` | Flutter's Material 3 default |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding around the time picker dialog when the entry mode is dial or dial only. | `TimePickerThemeData.padding` | Flutter's Material 3 default |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of the dialog that the time picker is presented in. | `TimePickerThemeData.shape` | Flutter's Material 3 default |
| `time-selector-separator-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The color of the time selector separator between the hour and minute controls. | `TimePickerThemeData.timeSelectorSeparatorColor` | Flutter's Material 3 default |
| `time-selector-separator-text-style` | text style | a style name (`title-large`) or a map | yes | Used to configure the text style for the time selector separator between the hour and minute controls. | `TimePickerThemeData.timeSelectorSeparatorTextStyle` | Flutter's Material 3 default |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.timePickerTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).timePickerTheme;
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
