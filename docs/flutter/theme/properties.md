---
title: "Theme properties — Spring for Dart"
description: "Every root property of spring.flutter.theme and of a theme: active, extends, brightness, seed-color, scheme-variant, contrast, splash, source."
slug: /docs/flutter/theme/properties
section: Flutter / Theme
order: 2
keywords: [flutter, theme, yaml, properties, seed-color, scheme-variant, contrast, visual-density, splash, extends, theme source]
---

# Theme properties

This page lists every property at the top of `spring.flutter.theme` and at
the top of a theme (`themes.<name>`). Properties that have their own page
(colors, typography, and so on) are listed here with a link.

```yaml
spring:
  flutter:
    theme:
      active: system
      system-light: light
      system-dark: dark

      brightness: light
      seed-color: deepPurple
      scheme-variant: tonalSpot
      contrast: 0
      visual-density: adaptive
      tap-target-size: padded
      splash: sparkle

      themes:
        dark:
          seed-color: deepPurple.shade200
        ocean:
          seed-color: teal
          scheme-variant: vibrant
          splash: none
        ocean-night:
          extends: ocean
          brightness: dark
```

Names are compared without case, `-` and `_`: `seed-color`, `seedColor` and
`seed_color` mean the same key. Any other key at this level stops the start
and the message lists the valid ones (`a theme is themes.<name>.<property>`
when you forgot the `themes.` part).

## Which theme is shown

These keys exist at the root only. Inside `themes.<name>` they are an error.

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `active` | text | `system` or a theme name | `system` | The theme shown at start. `ThemeSelection.select(...)` changes it at run time. A name that is no theme stops the start and lists the themes |
| `system-light` | theme name | any theme | `light` | The theme `system` shows when the device is in light mode |
| `system-dark` | theme name | any theme | `dark` | The theme `system` shows when the device is in dark mode |
| `themes.<name>` | map | any theme name | none | A theme of your own, or the changes of `light` or `dark`. It holds the keys of the next two tables |

## Where a theme comes from

