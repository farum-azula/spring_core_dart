# Theme Showcase Cupertino

The theme of
[`spring_boot_starter_flutter`](../../../spring_boot_starter_flutter/README.md)
on a **`CupertinoApp`**, with Cupertino widgets only (no Material). There is no
`CupertinoThemeData` in the Dart code: the iOS look, four themes and the looks
of the app's own widgets are YAML in [`lib/resources/`](lib/resources/).

## Run

```bash
flutter pub get
dart run build_runner build      # writes lib/spring_gen/*.spring.dart (checked in)
flutter run                      # desktop; -d chrome for the web (port 5080)
```

The window is wide on a desktop (a sidebar, as on macOS and iPadOS) and a
phone gets a tab bar with a "More" tab. The images are made by
`python3 tool/make_images.py` (standard library only).

## The themes

`light` (the root of `application.yml`) and `dark` (`extends: light`) use the
iOS system colors. [`themes/graphite.yml`](lib/resources/themes/graphite.yml)
is `dark` with an orange tint and a gradient behind the page;
[`themes/sunset.yml`](lib/resources/themes/sunset.yml) is `light` in warm
colors with a drifting picture. Both make the scaffolds see-through
(`cupertino.scaffold-background-color: transparent`) so the background shows.

## Navigation

The pages are screens of `spring_boot_starter_flutter_navigation`: each is a
`@ScreenRoute` (lib/src/pages/), and `SpringApp` builds a
`CupertinoApp.router` on them. The `Shell` (lib/src/app/shell.dart) is a
`@RouteShell` with a branch per tab, `/colors`, `/type`, `/controls`,
`/themes` and `/more`, each with its own stack: switching tabs loses
nothing. The other pages have flat addresses too (`/tokens`, `/motion`,
...) but live in the "More" tab (`@ScreenRoute('/motion', branch:
'/more')`): on a phone they open over its list, and back returns to it. On a
wide window the sidebar opens any of them at once, without a transition
(`go(path, transition: PageTransition.none)`). The first page is
`spring.flutter.navigation.initial: /colors`; on the web each page has its
address in the browser, and an unknown one shows the not-found screen.

## The pages

Each page shows a capability, the lines of YAML that make it (a box of
Markdown, `MarkdownView.code`, in Xcode's colors from `styles.code`) and the
result. A test checks that every quoted line is in `lib/resources/`.

1. **Colors**: the Cupertino palette (`cupertino.*`), declared colors, color
   objects (`alpha`, `mix`) and `$` references.
2. **Typography**: `typography.*` and how it reaches the Cupertino text theme.
3. **Tokens**: nested groups, lists, durations, an image token.
4. **Own widgets**: `styles.*` with `ThemeStates` (chip, button, field, card):
   a value per state, and `transition`.
5. **Controls**: a gallery of Cupertino controls under the theme.
6. **Motion**: `motion.*`, `ThemeAnimation`, reduce motion, the iOS page slide.
7. **Loaders**: `loaders.*` in the iOS look (pulse, dots, a thin bar, a quiet
   skeleton) shown by `ThemeLoader` and `ThemeSkeleton`, and the `splash`
   (logo, title, dots) the app starts with. On the web the generator writes
   the splash into `web/index.html`, so the page shows it before Flutter runs.
8. **Background**: `background` and `ThemeBackground`.
9. **Images**: asset images and the network profile.
10. **Transitions**: how a screen comes in: none by default (the theme sets
    no `motion.page-transition`), the platform's iOS slide
    (`transition: PageTransition.platform`), a custom fade, and one
    navigation's (the sidebar's, `PageTransition.none`).
11. **Themes**: switching with `ThemeSelection`, a theme from a URL.

`application-network.yml` (profile `network`, off by default) points the
images at https with the assets as fallback.

## Tests

`flutter test` runs the pages in every theme (wide and phone, and scrolled on
desktop), the YAML boxes, the Cupertino theme, states, motion, backgrounds and
images. Screenshots (`--tags golden`, made on macOS) are in `test/goldens/`;
accept a new look with `flutter test --tags golden --update-goldens`.
