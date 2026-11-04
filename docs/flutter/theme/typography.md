---
title: "Theme typography — Spring for Dart"
description: "Set the font family, fallback fonts and the 15 Material 3 text styles plus code from YAML: size, weight, height, letter spacing, and fonts from assets."
slug: /docs/flutter/theme/typography
section: Flutter / Theme
order: 4
keywords: [flutter, theme, yaml, typography, fonts, text styles, font-family, font-weight, letter-spacing, google fonts, assets]
---

# Theme typography

Material 3 has 15 text styles: five groups (display, headline, title, body,
label) in three sizes (large, medium, small). You can set the font for the
whole app, change a whole group at once, or change a single style. A sixteenth
style, `code`, is for monospaced text.

```yaml
spring:
  flutter:
    theme:
      typography:
        font-family: Inter
        font-family-fallback: [Noto Sans JP, Noto Sans]
        defaults:
          letter-spacing: 0.1
        display:
          font-family: Playfair Display
          weight: bold
        title-large:
          size: 24
          weight: semibold
          height: 1.3
        body-medium:
          height: 1.5
        code:
          font-family: JetBrains Mono
          size: 13
```

Everything you do not set keeps Material's value.

## Properties

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `typography.font-family` | text | a font family name | the platform's font | The font of all text |
| `typography.font-family-fallback` | list of text | family names, as a YAML list or one comma-separated value | none | Fonts to try, in order, for characters the main font does not have (for example Japanese) |
| `typography.defaults.<key>` | | the style keys below | none | Applies to all 15 styles. The weakest layer |
| `typography.<group>.<key>` | | `display`, `headline`, `title`, `body`, `label` | none | Applies to the three sizes of that group |
| `typography.<style>.<key>` | | the 15 styles below | Material's | Applies to one style. The strongest layer |
| `typography.code.<key>` | | the style keys below | `monospace`, size 14 | The style of monospaced text, which Material has no role for |

### Style keys

These keys work under `defaults`, a group, a style and `code`.

| Key | Type | Values | Default | What it does |
|---|---|---|---|---|
| `font-family` | text | a font family name | the `typography.font-family` | The font of this style |
| `size` | number | logical pixels, `22`, `13.5` | Material's | Font size |
| `weight` | number or name | `100` to `900` in steps of 100, or `thin`, `extra-light`, `light`, `normal` (or `regular`), `medium`, `semibold`, `bold`, `extra-bold`, `black` | Material's | Font weight. It is also set on the `wght` axis, so variable fonts follow it |
| `height` | number | a multiple of the size, `1.4` | Material's | Line height. `1.5` means lines are one and a half times the font size |
| `letter-spacing` | number | logical pixels, may be negative | Material's | Space added after each letter |

Weight names ignore case, `-`, `_` and spaces: `semibold`, `semi-bold` and
`SemiBold` are the same. A number that is not a multiple of 100, or outside
`100`..`900`, is an error.

Any other key under a style, for example `font-family-fallback`, stops the
start and lists these five. `font-family-fallback` exists only directly under
`typography`.

### The layers

For one style the layers are put together in this order, the later one
winning key by key:

1. `typography.defaults`
2. the group (`typography.title`)
3. the style (`typography.title-large`)

```yaml
spring:
  flutter:
    theme:
      typography:
        defaults: { letter-spacing: 0.2 }   # every style
        title: { weight: 600 }              # title-large, title-medium, title-small
        title-small: { weight: 500 }        # only this one is lighter
```

## The text roles

Style names are written in kebab case (`display-large`); `displayLarge` also
works. The sizes are Material 3's reference sizes, which apply when you do
not set `size`.

| Style | Reference size | Use it for |
|---|---|---|
| `display-large` | 57 | The biggest text: a hero number or a welcome headline |
| `display-medium` | 45 | Large headlines on big screens |
| `display-small` | 36 | Large headlines on small screens |
| `headline-large` | 32 | Titles of screens and large sections |
| `headline-medium` | 28 | Section titles |
| `headline-small` | 24 | Smaller section titles; the title of a dialog |
| `title-large` | 22 | The title in an app bar |
| `title-medium` | 16 | Titles of list items and cards; medium weight |
| `title-small` | 14 | Small titles and tab labels; medium weight |
| `body-large` | 16 | Long text and the main text of a screen |
| `body-medium` | 14 | The default text size of most widgets |
| `body-small` | 12 | Captions and supporting text |
| `label-large` | 14 | Button text |
| `label-medium` | 12 | Small labels, such as on a navigation bar |
| `label-small` | 11 | The smallest labels and badges |
| `code` | 14 | Monospaced text: identifiers, logs, ISBNs. Not a Material role |

The groups are `display`, `headline`, `title`, `body` and `label`. Any other
name under `typography` stops the start and lists the valid names.

### The `code` style

`code` starts as the `monospace` family at size 14, and your
`typography.code` keys go over it. It is read with
`SpringTheme.of(context).textStyle('code')`. If the monospace font is missing
on a platform, the text falls back to the theme's `font-family` and
`font-family-fallback`.

```yaml
spring:
  flutter:
    theme:
      typography:
        code: { font-family: JetBrains Mono, size: 13, letter-spacing: 0 }
```

## Fonts from assets

Put the font files in any directory listed under `flutter: assets:` in
`pubspec.yaml`. You do not need a `flutter: fonts:` section.

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/fonts/     # Inter-Regular.ttf, Inter-SemiBold.ttf, PlayfairDisplay-Bold.ttf
```

The starter loads every `.ttf` and `.otf` asset before the first frame. The
family name is the one stored inside the font file, not the file name, so
`Inter-SemiBold.ttf` becomes a weight of `Inter` and `PlayfairDisplay-Bold.ttf`
one of `Playfair Display`. Use that name in `font-family`.

- A file whose family name cannot be read (a `.ttc` collection or a broken
  file) is skipped with a warning.
- Assets that come from other packages (paths starting with `packages/`)
  are not loaded this way; declare the fonts of a package in its own
  `pubspec.yaml`.
- A family the theme names that is neither a loaded asset nor under
  `flutter: fonts:` is logged as a warning at start. It may still be a font
  of the platform. `monospace` is never reported.

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `spring.flutter.fonts.auto-load` | bool | `true`, `false` | `true` | `false` loads no font files this way. Fonts under `flutter: fonts:` still work |
| `spring.flutter.fonts.exclude` | list of globs | `assets/pdf/**` | none | Font assets not to load, such as fonts used only to make PDFs. `*` stays inside a directory, `**` crosses directories |

```yaml
spring:
  flutter:
    fonts:
      auto-load: true
      exclude: [assets/pdf/**]
```

## Read it in Dart

```dart
Text('NEON Books', style: Theme.of(context).textTheme.displaySmall);
Text(isbn, style: SpringTheme.of(context).textStyle('code'));
Text('Total', style: context.theme.typography.titleLarge);   // typed
```

`textStyle` accepts a style name in any spelling (`titleLarge`,
`title-large`) or `code`; another name throws an `ArgumentError`. With the
generator, `context.theme.typography` has a getter for each of the 15 styles
and `code` that you declare.

Components can take one of these styles by name:
`components.app-bar.title-text-style: title-large`. See
[components](components/index.md).

## See also

- [Properties](properties.md)
- [Cupertino](cupertino.md): how the text styles feed iOS-style text
- [Components](components/index.md): `text-style` properties
