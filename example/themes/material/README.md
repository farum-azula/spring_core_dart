# Theme Showcase Material

A Flutter app about one thing: the theme of
[`spring_boot_starter_flutter`](../../../spring_boot_starter_flutter/README.md).
Every look in it, colors, text, components, states, motion, backgrounds, is
a line of YAML. There is no `ThemeData` in the Dart code.

Open the app and the YAML side by side. Each page shows a capability, the
lines of YAML that make it (boxes of Markdown, `MarkdownView.code`, split by
the languages of `themes/code.yml` and colored by the theme's `styles.code`,
each with a copy button) and the result. A test checks that every line
in a box is really in `lib/resources/`.

## Run

```bash
flutter pub get
dart run build_runner build      # writes lib/spring_gen/ (checked in)
flutter run                      # desktop; -d chrome for the web (port 5070)
```

The app is offline. To see the network form of images, start it with the
opt-in profile (the hosts in the file are examples, put your own):

```bash
flutter run --dart-define=SPRING_PROFILES_ACTIVE=network
```

## Read the YAML

| File | What is in it |
|---|---|
| [`lib/resources/application.yml`](lib/resources/application.yml) | The shared theme (the root), numbered 2 to 8 as the pages: colors, typography, spacing, shape, tokens, components, `cupertino`, `styles`, motion, animations, and the standard `dark` theme |
| [`lib/resources/themes/ocean.yml`](lib/resources/themes/ocean.yml) | `ocean` and `ocean-night`: `extends`, a gradient background |
| [`lib/resources/themes/neon.yml`](lib/resources/themes/neon.yml) | `neon`: dark, yellow, cyan and pink, an image background that drifts, a screen background |
| [`lib/resources/themes/high-contrast.yml`](lib/resources/themes/high-contrast.yml) | `high-contrast`: `contrast: 1`, thick borders, no page transition |
| [`lib/resources/themes/code.yml`](lib/resources/themes/code.yml) | `syntax.*`: the languages of the code boxes (Dart, YAML, ...), a copy of farum-azula/themes' `code.yml`; the starter knows no language by itself |
| [`lib/resources/application-network.yml`](lib/resources/application-network.yml) | The `network` profile: https images with a fallback asset, and a theme from a URL (commented) |
| [`lib/resources/messages.properties`](lib/resources/messages.properties) | The texts, read as `context.messages.*` |

## The pages

Each page is a screen of
[`spring_boot_starter_flutter_navigation`](../../../spring_boot_starter_flutter_navigation/README.md)
with its own address: `/colors`, `/type`, `/tokens`, `/components`,
`/states`, `/motion`, `/loaders`, `/background`, `/images`,
`/transitions`, `/themes`. Each page is a branch of the shell, so the rail
and the drawer switch pages at once, without a transition. On
the web the browser shows it, and a link or a reload opens that page; `/`
opens the colors (`spring.flutter.navigation.initial`), any other address
the not-found page.

1. **Colors**: the Material roles made from `seed-color`, declared colors,
   references (`$colors.primary`), roles nobody declared
   (`$colors.outline`), color objects (`{ color, alpha, mix }`) and chains.
2. **Type and space**: text styles, `spacing.*`, the shape scale and
   shapes by reference (`$shape.extra-small`).
3. **Tokens**: nested groups, lists (`List<Color>`, `List<double>`,
   `List<String>`), durations and an image token.
4. **Components**: Flutter's own widgets (buttons, selection controls,
   chips, inputs, dialog, snack bar, tooltip, tabs, navigation, lists,
   cards) styled by `components.*`, with a value per state, and a Cupertino
   section (`cupertino.*`).
5. **Own widgets**: our own widgets (pill, action button, field, tile) styled
   by `styles.*` and `ThemeStates`: hover, focus, press, selected, disabled,
   error and a `transition`.
6. **Motion**: `motion.durations`, `motion.curves`, animations with
   `repeat: none | loop | reverse` played by `ThemeAnimation` (a glow border,
   a pulse, an entrance), a reduce-motion switch, and page transitions.
7. **Loaders**: `loaders.*` shown by `ThemeLoader` and `ThemeSkeleton`: a
   spinner for a fake refresh, a bar (indeterminate and with the progress of
   a fake upload), a skeleton of a list that appears after a short wait, and
   the `splash` the app starts with (a logo and a bar that follows the
   start). On the web the generator writes the same splash into
   `web/index.html` (between `<!-- spring:loader:start -->` and `end`), so
   the page shows it before Flutter runs.
8. **Background**: the theme's background (color, image, gradient, `drift`
   effect), `ThemeBackground.screen('showcase')` and `ThemeBackground.none`.
9. **Images**: `ThemeImage` from an asset, and the same from https with a
   cache and an asset `fallback` (profile `network`).
10. **Transitions**: how a screen comes in: none by default, a theme's own
   (`motion.page-transition: zoom` in neon), the platform's
   (`transition: PageTransition.platform`), a custom fade, and one
   navigation's (`go(path, transition: ...)`).
11. **Themes**: six themes (`light`, `dark`, `ocean`, `ocean-night` which
   `extends` ocean, `neon`, `high-contrast`), switched with `ThemeSelection`
   and the generated `AppThemes.*` constants. The theme chosen is kept
   between runs (`spring.flutter.theme.remember`, on by default) and shown
   again while the splash shows.

## The code

- `lib/main.dart`: `@SpringBootApplication` and `SpringApplicationWidget`,
  without a `home`: the screens of the navigation make the app.
- `lib/src/app/shell.dart`: the `@RouteShell` with a branch per page (a
  navigation rail, or a drawer when narrow), so each page keeps its state
  while another is shown, and the not-found screen.
- `lib/src/app/`: also the theme menu and the Spring logger (`@Log`, never
  `print`).
- `lib/src/pages/`: the eleven pages, each a `@ScreenRoute('/<page>')`
  screen; they read `context.theme.*` from the
  generated `lib/spring_gen/theme.spring.dart` (import `spring_gen/main.spring.dart`).
- `lib/src/widgets/styled_widgets.dart`: the widgets of our own, built with
  `ThemeStates` and `ThemeAnimation`.

## Tests

```bash
flutter test --exclude-tags golden          # every page in every theme, and more
flutter test --tags golden                  # screenshots, macOS only
flutter test --tags golden --update-goldens # accept a new look
```

No test touches the network: the `network` profile is checked with a mock
HTTP transport. CI (`.github/workflows/ci.yml`) runs the generated-code
check, format, analyze, the tests, a web build, and the goldens on macOS.

## Images

`assets/images/` is made by `python3 tool/make_images.py` (standard library only).
