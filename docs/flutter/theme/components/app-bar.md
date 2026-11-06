---
title: "App bar theme in YAML — Spring for Dart"
description: "Style the app bar in YAML: 17 properties such as background-color, foreground-color and elevation, set under app-bar."
slug: /docs/flutter/theme/components/app-bar
section: Flutter / Theme / Components
order: 1
keywords: [flutter, theme, yaml, app bar, AppBarTheme]
---

# App bar theme in YAML

The bar at the top of a screen, with a title and actions. It configures Flutter's `AppBarTheme`. Set it under `spring.flutter.theme.components.app-bar`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.app-bar`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        app-bar:
          background-color: $colors.primary
          elevation: level2
          shape: large
          icon-theme: { color: $colors.primary, size: 24 }
          center-title: true
          title-spacing: 16
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The fill color to use for an app bar's material. | `AppBarTheme.backgroundColor` |
| `foreground-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The default color for text and icons within the app bar. | `AppBarTheme.foregroundColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate at which to place this app bar relative to its parent. The value must be non-negative. | `AppBarTheme.elevation` |
| `scrolled-under-elevation` | elevation | `level0` to `level5`, or a number | no | The elevation that will be used if this app bar has something scrolled underneath it. The value must be non-negative. | `AppBarTheme.scrolledUnderElevation` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the shadow below the app bar. | `AppBarTheme.shadowColor` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the surface tint overlay applied to the app bar's background color to indicate elevation. | `AppBarTheme.surfaceTintColor` |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of the app bar's material as well as its shadow. A shadow is only displayed if the elevation is greater than zero. | `AppBarTheme.shape` |
| `icon-theme` | icon theme | a color, or a map of `color`, `size`, ... | no | The color, opacity, and size to use for toolbar icons. | `AppBarTheme.iconTheme` |
| `actions-icon-theme` | icon theme | a color, or a map of `color`, `size`, ... | no | The color, opacity, and size to use for the icons that appear in the app bar's actions. This property should only be used when the actions should be themed differently than the icon that appears in the app bar's leading widget. | `AppBarTheme.actionsIconTheme` |
| `center-title` | true / false | `true`, `false` | no | Whether the title should be centered. | `AppBarTheme.centerTitle` |
| `title-spacing` | number | a number | no | The spacing around title content on the horizontal axis. This spacing is applied even if there is no leading content or actions. | `AppBarTheme.titleSpacing` |
| `leading-width` | number | a number | no | Defines the width of leading widget. | `AppBarTheme.leadingWidth` |
| `toolbar-height` | number | a number | no | Defines the height of the toolbar component of an app bar. | `AppBarTheme.toolbarHeight` |
| `toolbar-text-style` | text style | a style name (`title-large`) or a map | no | The default text style for the AppBar's leading, and actions widgets, but not its title. | `AppBarTheme.toolbarTextStyle` |
| `title-text-style` | text style | a style name (`title-large`) or a map | no | The default text style for the AppBar's title widget. | `AppBarTheme.titleTextStyle` |
| `system-overlay-style` | choice | `light`, `dark` | no | The look of the phone status bar (clock, battery) above the app bar: light or dark icons. | `AppBarTheme.systemOverlayStyle` |
| `actions-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The padding between the actions and the end of the AppBar. | `AppBarTheme.actionsPadding` |

## Read it in Dart

The starter sets `ThemeData.appBarTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).appBarTheme;
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
