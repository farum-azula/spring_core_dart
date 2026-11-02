## Unreleased

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
