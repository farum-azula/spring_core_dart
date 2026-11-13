# spring_boot_starter_flutter_scene: example

A Flutter app with a 3D scene among its widgets.
[`example.dart`](example.dart) is the whole app; the generator writes
`spring_gen/example.spring.dart` (`dart run build_runner build`).

- `Showroom` shows the model `hero` in a scene of its own
  (`SpringSceneView.declarative` with `SpringSceneModel('hero')`), and
  under it what the scenes are doing, in words (`SceneStatus`).
- `LoadedModels` hears each model that finished loading: every step of
  the scenes' start is an application event (`@EventListener`).
- `lib/resources/application.properties` names the model
  (`spring.flutter.scene.models.hero.source`) and sets the ceiling on
  frames.

The model's file is an asset of the app:

```yaml
dependencies:
  spring_boot_starter_flutter_scene: ^0.8.0

flutter:
  assets:
    - assets/models/
```

Where scenes do not draw (`spring.flutter.scene.enabled=false`, a browser
without WebGL2) the same app shows the placeholder and no status: its
code has no branch for it.

A whole app to run, with the application's scene, a scene behind a widget
and the scenes' debug tab, is
[`example/scene`](https://github.com/farum-azula/spring_core_dart/tree/main/example/scene)
of the repository.
