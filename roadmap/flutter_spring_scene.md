# flutter_spring_scene (planned)

On `flutter_scene` — an allowed exception to the dependency policy, only in
this starter. Part of the [Flutter plan](flutter_spring.md).

## 3D scenes

3D scenes with the rest of the app's tools — models, materials and
environment maps loaded as resources (`classpath:` or assets), quality per
platform from profiles and properties (`scene.shadows`, `scene.msaa`),
`@OnFrame` methods on beans driven by the widget's ticker, and scene state
in `@Signal` fields like any other state.
