---
title: "Toggle buttons theme in YAML — Spring for Dart"
description: "Style the toggle buttons in YAML: 15 properties such as text-style, constraints and color, set under toggle-buttons."
slug: /docs/flutter/theme/components/toggle-buttons
section: Flutter / Theme / Components
order: 15
keywords: [flutter, theme, yaml, toggle buttons, ToggleButtonsThemeData]
---

# Toggle buttons theme in YAML

A row of buttons that can each be switched on or off. It configures Flutter's `ToggleButtonsThemeData`. Set it under `spring.flutter.theme.components.toggle-buttons`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.toggle-buttons`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        toggle-buttons:
          text-style: { style: title-large, weight: bold }
          constraints: { max-width: 640 }
          color: $colors.primary
          border-width: 16
          border-radius: medium
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `text-style` | text style | a style name (`title-large`) or a map | no | The text style of the button labels. Its color is ignored: color, selected-color and disabled-color are used instead. | `ToggleButtonsThemeData.textStyle` |
| `constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | Defines the button's size. Typically used to constrain the button's minimum size. | `ToggleButtonsThemeData.constraints` |
| `color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color for descendant text and icon widgets if the toggle button is enabled. | `ToggleButtonsThemeData.color` |
| `selected-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color for descendant text and icon widgets if the toggle button is selected. | `ToggleButtonsThemeData.selectedColor` |
| `disabled-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color for descendant text and icon widgets if the toggle button is disabled. | `ToggleButtonsThemeData.disabledColor` |
| `fill-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The fill color for selected toggle buttons. | `ToggleButtonsThemeData.fillColor` |
| `focus-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color to use for filling the button when the button has input focus. | `ToggleButtonsThemeData.focusColor` |
| `highlight-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The highlight color for the toggle button's ink well. | `ToggleButtonsThemeData.highlightColor` |
| `splash-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The splash color for the toggle button's ink well. | `ToggleButtonsThemeData.splashColor` |
| `hover-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color to use for filling the toggle button when the button has a pointer hovering over it. | `ToggleButtonsThemeData.hoverColor` |
| `border-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The border color to display when the toggle button is enabled. | `ToggleButtonsThemeData.borderColor` |
| `selected-border-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The border color to display when the toggle button is selected. | `ToggleButtonsThemeData.selectedBorderColor` |
| `disabled-border-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The border color to display when the toggle button is disabled. | `ToggleButtonsThemeData.disabledBorderColor` |
| `border-width` | number | a number | no | The width of the border surrounding each toggle button. This applies to both the greater surrounding border, as well as the borders dividing each toggle button. | `ToggleButtonsThemeData.borderWidth` |
| `border-radius` | corner radius | a token (`medium`) or a number | no | The radii of the border's corners. | `ToggleButtonsThemeData.borderRadius` |

## Read it in Dart

The Material starter sets `ThemeData.toggleButtonsTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).toggleButtonsTheme;
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
