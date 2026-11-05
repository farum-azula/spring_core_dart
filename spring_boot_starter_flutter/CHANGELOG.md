## 0.7.0

- Perf/generated code (#22)

## 0.6.3

### Changes

- The editor metadata of the starter's properties is made from code: `FlutterAppProperties` (`spring.flutter.app.*`, `type` is the `AppType` enum), `FlutterLifecycleProperties`, `FlutterFontsProperties`, `DesktopWindowProperties`, `FlutterWebProperties` (`spring.flutter.web.*`, with `@Range(0, 65535)` and the blocked ports as `@WarnValues` on `port`; the generator still reads these keys from the configuration files), `FlutterRestartProperties`, `FlutterSqliteProperties`, `FlutterDataSourceProperties` and `FlutterProperties` (`lib/src/properties/`); the hand-written `spring_metadata_additional.json` is gone. The classes are bound by the Binder (`@ComponentScan` module `flutterConfigBeans`, imported by the auto-configuration, so each is a bean too) and the starter reads nothing by key string any more: the `bind(Environment)` factories, `FlutterSqliteProperties.locationOf` and `SqliteLocation.parse` are gone. Keys and defaults are unchanged. A bad value now fails the start with the standard `Binding to target properties under '...' failed` report (a `ConfigurationPropertiesBindException`, not an `ArgumentError`) naming the key and the accepted values; booleans accept what Spring does (`true`/`false`, `on`/`off`, `yes`/`no`, `1`/`0`) and a bad one fails instead of counting as `true`. `spring.flutter.scan-os-environment` in the `--dart-define` values is bound the same way. A named data source's `url` is found by binding `spring.datasources.<name>.*`.
- Generated files live in `lib/spring_gen/`: import `package:app/spring_gen/main.spring.dart` (was `main.spring.dart`); the auto-configuration imports `spring_gen/spring_auto_configuration.spring.dart`.
- Themes without Dart (0.6.3): a design system in YAML under `spring.flutter.theme`.
  - References: `$colors.primary` names another value of the same theme (a whole value, or an operand of a color object), resolved per theme after `extends`. `${...}` stays Spring's placeholder. A cycle or an unknown path stops the start with the chain and a "did you mean".
  - Nested tokens of any depth, with lists (`List<Color>`, `List<double>`, `List<String>`) and durations (`250ms`); no JSON in a YAML string. Two-level tokens read as before.
  - `styles.<name>`: values per state (`default`, `hovered`, `focused`, `pressed`, `dragged`, `selected`, `scrolled-under`, `disabled`, `error`; a property with states must have `default`), insets, and `transition: <duration> [<curve>]`. New `ThemeStates` widget (hover, focus, press, disabled, keyboard activation, cursor, blended values), `ThemeStyle<V>` and `StateStyle`.
  - Motion: `motion.durations.<name>` and `motion.curves.<name>` (a named curve or four numbers), `Duration.zero` when the system asks for less motion. The old `motion.duration-<name>` / `motion.easing-<name>` forms are gone (an unknown `motion` key fails the start). `animations.<name>` (`duration`, `curve`, `repeat: none | loop | reverse`), `AnimationSpec` and the `ThemeAnimation` widget. Style and animation names read in any spelling.
  - `background` (color, image, overlay with a linear or radial gradient, `animation` and `effect` drift / zoom / pulse, `transition`, `screens.<name>`): `SpringApp` puts it under every screen and makes the Material scaffold and Cupertino page backgrounds transparent unless the theme sets them. `ThemeBackground`, `ThemeBackground.screen(name)` and `ThemeBackground.none`.
  - Images from the network: `ThemeImage` (`source`, `refresh`, `source-sha256`, `headers` as a map, `timeout`, `fallback`, `allow-http`) for `background.image`, the screens' backgrounds and image tokens (a token map with `source`). Cached through `FileTemplate` (`support`, `spring/images/<sha256 of source and pin>/`; IndexedDB on the web), read from the cache at once and re-read in the background with `refresh`; the start never waits for the network. `https` unless `allow-http: true`. A redirect to another origin (host, port or scheme: no https to http downgrade either) drops custom headers; headers and the image keys `source`, `fallback` and `source-sha256` are never searched for references, so a `$` from a placeholder stays. A file that does not match `source-sha256` is dropped with a warning. The web logs a CORS hint when a download fails.
  - References to the Material roles and shapes a theme does not declare (`$colors.outline`, `$colors.surface-container-lowest`, `$shape.extra-small`) are computed from the theme's own seed color, brightness, scheme variant and contrast. Durations take `ms`, `s`, `m`, `h`, `d` (any case, decimals, a space allowed: `250 ms`, `1.5s`); numbers take `+5`, `.5`, `1e3`. One shared fixture (`test/fixtures/theme_value_kinds.yaml`) fixes how a value is typed (number, duration, insets, color, text).
  - Fixes: `ThemeBackground` keeps the child's state when a theme switch adds or drops the background (and lays out under unbounded constraints); the image loader sets no refresh timer for an image that went away; with less motion an animation with `repeat: none` goes to its end; a style that animates with an overshooting curve never gets negative insets.
  - Fix: a `CupertinoThemeData` made from `typography` or `cupertino.text-theme` kept iOS blue in the action and nav action text styles; they now carry the theme's primary color.
  - The typed theme keys read from the generated `lib/spring_gen/theme.spring.dart` (see `spring_core_dart_generator`).
  - `ThemeStates(showFocusAlways: true)`: `focused` shows after a tap or a click too, not only with the keyboard (Flutter's focus highlight); for the frame of a text input.
  - One form for a color (0.6.3): a plain string (`#RGB`, `#RRGGBB`, `#AARRGGBB`, a `Colors` name, a `$` reference) or an object `{ color, mix: { with, amount }, alpha }` (`mix` first, then `alpha`; a percent is `0%..100%` or `0..1`; `color` is required; an unknown key fails with a "did you mean"). It works in `colors.*`, `seed-color`, tokens, styles (also per state), components (also per state), `cupertino.*`, `background` and gradient colors. A token or style map with a `color` is a color; `color` next to a key other than `mix` and `alpha` is an error. `ThemeProperties.color`, `colorList` and `ThemeValues.percent` read it; the generator and the editor check it with the same rules (`test/fixtures/theme_value_kinds.yaml`).
  - Loaders and the splash (0.6.3): `loaders.<name>` with the built-in kinds `spinner`, `dots`, `pulse`, `bar` and `skeleton`, `phases` (animations or `{progress: true}`) and kinds of your own (`@ThemeLoaderKind`, `ThemeLoaderPainter<P>`, `ThemeLoaderWidget<P>`, `LoaderFrame<P>`, the `ThemeLoaderKinds` registry); `ThemeLoader`, `ThemeSkeleton`; `splash` (background, logo, title, loader, animation, `min-duration`, `exit`) shown by `SpringApplicationWidget` from the moment the properties are read, following the start's progress (`SpringApplication.progressListener`), unless its own `splash:` builder is given; `window.springLoaderHandOff(progress)` is called on the web when the Flutter splash has painted. `ThemeKeyReader.loader` and `splash`; `ThemeBackground.data`. With less motion each phase is at its end and nothing shimmers. A plain `splash: ripple` is still the ink effect. A progress phase takes a `min-duration` (`fill: { progress: true, min-duration: 2.5s }`): it shows no more than its eased clock, so a fast start does not jump to 100 %. `splash.exit.reveal` lets the loader's last phase play over the app, which is already built under it (panels that part over the page instead of a fade from the splash's background). The splash takes the page loader's progress and elapsed time (`ThemeLoader.resumeFrom`, `resumeElapsed`, `LoaderFrame.elapsed`), so its phases, a flicker or a glitch go on where the page left them.
  - One duration syntax (0.6.3): a number with `ms`, `s`, `m`, `h` or `d`, decimals allowed, in motion, animations, styles, tokens, `transition`, `refresh` and `timeout` (the ISO-8601 form of `refresh` and `timeout` is gone).
  - Checks (0.6.3): `background.effect` without an `animation`, a radial gradient with `end` (it uses `begin` as its center), and a `contrast` outside -1 to 1 stop the start; `ThemeBackground.screen('x')` of a screen the theme does not have throws a `FlutterError` in debug that lists the screens. Every Material accent family is a color name (`pinkAccent.shade200`, shades 100, 200, 400, 700). A theme from a URL ignores `extends` with a warning, like `active` and `source`.
  - The type schema of the theme (`types.color`, `percent`, `duration`, ...) is in `tool/theme_metadata.json` for the editor and the JSON Schema.
- Removed: `lib/spring_keys.dart` is gone (import `spring_gen/main.spring.dart`); `classpath:` is gone (use `resources:`); the old motion forms `motion.duration-<name>` and `motion.easing-<name>` are gone (use `motion.durations.<name>` and `motion.curves.<name>`); the one-line color forms (`<color> alpha 12%`, `<color> mix <color> 14%`, chains, `role@38%`, bare role names such as `primary` in components, `0x` colors) are gone (use a color object or `$colors.primary`); `SpringThemeData.duration(name)` is gone (use `context.theme.motion` or `tokenDuration`); the `headers: ['Name: value']` list form of a theme image is gone (use a map).
- The theme section of `spring_metadata.json` lists every key of `spring.flutter.theme`, not only the components (`active`, `extends`, `colors.<role>`, `typography.<style>.<key>`, `shape.*`, `motion.*`, `animations.*`, `background.*`, `styles.*`, `tokens.*`, `cupertino.*`), with `scope` (`root` / `theme`) and `open`. `tool/theme_metadata.json` has them as `properties`.


## 0.6.2

### Changes

- Files of the app (0.6.2): `FileTemplate` (beans `fileTemplate` and `platformFileStore`, each only when the app declares none) writes and reads text, bytes and objects (JSON through the `ObjectMapper`) in the places `support` (default), `cache` and `documents` (`files.cache.write(...)`), with `exists`, `delete`, `list(prefix)` and `modifiedAt`. Writes are atomic (temporary file, then rename), paths stay inside their place (`..` and absolute paths are refused). `temp((file) async {...})` and `tempDir(...)` give a unique temporary file or folder deleted after the block (an error too); `createTemp()` leaves the deleting to the caller; leftovers are removed when the context closes and, for runs that died, at the next start (`<system temp>/spring/<run id>/`). The bytes go through a replaceable `FileStore` (`LocalFileStore` on `path_provider`'s directories, IndexedDB in a browser; temporary files in memory there, with no path). New dependency: `spring_web_dart` (see below).
- One set of app directories (0.6.2): SQLite's `location` and `FileTemplate`'s places share one mapping. On Windows `support` is `%LOCALAPPDATA%\<company>\<product>` (the machine's own) for both, and `cache` is the `cache` folder inside it (`path_provider`'s cache directory is the local root itself, so it would have been the same folder as `support`); the other platforms are unchanged.
- The theme from a URL (0.6.2): `spring.flutter.theme.themes.<name>.source` (an `https` URL or `github:owner/repo/path@ref`), `source-sha256` and `refresh`. The theme is cached through `FileTemplate` (`support`, `spring/themes/<sha256 of source and pin>/theme.yml` and `meta.json`) and survives restarts: without `refresh` downloaded once and read from the cache for ever; with `refresh` the cache is used at once and read again in the background (`If-None-Match` / `If-Modified-Since`) when older, and a new theme is shown live. Another `source` or `source-sha256` downloads again; caches of sources no longer configured are removed at start; offline or on any error the cache, else the theme of the app's own files; size limit 1 MiB, timeout 10 s, `https` only (redirects too). Only the theme's keys are taken from the file, the rest is ignored with a warning. `SpringThemes.applySource` sets the properties of one such theme. The HTTP client is the app's `HttpTransport` bean or `spring_web_dart`'s platform client: the package depends on `spring_web_dart` now.
- The whole theme (0.6.2): `spring.flutter.theme.components.*` sets every component theme of `ThemeData` (48: app bar, badge, banner, bottom app bar, bottom navigation bar, bottom sheet, the buttons, card, carousel, checkbox, chip, data table, date and time pickers, dialog, divider, drawer, dropdown menu, expansion tile, icon themes, input decoration, list tile, menu, menu bar, menu button, navigation bar, drawer and rail, popup menu, progress indicator, radio, scrollbar, search bar and view, slider, snack bar, switch, tab bar, text selection, toggle buttons, tooltip) with Flutter's own property names in kebab case, read by the type of the value (color, shape, border side, insets, size, constraints, text style, icon theme, number, elevation, enum, duration, mouse cursor, alignment, decoration, input border); `cupertino.*` sets `CupertinoThemeData` (primary and contrasting colors, backgrounds, handles, `text-theme.*`). Every `WidgetStateProperty` takes one value or a map per state (`default`, `hovered`, `focused`, `pressed`, `dragged`, `selected`, `scrolled-under`, `disabled`, `error`; the strongest wins in that order of strength: disabled, error, pressed, dragged, hovered, focused, selected, scrolled-under, default). Colors take an opacity (`primary@12%`), shapes a map (`type`, `radius`, `side`), text styles a map over a base style. An unknown component or property, or a wrong value, stops the start naming the valid ones, with a "did you mean". The 16 earlier components keep their keys. One fix: when `button` and a button kind (`filled-button`, ...) set the same property, the kind's value now wins (it was the shared one). The component reference of `docs/configuration.md` is generated from the mapping and a test keeps it in step.
- `ThemeKeyReader` (`context.theme` of the generated `lib/spring_keys.dart`): the typed theme keys read the theme shown now through `SpringTheme.of(context)`. See `spring_core_dart_generator`.
- The theme files and the property-file lookup use `resources:` (`resources:themes/*.yml`); `classpath:` still works with a warning (see `spring_core_dart`).

## 0.6.1

### Changes

- The desktop window from properties (0.6.1): `spring.flutter.desktop.window.title-bar` (`default`, `transparent`, `hidden`), `title` (the window's title; blank is none), `initial-size`, `min-size` and `max-size` (`1280x800`, logical pixels; min <= initial <= max, else the start stops naming the values; `max-size` is macOS `contentMaxSize`, Windows `ptMaxTrackSize` and GTK `GDK_HINT_MAX_SIZE`). `SpringApplicationWidget` reads them when the environment is ready and makes one call to the new platform code, before the first frame is shown (the frame is held back until the window is set, at most five seconds). A malformed value, or sizes that contradict each other, stops the start; phones and the web ignore the keys. `DesktopWindow` / `DesktopWindowInsets` give the space the window buttons take, `WindowDragArea` moves the window and maximizes it on a double click. The starter becomes a Flutter plugin for macOS (Swift: `NSWindow`), Windows (C++: DWM, `WM_GETMINMAXINFO`, `WM_NCCALCSIZE`) and Linux (GTK): its own code, no third-party package; it needs Flutter 3.47.

## 0.6.0

### Changes

- Where a SQLite database lives: with a SQL database in the properties (`spring.datasource.url`, or `spring.datasources.<name>.url`), `SpringApplicationWidget` reads the app's directories from `path_provider` before the application starts and, once the configuration files are read, sets `spring.datasource.sqlite.base-directory` to the directory of `spring.datasource.sqlite.location` (`support`, the default; `cache`; `documents`; any other value stops the start) and `spring.datasource.sqlite.isolate=true`, with the lowest precedence (the app's own properties win), for the primary data source and each named one. `support` is Android's `databases/` directory, iOS's and macOS's Application Support, Windows' `%LOCALAPPDATA%\<company>\<product>` (not the roaming directory) and Linux's `$XDG_DATA_HOME/<app id>`. The directory is created when it is missing. Nothing is set on the web or in a widget test (no `path_provider` plugin). The starter depends on `path_provider` (flutter.dev) and its platform interface, and only sets properties: it does not depend on the data starter.
- `BeanReadsPointcut.annotationTypes` and `NotifyListenersPointcut.annotationTypes` list the annotations the pointcuts match (`@ChangeNotifierComponent`, `@NotifyListeners`); the generator reads them to give a proxy class only to the beans that carry one (smaller generated code; regenerate the `.spring.dart` files).

## 0.5.0

### Changes

- `SpringApplicationWidget` closes the application context when a check fails after the start, and a hot reload's restart that fails closes both contexts, so runners and scheduled tasks no longer run behind the failure screen, and each retry no longer leaves another context running.

## 0.4.3

- Flutter security (#15)
- feat(security): spring_boot_starter_flutter_security — app login on e… (#13)
- feat: single sign-on with OAuth 2.0 / OpenID Connect (spring_boot_sta… (#11)
- docs: the READMEs and docs/ rewritten: what it is, why and when you need it, an example, then Spring (#10)

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- feat: spring_security_core, spring_boot_starter_security and a CI quality gate

## 0.3.2

- feat: hot reload on the Dart VM, flutter_notes example, fixes for example resources and workspace builds

## 0.3.1

- The example is a Spring Boot application written by the generator: a `@ChangeNotifierComponent` counter and Spring widgets.
- `spring_auto_configuration.dart` re-exports the logging starter's (and through it `spring_boot_dart`'s) auto-configuration, so a test naming `springBootAutoConfiguration` (`ApplicationContextRunner`) needs no other dependency.

## 0.3.0

- Reading is free: a `SpringStatelessWidget` or `SpringState` listens to a `@ChangeNotifierComponent` or `@NotifyListeners` bean of its record only when its `build` read the bean's state (a getter, a field, through the proxy); calling its methods (`onPressed: counter.increment`) no longer rebuilds the widget. A read outside the widget's build (an item builder, a `Builder` below it, a callback) keeps it listening; a `ChangeNotifier` bean without either annotation is listened to always, as before.
- The `flutter_counter` example uses Spring widgets for every widget that takes beans (`CounterPage`, `AboutPage`).
- **Breaking:** `spring.flutter.app.theme-mode` is gone (the theme shown is `spring.flutter.theme.active`), and so are `FlutterAppSettings.themeMode`, `color`, `theme`, `darkTheme` and `cupertinoTheme` (the theme comes from `SpringThemes`; `ThemeData` beans `theme` / `darkTheme` and a `CupertinoThemeData` bean still replace the made ones).
- Themes from properties (`spring.flutter.theme.*`): a shared part, the standard `light` / `dark` themes and named custom ones (`themes.<name>`, `extends`), the full `ColorScheme` (seed, variant, contrast, any role), the 15 `TextTheme` styles plus `code`, the Material 3 shape scale, elevations, density, splash, page transitions, motion, spacing, 19 components and the app's own tokens; checked at the start (values and the keys themselves: a misspelled key fails too), each made once into a `SpringThemeData`, a Material `ThemeData` and a `CupertinoThemeData`. `ThemeSelection` (`active`, `system-light`, `system-dark`, `select`) switches at run time; `SpringThemes.loadYaml` adds themes from a server; `SpringTheme.of(context)` for the app's own widgets; `ThemeCustomizer` / `CupertinoThemeCustomizer` beans; `ThemeData` beans `theme` / `darkTheme` still replace the made ones. Replaces `spring.flutter.app.theme-mode` (now `spring.flutter.theme.active`).
- Fonts from the assets: every `.ttf` / `.otf` under `flutter: assets:`, in any directory, is loaded before the first frame in the family its file names (`spring.flutter.fonts.auto-load`, `spring.flutter.fonts.exclude`); a family the theme names but nothing provides is logged.

## 0.2.3

- `SpringApplicationWidget(home: ...)` builds the app widget from the configuration (`SpringApp`): `spring.flutter.app.type` (`widgets` by default, `material`, `cupertino`), `title`, `debug-banner`, `theme-mode`, `locales` (by default the languages of the messages files), the `ThemeData` beans `theme` / `darkTheme` and a `CupertinoThemeData` bean, `NavigatorObserver` beans, `FlutterAppCustomizer` beans; Flutter's localization delegates come with the starter (`flutter_localizations`). `child:` keeps working for an app's own `MaterialApp`.
- An example (`example/`): the counter app in one runnable file, and the way with the generator step by step.

## 0.2.2

- **Breaking:** `SpringStatelessWidget.build` takes only the `BuildContext`; the widget reads its beans as `beans`, like a `SpringState` (in `build` and the callbacks made there). Tests build it with fakes through `buildWith(context, beans)`.
- README: the generator's check of `@Value('asset:...')`.

## 0.2.1

- First version: `SpringApplicationWidget` (starts the application, splash and failure screens, restarts the context on a hot reload when the generated code changed, switched off with `spring.devtools.restart.enabled=false`, closes the context when removed), `SpringScope`, `context.bean<T>()`, getters generated for `@BuildContextAccess` beans, `SpringStatelessWidget<(...)>` and `SpringStatefulWidget<(...)>` with `SpringState<W, (...)>`, beans checked at startup, `AppLifecycleStateEvent` with the context paused in the background and restarted in the foreground (`spring.flutter.lifecycle.pause-in-background`), platform profiles (`android`, `ios`, `web`, `macos`, `windows`, `linux`, `mobile`, `desktop`), the OS environment off unless `spring.flutter.scan-os-environment`, `context.message` in the app's locale.
- `@ChangeNotifierComponent(exclude: [...])`: a stereotype for a plain class whose proxy mixes `ChangeNotifier` in and notifies after every public method and setter; `listenableOf(bean)`.
- `SpringStatelessWidget` and `SpringState` rebuild when a `Listenable` bean of their record notifies.
- `@NotifyListeners(exclude: [...])` on a `ChangeNotifier` bean (or some of its methods): `notifyListeners()` after each call through the AOP proxy, after a returned `Future` completes, also after an error.
- `asset:` resources: `@Value('asset:assets/intro.mp4') Resource video` injects an `AssetResource` of the app's asset bundle (`key` for Flutter's APIs, `exists()` from the asset manifest), like `classpath:` for `lib/resources/`.
- Brings `spring_boot_starter_logging`, switched on (console output in Boot's format, `logging.*`, `LogBuffer`).
- Exports `spring_core_dart`, `spring_boot_dart` and `spring_boot_starter_logging` (without `Banner` and `Size`, which clash with Flutter's; the constraint is `SizeConstraint`), so an app depends only on `spring_boot_starter_flutter`.
