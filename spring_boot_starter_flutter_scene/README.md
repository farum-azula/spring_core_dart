# spring_boot_starter_flutter_scene

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-boot-starter-flutter-scene](https://farum-azula.org/components/spring-boot-starter-flutter-scene)

3D scenes for Flutter apps built on
[`spring_boot_starter_flutter`](https://pub.dev/packages/spring_boot_starter_flutter),
on [`flutter_scene`](https://pub.dev/packages/flutter_scene) (WebGL2 in a
browser, Impeller elsewhere).

- **Scenes that are widgets**: `SpringSceneView` among the app's widgets,
  `SceneBackdrop` behind one. Where scenes do not draw (turned off, no
  WebGL2, the engine failed) they are plain widgets over their
  placeholders: the app's code has no branch for it.
- **What a scene costs, from properties**: a ceiling on frames, a still
  frame, a pause off the screen, the scenes' own pixel ratio.
- **One start of the engine**, with the splash or when the first scene
  shows; the splash waits for what is eager.
- **Models from properties**: `spring.flutter.scene.models.<name>`,
  loaded once, cloned by every use.
- **The application's scene**: one scene for the whole app, under every
  screen.
- **The start in events and in words**: what is being loaded right now,
  for a loader to say.
- **A tab of the debug panel**: every scene and model by name, with what
  it costs.

## Contents

- [Install](#install)
- [Native platforms](#native-platforms)
- [A scene](#a-scene)
- [A scene behind a widget](#a-scene-behind-a-widget)
- [Properties](#properties)
- [Where scenes do not draw](#where-scenes-do-not-draw)
- [Models](#models)
- [The application's scene](#the-applications-scene)
- [The start: events and words](#the-start-events-and-words)
- [The engine's log](#the-engines-log)
- [The debug tab](#the-debug-tab)
- [The engine's shaders](#the-engines-shaders)
- [What a scene costs](#what-a-scene-costs)
- [Things of the engine to know](#things-of-the-engine-to-know)

## Install

```yaml
dependencies:
  spring_boot_starter_flutter_scene: ^0.8.1
  # The engine's own scene widgets and geometry (SceneNode, SceneMesh,
  # materials), when the app's code names them.
  flutter_scene: ^0.24.3
```

The package re-exports the Flutter starter: an app lists it instead. It
needs Flutter 3.50 or newer (Dart 3.14), as the Flutter starter does.
`flutter_scene` compiles its shaders with the SDK's shader compiler when
the app is built.

## Native platforms

In a browser nothing more is needed. On every other platform the engine
draws with Flutter GPU, which is turned on once per platform, in the
platform's own file:

| Platform | File | Add |
|---|---|---|
| iOS | `ios/Runner/Info.plist` | `<key>FLTEnableFlutterGPU</key><true/>` |
| macOS | `macos/Runner/Info.plist` | `<key>FLTEnableFlutterGPU</key><true/>` |
| Android | `android/app/src/main/AndroidManifest.xml`, in `<application>` | `<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true" />` |
| Linux | `linux/runner/my_application.cc`, after `fl_dart_project_new()` | `fl_dart_project_set_enable_flutter_gpu(project, TRUE);` |
| Windows | `windows/runner/main.cpp`, after `flutter::DartProject project(L"data");` | `project.set_enable_flutter_gpu(true);` |

Without it the engine does not start there: the app runs, and its scenes
are their placeholders ([Where scenes do not draw](#where-scenes-do-not-draw)).
The scene showcase of the repository (`example/scene`) has all five.
Scenes were seen drawing in a browser and on macOS; the other platforms
are set up the same way and were not run.

## A scene

```dart
SpringSceneView.declarative(
  name: 'showroom',                       // its name in the debug tab
  placeholder: const ShowroomPicture(),   // until it draws, or where it cannot
  children: [
    SpringSceneModel('hero'),             // spring.flutter.scene.models.hero
    SceneMesh(geometry: floor, material: concrete),
  ],
)
```

The children are scene widgets: the engine's (`SceneNode`, `SceneMesh`,
`SceneModel`, lights) and the starter's `SpringSceneModel`. The view owns
its scene and frees it with the widget. `const SpringSceneView()` shows
[the application's scene](#the-applications-scene) instead.

Around the engine's `SceneView` the starter:

- starts the engine if nothing has, with the placeholder meanwhile;
- shows the scene once it is whole: its models loaded, and the engine
  asked to compile the programs of its materials beforehand (`warmUp`,
  on by default), so no half-built scene is drawn. In a browser the
  first frame then built no program; on macOS the engine still reported
  programs built in the first frame;
- draws at most `spring.flutter.scene.max-frame-rate` frames a second
  (`maxFrameRate` on the widget asks for fewer);
- draws one frame that stands with `render: still` or when the system
  asks for less motion;
- stops drawing when scrolled off the screen (`pause-off-screen`).

A still frame is drawn again when the view is rebuilt. A scene widget
that changes what is drawn without a rebuild (a value set on a material
in a callback) asks for a frame: `SpringSceneView.repaintOf(context)`.

## A scene behind a widget

```dart
SceneBackdrop(
  name: 'match-header',
  margin: 48,                              // light that reaches past the edge
  tilt: 0.7,                               // degrees, after the pointer
  placeholder: const PlainPanel(),
  scene: (context, surface) => [GlassPanel(surface), NeonEdge(surface)],
  child: const MatchHeader(),
)
```

The scene is as large as the child and `margin` pixels around it, and a
pixel of the child is a pixel of the scene: `surface` (`SceneSurface`) is
the child's rectangle as a plane, 100 pixels to a unit, the origin in its
middle, `+Y` up; `surface.toScene(Offset(x, y))` is a point of the widget
in the scene.

## Properties

```yaml
spring:
  flutter:
    scene:
      enabled: true          # false: no scene bean, placeholders only
      render: animated       # animated | still | off
      max-frame-rate: 30     # the ceiling of every scene
      pixel-ratio: 1.5       # the scenes' own; not set: the device's
      pause-off-screen: true
      preload: lazy          # eager: the engine starts with the splash
      engine-log: true       # the engine's messages in the app's log
      models:
        hero:
          source: asset:assets/models/hero.glb
          preload: eager     # not set: as `preload` above
      app:
        enabled: false       # true: the application's scene
        placement: background  # background | none
        camera:
          position: 0, 1.5, -4
          target: 0, 1, 0
          fov: 45
      debug:
        enabled: true        # the scenes' tab; not set: debug and profile builds
```

A value for one platform goes into its profile file, as everywhere:
`render: still` in `application-android.yml`, or in the profile a debug
run uses, where a frame costs several times a release's.

## Where scenes do not draw

| When | What the widgets do | The beans |
|---|---|---|
| `spring.flutter.scene.enabled: false` | their placeholders | none exists; in the application's own configuration the build leaves the starter's module out (the engine's code stays in the build as long as the app has scene widgets, which name it) |
| `render: off` | their placeholders | exist; the engine is never started |
| The engine did not start (no WebGL2, no Flutter GPU) | their placeholders | exist; `SceneUnavailableEvent` says why, once |

The widgets need no check. The app's own code that wants a scene bean
takes it as one that may be absent:

```dart
@Component()
class Showroom {
  Showroom(this.models);

  final ObjectProvider<SceneModels> models;

  Future<void> open() async => models.getIfAvailable()?['hero'].load();
}
```

`SceneAvailability` (`draws`, `isReady`, `reason`) is the one place that
knows whether scenes draw here.

## Models

A model is named in the properties with its file, a binary glTF (`.glb`):

- an asset of the app: `asset:assets/models/hero.glb`, listed under
  `flutter: assets:`;
- an address: `https://cdn.example.com/hero.glb`, read with one GET
  through the app's `HttpTransport` bean (the platform's client without
  one), in a browser too. Only `https`, and `http` with
  `spring.remote.allow-insecure: true`. In a browser the server must
  allow the page's origin (CORS), and under `require-corp` isolation
  nothing else is loaded from another origin.

Not a file of `lib/resources/`: those are embedded into the app's code,
a megabyte at most. Another format is a `SceneModelImporter` bean of the
app.

- `SpringSceneModel('hero', position: ..., animations: [...])` shows it
  in a scene: a clone of its template, so every use has its own
  transform and animation while the geometry, textures and materials
  stay shared on the GPU.
- `SceneModels` (`sceneModels`) gives it to code: `models['hero']` is its
  `SceneModelHandle` (`load()`, `state`, `template`); an unknown name
  fails naming those there are.
- An eager model is loaded while the splash shows; a lazy one when a
  scene first shows it. Either way it is loaded once and kept: a model
  that left the screen and came back is not imported again.

## The application's scene

With `spring.flutter.scene.app.enabled: true` the app has one scene of
its own, the `applicationScene` bean, made with the splash. It shows
under every screen (`placement: background`; the screens must not paint
an opaque background of their own) and in every `const SpringSceneView()`.

```dart
@Component()
class Stage implements SceneCustomizer {
  Stage(this.models);

  final ObjectProvider<SceneModels> models;

  @override
  Future<void> customize(Scene scene) async {
    scene.add((await models.getObject()['stage'].load()).clone());
  }
}
```

Every `SceneCustomizer` bean receives the scene once, in `@Order`. A
screen adds to it with the engine's `SceneSubtree` and takes its part
away when it leaves. It is where scenes cost most: a scene under every
screen draws the whole page again for each of its frames.

## The start: events and words

Each step is an application event (a `SceneEvent`), heard like any other:

| Event | When |
|---|---|
| `SceneEngineStartingEvent`, `SceneEngineReadyEvent` | the engine starts (its shaders are compiled), with the time it took |
| `SceneModelLoadingEvent`, `SceneModelLoadedEvent` | a model, with its name, its place among those loaded together, its size and time |
| `SceneReadyEvent` | everything asked for with the splash is ready |
| `SceneFailedEvent` | a step failed (the engine, a model, the application's scene); the app goes on |
| `SceneUnavailableEvent` | scenes do not draw here, and why |

An event is a `MessageSourceResolvable`: its words come from the app's
messages by its code, else its own English.

```properties
# lib/resources/messages.properties
scene.loading.engine=Compiling shaders…
scene.loading.model=Loading {0}, {1} of {2}…
```

`SceneStatus` (`sceneStatus`) is the current step for a loader: a
`ValueListenable` whose `text` is "Compiling shaders…", then
"Loading hero, 2 of 5…", and `null` when nothing is being loaded.

The splash waits for what is eager (the engine with `preload: eager`,
the eager models, the application's scene) as for any `SplashTask`, and
its loader moves with the steps. A step that fails does not stop the
start.

## The engine's log

`flutter_scene` writes what it has to say with Flutter's `debugPrint`:
bare lines beside the app's log. The starter takes them into the
application's log, under the logger `flutter_scene`:

```
2026-11-13T19:35:55.592+02:00  INFO 48654 --- [main] flutter_scene : Unpacking glTF (nodes: 1, meshes: 1, materials: 1, skins: 0, animations: 0)
2026-11-13T19:35:55.933+02:00  WARN 48654 --- [main] flutter_scene : pipeline build took 66ms mid-frame. Draw this material once during a load screen...
```

So they have a time and a level, go where the app's log goes (the debug
panel's Logs tab too), and are set like any logger:

```yaml
logging:
  level:
    flutter_scene: warn    # only what went wrong
```

A message that tells of trouble (failed, skipped, missing, a program
built in the middle of a frame) is a warning; the rest is `info`.
`debugPrint` is one function for all of Flutter, so the engine's messages
are told apart: by how the engine begins them (`flutter_scene:`,
`fscene:`, `glTF import:`...) and, outside a release build, by where the
call came from; everything else goes on as it was.
`spring.flutter.scene.engine-log: false` leaves `debugPrint` alone. Not
caught: the few lines the engine writes with `print`.

## The debug tab

"Scenes" in the debug panel
(`spring.flutter.scene.debug.enabled`; not set: debug and profile builds):

- **the engine**: its state, the time of its start, whether the web page
  is cross-origin isolated, the steps of the start in words;
- **every scene on the screen by its name**: frames a second against
  those it may draw, why it stands still, the surface, the engine's
  numbers of its last frame (draw calls, vertices, programs bound and
  built in the frame), each pass with its time on the page's thread;
- **every model by its name**: its file, size, time to read and to
  import, what it is made of, and a switch that hides it everywhere: the
  frame's numbers with and without it are what it costs;
- **memory**: what the engine's caches hold.

The engine gives no time on the GPU, and nothing per model: a model's
cost is seen by hiding it.

## The engine's shaders

`flutter_scene` compiles every shader of its bundle before the first
frame: 88 shaders, the lit materials and every effect among them. In a
browser that holds the page for 0.3 to 0.7 seconds, and over 3 seconds on
a first visit. An app whose scenes draw with a few of them builds a
bundle of those alone, in a hook of its own (the engine reads the app's
tree first; a package's copy never wins):

```dart
// hook/build.dart of the app
import 'package:hooks/hooks.dart';
import 'package:spring_boot_starter_flutter_scene/build_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildSceneShaders(buildInput: input, buildOutput: output);
  });
}
```

```yaml
# pubspec.yaml of the app
dependencies:
  hooks: ^2.0.0
flutter:
  assets:
    - flutter_scene_generated/
    - path: flutter_scene_generated/opengl_es/
      platforms: [web]
```

The default list (`unlitSceneShaders`, six shaders) is for scenes of
unlit and custom unlit (`.fmat`) materials. A scene with lit materials
(a `.glb` model has them) names what it needs, or keeps the engine's
whole bundle by having no hook. A shader missing from the bundle fails
at draw time with no name in the error: look at every scene after
changing the list.

## What a scene costs

Measured on a page of [Dota Passport](https://dotapassport.com) (Chrome,
Apple M5, a release build):

- **The scene is not what costs.** It was about 1% of the page's thread.
  The rest is Flutter drawing the whole page again for every frame of the
  scene: 20% of the thread at 30 frames a second.
- **Isolation halves it.** With the page cross-origin isolated Flutter
  draws in a worker: 9%. The headers are `Cross-Origin-Opener-Policy:
  same-origin` and `Cross-Origin-Embedder-Policy: require-corp`, on the
  host and, for `flutter run`, under `spring.flutter.web.dev-server.headers`.
  `require-corp` forbids cross-origin resources without CORS.
- **A debug build misleads**: several times a release's numbers. Measure
  a release.
- **An animation that never stops is a standing cost.** Fewer frames, a
  still frame and the pause off the screen are what help.

## Things of the engine to know

- **`Component` is two classes.** The engine's `Component` (behaviour on
  a node) and Spring's `@Component()` meet in a file that imports both:
  `import 'package:flutter_scene/scene.dart' show Scene;` (or `hide
  Component`) in the file of a bean.
- **Colours are linear light.** A `Color` of the app is sRGB:
  `color.linear` and `color.linearWithAlpha` (`SceneColor`) are what a
  material takes; given as it is, a colour comes out pale.
- **An additive material leaves no alpha**, so its light does not show
  outside the scene's own surfaces. A glow over the page is alpha
  blending with the brightness as alpha.
- **A pause is not `autoTick`.** The engine's view fails in a debug
  build when its `autoTick` goes from `false` back to `true` (it makes a
  second ticker). The starter's views pause by muting the ticker and
  stopping the scene's clock, so they come back without a jump; a
  `SceneView` of the app's own should pause the same way
  (`TickerMode`), not by its `autoTick`.
- **Per-frame values** are set on a material or a node by a component or
  a listener of the scene's clock (`SceneScope.of(context).elapsed`), not
  by rebuilding widgets.
- **Generated assets are bound to the Flutter that compiled them**:
  `flutter_scene_generated/` is never committed.
- **A test has no GPU**: a `Scene` cannot be made there, so in a widget
  test of the app the engine fails to start (logged once, as a warning)
  and the scene widgets are their placeholders. A test that wants it
  quiet sets `spring.flutter.scene.render=off` or replaces the
  `SceneBackend` bean; `SceneModelImporter` is a bean a test replaces
  too.
