---
title: "Banner theme in YAML — Spring for Dart"
description: "Style the banner in YAML: 8 properties such as background-color, surface-tint-color and shadow-color, set under banner."
slug: /docs/flutter/theme/components/banner
section: Flutter / Theme / Components
order: 3
keywords: [flutter, theme, yaml, banner, MaterialBannerThemeData]
---

# Banner theme in YAML

A message bar at the top of a screen with actions to dismiss or follow it. It configures Flutter's `MaterialBannerThemeData`. Set it under `spring.flutter.theme.components.banner`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.banner`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        banner:
          background-color: $colors.primary
          surface-tint-color: $colors.on-primary
          content-text-style: { style: title-large, weight: bold }
          elevation: level2
          padding: { horizontal: 16, vertical: 8 }
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The background color of a material banner. | `MaterialBannerThemeData.backgroundColor` |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color used as an overlay on background color to indicate elevation. This is not recommended for use. | `MaterialBannerThemeData.surfaceTintColor` |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the shadow below the material banner. | `MaterialBannerThemeData.shadowColor` |
| `divider-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the divider. | `MaterialBannerThemeData.dividerColor` |
| `content-text-style` | text style | a style name (`title-large`) or a map | no | Used to configure the default text style for the content widget. | `MaterialBannerThemeData.contentTextStyle` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | How far the banner is raised above the screen, which sets the size of its shadow. | `MaterialBannerThemeData.elevation` |
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The amount of space by which to inset content. | `MaterialBannerThemeData.padding` |
| `leading-padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The amount of space by which to inset leading. | `MaterialBannerThemeData.leadingPadding` |

## Read it in Dart

The starter sets `ThemeData.bannerTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).bannerTheme;
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
