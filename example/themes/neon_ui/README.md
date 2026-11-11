# neon_ui

NEON, a design system for apps of type `widgets` (no Material, no Cupertino):
a theme written in YAML, fonts, a background picture and thirteen widgets.
It is the example of a **library that ships a theme**, on the "themes without
Dart" of `spring_boot_starter_flutter` 0.6.3. Not published (`publish_to:
none`). The app that shows it is [`theme_showcase_neon`](../neon/README.md).

## Use it

```yaml
# pubspec.yaml
dependencies:
  neon_ui:
    path: ../neon_ui
```

```yaml
# lib/resources/application.yml of the app
spring:
  config:
    import: resources:themes/neon.yml      # the library's theme
  flutter:
    app:
      type: widgets
    theme:
      active: neon
```

```dart
import 'package:neon_ui/neon_ui.dart';

NeonPanel(title: 'Books', child: NeonButton(label: 'Save', onPressed: save));
```

The package's `lib/spring_auto_configuration.dart` is both the
`@ComponentScan` root and the `@AutoConfigurationModule`; the generator
embeds `lib/resources/` in it, so `resources:themes/neon.yml` finds the file
in the library. An app can add themes of its own that `extends: neon`.

## The theme: `lib/resources/themes/neon.yml`

All of the look is in this one commented file:

| Section | What it holds |
|---|---|
| `colors`, `typography`, `shape`, `spacing` | the palette (the roles refer to `$neon.yellow` and the like), Space Grotesk for headings and JetBrains Mono for the rest |
| `tokens.neon` | accents, surfaces, sizes, `tone` / `tone-soft` for the badges, `modal` (a group: width, barrier, `border.colors` a list) |
| `tokens.logs` | the colors of the log panel |
| `styles.*` | `neon-button`, `neon-button-outline`, `neon-chip`, `neon-text-field`, `neon-resize-handle`: a value per state; `code`: the code panel and the colors of code (`NeonCode`, `MarkdownView`) |
| `loaders` | `neon-gate`: the gate loader (phases `enter`, `fill` by progress with a `min-duration`, `exit`; gate, edge, flicker, box and label looks; `web` file) |
| `motion`, `animations` | `border-spin` (the modal's turning border), `gate-enter`, `gate-exit` and `gate-flicker` (the gate loader), `background-drift` |
| `background` | the picture with a veil, drifting, and the `stage` screen |

The widgets read it as `context.theme.*`, typed, from the library's own
generated `lib/spring_gen/theme.spring.keys.dart` (a `part` of
`lib/spring_gen/spring_auto_configuration.spring.dart`). The generated keys are the
library's: an app has its own `context.theme` for its own YAML and never sees
these. A theme used with these widgets has to hold the keys they read, so
make it `extends: neon`.

## Widgets

| Widget | What it is |
|---|---|
| `NeonLogo` | the RGB-split glowing logo |
| `NeonPanel` | translucent panel with a title and an accent mark |
| `NeonLabel`, `NeonBadge` (`NeonTone`) | upper-case labels, status badges |
| `NeonButton`, `NeonChip` | filled and outlined buttons, selectable chips: hover, focus, press, disabled by `ThemeStates` |
| `NeonTextField`, `NeonField` | text input on `EditableText` with mouse selection and an error state, a labelled field |
| `NeonCode` | a code block: `MarkdownView.code` in the theme's `styles.code` (the panel, the palette's colors), with a copy button. The languages come from the app (`syntax.*`, such as a copy of farum-azula/themes' `code.yml`, as `theme_showcase_neon` imports); without them the code is plain text |
| `NeonGlowBorder`, `showNeonModal` | the border that turns (`ThemeAnimation`, still with reduce motion) and the dialog around it |
| `NeonResizeHandle` | a horizontal grip for resizable panels |
| `NeonGateLoader` | the `neon-gate` loader kind (`@ThemeLoaderKind('neon-gate')`), drawn by a painter: dark panels slide in one after the other from different sides and close like a gate (two halves meeting at a slanted seam, platforms over them), their edges glowing in cyan and red with a little flicker; an angled red box in the middle fills by the progress with its number (`label-small`). When the work is done the box goes and the panels part the way they came, over the app with the splash's `exit.reveal`. Its keys are `loaders.neon-gate` in `themes/neon.yml` (colors are tokens, times are `animations.gate-enter`, `gate-exit` and `gate-flicker`); the geometry is in `lib/src/neon_gate_loader.dart`, the same numbers as its look for the web page before Flutter runs, `lib/resources/loaders/neon-gate.html` |
| `NeonLogsPanel` | a `LogBuffer` in the colors of the Spring console (no `dart:io`: works on the web; give it a `processId` to show one) |

The background is not a widget: the theme's `background` goes under every
screen of the app by itself (`ThemeBackground.screen('stage', ...)` and
`ThemeBackground.none(...)` pick another one for a screen).

## YAML instead of Dart

What a theme package written in Dart needs, and what this one has instead:

| Written in Dart | Here, in YAML |
|---|---|
| helpers that read tokens by string (`tokenColor('neon.cyan')`) and fall back silently on a typo | `context.theme.tokens.neon.cyan`, typed; a renamed token breaks the build |
| a JSON string inside YAML for structured values, parsed by hand | nested token groups: `tokens.neon.modal.border.colors` is a `List<Color>` |
| derived colors as Dart constants (an alpha for a badge, a lighter fill on hover) | color objects: `{ color: $colors.primary, alpha: 12% }`, `{ color: $colors.primary, mix: { with: white, amount: 14% } }` |
| a hover/focus/press tracker in every button, chip and field | `ThemeStates` with `styles.neon-button` and the like: a value per state and a `transition` |
| an `AnimationController` per animated widget, with reduce-motion handling | `ThemeAnimation(context.theme.animations.borderSpin)` |
| a background widget wrapped around every screen | `background:` in the theme; the starter puts it under every screen |
| the same color typed again in every place | written once; everything else says `$neon.yellow` or `$colors.primary`, so a theme that `extends: neon` and changes `colors.primary` repaints the lot |

A color, a size or a state change is a line of YAML.

## Fonts and the picture

JetBrains Mono and Space Grotesk are under the SIL Open Font License 1.1; the
license of each is next to the fonts (`assets/fonts/JetBrainsMono-OFL.txt`,
`assets/fonts/SpaceGrotesk-OFL.txt`, copied from the upstream repositories).
Declared under `flutter: fonts:`, their families are
`packages/neon_ui/Space Grotesk` and `packages/neon_ui/JetBrains Mono`.

The background picture `assets/images/neon-background.jpg` is generated:

```bash
python3 tool/neon_background.py assets/images/neon-background.jpg   # numpy, pillow
```

## Develop

```bash
flutter pub get
dart run build_runner build     # lib/spring_gen/theme.spring.keys.dart, lib/spring_gen/spring_auto_configuration.spring.dart (checked in)
flutter test
flutter analyze --fatal-infos
```

`build.yaml` sets `aop_prune: false`: a `publish_to: none` package counts as
an application, and the generator would otherwise stop on the
auto-configuration file.
