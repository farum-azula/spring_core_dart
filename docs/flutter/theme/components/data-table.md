---
title: "Data table theme in YAML — Spring for Dart"
description: "Style the data table in YAML: 15 properties such as decoration, data-row-color and data-row-min-height, set under data-table."
slug: /docs/flutter/theme/components/data-table
section: Flutter / Theme / Components
order: 21
keywords: [flutter, theme, yaml, data table, DataTableThemeData]
---

# Data table theme in YAML

A table of rows and columns of data. It configures Flutter's `DataTableThemeData`. Set it under `spring.flutter.theme.components.data-table`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.data-table`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        data-table:
          decoration: { color: $colors.surface-container, radius: medium }
          data-row-color:
            default: $colors.primary
            hovered:
              color: $colors.primary
              alpha: 90%
            disabled:
              color: $colors.on-surface
              alpha: 12%
          data-row-min-height: 16
          data-text-style: { style: title-large, weight: bold }
          heading-cell-cursor: click
          heading-row-alignment: start
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `decoration` | decoration | a color, or a map of `color`, `radius`, `border`, `shape` | no | The background and border decoration for the table. | `DataTableThemeData.decoration` |
| `data-row-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The background color for the data rows. The color is painted as an overlay to the row. | `DataTableThemeData.dataRowColor` |
| `data-row-min-height` | number | a number | no | The minimum height of each row (excluding the row that contains column headings). | `DataTableThemeData.dataRowMinHeight` |
| `data-row-max-height` | number | a number | no | The maximum height of each row (excluding the row that contains column headings). | `DataTableThemeData.dataRowMaxHeight` |
| `data-text-style` | text style | a style name (`title-large`) or a map | no | The text style for data rows. | `DataTableThemeData.dataTextStyle` |
| `heading-row-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The background color for the heading row. The color is painted as an overlay to the row. | `DataTableThemeData.headingRowColor` |
| `heading-row-height` | number | a number | no | The height of the heading row. | `DataTableThemeData.headingRowHeight` |
| `heading-text-style` | text style | a style name (`title-large`) or a map | no | The text style for the heading row. | `DataTableThemeData.headingTextStyle` |
| `horizontal-margin` | number | a number | no | The horizontal margin between the edges of the table and the content in the first and last cells of each row. When a checkbox is displayed, it is also the margin between the checkbox the content in the first data column. | `DataTableThemeData.horizontalMargin` |
| `column-spacing` | number | a number | no | The horizontal margin between the contents of each data column. | `DataTableThemeData.columnSpacing` |
| `divider-thickness` | number | a number | no | The width of the divider that appears between table rows. Must be greater than or equal to zero. | `DataTableThemeData.dividerThickness` |
| `checkbox-horizontal-margin` | number | a number | no | Horizontal margin around the checkbox, if it is displayed. | `DataTableThemeData.checkboxHorizontalMargin` |
| `heading-cell-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over the heading row. | `DataTableThemeData.headingCellCursor` |
| `data-row-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over the data row. | `DataTableThemeData.dataRowCursor` |
| `heading-row-alignment` | choice | `start`, `end`, `center`, `space-between`, `space-around`, `space-evenly` | no | Defines the horizontal layout of the label and sort indicator in the heading row. | `DataTableThemeData.headingRowAlignment` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.dataTableTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).dataTableTheme;
```

## See also

- [All component themes](index.md)
- [Theme overview](../index.md)
- [Colors](../colors.md)
- [Typography](../typography.md)
- [Styles and states](../styles-and-states.md)
- [Tokens and references](../tokens-and-references.md)
- [Root theme properties](../properties.md)
- [Configuration reference](../../../configuration.md) (all properties of the framework)

---

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.9), copyright The Flutter Authors, BSD 3-Clause license.*
