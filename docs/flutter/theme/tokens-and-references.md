---
title: "Theme tokens and references — Spring for Dart"
description: "Your own theme values (tokens) at any depth, how a value is typed, and $ references to other values with color objects, in Flutter theme YAML."
slug: /docs/flutter/theme/tokens-and-references
section: Flutter / Theme
order: 6
keywords: [flutter, theme, yaml, tokens, design tokens, references, variables, alpha, mix, durations, lists]
---

# Tokens and references

**Tokens** are your own values: a brand color, a banner height, a list of
tags. They have no place in Material's theme, so they live under
`tokens` and are read in Dart. A **reference** (`$colors.primary`) lets one
value use another, so a design system is written once.

```yaml
spring:
  flutter:
    theme:
      colors:
        primary: '#F5E000'
      tokens:
        brand:
          accent: $colors.primary
          accent-soft: { color: $brand.accent, alpha: 16% }
          banner-height: 96
          fade: 250ms
          tag:
            radius: 14
            labels: [New, Staff pick, Sale]
            colors: [$brand.accent, '#00E5FF', white]
          hero:
            source: https://cdn.example.com/hero.png
            refresh: 1d
      themes:
        sepia:
          tokens:
            brand:
              accent: '#8B4513'      # accent-soft follows, because it refers to accent
```

## Tokens

`tokens.<group>.<key>` can be as deep as you like. A group is any key that
holds other keys. The theme checks nothing about names under `tokens`: they
are yours. Like every value, a token can differ per theme.

### How a value is typed

A token has no declared type. It is typed by what it looks like. The first
rule that matches wins, after surrounding spaces are removed:

| Order | Kind | It looks like | Examples | In Dart |
|---|---|---|---|---|
| 1 | number | digits with an optional sign, fraction or exponent; or `Infinity` in any case | `12`, `-3`, `+5`, `.5`, `2.`, `1.5`, `1e3`, `-2.5e-2`, `Infinity` | `double` |
| 2 | duration | a number (decimals allowed), optional spaces, then `ms`, `s`, `m`, `h` or `d` in any case | `250ms`, `250 ms`, `4s`, `1.5s`, `.5s`, `2m`, `1h`, `0.5d` | `Duration` |
| 3 | insets | two or four numbers separated by commas (or a YAML list of one, two or four numbers) | `12, 6`, `8, 4, 8, 4` | only in [styles](styles-and-states.md); in a token it is text |
| 4 | color | a hex code or a `Colors` name; or a map with a `color` (a color object) | `#F00`, `deepPurple.shade200`, `{ color: '#F00', alpha: 12% }`, `{ color: '#F00', mix: { with: white, amount: 50% }, alpha: 80% }` | `Color` |
| 5 | text | everything else | `hello`, `ease-out`, `bold`, `12px`, `https://example.com/a.png` | `String` |

A token or a style value that is a map with a `color` is a color. Next to
`color` it may have `mix` and `alpha` and nothing else: any other key is an
error (a group of tokens that has a `color` token next to others is not a
color, so call that token something else). The same duration syntax works
everywhere a time is read: motion, animations, styles, tokens, `transition`,
`refresh` and `timeout`.

Some things that are text, not what you might expect:

- `Red` and `WHITE` (color names are case sensitive), `#ABCD` and `#FF00`
  (wrong number of digits), `0x10` and `0xFF0000` (there is no `0x` color),
  `red.shade999`, `primary` and `on-surface` (a role is `$colors.primary`)
- `#F00 alpha 12%`, `#F00 mix white 14%` and `primary@38%` (the one-line
  color expressions are gone; a color with changes is an object)
- `12px`, `-5s` (no negative durations), `250 sec`, `NaN`
- `1,5,` and `12, red` (a list of numbers has only numbers)

Three or five numbers in a comma list are an error where insets are read
(a style).

### Lists

A list is a YAML list, or one comma-separated value. Its type comes from its
items: all colors is `List<Color>`, all numbers is `List<double>`, anything
else is `List<String>`. A list in a later layer (a theme, or the theme it
extends) replaces the whole list.

```yaml
spring:
  flutter:
    theme:
      tokens:
        chart:
          series: [$colors.primary, $colors.tertiary, '#FF6B00']   # List<Color>
          steps: [4, 8, 16]                                       # List<double>
          names: [Mon, Tue, Wed]                                  # List<String>
```

Write lists as YAML lists. A scalar such as `12, 6` is text in a token.

### Durations

A duration token is a number with a unit: `250ms`, `1.5s`, `2m`, `1h`. A
plain `250` is a number, not a duration. The same form is used by
[motion](motion-and-animations.md) and [styles](styles-and-states.md).

### Images

A token that is a map with a `source`, and whose other keys are only
`refresh`, `source-sha256`, `headers`, `timeout` and `fallback`,
is an **image**: it is downloaded, cached and refreshed like the
[background image](images.md). A map with any other key next to `source` is a
group of tokens, not an image. The image must be at least two groups deep:
`tokens.<group>.<key>`.

