---
title: "Theme motion and animations — Spring for Dart"
description: "Named durations and curves, page transitions, looping animations and reduced motion in Flutter theme YAML, with every curve name accepted."
slug: /docs/flutter/theme/motion-and-animations
section: Flutter / Theme
order: 8
keywords: [flutter, theme, yaml, motion, animation, duration, curve, easing, page transition, reduce motion, ThemeAnimation]
---

# Motion and animations

Motion in a theme has two parts. `motion` holds **durations** and **curves**
that you name, plus the **page transition**. `animations` holds named
**animations** that play by themselves: how long, along which curve, and
whether they repeat.

```yaml
spring:
  flutter:
    theme:
      motion:
        page-transition: fade-upwards
        durations:
          fast: 120ms
          medium: 250ms
        curves:
          out: ease-out
          emphasized: [0.2, 0, 0, 1]
      animations:
        border-spin:
          duration: 4s
          curve: linear
          repeat: loop
        glow-pulse:
          duration: 1.6s
          curve: ease-in-out
          repeat: reverse
```

## Properties

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `motion.page-transition` | enum, or a map | `platform`, `fade-upwards`, `zoom`, `cupertino`, `fade`, `none` | `none` | The page transition of every screen |
| `motion.page-transition.type` / `.duration` / `.curve` | enum / duration / curve | as above, `200ms`, a curve name | the kind's own | The map form: the kind with its duration and curve |
| `motion.text-change` | enum, or a map | `none`, `fade`, `morph` | `none` | What a `ThemeText` does when its text changes, another language say |
| `motion.text-change.type` / `.duration` / `.curve` / `.stagger` / `.keep-unchanged` / `.glyphs` / `.glyph-duration` | enum / duration / curve / duration / boolean / text / duration | as above, `450ms`, a curve name, `12ms`, `true` / `false`, any characters, a duration over zero | `none`, `450ms`, `ease-out`, `12ms`, `false`, `▓▒░<>/\|=+*#%&@$?!01`, `40ms` | The map form; `stagger` is how much later each character of `morph` starts; `keep-unchanged` leaves the characters that stay the same in place |
| `motion.overscroll` | `platform`, `none` | | `platform` | What a scrollable shows when pulled past its end: the app type's own (Material's stretch on Android, which distorts the content for a moment) or nothing |
| `motion.wheel-scroll` | `none`, or a map of `duration` and `speed` | | `none` (`250ms`, `1` in the map) | How a mouse wheel scrolls every scrollable: `none` jumps by the wheel's step as Flutter does; a map eases each step over `duration` and scales it by `speed` |
| `motion.scroll-to-top` | `none`, or a map of `duration` and `curve` | | `400ms`, `ease-out-cubic` | How a screen goes back to its top when it shows another page (`RouteContentView`); `none` jumps |
| `motion.content-change` | a kind, or a map | `none`, `fade`, `fade-up`, or a kind of the app's own | `none` | How a part of a screen shows other content in its place (another page in `RouteContentView`) |
| `motion.content-change.type` / `.duration` / `.curve` | kind / duration / curve | as above, `200ms`, a curve name | `none`, `200ms`, `ease-out` | The map form |
| `motion.durations.<name>` | duration | `120ms`, `1.5s`, `2m`, `1h` | `short` 100ms, `medium` 250ms, `long` 450ms | A named duration |
| `motion.curves.<name>` | curve | a curve name, or four numbers | `standard` | A named curve |
| `animations.<name>.duration` | duration | `4s`, `250ms` | required | How long one run takes |
| `animations.<name>.curve` | curve | a curve name, or four numbers | `linear` | The curve of one run |
| `animations.<name>.repeat` | enum | `none`, `loop`, `reverse` | `none` | What happens at the end of a run |

Inside `motion` only `page-transition`, `text-change`, `content-change`, `scroll-to-top`, `wheel-scroll`, `overscroll`, `durations` and `curves` exist.
Inside an animation only `duration`, `curve` and `repeat` exist; another key
stops the start and names the closest one.

## Page transitions

