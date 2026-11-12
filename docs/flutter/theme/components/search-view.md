---
title: "Search view theme in YAML — Spring for Dart"
description: "Style the search view in YAML: 13 properties such as background-color, elevation and surface-tint-color, set under search-view."
slug: /docs/flutter/theme/components/search-view
section: Flutter / Theme / Components
order: 42
keywords: [flutter, theme, yaml, search view, SearchViewThemeData]
---

# Search view theme in YAML

The full-screen view with suggestions that opens from a search bar. It configures Flutter's `SearchViewThemeData`. Set it under `spring.flutter.theme.components.search-view`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.search-view`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        search-view:
          background-color: $colors.primary
          elevation: level2
          side: { color: $colors.outline, width: 1 }
          shape: large
          header-height: 16
          header-text-style: { style: title-large, weight: bold }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The search view's background fill color. | `SearchViewThemeData.backgroundColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The elevation of the search view's material. | `SearchViewThemeData.elevation` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The surface tint color of the search view's material. This is not recommended for use. | `SearchViewThemeData.surfaceTintColor` |
| `side` | border side | `none`, or a map of `color`, `width`, `style` | no | The color and weight of the search view's outline. This value is combined with view shape to create a shape decorated with an outline. | `SearchViewThemeData.side` |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of the search view's underlying material. This shape is combined with view side to create a shape decorated with an outline. | `SearchViewThemeData.shape` |
| `header-height` | number | a number | no | The height of the search field on the search view. | `SearchViewThemeData.headerHeight` |
| `header-text-style` | text style | a style name (`title-large`) or a map | no | The style to use for the text being edited on the search view. | `SearchViewThemeData.headerTextStyle` |
| `header-hint-style` | text style | a style name (`title-large`) or a map | no | The style to use for the view hint text on the search view. | `SearchViewThemeData.headerHintStyle` |
| `constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | The size limits of the search view. | `SearchViewThemeData.constraints` |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding inside the search view. | `SearchViewThemeData.padding` |
| `bar-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding around the search field at the top of the search view. | `SearchViewThemeData.barPadding` |
| `shrink-wrap` | true / false | `true`, `false` | no | Whether the view is only as tall as its suggestions. | `SearchViewThemeData.shrinkWrap` |
| `divider-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the line between the search field and the suggestions. | `SearchViewThemeData.dividerColor` |

## Read it in Dart

The Material starter sets `ThemeData.searchViewTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).searchViewTheme;
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
