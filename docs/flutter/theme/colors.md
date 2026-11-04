---
title: "Theme colors — Spring for Dart"
description: "Material 3 color roles, seed color, scheme variants, contrast, named colors, hex forms and the color object with alpha and mix in Flutter theme YAML."
slug: /docs/flutter/theme/colors
section: Flutter / Theme
order: 3
keywords: [flutter, theme, yaml, colors, material 3, color scheme, seed color, hex, alpha, mix, color object, contrast]
---

# Theme colors

A theme's palette is made from one **seed color**. You can then change any
of the 46 Material 3 **color roles** by hand. Colors are written as names,
hex codes, references to other colors, or an object that changes the
opacity or mixes two colors.

```yaml
spring:
  flutter:
    theme:
      seed-color: '#0057B8'
      scheme-variant: vibrant
      contrast: 0.5
      colors:
        secondary: '#FFD700'
        error: '#B3261E'
        surface: '#FAFAFA'
        surface-container-low: grey.shade100
        outline-variant: { color: $colors.outline, alpha: 40% }
      themes:
        dark:
          seed-color: deepPurple.shade200
          colors:
            surface: '#121212'
```

## Seed, variant and contrast

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `seed-color` | color | any color | Flutter's baseline palette | The color the palette is made from. Without a seed (and without `scheme-variant` and `contrast`) the palette is Flutter's own Material 3 baseline, which is close to a purple seed but not the same |
| `scheme-variant` | enum | `tonalSpot`, `fidelity`, `content`, `vibrant`, `expressive`, `monochrome`, `neutral`, `rainbow`, `fruitSalad` | `tonalSpot` | How the palette is made from the seed |
| `contrast` | number | `-1` to `1` | `0` | Palette contrast |
| `brightness` | enum | `light`, `dark` | by theme | Light or dark tones. See [properties](properties.md#brightness) |
| `colors.<role>` | color | any color | from the seed | Replaces one role of the palette |

If you set `scheme-variant` or `contrast` without a `seed-color`, the seed is
Material's default purple (`#6750A4`).

### Scheme variants

The variant decides how the seed becomes primary, secondary, tertiary and
the greys. Names also work in kebab case (`fruit-salad`, `tonal-spot`).

| Variant | Result |
|---|---|
| `tonalSpot` | Material 3's default. Calm, medium-strength colors; secondary and tertiary are softer relatives of the seed |
| `fidelity` | Primary stays as close to the seed as possible. Good when the seed is your brand color |
| `content` | Like `fidelity`, made for colors taken from content such as an image |
| `vibrant` | Bright, strong colors |
| `expressive` | Playful: the hues of secondary and tertiary are turned away from the seed |
| `monochrome` | Greys only, no hue |
| `neutral` | Almost grey, with a hint of the seed |
| `rainbow` | Neutral surfaces with accents spread over many hues |
| `fruitSalad` | Playful and colorful, with hues turned further from the seed |

### Contrast

`contrast` moves the palette towards less or more contrast between a color
and the color shown on it. `0` is the Material 3 standard, `1` is the high
contrast level for accessibility, `-1` is reduced contrast. The value must
be from `-1` to `1`; anything else stops the start.

```yaml
spring:
  flutter:
    theme:
      seed-color: deepPurple
      themes:
        high-contrast:
          contrast: 1
```

## The color roles

`colors.<role>` takes any role below, in kebab case (`on-surface`). A role
you do not write comes from the seed. A role you do write replaces only that
one role; the others stay as the seed made them.

### Primary, secondary and tertiary

Primary is the main accent: buttons, active controls, key components.
Secondary is for less prominent components such as filter chips. Tertiary is
for contrasting accents that balance primary and secondary.

| Role | What it is used for |
|---|---|
| `primary` | The main accent: filled buttons, switches that are on, focus rings, links |
| `on-primary` | Text and icons on `primary` |
| `primary-container` | A softer accent surface: a prominent card, a selected navigation indicator |
| `on-primary-container` | Text and icons on `primary-container` |
| `primary-fixed` | An accent surface whose color does not change between light and dark |
| `primary-fixed-dim` | A dimmer `primary-fixed`, for emphasis next to it |
| `on-primary-fixed` | Text and icons on `primary-fixed` and `primary-fixed-dim` |
| `on-primary-fixed-variant` | Lower-emphasis text and icons on the fixed colors |
| `secondary` | A less prominent accent: filter chips, tonal buttons |
| `on-secondary` | Text and icons on `secondary` |
| `secondary-container` | A soft surface for secondary components: tonal buttons, selected chips |
| `on-secondary-container` | Text and icons on `secondary-container` |
| `secondary-fixed` | A secondary surface that stays the same in light and dark |
| `secondary-fixed-dim` | A dimmer `secondary-fixed` |
| `on-secondary-fixed` | Text and icons on the secondary fixed colors |
| `on-secondary-fixed-variant` | Lower-emphasis text and icons on the secondary fixed colors |
| `tertiary` | A contrasting accent for balance: badges, highlights |
| `on-tertiary` | Text and icons on `tertiary` |
| `tertiary-container` | A soft surface for tertiary components |
| `on-tertiary-container` | Text and icons on `tertiary-container` |
| `tertiary-fixed` | A tertiary surface that stays the same in light and dark |
| `tertiary-fixed-dim` | A dimmer `tertiary-fixed` |
| `on-tertiary-fixed` | Text and icons on the tertiary fixed colors |
| `on-tertiary-fixed-variant` | Lower-emphasis text and icons on the tertiary fixed colors |

### Error

| Role | What it is used for |
|---|---|
| `error` | Errors: invalid fields, destructive actions, error text |
| `on-error` | Text and icons on `error` |
| `error-container` | A soft surface for an error message |
| `on-error-container` | Text and icons on `error-container` |

### Surfaces

Surfaces are the backgrounds of the app. The container roles are five steps
from the lowest to the highest, so cards and sheets can sit above the page.

| Role | What it is used for |
|---|---|
| `surface` | The default background of screens, cards and sheets |
| `on-surface` | Text and icons on any surface; the main text color |
| `on-surface-variant` | Lower-emphasis text and icons on surfaces: hints, secondary text |
| `surface-dim` | A surface that is always darker than `surface` |
| `surface-bright` | A surface that is always brighter than `surface` |
| `surface-container-lowest` | The lowest container step, for areas behind others |
| `surface-container-low` | A low container step: cards, sheets |
| `surface-container` | The middle container step: navigation bars, dialogs |
| `surface-container-high` | A high container step: menus, date pickers |
| `surface-container-highest` | The highest container step: text fields, segmented buttons |
| `surface-tint` | The color laid over a surface to show elevation in some components |

### Inverse, outline and system

| Role | What it is used for |
|---|---|
| `inverse-surface` | A surface that looks the opposite of the theme: snack bars |
| `on-inverse-surface` | Text and icons on `inverse-surface` |
| `inverse-primary` | An accent shown on `inverse-surface`, such as the action of a snack bar |
| `outline` | Borders of text fields and outlined buttons; important dividers |
| `outline-variant` | Decorative dividers and lighter borders |
| `shadow` | The color of shadows |
| `scrim` | The color that dims the page behind a modal sheet or dialog |

Any other name under `colors` stops the start and lists the valid roles.

## Writing a color

A color value is one of these:

| Form | Examples | Notes |
|---|---|---|
| `#RGB` | `'#F00'` | Each digit is doubled: `#F00` is `#FF0000` |
| `#RRGGBB` | `'#FF40A0'` | Opaque |
| `#AARRGGBB` | `'#80FF0000'` | The first two digits are the opacity |
| A `Colors` name | `white`, `black`, `transparent`, `red`, `grey`, `deepPurple`, `black54`, `white70` | Flutter's `Colors` names |
| A shade | `red.shade200`, `deepPurple.shade700`, `redAccent.shade100` | `shade50`, `shade100` ... `shade900`; an accent family has 100, 200, 400 and 700 |
| A reference | `$colors.primary`, `$brand.accent` | A role or any value of the theme. See [tokens and references](tokens-and-references.md) |
| An object | `{ color: $colors.primary, alpha: 12% }` | A color with changes, below |

There is one form for a color with changes: the object. A role name alone
(`primary`) or a role with an opacity (`primary@12%`) is not a color; write
`$colors.primary`.

Notes:

- **Quote anything that starts with `#`** in YAML, or the rest of the line is
  a comment (also inside `{ ... }`).
- A `Colors` name can be written in camelCase (`deepPurple`), kebab case
  (`deep-purple`) or snake case (`deep_purple`). Names are case sensitive:
  `Red` is not a color.
- The families of Flutter's `Colors` are `red`, `pink`, `purple`,
  `deepPurple`, `indigo`, `blue`, `lightBlue`, `cyan`, `teal`, `green`,
  `lightGreen`, `lime`, `yellow`, `amber`, `orange`, `deepOrange`, `brown`,
  `grey` and `blueGrey`, each with `.shade50` to `.shade900`. Every colored
  family but `brown`, `grey` and `blueGrey` also has an accent family:
  `redAccent`, `pinkAccent`, `purpleAccent`, `deepPurpleAccent`,
  `indigoAccent`, `blueAccent`, `lightBlueAccent`, `cyanAccent`,
  `tealAccent`, `greenAccent`, `lightGreenAccent`, `limeAccent`,
  `yellowAccent`, `amberAccent`, `orangeAccent` and `deepOrangeAccent`,
  each with `.shade100`, `.shade200`, `.shade400` and `.shade700`
  (`pinkAccent.shade200`). `black87`, `black54`,
  `black45`, `black38`, `black26`, `black12`, `white70`, `white60`,
  `white54`, `white38`, `white30`, `white24`, `white12` and `white10` are the
  Flutter colors with that opacity.

### Opacity and mixing: the color object

A color with changes is an object. Only `color` is required:

```yaml
badge-fill:
  color: $colors.primary
  alpha: 12%
hover-fill:
  color: $colors.primary
  mix: { with: white, amount: 14% }
```

| Key | What it does |
|---|---|
| `color` | The color to start from: a plain color, a reference, or another object. Required |
| `mix` | `{ with: <color>, amount: <percent> }` moves the color that share of the way to `with` |
| `alpha` | Sets the opacity of the result to that share. It replaces the opacity the color had |

`mix` is applied first, then `alpha`, whatever the order of the keys. A
percent is `0%` to `100%`, or `0` to `1` (`12%` and `0.12` are the same).
A percent outside that range, a missing `color`, or a key that is not
`color`, `mix` or `alpha` stops the start and names the closest key
(`alfa` gives "did you mean 'alpha'"). The object works everywhere a color
does: `colors.*`, `seed-color`, tokens, styles (also per state), components
(also per state), `cupertino`, `background` and the colors of a gradient.
In a `.properties` file the object is written key by key:

```properties
spring.flutter.theme.colors.primary-container.color=$colors.primary
spring.flutter.theme.colors.primary-container.alpha=18%
```

```yaml
spring:
  flutter:
    theme:
      colors:
        primary: '#F5E000'
        primary-container: { color: $colors.primary, alpha: 18% }
        secondary-container:
          color: $colors.primary
          mix: { with: white, amount: 80% }
      tokens:
        glass: { color: '#FFFFFF', alpha: 8% }
```


Roles are not written by name in `colors`. To use one role in the definition
of another, or in `components` and `cupertino`, use a reference:
`$colors.primary`, `$colors.surface-container-low`; see
[components](components/index.md).

## Read it in Dart

```dart
final colors = Theme.of(context).colorScheme;        // Material apps
final theme = SpringTheme.of(context);               // any app type
theme.colorScheme.secondary;
theme.role('surface-container-low');                 // by name
```

With the generator, every role you declare under `colors` is typed:

```dart
context.theme.colors.surfaceContainerLow;   // Color
context.theme.colors.outline;               // a Material role also works
```

`context.theme.colors.<role>` gives the theme's own value, or the Material
role of that name from the palette. Roles you did not declare have no getter
(use `Theme.of(context).colorScheme`).

## See also

- [Properties](properties.md): `brightness`, `seed-color`, `scheme-variant`, `contrast`
- [Tokens and references](tokens-and-references.md): `$colors.primary` and color objects
- [Components](components/index.md): colors of buttons, cards and bars
- [Background](background.md): colors and gradients behind screens