`motion.page-transition` sets how screens come in and go out, for the whole
app. The router of
[`spring_boot_starter_flutter_navigation`](../../../spring_boot_starter_flutter_navigation/README.md#transitions)
follows it in every app type (Material, Cupertino and `widgets`), and
Material's own page routes follow it too.

| Value | What it does |
|---|---|
| `none` | No transition: the new page appears at once (the default) |
| `platform` | The app type's own: Material's per platform, the iOS slide in a `CupertinoApp`, none in an app of type `widgets` |
| `fade-upwards` | The new page slides up a little and fades in |
| `zoom` | The new page grows from the centre while it fades in (Android 10 style) |
| `cupertino` | The iOS slide from the right, with the swipe-back gesture, in any app type |
| `fade` | The new page fades in |

Screens show at once by default, in every app type. Turn the platform's
transition on for every screen:

```yaml
spring:
  flutter:
    theme:
      motion:
        page-transition: platform
```

Or choose and tune one: the map form gives the kind its duration and curve, which may
refer to the theme's own (`$motion.durations.fast`):

```yaml
spring:
  flutter:
    theme:
      motion:
        durations: { fast: 150ms }
        page-transition: { type: fade, duration: $motion.durations.fast, curve: ease-out }
      themes:
        cinema:
          motion:
            page-transition: zoom
```

A theme of `themes.<name>` may choose its own; switching themes applies to
the next navigation. With reduced motion on the device every transition is
instant. One screen can still choose its own
(`@ScreenRoute(transition: PageTransition.none)`), and one navigation too
(`context.route.go(path, transition: PageTransition.none)`): see the
navigation starter.

## Text changes

When the app's language switches, every text changes at once. Write
`motion.text-change` and the texts shown with `ThemeText` change the
theme's way instead:

```yaml
spring:
  flutter:
    theme:
      motion:
        text-change: { type: morph, duration: 600ms, curve: ease-out, stagger: 12ms }
```

```dart
ThemeText(context.messages.home.title, style: theme.typography.displaySmall);
```

- `morph`: the characters change one after the other from the start of
  the line, each running through a few glyphs before it settles on the
  new one; `stagger` is the delay from one character to the next. By
  default the wave runs over the whole line, the characters that stay the
  same too; `keep-unchanged: true` leaves those in place, so only the part
  that changed runs (a breadcrumb whose last part changes).
  `glyphs` are the characters it runs through (taken as written, `$`
  included), `glyph-duration` how long each one shows:

```yaml
text-change:
  type: morph
  duration: 650ms
  stagger: 14ms
  glyphs: '01<>/'          # default ▓▒░<>/\|=+*#%&@$?!01
  glyph-duration: 30ms     # default 40ms
```
- `fade`: the old text fades out while the new one fades in.
- `none` (the default): the new text at once.

A `ThemeText` changes whenever the same widget gets another text: a new
language, a value that updated, a result of a search as the query is
typed. Its `highlights` (ranges of the text, the words a search found)
show in `highlightStyle` once the change has settled. With reduced motion it changes at once.
To act on the language itself, listen to the navigation's
`LanguageChangedEvent` with `@EventListener`.

## Content changes

A part of a screen that shows other content in its place, the article of
a documentation page when another page of the same screen opens, keeps
what it shows until the next content is read: it never collapses to
nothing for a frame. `motion.content-change` says how the new content
replaces the old one:

```yaml
spring:
  flutter:
    theme:
      motion:
        content-change: { type: fade-up, duration: 220ms, curve: ease-out }
```

- `fade`: the old content fades out while the new one fades in.
- `fade-up`: the same, the new content rising a little.
- `none` (the default): the new content at once.

When another page opens on the same screen (`RouteContentView`), the
screen also goes back to its top, as a browser opens a page:
`motion.scroll-to-top` (400ms ease-out-cubic by default; `none` jumps,
and so does reduced motion):

```yaml
motion:
  scroll-to-top: { duration: 500ms, curve: ease-in-out }
```

The new content gives the height; the old one is cut to it while it goes.
`RouteContentView` and `MarkdownView.resource` change this way. Wrap any
other content in `ContentChange(id: ..., child: ...)`: a new `id` is a
change. With reduced motion the content changes at once.

A kind of your own is registered before the application starts (the
themes are read at the start, and a kind no one registered stops it with
the names that exist):

```dart
void main() {
  ContentTransitions.register(
    'scale',
    (child, animation) => ScaleTransition(scale: animation, child: child),
  );
  runApp(SpringApplicationWidget(application: createApplication));
}
```

## The mouse wheel

Flutter moves a scrollable by the wheel's whole step at once: on the web
a page jumps 100 pixels or so per notch, which reads as a stutter.
`motion.wheel-scroll` eases every step of the wheel, for every scrollable
of the app, with no controller to set:

```yaml
motion:
  wheel-scroll: { duration: 250ms, speed: 0.8 }
```

- `duration`: how long a step takes to arrive; steps that come one after
  the other add up and keep moving.
- `speed`: the share of the step, below 1 slower, above faster.
- `none` (the default): Flutter's own behavior.

Touch scrolling keeps its physics. A trackpad that the platform reports
as wheel steps (the web) is eased too; its steps are small, so it moves
almost as before. `WheelScrollSmoother` does the work, and `SpringApp`
sets it from the active theme.

## Durations

`motion.durations.<name>` are durations with any name you like, for your own
animations.

A duration is a number, optional spaces, and a unit: `ms`, `s`, `m`, `h` or
`d` (any case). Decimals are fine (`1.5s`, `0.5d`). A plain number is
milliseconds. A negative number or another unit is an error. It is the one
syntax of every time in a theme: motion, animations, styles, tokens,
`transition`, `refresh` and `timeout`.

`short`, `medium` and `long` exist even if you do not write them: 100 ms,
250 ms and 450 ms. Reading another name you did not declare
(`context.theme.motion` has only the names you wrote) is an error that lists
the closest name.

```dart
AnimatedContainer(
  duration: context.theme.motion.fast,                 // a Duration
  curve: context.theme.motion.curves.emphasized,       // a Curve
  height: expanded ? 200 : 80,
)
```

## Curves

A curve is a name from the table below, or four numbers for a cubic curve
(the same as CSS `cubic-bezier`). Four numbers are written as a YAML list or
as one quoted text.

```yaml
spring:
  flutter:
    theme:
      motion:
        curves:
          standard: '0.2, 0, 0, 1'
          bounce: bounce-out
          snap: [0.4, 0, 0.2, 1]
```

Names are written in kebab case; `easeIn` and `ease_in` also work.

| Curve | What it feels like |
|---|---|
| `linear` | Constant speed |
| `ease` | Starts slowly, speeds up, ends slowly (the CSS `ease`) |
| `ease-in` | Starts slowly |
| `ease-out` | Ends slowly |
| `ease-in-out` | Starts and ends slowly |
| `fast-out-slow-in` | Quick start, long gentle end (Material's classic curve) |
| `decelerate` | Fast start that slows down in a smooth way |
| `standard` | Material 3's standard easing |
| `standard-accelerate` | Material 3's standard easing for things that leave |
| `standard-decelerate` | Material 3's standard easing for things that arrive |
| `emphasized` | A strong ease: `0.2, 0, 0, 1` |
| `emphasized-accelerate` | Emphasized, for things that leave |
| `emphasized-decelerate` | Emphasized, for things that arrive |
| `ease-in-sine`, `ease-out-sine`, `ease-in-out-sine` | A very gentle ease |
| `ease-in-cubic`, `ease-out-cubic`, `ease-in-out-cubic` | A stronger ease |
| `ease-in-back`, `ease-out-back`, `ease-in-out-back` | Goes a little backwards first, or overshoots the end |
| `bounce-in`, `bounce-out`, `bounce-in-out` | Bounces like a ball |
| `elastic-in`, `elastic-out`, `elastic-in-out` | Springs like a rubber band |

Anything else is an error that lists these names. A curve you have not
declared in `motion.curves` is Material's standard easing when read with
`SpringTheme.of(context).curve(name)`; the generated
`context.theme.motion.curves.<name>` exists only for names you declare.

## Animations

`animations.<name>` is a named animation: the time of one run, its curve and
what happens at the end.

| `repeat` | What happens at the end |
|---|---|
| `none` | Plays once and stays at the end |
| `loop` | Starts again from the beginning, for ever |
| `reverse` | Plays back and forth, for ever |

`ThemeAnimation` plays one. It owns the controller, repeats as asked, takes a
new duration or curve when the theme changes, and gives your builder a
progress from 0 to 1 along the curve:

```dart
ThemeAnimation(
  context.theme.animations.borderSpin,
  builder: (context, t) =>
      Transform.rotate(angle: t.value * 2 * pi, child: ring),
)
```

An animation can also move a [background](background.md) image
(`background.animation: border-spin`). Every animation needs a `duration`;
one without it stops the start.

## Reduced motion

When the device asks for less motion (`MediaQuery.disableAnimations`):

- every duration read through `context.theme.motion` is `Duration.zero`,
- a `ThemeAnimation` with `repeat: none` jumps to its end (`t` is 1); `loop`
  and `reverse` stand still at 0,
- an animation of zero duration does the same,
- `ThemeStates` changes values at once,
- the [background](background.md) stands still and changes without a fade.

A duration read from a token (`SpringTheme.of(context).tokenDuration(...)`)
is the plain duration and is not reduced; use the typed
`context.theme.motion` getters, or check
`MediaQuery.disableAnimationsOf(context)` yourself.

## See also

- [Properties](properties.md)
- [Styles and states](styles-and-states.md): `transition: 120ms ease-out`
- [Background](background.md): `animation`, `effect` and `transition`
- [Cupertino](cupertino.md): iOS page transitions
