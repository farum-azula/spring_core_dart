---
title: "List tile theme in YAML — Spring for Dart"
description: "Style the list tile in YAML: 22 properties such as dense, shape and style, set under list-tile."
slug: /docs/flutter/theme/components/list-tile
section: Flutter / Theme / Components
order: 31
keywords: [flutter, theme, yaml, list tile, ListTileThemeData]
---

# List tile theme in YAML

A row in a list with a title, a subtitle and icons. It configures Flutter's `ListTileThemeData`. Set it under `spring.flutter.theme.components.list-tile`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.list-tile`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        list-tile:
          dense: true
          shape: large
          style: list
          selected-color: $colors.primary
          title-text-style: { style: title-large, weight: bold }
          mouse-cursor:
            default: click
            hovered: click
            disabled: click
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field | Default |
|---|---|---|---|---|---|---|
| `dense` | true / false | `true`, `false` | no | Whether this list tile is part of a vertically dense list. | `ListTileThemeData.dense` | Flutter's Material 3 default |
| `shape` | shape | a token (`small`), a radius, or a map | no | Defines the tile's custom border and decoration shape. | `ListTileThemeData.shape` | Flutter's Material 3 default |
| `style` | choice | `list`, `drawer` | no | The style of the tile, list or drawer. It changes the default font of the title. | `ListTileThemeData.style` | Flutter's Material 3 default |
| `selected-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Defines the color used for icons and text when the list tile is selected. | `ListTileThemeData.selectedColor` | Flutter's Material 3 default |
| `icon-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Defines the default color for leading and trailing icons. | `ListTileThemeData.iconColor` | Flutter's Material 3 default |
| `text-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Defines the text color for the title, subtitle, leading, and trailing. | `ListTileThemeData.textColor` | Flutter's Material 3 default |
| `title-text-style` | text style | a style name (`title-large`) or a map | no | The text style for ListTile's title. | `ListTileThemeData.titleTextStyle` | Flutter's Material 3 default |
| `subtitle-text-style` | text style | a style name (`title-large`) or a map | no | The text style for ListTile's subtitle. | `ListTileThemeData.subtitleTextStyle` | Flutter's Material 3 default |
| `leading-and-trailing-text-style` | text style | a style name (`title-large`) or a map | no | The text style for ListTile's leading and trailing. | `ListTileThemeData.leadingAndTrailingTextStyle` | Flutter's Material 3 default |
| `content-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The tile's internal padding. Insets a list tile's contents: its leading, title, subtitle, and trailing widgets. | `ListTileThemeData.contentPadding` | Flutter's Material 3 default |
| `tile-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Defines the background color of ListTile when selected is false. | `ListTileThemeData.tileColor` | Flutter's Material 3 default |
| `selected-tile-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Defines the background color of ListTile when selected is true. | `ListTileThemeData.selectedTileColor` | Flutter's Material 3 default |
| `horizontal-title-gap` | number | a number | no | The horizontal gap between the titles and the leading/trailing widgets. | `ListTileThemeData.horizontalTitleGap` | Flutter's Material 3 default |
| `min-vertical-padding` | number | a number | no | The minimum padding on the top and bottom of the title and subtitle widgets. | `ListTileThemeData.minVerticalPadding` | Flutter's Material 3 default |
| `min-leading-width` | number | a number | no | The minimum width allocated for the leading widget. | `ListTileThemeData.minLeadingWidth` | Flutter's Material 3 default |
| `min-tile-height` | number | a number | no | The least height of the tile. | `ListTileThemeData.minTileHeight` | Flutter's Material 3 default |
| `enable-feedback` | true / false | `true`, `false` | no | Whether a tap or a long press gives a sound or a vibration. | `ListTileThemeData.enableFeedback` | Flutter default: true |
| `mouse-cursor` | mouse cursor | `click`, `basic`, `forbidden`, `text`, ... | yes | The cursor for a mouse pointer when it enters or is hovering over the widget. | `ListTileThemeData.mouseCursor` | Flutter's Material 3 default |
| `visual-density` | visual density | `standard`, `compact`, `comfortable`, `adaptive`, or `h, v` | no | Defines how compact the list tile's layout will be. Density, in the context of a UI, is the vertical and horizontal "compactness" of the elements in the UI. | `ListTileThemeData.visualDensity` | Flutter's Material 3 default |
| `title-alignment` | choice | `three-line`, `title-height`, `top`, `center`, `bottom` | no | Defines how leading and trailing are vertically aligned relative to the list tile's titles (title and subtitle). | `ListTileThemeData.titleAlignment` | Flutter's Material 3 default |
| `control-affinity` | choice | `leading`, `trailing`, `platform` | no | Where the checkbox, radio button or switch goes in a list tile: leading, trailing or platform. | `ListTileThemeData.controlAffinity` | Flutter's Material 3 default |
| `is-three-line` | true / false | `true`, `false` | no | Whether this list tile is intended to display three lines of text. When using a text widget for title and subtitle, you can enforce line limits using max lines. | `ListTileThemeData.isThreeLine` | Flutter's Material 3 default |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.listTileTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).listTileTheme;
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
