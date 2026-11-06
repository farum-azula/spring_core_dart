---
title: "Search bar theme in YAML — Spring for Dart"
description: "Style the search bar in YAML: 12 properties such as elevation, background-color and shadow-color, set under search-bar."
slug: /docs/flutter/theme/components/search-bar
section: Flutter / Theme / Components
order: 41
keywords: [flutter, theme, yaml, search bar, SearchBarThemeData]
---

# Search bar theme in YAML

A field to type a search, with a leading icon and actions. It configures Flutter's `SearchBarThemeData`. Set it under `spring.flutter.theme.components.search-bar`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.search-bar`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        search-bar:
          elevation: level2
          background-color:
            default: $colors.primary
            hovered:
              color: $colors.primary
              alpha: 90%
            disabled:
              color: $colors.on-surface
              alpha: 12%
          side: { color: $colors.outline, width: 1 }
          shape: large
          padding: { horizontal: 16, vertical: 8 }
          text-style: { style: title-large, weight: bold }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `elevation` | elevation | `level0` to `level5`, or a number | yes | The elevation of the search bar's material. | `SearchBarThemeData.elevation` |
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The search bar's background fill color. | `SearchBarThemeData.backgroundColor` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The shadow color of the search bar's material. | `SearchBarThemeData.shadowColor` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The surface tint color of the search bar's material. This is not recommended for use. | `SearchBarThemeData.surfaceTintColor` |
| `overlay-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The highlight color that's typically used to indicate that the search bar is focused, hovered, or pressed. | `SearchBarThemeData.overlayColor` |
| `side` | border side | `none`, or a map of `color`, `width`, `style` | yes | The color and weight of the search bar's outline. This value is combined with shape to create a shape decorated with an outline. | `SearchBarThemeData.side` |
| `shape` | shape | a token (`small`), a radius, or a map | yes | The shape of the search bar's underlying material. This shape is combined with side to create a shape decorated with an outline. | `SearchBarThemeData.shape` |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | yes | The padding between the search bar's boundary and its contents. | `SearchBarThemeData.padding` |
| `text-style` | text style | a style name (`title-large`) or a map | yes | The style to use for the text being edited. | `SearchBarThemeData.textStyle` |
| `hint-style` | text style | a style name (`title-large`) or a map | yes | The style to use for the hint text. | `SearchBarThemeData.hintStyle` |
| `constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | The size limits of the search bar. | `SearchBarThemeData.constraints` |
| `text-capitalization` | choice | `words`, `sentences`, `characters`, `none` | no | How typed text is capitalized: none, words, sentences or characters. | `SearchBarThemeData.textCapitalization` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.searchBarTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).searchBarTheme;
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
