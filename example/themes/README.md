# Theme examples

One folder, three designs, all made the same way: **the look is YAML** in
`lib/resources/`, and the Dart code only reads it (`context.theme`,
`ThemeStates`, `ThemeAnimation`, `ThemeBackground`, `ThemeImage`). Each app
has pages that show a part of the theme next to the YAML that makes it; a
test checks that every quoted line is in the files.

| Design | App | What it is |
|---|---|---|
| Material | [`material/`](material/README.md) | A `MaterialApp`. The theme sets Flutter's own components (buttons, inputs, cards, bars...) per state, and styles for our own widgets. Port 5070 on the web. |
| Cupertino | [`cupertino/`](cupertino/README.md) | A `CupertinoApp` with only Cupertino widgets, themed from the `cupertino:` section. Port 5080 on the web. |
| Custom widgets | [`neon/`](neon/README.md) on [`neon_ui/`](neon_ui/README.md) | An app of type `widgets` (no Material, no Cupertino). Its components are not Flutter's: they are the widgets of a **component library**, `neon_ui`, delivered as a Dart package with its fonts, picture and a theme file (`themes/neon.yml`) that the app imports. Port 1010 on the web. |

`neon_ui` is a library: it has tests and no app of its own. A design system
can live in its own package and be reused by many apps; the app only adds
its own tokens, styles and themes (`extends`).

## Run

Each app is a Flutter project in its own folder (they are not in the pub
workspace):

```bash
cd example/themes/material      # or cupertino, or neon
flutter pub get
flutter run -d macos            # or linux, windows, or an emulator
flutter run -d chrome           # the web port is in lib/resources/application.yml
```

After a change of the YAML or of the annotated classes, regenerate the code
in `lib/spring_gen/`:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Test

```bash
flutter test --exclude-tags golden     # everywhere
flutter test --tags golden             # screenshots, made on macOS
```

For `neon`, `neon_ui` has to be resolved too (`cd ../neon_ui && flutter pub get`).
