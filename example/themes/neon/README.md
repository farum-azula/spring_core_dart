# Theme Showcase NEON

A custom design system on the theme of
[`spring_boot_starter_flutter`](../../../spring_boot_starter_flutter/README.md),
in an app of type `widgets`: **no Material, no Cupertino, no `ThemeData`**.
Everything on screen is a widget of [`neon_ui`](../neon_ui/README.md), the
NEON design system shipped as a library, or a small widget of this app.

The look is YAML. [`neon_ui`'s `themes/neon.yml`](../neon_ui/lib/resources/themes/neon.yml)
is imported with `spring.config.import: resources:themes/neon.yml`, and
[`lib/resources/application.yml`](lib/resources/application.yml) adds a theme
of its own, `neon-ice`, that `extends: neon` and changes one color.

## Run

```bash
flutter pub get
dart run build_runner build      # writes lib/spring_gen/*.spring.dart (checked in)
flutter run                      # desktop; -d chrome for the web (port 5090)
```

## The pages

The navigation is built from `NeonChip`s; each page shows a capability, the
lines of YAML that make it (`NeonCode` boxes) and the result. A test checks
that every quoted line is in the resources.

1. **Overview**: what the app is, the import of the library's theme.
2. **Components**: buttons, chips, badges, text fields, code, panel and
   resize handle, logo, with their looks per state (`styles.*`).
3. **States**: `ThemeStates`: disabled, error, selected, hover, focus,
   press; a style of the app's own (`styles.showcase-tile`).
4. **Motion**: the glow modal whose border turns (`ThemeAnimation`,
   `animations.border-spin`), `motion.*` durations, reduce motion.
5. **Loaders**: the **gate** loader of `neon_ui` (`neon-gate`: dark panels
   slide in from different sides and close like a gate, their edges glowing
   in cyan and red with a little flicker; an angled red box in the middle
   fills by the real progress with its number, in 2.5 s at least; the panels
   part when it is done) with a progress slider, the built-in kinds in the
   neon colors (a spinner, dots, a bar with a fake upload), a skeleton, and
   the `splash` the app starts with, which is the gate alone (no image: the
   loader draws it all) and parts over the app (`exit.reveal`). On the web
   the page shows the same picture (CSS and SVG) and percentage before
   Flutter runs, and the splash goes on from the page's progress and time
   without a jump (the generator writes it into `web/index.html` from
   `neon_ui`'s `lib/resources/loaders/neon-gate.html`).
6. **Background**: the theme's `background` (a picture, a veil, a drift),
   `ThemeBackground.screen('stage')` and `ThemeBackground.none`.
7. **Tokens**: nested groups, a `List<Color>`, references and color
   expressions.
8. **Logs**: `NeonLogsPanel` on the app's `LogBuffer`; the pages and the
   theme switches write there through the Spring logger (never `print`).
9. **Themes**: `neon` and `neon-ice`, switched with `ThemeSelection` and the
   generated `AppThemes.*` constants.

## The code

- `lib/main.dart`: `@SpringBootApplication` and `SpringApplicationWidget`.
- `lib/src/app/`: the shell, the theme switcher, the logging beans.
- `lib/src/pages/`: the nine pages; they read `context.theme.*` from the
  generated `lib/spring_gen/theme.spring.dart`. The app's keys include the library's
  theme: the generator follows `spring.config.import: resources:...` into
  the packages the app depends on.
- `lib/src/widgets/`: the frame of a page, a section, a code box, a swatch,
  a tile in the app's own style.

## Tests

```bash
flutter test --exclude-tags golden          # every page in both themes, and more
flutter test --tags golden                  # screenshots, macOS only
flutter test --tags golden --update-goldens # accept a new look
```

The tests cover every page in every theme (also a desktop run that scrolls,
and a narrow window), the theme switch, states, the modal, reduce motion,
the log and the YAML boxes.
