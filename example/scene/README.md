# Scene Showcase

3D scenes among Flutter widgets with
[`spring_boot_starter_flutter_scene`](../../spring_boot_starter_flutter_scene):
everything is set up in `lib/resources/application.yml`.

## What it shows

| Where | What |
|---|---|
| `lib/resources/application.yml` | `spring.flutter.scene.*`: the frame ceiling, the engine started with the splash, the model `crate`, the application's scene and its camera, the scenes' debug tab in every build; the isolation headers of the dev server |
| `lib/src/backdrop.dart` | the application's scene under the page: a `SceneCustomizer` bean adds three clones of the model, each turned by a component; the models come through an `ObjectProvider`, so the app also starts with scenes turned off |
| `lib/src/showroom.dart` | `SpringSceneView.declarative` with `SpringSceneModel('crate')`, and its placeholder |
| `lib/src/plate_card.dart` | `SceneBackdrop`: a mesh of the widget's own size behind it, laid out by its pixels, leaning after the pointer; a colour of the app as linear light |
| `lib/src/showcase_page.dart` | the status line (`SceneStatus`), a page with no background of its own |
| `lib/resources/messages.properties` | the steps of the start in the app's own words |
| `assets/models/crate.glb` | the model: a cube with one material |
| `android/`, `ios/`, `macos/`, `linux/`, `windows/` | Flutter GPU turned on for the platform (the one line the engine needs there; the starter's README has the table) |
| `integration_test/scenes_test.dart` | on a device, where there is a GPU: the engine starts, the model loads, each scene draws frames with draw calls |

## Run

```bash
flutter pub get
dart run build_runner build
flutter run -d chrome          # http://localhost:5075/
flutter run -d macos           # or another device
flutter test                   # the page with placeholders (a test has no GPU)
flutter test integration_test -d macos   # the scenes drawing
```

The debug panel opens with ⌘⇧D (Ctrl+Shift+D) or the link on the page;
its "Scenes" tab has every scene and model by name.

To see the other modes, change `spring.flutter.scene.render` to `still`
(one frame that stands) or `off`, or set `spring.flutter.scene.enabled:
false` (no scene bean, placeholders only), and run `build_runner` again.

The app has no hook of its own, so the engine compiles its whole shader
bundle at the start (about 0.35 s here): the model's material is lit.
See "The engine's shaders" in the starter's README.
