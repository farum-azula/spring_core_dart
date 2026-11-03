---
title: "Theme background — Spring for Dart"
description: "Put a color, an image, a gradient overlay and a slow drift, zoom or pulse behind every Flutter screen from YAML, with per-screen overrides."
slug: /docs/flutter/theme/background
section: Flutter / Theme
order: 9
keywords: [flutter, theme, yaml, background, image, gradient, overlay, blur, animation, transparent scaffold, ThemeBackground]
---

# Theme background

A theme can have a **background**: a base color, an image, something painted
over the image (a color or a gradient), and a slow movement of the image. The
app paints it behind every screen. A theme switch or a new image cross-fades.
One screen (a login screen, say) can have its own background.

```yaml
spring:
  flutter:
    theme:
      animations:
        background-drift:
          duration: 40s
          curve: ease-in-out
          repeat: reverse
      background:
        color: $colors.surface-container-lowest
        image:
          source: https://cdn.example.com/neon/background.jpg
          fallback: assets/images/background.jpg
          refresh: 1d
          fit: cover
          alignment: center
          opacity: 0.9
          blur: 4
        overlay:
          color: '#330A0C12'
          gradient:
            type: linear
            begin: top
            end: bottom
            colors: [transparent, '#CC0A0C12']
            stops: [0, 1]
        animation: background-drift
        effect: drift
        transition: 400ms ease-out
        screens:
          login:
            image:
              source: assets/images/login.jpg
              blur: 0
            overlay:
              color: '#66000000'
```

## Properties

A theme has no background unless it has at least one key under `background`.
Any other key stops the start and lists the valid ones.

