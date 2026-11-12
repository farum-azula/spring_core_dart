# Theme examples

One folder, three designs, all made the same way: **the look is YAML** in
`lib/resources/`, and the Dart code only reads it (`context.theme`,
`ThemeStates`, `ThemeAnimation`, `ThemeBackground`, `ThemeImage`). Each app
has pages that show a part of the theme next to the YAML that makes it, in
a block of Markdown (`MarkdownView.code`) colored by the theme's own
`styles.code`; a test checks that every quoted line is in the files.

Every app also shows all three loaders of the theme, and starts with a
**splash** written in YAML (`splash:` with a logo, a title, a loader and a
`min-duration`): component loaders (`ThemeLoader`, `ThemeSkeleton`) on a
Loaders page, the splash while the app starts, and, on the web, the same
splash in `web/index.html` before Flutter runs (written by build_runner
between `<!-- spring:loader:start -->` and `<!-- spring:loader:end -->`; the
default blank page is gone). Material shows a spinner, a bar and a skeleton,
Cupertino a pulse, dots, a thin bar and a skeleton in the iOS look, and NEON a
loader kind of its own: a gate of panels, written in Dart in `neon_ui` (see below).

| Design | App | What it is |
|---|---|---|
| Material | [`material/`](material/README.md) | A `MaterialApp`, with `spring_boot_starter_flutter_material`. The theme sets Flutter's own components (buttons, inputs, cards, bars...) per state, and styles for our own widgets. Port 5070 on the web. |
| Cupertino | [`cupertino/`](cupertino/README.md) | A `CupertinoApp` with only Cupertino widgets, with `spring_boot_starter_flutter_cupertino`, themed from the `cupertino:` section. Port 5080 on the web. |
| Custom widgets | [`neon/`](neon/README.md) on [`neon_ui/`](neon_ui/README.md) | An app of type `widgets` (no Material, no Cupertino: no design library and no design starter in its dependencies). Its components are not Flutter's: they are the widgets of a **component library**, `neon_ui`, delivered as a Dart package with its fonts, picture and a theme file (`themes/neon.yml`) that the app imports. Port 1010 on the web. |

The **gate** loader (`neon_ui`'s `@ThemeLoaderKind('neon-gate')` widget, the
`loaders.neon-gate` in its `themes/neon.yml` and
`lib/resources/loaders/neon-gate.html` for the web page) is drawn without a
single image: dark panels slide in one after the other from different sides
and close like a gate, their edges glowing in cyan and red with a little
flicker, and an angled red box in the middle fills with the real start
progress and its number (in no less than 2.5 s: `fill: { progress: true,
min-duration: 2.5s }`). When the app is ready the panels part the way they
came, over the app itself (`splash.exit.reveal`), not over a blank screen.
The colors are tokens (`neon.red`, `neon.cyan`, `neon.navy`). Every app that
uses the `neon` theme gets it.

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
