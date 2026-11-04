---
title: "Shape, spacing and elevation in a theme — Spring for Dart"
description: "The Material 3 corner scale, your own spacing names and the six elevation levels in Flutter theme YAML, and how components use them."
slug: /docs/flutter/theme/shape-spacing-elevation
section: Flutter / Theme
order: 5
keywords: [flutter, theme, yaml, shape, corner radius, spacing, elevation, material 3, tokens]
---

# Shape, spacing and elevation

Three small scales sit under every theme. **Shape** is the size of rounded
corners. **Spacing** is a set of gaps for your own widgets. **Elevation** is
how high a surface floats. You name a step in one place and components and
widgets refer to it by name.

```yaml
spring:
  flutter:
    theme:
      shape:
        medium: 16
        large: 24
        full: infinity
      elevation:
        level1: 2
      spacing:
        m: 16
        gutter: 20
      components:
        card:
          shape: large
          elevation: level1
```

## Shape: the corner scale

`shape.<token>` sets a corner radius in logical pixels. Names are Material 3's
and are written in kebab case.

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `shape.none` | number | radius | `0` | Square corners |
| `shape.extra-small` | number | radius | `4` | Very small rounding: text fields, tooltips, snack bars |
| `shape.small` | number | radius | `8` | Chips |
| `shape.medium` | number | radius | `12` | Cards |
| `shape.large` | number | radius | `16` | Floating action buttons |
| `shape.large-increased` | number | radius | `20` | A step between large and extra large |
| `shape.extra-large` | number | radius | `28` | Dialogs and bottom sheets |
| `shape.extra-large-increased` | number | radius | `32` | A step above extra large |
| `shape.extra-extra-large` | number | radius | `48` | The largest rounding |
| `shape.full` | number | radius or `infinity` | infinity | A stadium: fully round ends. Buttons use it |

Any other token name stops the start and lists these ten.

### Where shape tokens are used

A component follows a shape token. When a theme changes that token, the
component changes with it, without you writing the component:

| Component | Follows | Notes |
|---|---|---|
| `button` and the buttons that start from it (`elevated-button`, `filled-button`, `outlined-button`, `text-button`) | `full` | |
| `floating-action-button` | `large` | |
| `card` | `medium` | |
| `chip` | `small` | |
| `dialog` | `extra-large` | |
| `bottom-sheet` | `extra-large` | Top corners only |
| `input` | `extra-small` | |
| `popup-menu` | `extra-small` | |
| `snack-bar` | `extra-small` | |
| `tooltip` | `extra-small` | |

A component keeps Flutter's own shape until the theme changes its token.
Setting `shape.medium: 16` makes every card rounder; it does nothing to
components that follow another token.

### How a component refers to a shape

In a component, `shape` takes a token name, a radius, `stadium`, `circle`, or
a map:

```yaml
spring:
  flutter:
    theme:
      components:
        card:
          shape: large                      # a token
        chip:
          shape: 6                          # a radius
        filled-button:
          shape: stadium
        dialog:
          shape:
            type: continuous                # rounded, continuous, beveled, stadium, circle
            radius: extra-large
            side: { color: $colors.outline, width: 1 }
```

The corner types: `rounded` (the default), `continuous` (the smooth iOS
curve), `beveled` (cut corners), `stadium` and `circle`. A radius of
`infinity` (the `full` token) with the `rounded` type gives a stadium. A
`radius` or `border-radius` property takes a token name or a number too.

Anywhere in a theme a reference can read a token, even one you did not write:
`$shape.extra-small` is `4` unless your theme changes it. That makes a corner
in a `styles` entry follow the theme:

```yaml
spring:
  flutter:
    theme:
      styles:
        tag:
          radius: $shape.small
```

## Elevation levels

`elevation.<level>` sets the height of one of the six Material 3 levels.

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `elevation.level0` | number | any number | `0` | Flat on the surface |
| `elevation.level1` | number | any number | `1` | Cards, resting buttons |
| `elevation.level2` | number | any number | `3` | Raised or scrolled app bars |
| `elevation.level3` | number | any number | `6` | Menus and floating buttons at rest |
| `elevation.level4` | number | any number | `8` | Higher menus, hovered floating buttons |
| `elevation.level5` | number | any number | `12` | Dragged surfaces |

Any other name stops the start and lists `level0` ... `level5`.

Where a component property takes an elevation, you can write the level name
or a number:

```yaml
spring:
  flutter:
    theme:
      elevation:
        level1: 2          # every component that says level1 now uses 2
      components:
        card:
          elevation: level1
        app-bar:
          elevation: 0
          scrolled-under-elevation: level2
        filled-button:
          elevation: { default: level1, hovered: level2, pressed: level0 }
```

Changing a level changes only the components that name it. A component that
you do not give an elevation keeps Flutter's value.

## Spacing

`spacing.<name>` is a set of gaps for **your own widgets**. Material
components do not read it. Any name is allowed, and the values are numbers
in logical pixels.

| Name | Default | What it is for |
|---|---|---|
| `xs` | 4 | The smallest gap |
| `s` | 8 | A small gap between related items |
| `m` | 16 | The normal page padding |
| `l` | 24 | A gap between sections |
| `xl` | 32 | A large gap |
| any other name | none | Your own, such as `gutter: 20` |

```yaml
spring:
  flutter:
    theme:
      spacing:
        m: 12             # change a default
        gutter: 20        # add your own
      themes:
        compact:
          spacing: { s: 4, m: 8 }
```

### Read it in Dart

```dart
final theme = SpringTheme.of(context);
EdgeInsets.all(theme.space('m'));        // 16, or what the theme says
theme.space('gutter');                   // 20
theme.shape('large');                    // the corner radius, 16 by default
theme.elevation('level2');               // 3 by default

EdgeInsets.all(context.theme.spacing.gutter);   // typed
```

`space`, `shape` and `elevation` accept names in any spelling
(`extra-large`, `extraLarge`). An unknown name throws an `ArgumentError`.
With the generator, `context.theme.spacing` has a getter for each name you
declare; the defaults you did not write have none, so declare `s` and `m` if
you want `context.theme.spacing.m`. Shapes and elevations are not generated;
read them with `theme.shape(...)` and `theme.elevation(...)`.

## See also

- [Properties](properties.md)
- [Components](components/index.md): `shape`, `elevation` and `padding` per component
- [Tokens and references](tokens-and-references.md): `$spacing.m` and `$shape.large`
- [Styles and states](styles-and-states.md): numbers and insets for your own widgets