### The background

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `background.color` | color | any [color](colors.md#writing-a-color) | the theme's `surface` | The base layer under everything else. It also shows while the image loads |
| `background.image` | map | the image keys below | none | A picture painted over the color |
| `background.overlay` | map | `color`, `gradient` | none | What is painted over the image |
| `background.animation` | text | the name of an `animations.<name>` | none | The animation that moves the image |
| `background.effect` | enum | `drift`, `zoom`, `pulse` | `drift` when `animation` is set | How the image moves |
| `background.transition` | text | `<duration> [<curve>]`, such as `400ms ease-out` | `300ms ease-out` | The cross-fade when the background changes |
| `background.screens.<name>` | map | the keys above except `screens` | none | A background for one screen. See [per-screen backgrounds](#per-screen-backgrounds) |

### The image

`background.image` takes every key of an [image](images.md) (`source`,
`refresh`, `source-sha256`, `headers`, `timeout`, `fallback`, `allow-http`)
and four keys about how the picture fills the screen.

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `source` | text | an asset path, an `https` URL, an `http` URL with `allow-http` | required | The picture. See [images](images.md) for the download, cache and refresh keys |
| `fit` | enum | `cover`, `contain`, `fill`, `fit-width`, `fit-height`, `none`, `scale-down` | `cover` | How the picture fills the screen |
| `alignment` | alignment | see below | `center` | Which part of the picture stays in view |
| `opacity` | number | `0` to `1` | `1` | How opaque the picture is. The color shows through the rest |
| `blur` | number | `0` or more | `0` | How much the picture is blurred (a Gaussian blur of that radius in logical pixels). `0` is sharp |

Values of `fit`:

| Value | What it does |
|---|---|
| `cover` | Fills the screen and keeps the shape, cropping what does not fit |
| `contain` | Shows the whole picture inside the screen, keeping its shape, and leaves empty space |
| `fill` | Stretches the picture to the screen, changing its shape |
| `fit-width` | Makes the width match the screen; the height may be cropped or short |
| `fit-height` | Makes the height match the screen; the width may be cropped or short |
| `none` | Shows the picture at its own size |
| `scale-down` | Like `contain`, but never makes the picture bigger than its own size |

Values of `alignment`:

| Value | Position |
|---|---|
| `center` | Centre |
| `top` or `top-center` | Top edge, centre |
| `bottom` or `bottom-center` | Bottom edge, centre |
| `left` or `center-left` | Left edge, centre |
| `right` or `center-right` | Right edge, centre |
| `top-left`, `top-right`, `bottom-left`, `bottom-right` | The corners |
| `x, y` | Two numbers from `-1` (left or top) to `1` (right or bottom); `0, 0` is the centre, `0, -0.5` is half way to the top |

`fit` and `alignment` matter when the picture and the screen have different
shapes. With `cover`, `alignment: top` keeps the top of the picture.

### The overlay

An overlay is painted over the image, so text stays readable. It can have a
flat `color`, a `gradient`, or both (the gradient is on top).

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `overlay.color` | color | any color, with alpha | none | A flat color over the whole screen. Use a color with some transparency (`'#330A0C12'`, `{ color: $colors.scrim, alpha: 30% }`) |
| `overlay.gradient.type` | enum | `linear`, `radial` | `linear` | The kind of gradient |
| `overlay.gradient.begin` | alignment | same as `alignment` | `top` (linear), `center` (radial) | Where a linear gradient starts. For a radial gradient it is the centre |
| `overlay.gradient.end` | alignment | same as `alignment` | `bottom` | Where a linear gradient ends. A radial gradient does not use it: giving `end` with `type: radial` stops the start ("radial uses begin as its center") |
| `overlay.gradient.colors` | list of colors | at least two | required | The colors, from `begin` to `end` (or from the centre outwards) |
| `overlay.gradient.stops` | list of numbers | `0` to `1`, as many as `colors` | even spacing | Where each color sits along the gradient |

A radial gradient has a radius of 0.8 of the screen's shorter side.
`colors` and `stops` are YAML lists or one comma-separated value. A list of
fewer than two colors, or `stops` with a different length than `colors`, stops
the start.

```yaml
spring:
  flutter:
    theme:
      background:
        color: '#0A0C12'
        overlay:
          gradient:
            type: radial
            begin: top-right
            colors: ['#33FF40A0', transparent]
```

### The painting order

From the back to the front: `color`, the image (blurred, with its opacity),
`overlay.color`, `overlay.gradient`. Only the image moves when there is an
`animation`; the color and the overlay stay still.

### Animation and effect

`animation` names an entry of [`animations`](motion-and-animations.md#animations)
of the same theme; a name that is not one stops the start and lists the
animations (an animation of this theme must exist). It gives the speed, the
curve and the repeat. `effect` says what the image does with the progress `t`
that goes from 0 to 1:

| Effect | What the image does |
|---|---|
| `drift` | The image is made 12% larger, so no edge shows, and slides slowly to and fro: up to 4% of the width across and 2% of the height up and down |
| `zoom` | The image grows from its normal size to 12% larger |
| `pulse` | The image fades a little in and out: between 70% and 100% of its opacity |

Notes:

- `effect` needs an `animation` next to it: without one the start fails and
  says so. With `animation` and no `effect`, it is `drift`.
- Without an `image`, there is nothing to move.
- With `repeat: loop` the movement jumps back at the end of a run; with
  `repeat: reverse` it goes there and back smoothly, which suits a
  background. A long `duration` (30 seconds or more) keeps it calm.
- When the device asks for less motion, the image stands still.

### The transition

`transition` is the cross-fade when the background changes: a theme switch,
a new image from the network, or a changed color. It is a duration and an
optional [curve](motion-and-animations.md#curves): `400ms ease-out`,
`1s`, `250ms linear`. The default is `300ms ease-out`. When the device asks
for less motion, there is no fade.

A new network image is loaded first and fades in over the old one, so there is
never an empty flash.

## Per-screen backgrounds

`background.screens.<name>` changes the background for the screen with that
name. It uses the same keys, except `screens`.

```yaml
spring:
  flutter:
    theme:
      background:
        color: $colors.surface
        image: { source: assets/images/main.jpg, opacity: 0.8 }
        screens:
          login:
            image: { source: assets/images/login.jpg }
          settings:
            image: { blur: 12 }         # same picture as the theme's, blurred
            overlay: { color: '#80000000' }
```

A screen starts from the theme's background and changes what it writes:

- `color`, `animation`, `effect` and `transition` replace the theme's.
- `image` goes over the theme's image key by key: a screen can write only
  `blur` and keep the theme's picture. A screen with no theme image must give
  a `source`; otherwise the start stops.
- `overlay` replaces the theme's overlay as a whole. It is not merged.

Names are compared without case, `-` and `_`.

## Show it

`SpringApp` (that is, `SpringApplicationWidget`) puts the background around
the app's navigator when the active theme has one, so every screen shows it.
To make that visible it also makes the **Material scaffold** and the
**Cupertino page** background transparent for a theme with a background. A
Cupertino theme that sets `cupertino.scaffold-background-color` keeps its
color.

Three widgets give a screen control:

```dart
// The theme's background (this is what the app itself uses).
ThemeBackground(child: const HomePage());

// background.screens.login over the theme's own. A name the theme does not
// list throws a FlutterError in debug (it lists the screens the theme has,
// and the closest name); in release it shows just the child.
ThemeBackground.screen('login', child: const LoginForm());

// A plain surface-colored background that hides the theme's one.
ThemeBackground.none(child: const ReaderPage());
```

Read the values in Dart with `context.theme.background`. It is a
`ThemeBackgroundData?`, `null` in a theme without a background:

```dart
final bg = context.theme.background;
bg?.color;          // Color?
bg?.screen('login'); // the login screen's resolved background
```

A theme without a background has opaque scaffolds again. If a theme switch
adds or removes the background, the screens keep their state.

## See also

- [Images](images.md): every image key, the cache and the refresh
- [Motion and animations](motion-and-animations.md): `animations.*` and curves
- [Colors](colors.md): `alpha` for the overlay
- [Properties](properties.md)