```yaml
spring:
  flutter:
    theme:
      tokens:
        brand:
          hero: { source: https://cdn.example.com/hero.png, refresh: 1d, fallback: assets/hero.png }
```

### Read tokens in Dart

```dart
final theme = SpringTheme.of(context);
theme.tokenColor('brand.accent');          // Color?
theme.tokenNumber('brand.banner-height');  // double?
theme.tokenDuration('brand.fade');         // Duration?
theme.token('brand.badge-text');           // String?
theme.tokenTexts('brand.tag.labels');      // List<String>?
theme.tokenColors('brand.tag.colors');     // List<Color>?
theme.tokenNumbers('chart.steps');         // List<double>?
theme.tokenImage('brand.hero');            // ThemeImage?
```

Each returns `null` when the token is missing or is not of that kind. With
the generator the types are fixed for you and every group becomes a small class:

```dart
final tag = context.theme.tokens.brand.tag;
tag.radius;      // double
tag.labels;      // List<String>
tag.colors;      // List<Color>
context.theme.tokens.brand.hero;   // ThemeImage
context.theme.tokens.brand.fade;   // Duration
```

A token must have one type in every theme. A token that is a color in one
theme and a number in another fails the build and names both places.

## References

A reference names another value of the same theme with `$` and its path.

| Form | Meaning |
|---|---|
| `$colors.primary` | The value at `colors.primary` |
| `$spacing.m` | The value at `spacing.m` |
| `$motion.durations.fast` | The value at `motion.durations.fast` |
| `$tokens.brand.accent` | The token, in full |
| `$brand.accent` | The token, shorter: `tokens.` may be dropped when the first segment is not the name of a theme section |
| `$colors.outline` | A Material color role you did not write: the role of the palette that the theme's `seed-color`, `brightness`, `scheme-variant` and `contrast` make |
| `$shape.extra-small` | A Material 3 corner radius you did not write |
| `$$` | A literal `$` |

The sections that start a path are exactly these: `brightness`, `seed-color`,
`scheme-variant`, `contrast`, `colors`, `typography`, `shape`, `elevation`,
`spacing`, `visual-density`, `tap-target-size`, `splash`, `motion`,
`components`, `tokens`, `cupertino`, `styles`, `animations` and `background`.
A group of tokens with one of these names (a group called `colors`) can only
be reached as `$tokens.colors.x`.

Rules:

- **A reference stands for the value's text.** A color object is referenced
  as the color it makes, so `{ color: $brand.accent, alpha: 12% }` can sit on
  a token that is itself an object. A list is referenced as its items joined
  with commas. A reference can sit anywhere in a value:
  `transition: $motion.durations.fast ease-out`.
- **Declared values win.** A role you wrote in `colors` is used as written.
  A role you did not write comes from the palette without your `colors`
  changes, so `$colors.outline` is stable.
- **Per theme, after `extends`.** References are resolved when the theme is
  put together. A dark theme that changes `colors.primary` changes everything
  that refers to it.
- **Path spelling.** Paths follow the usual key rules: no case, `-` and `_`
  differences. A dot or a dash at the very end (`$colors.primary.`, as in the
  end of a sentence) is not part of the path.
- **`$` and a non-letter is text.** `$5` stays `$5`.
- **A cycle or an unknown path stops the start.** The message shows the chain
  of references, or the closest known path ("did you mean").
- **Some values are never resolved.** Anything under `headers`, and the
  image keys `source`, `fallback` and `source-sha256`, are left exactly as
  written, including `$$`. A secret that arrives from a placeholder may
  contain `$`.

```yaml
spring:
  flutter:
    theme:
      seed-color: $brand.seed
      colors:
        primary-container: { color: $brand.accent, alpha: 18% }
        outline-variant: { color: $colors.outline, alpha: 40% }
      shape:
        small: 6
      styles:
        chip:
          radius: $shape.small
          padding: $spacing.s
      tokens:
        brand:
          seed: '#0057B8'
          accent: '#FF6B00'
```

### Why not `${...}`?

`${cdn.token}` is Spring's placeholder. It reads any property of the
application's `Environment` (a file, an environment variable,
`--dart-define`) and it still works inside a theme, for example in image
`headers`. A theme reference points at another value of the *same theme*,
by a path from the theme's root, and has to be resolved per theme, after
`extends`. A shorter form with its own sign keeps the two apart:
`${...}` is the application's, `$path` is the theme's.

## Color expressions

`alpha` and `mix` work on any color value, including references. See
[colors](colors.md#opacity-and-mixing-the-color-object).

## See also

- [Colors](colors.md)
- [Styles and states](styles-and-states.md): references inside `styles`
- [Images](images.md): image tokens
- [Overview](index.md#typed-keys-contexttheme): the generated `context.theme.tokens`
