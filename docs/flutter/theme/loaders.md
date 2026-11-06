---
title: "Loaders and the splash — Spring for Dart"
description: "Spinners, dots, pulse, bars and skeletons from YAML, loader kinds of your own with phases and progress, and the splash screen that shows while a Flutter app starts."
slug: /docs/flutter/theme/loaders
section: Flutter / Theme
order: 12
keywords: [flutter, theme, yaml, loader, spinner, skeleton, shimmer, splash screen, progress, ThemeLoader, ThemeSkeleton, ThemeLoaderKind, reduce motion, tracks, LoaderTrackDriver, SplashStage, yield-frames, compositor, startup trace]
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

### Tracks

Phases play one after another. A movement that runs beside them, such as a
turn, a glow that starts with the context or a fill that follows the
progress, is a **track**: a value from 0 to 1 that the loader reads each
frame with `frame.track(name)`. What leads a track is its `follows`:

```yaml
loaders:
  spring-leaf:
    kind: spring-leaf
    tracks:
      spin: { duration: 2.4s, repeat: loop }                 # follows: time
      glow: { follows: stage, from: starting, duration: 1.2s, repeat: reverse }
      draw: { follows: stage, from: splash, duration: 900ms, curve: ease-out }
      fill: { follows: progress, smoothing: 400ms, curve: ease-in-out }
```

