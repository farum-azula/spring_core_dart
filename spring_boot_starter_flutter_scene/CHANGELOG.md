## Unreleased

- The first release. `SpringSceneView` (a view that owns its scene, or the application's) and `SceneBackdrop` (a scene behind a widget) over `flutter_scene`'s `SceneView`: plain widgets over their placeholders where scenes do not draw, a ceiling on frames, a still frame, a pause off the screen, a scene shown only whole.
- `spring.flutter.scene.*`: `enabled`, `render` (`animated`, `still`, `off`), `max-frame-rate`, `pixel-ratio`, `pause-off-screen`, `preload`, `models.<name>`, `app.*`, `debug.enabled`.
- One start of the engine for the app (`SceneEngine`), with the splash (`preload: eager`) or when the first scene shows; `SceneAvailability` says whether scenes draw here.
- The models of the properties (`SceneModels`, `SpringSceneModel`): an asset or an address (read in a browser too), loaded once with the splash or when first shown, cloned by every use.
- The application's scene (`ApplicationScene`, `SceneCustomizer`), under every screen or where the app puts a view.
- The start in application events (`SceneEvent`: the engine, each model, a failure) and in words (`SceneStatus`, the texts by message codes); the splash waits for what is eager (`SceneStart`, a `SplashTask`).
- The engine's own messages (`debugPrint`) as records of the application's log, under the logger `flutter_scene` (`spring.flutter.scene.engine-log`).
- The scenes' tab of the debug panel: the engine, every scene and model by name with what it costs.
- `build_hooks.dart`: `buildSceneShaders`, the engine's shader bundle with only what the app's scenes draw with.
- With `spring.flutter.scene.enabled: false` no scene bean exists and the build leaves the module out.
