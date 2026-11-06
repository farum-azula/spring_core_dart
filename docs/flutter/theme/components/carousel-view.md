---
title: "Carousel view theme in YAML — Spring for Dart"
description: "Style the carousel view in YAML: 6 properties such as padding, background-color and elevation, set under carousel-view."
slug: /docs/flutter/theme/components/carousel-view
section: Flutter / Theme / Components
order: 18
keywords: [flutter, theme, yaml, carousel view, CarouselViewThemeData]
---

# Carousel view theme in YAML

A scrolling row of large items that stretch and shrink as you swipe. It configures Flutter's `CarouselViewThemeData`. Set it under `spring.flutter.theme.components.carousel-view`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.carousel-view`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        carousel-view:
          padding: { horizontal: 16, vertical: 8 }
          elevation: level2
          shape: large
          item-clip-behavior: none
          overlay-color:
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

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `padding` | insets | `16`, `h, v`, `l, t, r, b`, or a map | no | The amount of space to surround each carousel item with. | `CarouselViewThemeData.padding` |
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The background color for each carousel item. | `CarouselViewThemeData.backgroundColor` |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate of each carousel item. | `CarouselViewThemeData.elevation` |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of each carousel item's material. Defines each item's shape. | `CarouselViewThemeData.shape` |
| `item-clip-behavior` | choice | `none`, `hard-edge`, `anti-alias`, `anti-alias-with-save-layer` | no | The clip behavior for each carousel item. The item content will be clipped (or not) according to this option. | `CarouselViewThemeData.itemClipBehavior` |
| `overlay-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | yes | The highlight color to indicate the carousel items are in pressed, hovered or focused states. | `CarouselViewThemeData.overlayColor` |

### Values per state

A property with **yes** in the States column takes one value, or a map with a value for each state the widget can be in: `default`, `hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, `dragged` and `scrolled-under`. The widget uses the value of the strongest state it is in, in that order (`disabled` first), and then `default`. A state you leave out keeps Flutter's value. See [Styles and states](../styles-and-states.md).

## Read it in Dart

The starter sets `ThemeData.carouselViewTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).carouselViewTheme;
```

## See also

- [All component themes](index.md)
- [Theme overview](../index.md)
- [Colors](../colors.md)
- [Shape, spacing and elevation](../shape-spacing-elevation.md)
- [Styles and states](../styles-and-states.md)
- [Tokens and references](../tokens-and-references.md)
- [Root theme properties](../properties.md)
- [Configuration reference](../../../configuration.md) (all properties of the framework)

---

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.9), copyright The Flutter Authors, BSD 3-Clause license.*