| `follows` | Keys | The value |
|---|---|---|
| `time` (default) | `duration`, `curve`, `repeat` (`none`, `loop`, `reverse`), `delay` | Runs from the loader's start; on the web from the page loader's start, so it goes on where the page left it |
| `stage` | `from` (a [stage](#the-stages-of-the-start)), `duration`, `curve`, `repeat`, `delay` | 0 until the start reaches `from`, then runs. A stage reached before the loader showed counts from when it was reached |
| `progress` | `smoothing` (300ms), `curve` | The start's progress, moving towards the real value with the time constant `smoothing`: it never jumps, even when the progress does |

`frame.stage` is the stage itself, for a picture that changes by stage
rather than over time. With the system asking for less motion a track rests:
a track that plays once is at 1, a looping one at 0, a progress track at the
progress.

Each `follows` is read by a `LoaderTrackDriver`, and the drivers form a
registry, `LoaderTrackDrivers`. A movement led by something else (a beat, the
network, the battery) is a driver of your own, not a change to the starter.
Register it before the application starts; the themes are read at the start:

```dart
// `follows: beat`: 1 for the first 100 ms of every `every`, else 0.
final class BeatTrackDriver implements LoaderTrackDriver {
  const BeatTrackDriver();

  @override
  String get name => 'beat';

  @override
  List<String> get keys => const ['every'];

  @override
  LoaderTrack parse(LoaderValues values) =>
      BeatTrack(values.duration('every'));
}

final class BeatTrack implements LoaderTrack, LoaderTrackRun {
  const BeatTrack(this.every);

  final Duration every;

  @override
  LoaderTrackRun run() => this; // a run with state is its own object

  @override
  double still(double? progress) => 0;

  @override
  double advance(LoaderClock clock) =>
      clock.elapsed.inMicroseconds % every.inMicroseconds < 100000 ? 1 : 0;
}

void main() {
  LoaderTrackDrivers.register(const BeatTrackDriver());
  runApp(SpringApplicationWidget(application: createApplication));
}
```

`LoaderClock` gives the driver the time (`elapsed`, `dt` since the last
frame), the `progress`, the `stage` and `since(stage)`. `LoaderValues` reads
the track's keys and names the property in its errors (`values.fail(key,
expected)`). A key the driver does not list, or a `follows` no driver has,
stops the start, naming the property and the closest name.

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

## The stages of the start

`SpringApplicationWidget` tells the splash where the start is. The stages
come in this order (`SplashStage`):

| Stage | What happens |
|---|---|
| `page` | The browser opened the page and downloads the app's code (`main.dart.js`). The page loader of `web/index.html` shows |
| `engine` | Flutter's engine starts (CanvasKit or skwasm). The page loader still shows |
| `splash` | Flutter drew its first frame: the theme's splash is on screen and the page loader is removed |
| `starting` | The application starts: the configuration is read, the beans are created; the splash shows the progress |
| `ready` | The context is ready: the loader plays its last phase, the splash waits for its `min-duration` |
| `exit` | The splash plays its exit (`exit.transition` or `exit.reveal`) |
| `app` | The splash is gone; the app shows |

Each platform goes through the stages it has:

| Platform | Stages | Before the first stage |
|---|---|---|
| Web | `page`, `engine`, `splash`, `starting`, `ready`, `exit`, `app` | Nothing: the page loader shows from the first paint of the page |
| Android, iOS | `splash`, `starting`, `ready`, `exit`, `app` | The system's launch screen (`launch_background.xml`, `LaunchScreen.storyboard`) while the engine starts |
| macOS, Windows, Linux | `splash`, `starting`, `ready`, `exit`, `app` | The window is not shown yet: the starter holds the first frame until the window's size and title are set |

The stages only go forward. When no splash shows (no theme splash, no
`splash:` builder) the app is shown with the context, so `splash` may be
skipped.

The page script records `page` and `engine` with their time in
`window.springLoader.stages`, sets `data-splash-stage` on the loader's
element and sends a `spring-splash-stage` event, so the page's own CSS can
react. The Flutter side reads them at its first frame and goes on with the
same clock: times are milliseconds since the page started loading, on every
platform since `SpringApplicationWidget` was created.

Read the stages in three ways:

- In a loader: `frame.stage`, and tracks with `follows: stage`.
- As a bean: `SplashStages` (a `ValueListenable<SplashStage>`) with
  `reached` (each stage with its time), `at(stage)` and `now`.
- As events: a `SplashStageEvent` (`stage`, `at`) for each stage. Stages
  reached before the context existed are published when it is ready, in
  order, so a listener sees all of them:

```dart
@Component()
class StartMetrics {
  @EventListener()
  void onStage(SplashStageEvent event) =>
      analytics.record('start.${event.stage.name}', event.at);
}
```

## A web page loader that does not freeze

While the page loader shows, the browser is busy: it downloads
`main.dart.js` (several megabytes), parses and compiles it, then starts
CanvasKit or skwasm. All of this runs on the browser's **main thread**, the
thread that also runs the page's JavaScript, lays the page out and paints
most of it. While it is busy, everything it drives stops: a progress number
that does not move, an SVG line that stops drawing, a glow that stops
pulsing. That is the freeze you see in the first second or two.

Some animations do not need the main thread. The browser hands CSS
animations of **`transform`** and **`opacity`** to the **compositor**, a
separate thread that moves and fades layers that are already painted. They
keep running while the main thread compiles the app.

| Runs on the compositor (smooth) | Runs on the main thread (stalls) |
|---|---|
| `transform`: `rotate`, `scale`, `translate` | `stroke-dashoffset`, `stroke-dasharray` |
| `opacity` | `filter`, `drop-shadow`, `box-shadow` |
| | `width`, `height`, `top`, `left`, `background-position` |
| | colors, gradients, CSS variables a script changes |

Recommendations:

- Animate `transform` and `opacity` with CSS `@keyframes`, not with a script.
  Add `will-change: transform` (or `opacity`) so the element gets its own
  layer up front.
- Animate an element of the page (a `div`, or a whole `<svg>`), not a
  shape inside an SVG: a `transform` of a `<g>` or a `<path>` is painted by
  the main thread. Give each moving part its own `<svg>`.
- To draw a stroke, do not animate `stroke-dashoffset`. Put the finished
  stroke under a mask, and move or turn the mask with `transform`.
- To make a glow pulse, do not animate `filter: blur()` or `drop-shadow`.
  Draw the glow once as its own blurred layer, and animate its `opacity`
  (and `transform: scale`).
- Gradients that turn: turn the element (`transform: rotate`), not the
  gradient's angle.
- Progress comes from the script (`--spring-progress`), so it is
  main-thread: it stalls while the app compiles. Show it as something that
  can wait, such as a bar that `scale`s by the variable, next to a movement
  that never stops (a turn, a pulse).
- Keep the page loader small: every byte of its HTML and CSS is downloaded
  before anything shows.
- Match the first frame of the Flutter splash: same size and place, and the
  tracks follow `time`, which goes on from the page's clock, so the hand-off
  does not jump.

Check it in the browser's Performance tab with the CPU slowed down (4×
slowdown): the loader should keep moving while the long "Evaluate script"
and "Compile" blocks of the main thread run.

## Yielding frames during the start

Creating the beans is also main-thread work, in Dart this time: while a bean
is made, Flutter draws no frame and the splash stands still. On the web every
frame of the splash is drawn by the same thread, so a start of a few hundred
milliseconds is a visible stop.

`spring.flutter.splash.yield-frames` lets frames in between:

```yaml
spring:
  flutter:
    splash:
      yield-frames: true     # default: true on the web, false elsewhere
      frame-budget: 8ms      # the work between two frames
```

How it works:

1. The bean factory creates the eager singletons one by one. Between two
   beans it asks its `StartupPacer` whether to wait.
2. The starter's pacer, `FramePacer`, measures the time since the last frame.
   Under `frame-budget` it says go on, and the next bean is made at once.
   Over it, it asks Flutter for a frame and waits for its end
   (`SchedulerBinding.endOfFrame`). The splash draws, then the beans go on.
3. With a budget of 8 ms and a frame of about 16 ms, the splash keeps about
   half the frames while the start goes on.

Limits:

- A single bean that takes 200 ms still holds the thread for 200 ms. The
  pacer only waits between beans. Move such work out of the constructor: an
  `@Async` method, a runner, or work that waits for something.
- The start takes a little longer, by the frames it gives away. With
  `yield-frames: false` it is not paced at all and is as fast as before.
- Off the web the splash is drawn on the raster thread, but the UI thread
  still builds each frame. Turn it on there for a long start that stalls the
  splash.

Another `StartupPacer` is set on the bean factory
(`DefaultListableBeanFactory.startupPacer`) by an
`ApplicationContextInitializedEvent` listener, for a pacing of your own.

## Tracing the start

`spring.flutter.splash.trace: true` (off by default) measures the start:

- each stage with its time;
- each bean's creation (`spring.beans.instantiate` with its `beanName`) and
  the application's own steps (`spring.boot.application.*`), through
  Spring's `ApplicationStartup`;
- at `app`, a log line with the stages and the five slowest beans:

```
INFO SplashTrace: The start: page 40 ms, engine 910 ms, splash 1420 ms, starting 1450 ms, ready 1730 ms, exit 2950 ms, app 3350 ms. 42 beans; the slowest: spring.beans.instantiate beanName=catalogRepository 96 ms, ...
```

On the web the same steps are marks and measures of the browser's
performance timeline (`spring:splash:<stage>`, and one measure per bean),
shown in the Performance tab next to the main thread's work. That shows
which bean stalled which frame.

The trace is a `BufferingApplicationStartup`, like Spring's. A different
recorder is passed to `SpringApplication(applicationStartup:)`.

## See also

- [Background](background.md): the keys of `splash.background`
- [Images](images.md): the keys of `splash.logo`
- [Motion and animations](motion-and-animations.md): `animations.*` and curves
- [Styles and states](styles-and-states.md)
- [Configuration](../../configuration.md): `spring.flutter.splash.*`
