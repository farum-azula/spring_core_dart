---
title: "Loaders and the splash — Spring for Dart"
description: "Spinners, dots, pulse, bars and skeletons from YAML, loader kinds of your own with phases and progress, and the splash screen that shows while a Flutter app starts."
slug: /docs/flutter/theme/loaders
section: Flutter / Theme
order: 12
keywords: [flutter, theme, yaml, loader, spinner, skeleton, shimmer, splash screen, progress, ThemeLoader, ThemeSkeleton, ThemeLoaderKind, reduce motion]
---

# Loaders and the splash

A theme can describe the loaders of an app and the splash screen that shows
while the app starts. There are three places for them, with one look:

1. **Component loaders**, `loaders.<name>`, shown by `ThemeLoader` and
   `ThemeSkeleton` anywhere in the app.
2. **The splash**, `splash`, shown by `SpringApplicationWidget` while the
   application context starts.
3. **The web page loader**, written by the generator into `web/index.html`
   from the theme's `splash`, shown while the browser downloads Flutter.

```yaml
spring:
  flutter:
    theme:
      loaders:
        dots:   { kind: dots, color: $colors.primary, size: 10, count: 3 }
        upload: { kind: bar, color: $colors.primary, height: 3 }
        card:
          kind: skeleton
          base: $colors.surface-container-high
          highlight: $colors.surface-container-highest
          radius: $shape.medium
          shimmer: { duration: 1.2s, angle: 20 }
      splash:
        background: { color: $colors.surface-container-lowest }
        logo: { source: assets/images/logo.png, size: 96 }
        title: NEON
        loader: dots
        min-duration: 1.2s
        exit: { transition: 400ms ease-out }
```

## Built-in kinds

Every key is optional. Colors take the theme's one color form (a name,
`#RRGGBB`, a `$` reference, or `{ color, mix, alpha }`), durations the one
duration syntax (`900ms`, `1.2s`). `animation` is written inline
(`duration`, `curve`, `repeat`) or is the name of an `animations.<name>`.

| Kind | Keys (defaults) |
|---|---|
| `spinner` | `color` (theme primary), `size` (24), `stroke` (3), `track` (none), `animation` (1s, linear, loop) |
| `dots` | `color`, `size` (8), `count` (3), `gap` (half the size), `animation` (900ms, ease-in-out, loop) |
| `pulse` | `color`, `size` (24), `animation` (1.2s, ease-in-out, back and forth) |
| `bar` | `color`, `track` (the color at 20 %), `height` (4), `width` (120), `radius` (half the height), `animation` (1.4s, ease-in-out, loop; for the indeterminate bar) |
| `skeleton` | `base` (`#E0E0E0`), `highlight` (`#F5F5F5`), `radius` (8), `shimmer.duration` (1.2s), `shimmer.curve` (linear), `shimmer.angle` (20) |

A built-in kind has one implicit phase and takes no `phases`. An unknown
`kind` or a key the kind does not take stops the start, naming the property
and the closest name.

## Showing them

```dart
// Indeterminate, or with progress from 0 to 1.
ThemeLoader(context.theme.loaders.dots)
ThemeLoader(context.theme.loaders.upload, progress: sent / total)

// The content, or a skeleton of it while loading.
ThemeSkeleton(
  context.theme.loaders.card,
  loading: !book.hasLoaded,
  placeholder: const BookTilePlaceholder(), // optional: the shape to show
  child: BookTile(book),
)
```

`ThemeLoader(spec, {progress, ready, size, onFinished})`: a bar fills with
`progress`; when the loader is `ready` (by default when `progress` reaches 1)
its looping phases end and its last phase plays. `ThemeSkeleton(spec,
{loading, child, placeholder})` paints the placeholder (or the child) in the
skeleton's base color with the highlight crossing it, and hides it from taps
and screen readers. Without a placeholder or child it is a plain block.

Read a loader by name with `context.theme.loaders.<name>` (generated), or
`ThemeKeyReader(theme).loader('neon-gate')`.

## A kind of your own

A kind of your own is a class marked `@ThemeLoaderKind('name')`. It extends
`ThemeLoaderPainter<P>` (paints a canvas) or `ThemeLoaderWidget<P>` (builds
widgets):

```yaml
loaders:
  neon-gate:
    kind: neon-gate
    phases:
      enter: { duration: 2s, curve: linear }
      fill:  { progress: true, min-duration: 2.5s }   # the real progress, 2.5 s at least
      exit:  { duration: 1400ms, curve: linear }
    edge: { color: $neon.cyan, accent: $neon.red, width: 2, glow: 6 }
    box:  { color: $neon.red, width: 420, height: 46, skew: -18 }
    web: loaders/neon-gate.html
```