These keys exist in `themes.<name>` only. They say where the theme starts
from, not how it looks.

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `extends` | theme name | `light`, `dark` or another theme | the root | Start from that theme instead of the root. The theme gets everything the parent has, then its own keys on top. A cycle or an unknown parent stops the start |
| `source` | text | an `https` URL or `github:owner/repo/path@ref` | none | Download the theme from this address. See [a theme from a URL](#a-theme-from-a-url) |
| `source-sha256` | text | 64 hexadecimal digits | none | Refuse a download that does not have this digest |
| `refresh` | duration | `30m`, `1h`, `1.5d` | none | Look at the address again in the background when the cache is older than this |

## What a theme sets

These keys exist at the root (shared by every theme) and in each
`themes.<name>`.

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `brightness` | enum | `light`, `dark` | `dark` for the `dark` theme, `light` for others; inherited from the parent with `extends` | Whether the theme is light or dark. It decides which tones the palette uses and what the system bars look like |
| `seed-color` | [color](colors.md#writing-a-color) | any color | Flutter's baseline Material 3 palette | The one color the whole palette is made from |
| `scheme-variant` | enum | `tonalSpot`, `fidelity`, `content`, `vibrant`, `expressive`, `monochrome`, `neutral`, `rainbow`, `fruitSalad` (also `tonal-spot` and so on) | `tonalSpot` | How the palette is made from the seed. See [colors](colors.md#scheme-variants) |
| `contrast` | number | `-1` to `1` | `0` | Palette contrast: `-1` softer, `0` standard, `1` high. See [colors](colors.md#contrast) |
| `colors.<role>` | color | any color | from the seed | Sets one of the 46 palette roles by hand. See [colors](colors.md#the-color-roles) |
| `typography.*` | map | | Material's | Font family, fallback fonts, the 15 text styles and `code`. See [typography](typography.md) |
| `shape.<token>` | number | a radius, or `infinity` | Material 3's | The corner scale. See [shape, spacing and elevation](shape-spacing-elevation.md#shape-the-corner-scale) |
| `elevation.<level>` | number | `level0` to `level5` | 0, 1, 3, 6, 8, 12 | The elevation levels. See [shape, spacing and elevation](shape-spacing-elevation.md#elevation-levels) |
| `spacing.<name>` | number | any name | `xs` 4, `s` 8, `m` 16, `l` 24, `xl` 32 | The gaps of your own widgets. See [shape, spacing and elevation](shape-spacing-elevation.md#spacing) |
| `visual-density` | enum | `adaptive`, `standard`, `comfortable`, `compact` | Flutter's | How tightly components are packed. See [below](#visual-density) |
| `tap-target-size` | enum | `padded`, `shrink-wrap` | Flutter's | The minimum size of a tap target. See [below](#tap-target-size) |
| `splash` | enum | `ripple`, `sparkle`, `none` | Flutter's | The ink effect when something is tapped. See [below](#splash) |
| `motion.page-transition` | enum, or a map of `type`, `duration`, `curve` | `platform`, `fade-upwards`, `zoom`, `cupertino`, `fade`, `none` | `none` | The page transition of every screen, in every app type. See [motion](motion-and-animations.md#page-transitions) |
| `motion.durations.<name>` | duration | `250ms`, `1.5s` | `short` 100ms, `medium` 250ms, `long` 450ms | Named durations. See [motion](motion-and-animations.md#durations) |
| `motion.curves.<name>` | curve | a curve name or four numbers | Material's standard easing | Named curves. See [motion](motion-and-animations.md#curves) |
| `components.<component>.*` | map | | Material 3's | Adjusts one Material component. See [components](components/index.md) |
| `tokens.*` | any | | none | Your own values, at any depth. See [tokens and references](tokens-and-references.md) |
| `cupertino.*` | map | | iOS's | The `CupertinoThemeData`. See [Cupertino](cupertino.md) |
| `styles.<name>.*` | map | | none | A look per state for your own widgets. See [styles and states](styles-and-states.md) |
| `styles.code.*` | map | `background`, `text`, `keyword`, `string`, `comment`, `number`, `key`, `annotation`, `variable`, `type`, `punctuation`, `inline-text`, `inline-background`, `header`, `title`, `padding`, `radius`, `border`, `border-width` | the color scheme | The colors of code in `MarkdownView`. See [Markdown and code](styles-and-states.md#markdown-and-code-stylescode) |
| `syntax.<language>` | map | `rules` (`match`, `kind`), `keywords`, `types`, `aliases` | none | The languages of code blocks. See [the languages of code](styles-and-states.md#the-languages-of-code-syntax) |
| `animations.<name>.*` | map | | none | Named animations: `duration`, `curve`, `repeat`. See [motion](motion-and-animations.md#animations) |
| `background.*` | map | | none | A color, image, overlay and animation behind every screen. See [background](background.md) |

Only these keys are accepted. Inside `motion` only `page-transition`,
`durations` and `curves` exist.

### Visual density

| Value | What it does |
|---|---|
| `adaptive` | Compact on desktop platforms (macOS, Windows, Linux), standard elsewhere (Flutter's `adaptivePlatformDensity`) |
| `standard` | Normal spacing in buttons, lists and fields |
| `comfortable` | A little tighter than standard |
| `compact` | The tightest |

At this level only these four words are accepted. A component that has its
own `visual-density` also takes two numbers, `horizontal, vertical`.

### Tap target size

| Value | What it does |
|---|---|
| `padded` | Buttons and similar controls keep a tap area of at least 48 by 48 logical pixels, even when they look smaller |
| `shrink-wrap` | The tap area is as big as the control looks. Use it for dense desktop layouts |

### Splash

| Value | What it does |
|---|---|
| `ripple` | The classic Material ripple |
| `sparkle` | The Material 3 sparkle effect (Flutter's default on Android) |
| `none` | No ink effect |

### Brightness

```yaml
spring:
  flutter:
    theme:
      themes:
        night:
          brightness: dark
          seed-color: '#FF40A0'
```

A custom theme is light unless it says `brightness: dark` or extends a dark
theme. The palette is made for that brightness from the same seed.

## Layers

A theme is the sum of layers, each over the one before:

1. `brightness` (`dark` for the `dark` theme, otherwise `light`),
2. the root properties, or the resolved theme it `extends`,
3. its own properties (without `extends`, `source`, `source-sha256` and
   `refresh`, which are about where it comes from).

A list in a later layer replaces the whole list of an earlier layer. In
`styles`, a later layer's plain value, list or map of states replaces one of
another shape; maps of states merge state by state.

## A theme from a URL

A custom theme can be downloaded under a name your app chooses. The file's
own name for its theme does not matter.

`source` on `spring.flutter.theme` itself (with its `source-sha256` and
`refresh`) downloads values that **every** theme shares, under what your
own files set: the languages of code blocks
([`syntax`](styles-and-states.md#the-languages-of-code-syntax)), a palette
of tokens. A `themes.<name>.source` is one theme, over its files.

```yaml
spring:
  flutter:
    theme:
      active: brand
      themes:
        brand:
          source: https://themes.example.com/ocean.yml
          source-sha256: 3f9a1c5e7b2d4a6f8c0e1b3d5f7a9c2e4b6d8f0a1c3e5b7d9f1a3c5e7b9d1f3a
          refresh: 1h
        brand-dark:
          extends: brand
          brightness: dark
        release:
          source: github:neon/themes/ocean.yml@v3
```

| Property | What it does |
|---|---|
| `source` | An `https` URL, or `github:owner/repo/path/to/theme.yml@ref`, which means `https://raw.githubusercontent.com/owner/repo/ref/path`. `ref` is a branch, a tag or a commit; without it `HEAD` is used. `http` and any other scheme stop the start and name the property |
| `source-sha256` | The file must have exactly this SHA-256 digest (lowercase hexadecimal, 64 digits). Another content is refused: not shown and not cached. It is part of the cache's identity |
| `refresh` | How old the cache may get before the file is read again in the background: `30m`, `1h`, `1.5d` (a number with ms, s, m, h or d). Without it the first download is kept for ever |

`source-sha256` and `refresh` need a `source` in the same theme.

How it works:

- **The file** is written like the theme part of `application.yml`: under
  `spring.flutter.theme`, or with the theme keys at the top, or as one
  `themes.<any name>` block. Only the look is taken, and it becomes your
  `<name>`. `active`, `extends`, `system-light`, `system-dark`, `source`,
  `source-sha256`, `refresh` and every other `spring.*` setting in the file
  are ignored with a warning: a downloaded file never changes your other
  settings, picks the theme shown or points to more downloads.
- **The cache** is in the app's `support` files place, in
  `spring/themes/<sha256 of source and digest>/` (`theme.yml` and
  `meta.json`). It survives restarts. Another `source` or `source-sha256`
  downloads again, and the cache folders of sources you no longer
  configure are removed at start.
- **Start.** With a cache, the theme is applied at once, before the first
  frame. With `refresh` and an old cache the file is read again in the
  background (with `If-None-Match` and `If-Modified-Since`; a `304` only
  renews the age) and the new theme is shown as soon as it arrives. Without
  `refresh` there is never another request.
- **No cache.** The file is downloaded before the first frame, for at most
  10 seconds and 1 MiB. Offline, a timeout, a wrong digest, a file that is
  too big, not UTF-8 or not a valid theme leave the theme your own files
  describe for that name; the next start tries again. A failed refresh keeps
  the theme in use and is tried again after the refresh time, but not later
  than five minutes.
- **Redirects** are followed only to `https`. The request has no custom
  headers.
- **Typed keys.** The generated `context.theme` comes from the build. The
  downloaded file changes values; it does not add keys.

## Kinds of addresses

An address is read by a chain of resolvers: the application's own first,
then `github:owner/repo/path@ref` and `https://` / `http://`. Add a kind
(a company's `cdn:`) with a `RemoteAddressResolver`, given to
`SpringApplication(addressResolvers: [...])`, and every place that takes
an address (theme sources, images) accepts it. The build reads a page
loader's `web:` with the built-in kinds only.

## Insecure connections

Every address the configuration downloads from (a theme's `source`, the
shared `source`, an image, a page loader's `web:`) is read the same way
(`https://`, `github:owner/repo/path@ref`) and checked at the start: an
`http://` address stops the application with "the connection is not
secure", naming the address and its property. For a server without
https (a theme server of the local network, say):

```yaml
spring:
  remote:
    allow-insecure: true
```

Then `http://` works, as `https://` with a certificate that is expired,
self-signed or for another host (not in a browser, which checks
certificates by itself), and a warning at the start lists every insecure
address. A page loader's `web:` is downloaded by the build, which applies
the same rule.

## Related settings outside the theme

| Property | Type | Default | What it does |
|---|---|---|---|
| `spring.flutter.app.type` | `widgets`, `material`, `cupertino` | `widgets` | Which app widget is built. `material` uses the Material `ThemeData` of the theme shown, `cupertino` the `CupertinoThemeData` |
| `spring.flutter.fonts.auto-load` | bool | `true` | Load every `.ttf` and `.otf` file under `flutter: assets:` before the first frame. See [typography](typography.md#fonts-from-assets) |
| `spring.flutter.fonts.exclude` | list of globs | none | Font assets not to load |

## Change a theme in code

Properties cover most themes. For the rest, declare a bean:

```dart
@Component()
class RoundedChips implements ThemeCustomizer {
  @override
  ThemeData customize(ThemeData theme, SpringThemeData spring) =>
      theme.copyWith(chipTheme: theme.chipTheme.copyWith(shape: const StadiumBorder()));
}
```

A `ThemeCustomizer` runs on every Material theme the properties make, and a
`CupertinoThemeCustomizer` on every Cupertino theme. A `ThemeData` bean
named `theme` or `darkTheme` replaces the `light` or `dark` theme.

## See also

- [Overview](index.md)
- [Colors](colors.md)
- [Tokens and references](tokens-and-references.md)
- [Components](components/index.md)
