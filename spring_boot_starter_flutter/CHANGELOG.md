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