```dart
@ThemeLoaderKind('neon-gate')
class NeonGateLoader extends ThemeLoaderWidget<NeonGateLoaderProps> {
  const NeonGateLoader();

  @override
  Widget build(BuildContext context, LoaderFrame<NeonGateLoaderProps> frame) {
    final enter = frame.phase('enter'); // 0..1
    final box = frame.props.box;        // typed from the theme's keys
    // ... return a widget (a CustomPaint, for example)
  }
}
```

- `frame.phase(name)` is 0 (not started) to 1 (done); `frame.progress` is the
  progress given to the loader (`null` when indeterminate); `frame.props` is
  `P`; `frame.values` reads the loader's keys untyped
  (`values.color('box.color')`); `frame.reduceMotion` is true when the
  system asks for less motion.
- Phases play in the order written. An animated phase (`duration`, `curve`,
  `repeat`) plays and the next starts; a looping phase goes on until the
  loader is ready; `{progress: true}` follows the progress and ends when it
  reaches 1; the last of several waits for ready. A progress phase with a
  `min-duration` shows no more than its eased clock over that time, so a fast
  start still fills slowly (the web page loader honours it too).
- The generator writes `P` from the keys the theme gives the loaders of that
  kind and registers the class in `ThemeLoaderKinds`. Without the generator
  call `ThemeLoaderKinds.register<P>('neon-gate', widget: NeonGateLoader(),
  props: NeonGateLoaderProps.from, keys: [...])` before the application starts, since
  the themes are read at the start and check every `kind`.
- `web` names an HTML file that shows the kind in the web page loader before
  Flutter runs. The loader's keys are CSS variables in it (`edge.glow` is
  `--edge-glow`; a list of colors also gives `--<name>-first`, so a conic
  gradient can close its circle). The page's script exposes
  `springLoader.progress` and `springLoader.elapsed` (milliseconds); the splash
  starts its phases from the progress (`ThemeLoader.resumeFrom`) and
  `LoaderFrame.elapsed` from the elapsed time (`ThemeLoader.resumeElapsed`), so
  a flicker or a glitch goes on where the page left it.
- A kind that draws the whole picture is a `ThemeLoaderPainter` or
  `ThemeLoaderWidget`; a splash with such a loader needs no `logo` or
  `title`. NEON's splash does this: dark panels that slide in from different
  sides with glowing, flickering edges and a skewed red box with the progress,
  all drawn from the theme's keys (CSS and SVG on the web page).

A library can ship loader kinds with its theme: the kind lives in the library,
the theme that uses it in the library's configuration.

## The splash

`splash` is a map; a plain `splash: ripple` is still the ink effect of taps.

| Key | What it does |
|---|---|
| `background` | The keys of the theme's [background](background.md) (without `screens`). Default: the theme's surface |
| `logo` | An [image](images.md); `size` is its width (96) |
| `title` | Text under the logo |
| `loader` | The name of a `loaders.<name>`. A built-in kind sits under the title; a kind of your own covers the whole splash, behind the logo and the title |
| `animation` | The name of an `animations.<name>` that fades and grows the logo |
| `min-duration` | The splash stays at least this long (default none) |
| `exit.transition` | The fade out: `<duration> [<curve>]` (default `300ms ease-out`) |
| `exit.reveal` | `true`: when the loader's last phase starts, the splash's background goes and the loader plays over the app, which is built under it (panels that part over the page). Default `false` |

`SpringApplicationWidget` shows the active theme's splash from the moment the
properties are read, until the context is ready:

- The loader gets the start's progress: the share of bean definitions created
  and runners called. A `{progress: true}` phase follows it.
- When the context is ready the loader's last phase plays, then the splash
  fades out over `exit`, and not before `min-duration`. The app is built under
  it meanwhile.
- The widget's own `splash:` builder wins over the theme's splash.
- With the system asking for less motion each phase is at its end, nothing
  flickers or shimmers, and the splash goes without a fade.

On the web, when the Flutter splash has painted its first frame it calls
`window.springLoaderHandOff(progress)` if the page defines it, so the page
loader can remove itself without a jump. Off the web nothing is called.

## See also

- [Background](background.md): the keys of `splash.background`
- [Images](images.md): the keys of `splash.logo`
- [Motion and animations](motion-and-animations.md): `animations.*` and curves
- [Styles and states](styles-and-states.md)
