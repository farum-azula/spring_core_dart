## Unreleased

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
