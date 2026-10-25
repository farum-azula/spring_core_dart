# flutter_themes

Themes from properties on [`spring_boot_starter_flutter`](../../spring_boot_starter_flutter/README.md):
one gallery page (palette, text styles, Material components, the app's own
tokens) in the standard `light` and `dark` themes and four custom ones,
switched at run time. There is no `ThemeData` in the code.

| File | What it shows |
|---|---|
| `lib/resources/application.yml` | the shared part of every theme (seed color, fonts per text role, shapes, components, tokens), the standard `dark` theme's differences, which theme is active (`system`) |
| `lib/resources/themes/*.yml` | one custom theme per file (`spring.config.import`): `ocean`, `ocean-night` (`extends: ocean`, dark), `sepia` (own colors, flat shapes, no splash), `high-contrast` (`extends: light`, `contrast: 1.0`) |
| `res/fonts/` | Roboto and Roboto Condensed (Apache 2.0, from the Flutter SDK): font files in an asset directory of their own, loaded by family, listed nowhere |
| `assets/remote/winter.yml` | a theme as a server would send it; the menu's *Load a theme from the server* adds it with `SpringThemes.loadYaml` and shows it |
| `lib/src/gallery_page.dart` | the page; `ThemeMenu` is a `SpringStatelessWidget<(ThemeSelection, SpringThemes)>`, `ThemeBanner` reads the brand tokens through `SpringTheme.of(context)` |
| `test/widget_test.dart` | the themes and their order, switching with the menu, the theme from the server, a broken property failing the start |
| `test/golden_test.dart` | a screenshot of the gallery in each theme (`test/goldens/*.png`, made on macOS, compared on a macOS runner in CI) |

## Run

```sh
flutter run
flutter run --dart-define=SPRING_FLUTTER_THEME_ACTIVE=sepia   # start in a custom theme
```

After changing beans or annotations, regenerate `lib/main.spring.dart`
(`dart run build_runner build`). Theme properties are files of
`lib/resources/`, so a changed theme also shows after a hot reload.

## Screenshot tests

```sh
flutter test test/golden_test.dart                    # compare
flutter test test/golden_test.dart --update-goldens   # accept the new look
```

The screenshots use the app's own fonts (loaded from `res/fonts/` by the
starter, as on a device); only the Material icons come from the Flutter
SDK (`test/flutter_test_config.dart`). Like in `flutter_counter`, they are
made on macOS and only match there, so the file is tagged `golden` and
left out elsewhere with `flutter test --exclude-tags golden`.
