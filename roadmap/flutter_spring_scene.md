# spring_boot_starter_flutter_scene (first version built, released with the next version)

On `flutter_scene`: an allowed exception to the dependency policy, only in
this starter. Part of the [Flutter plan](spring_boot_starter_flutter.md).

The first version is in the repository (`spring_boot_starter_flutter_scene`,
its README is the reference; `example/scene` shows it). The owner decided
to release it: it goes to pub.dev with the family's next version (a new
package's first version is published by a person, `tool/publish.dart`);
until then an app takes it by git. It grew out of a prototype in the Dota
Passport site (`~/dev/dota2passport`, `app/packages/neon_scene`): a neon
frame with a hologram glass around ordinary widgets, on `flutter_scene`
0.24.3 as published. Everything under
[What the prototype showed](#what-the-prototype-showed) was measured there
in November 2026.

## Built (the first version, November 2026)

What went into it was decided by the owner: the core, the models of the
properties, the application's scene and the debug tab; the neon widgets
stay outside (they are a look: a theme's or an app's).

| Part | What is there |
|---|---|
| Properties | `spring.flutter.scene.*`: `enabled`, `render` (`animated`, `still`, `off`), `max-frame-rate`, `pixel-ratio`, `pause-off-screen`, `preload`, `engine-log`, `models.<name>` (`source`, `preload`), `app.*` (`enabled`, `placement`, `camera`), `debug.enabled` |
| The engine | `SceneEngine`: one start for the app, with the splash or when the first scene shows, a failure kept and not thrown; `SceneBackend` and `SceneModelImporter` are beans an app or a test replaces |
| Whether scenes draw | `SceneAvailability`; with `enabled: false` no scene bean exists and the build leaves the module out (decision 9) |
| Widgets | `SpringSceneView` (declarative, or the application's scene), `SceneBackdrop` (a scene behind a widget, `SceneSurface`), `SpringSceneModel`; placeholders where scenes do not draw; the frame ceiling, the still frame, the pause off the screen; a scene is shown only whole (its loads done, its programs compiled) |
| Models | `SceneModels`, `SceneModelHandle`: an asset or an address (`RemoteModelResource`: the framework's `UrlResource` does not read in a browser), loaded once, eager with the splash or lazy, a clone per use, kept when they leave the screen |
| The application's scene | `ApplicationScene`, `SceneCustomizer` beans, under every screen (`ApplicationSceneBackground`) or in `SpringSceneView()` |
| The start | `SceneEvent`s with message codes, `SceneStatus` (the current step in words), `SceneStart` (a `SplashTask`: the splash waits and its loader moves) |
| The debug tab | `SceneDebugSection`: the engine, every scene and model by name; a module of its own, out of release builds |
| The engine's log | `SceneEngineLog`: the engine's `debugPrint` lines as records of the logger `flutter_scene`, with a level (asked for by the owner) |
| The shaders | `buildSceneShaders` for an app's `hook/build.dart` (`build_hooks.dart`) |

Seen drawing in a browser (Chrome, a release build of `example/scene`):
the three kinds of scene, a model from the properties and from an
address, the tab, the still frame, scenes turned off. And on macOS
(Impeller, Metal): the showcase's device test
(`integration_test/scenes_test.dart`) finds the engine started, the model
loaded and every scene drawing frames with draw calls. Not run: iOS,
Android, Windows, Linux (the showcase is set up for them), a phone.

Found while building it:

- **A still frame was drawn before its model came**, and nothing drew it
  again: the engine repaints a view that does not tick only when its
  widget is rebuilt. So every view of the starter is gated on its loads
  (the engine then waits for the models of its scene widgets and shows
  the scene whole), and `SpringSceneView.repaintOf(context)` asks for a
  frame after a change without a rebuild.
- **The warm-up does not take every program out of the first frame.**
  With `warmUp` the browser's first frame built none (before: four, and
  32 ms), but on macOS, in a debug run, the engine still logged
  "pipeline build took 173ms mid-frame" for the model's material. To
  look into: which targets the warm-up compiles for.
- **The engine's view cannot be told to tick again.** Its state is a
  `SingleTickerProviderStateMixin` and makes a new ticker each time
  `autoTick` goes back to `true`: Flutter refuses the second one (an
  assertion, so a debug build shows the red box; found by the owner,
  turning animations off and on in the showcase). The starter never
  changes `autoTick` after a view is made: a pause (less motion, off the
  screen) mutes the view's ticker (`TickerMode`) and stops the clock the
  engine steps by (`SceneClock`), so a scene goes on from where it stood
  and does not jump by the time of the pause. The time of the view
  itself (`SceneScope.elapsed`, a shader's phase) still includes the
  pause: it is the ticker's. To report upstream.
- **`Component` is two classes**: the engine's and Spring's `@Component()`
  meet in a file that imports both. The README says to import the engine
  with `show` or `hide` there. A rename is not ours to make.
- **A test has no GPU.** A `Scene` cannot be made in `flutter test`, so the
  tests cover the beans, the events and the widgets as placeholders, and
  a scene that draws is looked at in the showcase.
- **The engine does not give a geometry's vertex count**, so the tab says
  what a model is made of (nodes, meshes, draw calls, materials) and
  reads vertices from a frame's counters only.

## Later

Not in the first version, in the order they are likely to come:

- **The generator's part**: the app's `hook/build.dart`, the asset
  entries and the shader list (`spring.flutter.scene.shaders`) written
  by the build, so an app writes none of it; `resources:` models
  converted at build time; Flutter GPU turned on per native platform.
- **The theme section** (`scene:`, `context.theme.scene`) with typed
  keys, once the starter has widgets with a look of their own (decision 1).
- **A line of the splash for the status** (`splash.status`): today a
  loader of the app shows `SceneStatus` itself.
- **Stereotypes** (`@SceneMaterial`, `@SceneModel`, `@SceneComponent`),
  `@OnFrame`, scene state in `@Signal` fields.
- **A cheaper debug run by default** (a lower frame ceiling or a still
  frame in a debug build): today the app's profile file sets it.
- The engine's code out of a build with scenes off: the module is left
  out, but the widgets still name the engine, so the compiler keeps it.
- The environment of the application's scene from properties; a poster
  of a model as its placeholder; the cost of a model measured by the tab
  itself (hidden for a second, compared).

## What the starter is for

3D scenes with the rest of the app's tools: models, materials and
environment maps as resources, the look from the theme, quality and frame
rate from properties and profiles, `@OnFrame` methods on beans driven by the
scene's clock, and scene state in `@Signal` fields like any other state.

An app that uses it writes no hook, no shader list, no loading code and no
"can this device draw it" check.

## Decided (the owner, November 2026)

1. **Its own section of the theme.** The look of the scene widgets is set
   in the theme, apart from the rest: colours, glow, glass, tilt, motion.
2. **It can be turned off entirely.** The widgets stay in the app's code
   and become empty proxies: they show their child (and their placeholder)
   and draw no scene. Nothing of the engine starts.
3. **A ceiling on frames, or a still frame.** A scene must not draw more
   than it is asked to, above all in a debug build, where a frame costs
   several times more. Either a top frame rate, or one frame that stands
   still when drawing is off. The exact shape is open: see
   [Rendering modes](#rendering-modes-open).
4. **Models from properties.** A model is named in the properties with its
   source, injected like any other resource, and loaded and drawn ahead of
   time by the starter, so a screen shows it at once.
5. **A debug panel of its own**, with detailed measurements by name: what
   each model costs (resources, frames a second and the rest). See
   [The scene debug panel](#the-scene-debug-panel).
6. **Both ways to a scene.** A scene of the whole application, turned on
   once in the starter, and a scene declared in one place, by a widget.
   See [Two ways to a scene](#two-ways-to-a-scene).
7. **Stereotypes, to think through.** Materials, models and the like as
   beans of their own kinds, injected where they are used. They are
   singletons and prototypes already, so they should lie well on Spring.
   See [Stereotypes](#stereotypes-to-think-through).
8. **The start tells what it is doing.** The starter publishes application
   events of its own, detailed: what is being loaded or compiled right
   now. With the starter in the app, the loader waits for the scenes to be
   ready as it waits for the rest of the start, and can say in words what
   is going on (shaders are compiling, a model is loading). See
   [Start and loading](#start-and-loading-events-and-the-loader).
9. **With scenes off, nothing is injected.** No scene bean exists then.
   Code that needs one asks through what the framework already has for a
   bean that may be absent (`ObjectProvider<T>`, a nullable parameter),
   checks, and handles it.

## Properties (sketch)

The starter's own keys, under `spring.flutter.scene.*`:

```yaml
spring:
  flutter:
    scene:
      enabled: true            # false: the widgets are proxies, the engine never starts
      render: animated         # animated | still | off  (open, see below)
      max-frame-rate: 30       # the ceiling of every scene; a widget may ask for less
      pixel-ratio: auto        # auto | a number: the scene's own, under the device's
      pause-off-screen: true   # no frames while the widget is scrolled away
      preload: lazy            # eager: with the splash; lazy: when the first scene shows
      shaders: [StandardFragment]   # engine shaders beyond what the starter's widgets use
      models:
        hero:
          source: resources:models/hero.glb
          preload: eager       # eager | lazy
          warm-up: true        # compile its pipelines before it is shown
        shop:
          source: https://cdn.example.com/models/shop.glb
```

Per platform as everywhere: a value for phones goes into the platform
profile file (`application-ios.properties`), a key only the web reads gets
the segment (`spring.flutter.scene.web.*`).

The look, in the theme file, a section of its own (`scene`), read as
`context.theme.scene`:

```yaml
scene:
  frames:
    neon:
      color: $colors.primary
      accent: $colors.secondary
      surface: $colors.surface-container
      cut: 18
      thickness: 0.8
      halo: 48
      glass: { strength: 0.022, opacity: 0.92, inset: 3 }
      edge: { brightness: 0.45 }          # the glass's own edge, in the accent colour
      tilt: 0.7deg
      power: { ignition: 900ms, hum: 0.05 }
```

Motion follows the theme that already exists: with less motion asked by the
system (`MediaQuery.disableAnimations`) a scene stands still, as
`context.theme.motion` does for durations.

## Rendering modes (open)

What the owner asked for is one of these or both; to be decided when the
starter is built.

| Mode | What it does | When |
|---|---|---|
| `animated` | The scene draws up to `max-frame-rate` | Release builds |
| `still` | One frame is drawn and kept; it is drawn again only when what it shows changes (size, theme, a property of the widget) | Debug builds, weak devices, less motion |
| `off` | No scene; the widget is a proxy over its placeholder | Devices that cannot draw it, an app that turns it off |

Options for the debug default, none chosen yet:

- A lower `max-frame-rate` in a debug build (a default by build mode), so
  hot reload stays quick.
- `render: still` in a debug build unless the app sets it.
- Leave it to the app's own profile file.

The engine supports all three as published: `SceneView.maxFrameRate`, and
`autoTick: false` draws one frame and repaints on demand (the prototype
uses it for less motion).

## Two ways to a scene

The engine has both, and the same scene widgets work under either:
`SceneView(scene, children: ...)` draws a `Scene` the application owns, and
`SceneView.declarative(children: ...)` owns its scene and frees it with the
widget. `SceneSubtree` hangs widgets under a node of an owned scene, and
`SceneNodeHost` puts an owned node into a declarative tree.

**The application's scene.** One `Scene` for the app, a singleton bean the
starter makes when it is turned on:

```yaml
spring:
  flutter:
    scene:
      app:
        enabled: true
        placement: background    # background: under every screen, as the theme's background is
                                 # none: only where the app puts a view of it
        environment: resources:environments/studio.hdr
        camera: { position: [0, 1.5, -4], target: [0, 1, 0], fov: 45deg }
```

- Beans fill it: models and materials are injected (below), a
  `SceneCustomizer` bean changes it at start, `@OnFrame` methods move it.
- A screen adds to it with `SceneSubtree` and takes its part away when it
  leaves; a scene of one screen is the same bean in the route's scope.
- Several views may look at it with cameras of their own
  (`SpringSceneView()` with no children shows the application's scene).
- It is where the cost is highest: a scene under every screen draws the
  whole page again for each of its frames
  ([what the prototype showed](#what-the-prototype-showed)). The still
  frame, the frame ceiling and the pause rules matter most here.

**A scene in one place.** `SpringSceneView.declarative(children: [...])`: a
scene that lives with its widget, as the prototype's neon frame does.
Nothing global is needed for it but the engine's start and the properties.

Both read the same properties, the same theme section and the same
switch; both are proxies when scenes are off.

## Start and loading: events and the loader

The scenes are a stage of the app's start, not something a screen finds
out later.

- **The loader waits.** With the starter in the app the splash stays until
  the scenes are ready too: the engine started, the shaders compiled, the
  eager models loaded and warmed up. Their steps count in the start's
  progress (`StartupProgress`: `done`, `total`), so a loader with a
  progress phase moves through them.
- **Every step is an application event**, heard like any other
  (`@EventListener`), and detailed enough to be told in words:

  | Event (sketch) | Carries |
  |---|---|
  | `SceneEngineStartingEvent` / `SceneEngineReadyEvent` | the backend (WebGL2, Impeller), the time it took |
  | `SceneShadersCompilingEvent` / `SceneShadersCompiledEvent` | which bundle, how many shaders, the time |
  | `SceneModelLoadingEvent` | the model's name and source, its place in the queue (3 of 5), bytes done and total |
  | `SceneModelLoadedEvent` | the name, the time, what it holds (meshes, textures, bytes) |
  | `SceneMaterialLoadingEvent` / `SceneMaterialLoadedEvent` | the material's source |
  | `SceneWarmingUpEvent` / `SceneWarmedUpEvent` | whose pipelines, how many, the time |
  | `SceneReadyEvent` | everything eager is ready; the total time |
  | `SceneFailedEvent` | the step, the name, the error |
  | `SceneUnavailableEvent` | why scenes do not draw here: turned off, no WebGL2, the engine failed |

- **In words.** Each event has a message key with its arguments
  (`scene.loading.shaders`, `scene.loading.model` with the name and the
  count), in the starter's own `messages.properties`, so a loader shows
  "Compiling shaders" or "Loading hero, 3 of 5" in the app's language
  and an app rewords it like any text. The splash gets a line for it
  (`splash.status: true`, say).
- **Later loads say the same.** A lazy model publishes the same events when
  it is first needed, so a loader of one screen (`ThemeLoader`,
  `ThemeSkeleton`) follows them too.
- **A failure is not a failed start.** The app starts, the scenes are
  proxies, and `SceneUnavailableEvent` says why once.
- The same events feed the log and the
  [scene debug panel](#the-scene-debug-panel): its times of loading and
  warm-up are theirs.

## Widgets as proxies

Every scene widget of the starter has two sides: what it draws in the
scene, and what stands in when it does not draw.

- With `enabled: false`, `render: off`, no WebGL2 on the web, or a failed
  start of the engine: the widget builds its child over its placeholder
  and nothing else. The app's code does not change and has no branch.
- The decision is one bean (a `SceneAvailability`, say), not a check in
  each widget: it holds the property, what the device can do and whether
  the engine started. It is also where "cannot run here" is reported once.
- Turned off by the build, the engine should not be in the app at all:
  `AutoConfigurationBuild` removes the module and what only it reaches
  (as the debug panel is removed today). To check: whether the proxy
  widgets can stay in a library that does not import `flutter_scene`, so
  the compiler really drops it. The engine's code is 0.33 MB of the app's
  WebAssembly; its assets (5.8 MB in the build output, most never
  downloaded) come from `flutter_scene`'s own `pubspec.yaml` and stay as
  long as the package is a dependency.

## Models, materials and other resources

- **Named in properties** (`spring.flutter.scene.models.<name>`), with a
  source: `resources:` (the app's or a package's), an asset, or a URL.
- **Injected** like other resources: `@Value('resources:models/hero.glb')`
  for a source, or the loaded model by its name (a `SceneModelRef` bean per
  entry, a typed key generated from the configuration as for the theme:
  `context.sceneModels.hero`).
- **Built by the generator's build, not by a hook the app writes.**
  `flutter_scene` converts `.glb` / `.fscene` (`buildScenes`), `.fmat`
  materials (`buildMaterials`) and textures (`buildTextures`) in a
  `hook/build.dart`, into `flutter_scene_generated/` of the package that
  owns them. The starter should run these for `lib/resources/` and write
  the asset entries.
- **Loaded ahead**: `preload: eager` loads with the splash
  ([loaders and the splash](spring_boot_starter_flutter.md#loaders-and-the-splash-063-the-owner-november-2026)),
  `lazy` when the first scene with the model shows. The engine has the
  parts: `ResourceGroup` (progress, `ready`), `SceneView.loading`,
  `Scene.preload`.
- **Drawn ahead** (`warm-up`): the pipelines of a model's materials are
  compiled before it is shown (`SceneView.warmUp`, `Scene.warmUp`, which
  yields to the event loop between compiles). Without it the engine logs
  "pipeline build took 50ms mid-frame" on the first frame that draws a
  material.
- **A poster** (to think through): a still of the model rendered once and
  kept (at build time or on first run) as the placeholder, so the proxy
  and the loading state show the model, not an empty box.

## Stereotypes (to think through)

What a scene is made of is costly to make, shared, and has a lifetime:
that is a bean. The engine already splits each kind the way Spring's
scopes do: a model is imported once into a template and every use mounts a
clone of it (geometry, textures and materials stay shared on the GPU); a
material is one object for everything that draws with it, or one per use
when its values differ.

A sketch, nothing decided:

```dart
/// One material for the app: every mesh that draws with it shares its values.
@SceneMaterial('resources:materials/hologram.fmat')
class HologramMaterial {
  @MaterialParam() Color tint = const Color(0xFF22E6FF);   // linear light is the starter's work
  @MaterialParam() double strength = 0.022;
  @MaterialParam.time() late double time;                  // fed by the scene's clock
}

/// A model: imported once, a clone for each injection.
@SceneModel('resources:models/hero.glb')
@Scope('prototype')
class Hero {
  @ScenePart('Armature/Head') late Node head;
  @SceneAnimation('Run') late AnimationClip run;
}

/// Behaviour on a node, with beans of the app.
@SceneComponent()
class FollowsBasket(this.basket) {
  final Basket basket;

  @OnFrame()
  void turn(Node node, Duration elapsed) { ... }
}
```

| Kind | Singleton | Prototype |
|---|---|---|
| Material | One set of values for all that use it | Values of its own per use; the program on the GPU is shared either way |
| Model | The imported template | A clone per injection: its own transform, animation state, material variant |
| Geometry | Built once | Rarely needed |
| Environment, sky | One | — |
| Component (behaviour) | State shared by its nodes | State per node (the engine's `cloneFor`) |

What it would give:

- **Typed values instead of names.** `material.parameters.setFloat('strength', ...)`
  becomes a field; the generator reads the `.fmat`'s parameters and
  writes the setters, and a wrong name is a build error.
- **Injection everywhere**: into widgets (`context.basket`,
  `SpringStatelessWidget<(HologramMaterial,)>`), into the application's
  scene, into other scene beans, by constructor.
- **Lifetime from the scope**: the app, a route (freed on leaving the
  screen), a widget; `@PreDestroy` frees what is on the GPU; `@Lazy` loads
  on first use, eager with the splash.
- **The same thing two ways**: a model named in the properties is this
  bean without a class, taken by its name (`@Qualifier('hero')`).
- **Tests**: `BeanOverride` puts a plain stand-in for a model or material.

Decided (the owner, November 2026): with scenes off these beans do not
exist and nothing is injected. A widget of the starter is a proxy by
itself; the app's own code that wants a material or a model takes an
`ObjectProvider<HologramMaterial>` (or a nullable parameter), checks, and
does what it does without scenes.

To think through before any of it:

- Loading is asynchronous. An eager bean is ready before the splash
  leaves ([Start and loading](#start-and-loading-events-and-the-loader));
  a lazy one that is injected before it is loaded needs a rule: a handle
  with a state (`loading`, `ready`, `failed`), as the widgets have.
- A lost GPU context (the web reports it) takes every resource with it:
  singletons must be made again, a scope that can be refreshed.
- Hot reload of a `.fmat` or a model against a bean kept in a field.
- Whether the kinds are stereotypes (`@SceneMaterial` on a class) or
  `@Bean` methods in a configuration class are enough; the first reads
  better when a material has typed values, the second needs no new
  annotation.

## The scene debug panel

A panel for whoever builds the app, apart from the frame meter: every
scene and every model **by its name** (the key of
`spring.flutter.scene.models.<name>`, a widget's own name for what is
built in code), with what it costs.

It comes the framework's way: a module of its own that the build leaves
out of a release (`spring.flutter.scene.debug.enabled`, as
`spring.flutter.debug.frame-meter.enabled`), opened by an action with keys
of its own (`scene.debug`), and shown as a `DebugPanelSection` of the
[debug panel](../docs/configuration.md#the-debug-panel) where that panel
is in the build. Whether it is only a tab or also a window over the app
is open.

What it shows, per scene (a `SceneView`):

| Measure | From |
|---|---|
| Frames a second, drawn and asked for (`max-frame-rate`), the mode (`animated`, `still`, `off`) and why (property, less motion, off screen) | the starter's view |
| Time of a frame on the page's thread: the scene's own part and Flutter's (build, paint, drawing the page again) | the scheduler's frame timings, the scene's painter timed |
| Draw calls, instances, vertices, culled items, pipeline binds, pipelines built in the frame (not zero in a steady state is a hitch) | the engine's `Scene.renderStats` (`RenderCounters`, per view and per pass) |
| The passes of the frame, with the time each took to encode on the page's thread and its counters; time on the GPU is not there yet (the engine waits for timestamp queries, flutter/flutter#190404) | the engine's `RenderPassStats` (`cpuMicros`, `gpuMicros` still null) |
| The surface: size in pixels, pixel ratio | the view |
| Whether the page is cross-origin isolated (the web), so Flutter draws in a worker | `crossOriginIsolated` |

Per model, by name:

| Measure | From |
|---|---|
| Source, size of the file, time to download, to decode and to warm up | the starter's loading |
| Meshes, vertices and triangles, materials, textures (count, size, bytes) | a walk of the model's nodes |
| Memory: geometry and textures of this model; the engine's total by kind (textures, render targets, templates) | the walk; the engine's `MemoryReport` |
| Draw calls and vertices it adds to a frame | the walk, against the frame's counters |
| Pipelines it built and when (at warm-up or in a frame) | the engine's log of pipeline builds |
| **What it costs a frame**: the frame time with the model hidden for a second, against with it shown | a switch per model in the panel |
| State: loading, ready, failed (with the error), shown as a proxy | The application's scene | A `Scene` bean made when `spring.flutter.scene.app.enabled` is set, placed under every screen or shown by views; `SceneCustomizer` beans change it |
| Events | The steps of the start and of every later load as application events with message keys; their steps in `StartupProgress`, so the splash waits and can say what is going on |
| Stereotypes (to think through) | `@SceneMaterial`, `@SceneModel`, `@SceneComponent`: scene resources as singleton and prototype beans, with typed values and injection |
| `SceneModels` |

And for the app: the engine's start (time, the shaders compiled and how
long the page was held), what was downloaded for scenes, the list of
engine shaders in the bundle against those used.

What the engine does not give: time on the GPU at all (see the passes
above), and nothing per model, on the GPU or on the page's thread. So the cost of one model is measured by taking it out
(the switch above), not read from a counter. The engine has an overlay of
its own (`PerformanceOverlay3D`) for frames and render counters; it knows
nothing of names.

The measurements of [What the prototype showed](#what-the-prototype-showed)
were made by hand with a browser's profiler; the panel should make each of
them one look: the page held at start, the thread's load, the part that is
Flutter's and not the scene's.

## The engine's shaders

`flutter_scene` compiles every shader of its engine bundle before the first
frame: 88 shaders, 2 MB of code. On the web that held the page 0.3 to 0.7 s,
and 3.3 s on a browser's first visit. A scene of unlit and custom materials
draws with six of them.

- The bundle can be replaced only by the **app's own** generated tree: the
  engine reads the app's tree first, then packages' in alphabetical order,
  so a starter's copy never wins over `flutter_scene`'s.
- So the app needs a `hook/build.dart` of its own, a `hooks` dependency and
  the asset entries. The prototype's hook is one call
  (`buildNeonSceneShaders`); the starter's build should write all three.
- The list of shaders comes from what the app's scenes use: the starter's
  widgets declare theirs, the app adds with `spring.flutter.scene.shaders`.
  A missing shader is a null error at draw time with no name in it, so the
  starter must check the list at build time or at start.
- Upstream would be better: a way to name the shaders, or compile on first
  use. To raise with the package's author.

## What the prototype showed

Chrome on an Apple M5, the match page of Dota Passport, a release build
(`flutter build web --release --wasm`) served compressed.

| What | Number |
|---|---|
| The app's WebAssembly | +0.33 MB (2.90 → 3.23 MB), about 110 kB compressed |
| Downloaded for a scene, with the engine's whole bundle | 263 kB compressed |
| The same with six shaders | 71 kB (two lookup tables of the lit materials, 57 kB, are loaded even when nothing is lit) |
| The page held while shaders compile, whole bundle | 0.3–0.7 s; 3.3 s on a first visit |
| The same with six shaders | under 0.1 s; about 0.85 s on a first visit, part of it Flutter's own shaders |
| The page's thread with the scene on screen, 30 frames a second | 20% |
| The same with the page cross-origin isolated | 9% |
| A page without a scene (the home page) | 0% |
| A debug build (`flutter run`) | 95% of the thread, 21 frames a second, 40 ms a frame |

What follows from it:

- **The scene is not what costs.** It was about 1% of the thread. The rest
  is Flutter drawing the whole page again for every frame of the scene.
  Fewer meshes, no bloom, no multi-sampling and a `RepaintBoundary` changed
  nothing measurable. What helps: fewer frames, a still frame, and
  isolation.
- **Isolation halves it.** With `Cross-Origin-Opener-Policy: same-origin`
  and `Cross-Origin-Embedder-Policy: require-corp` Flutter draws in a
  worker. `require-corp` and not `credentialless`: Safari has no
  `credentialless`, and phones are where it matters. It forbids
  cross-origin resources without CORS, so the starter's docs must say what
  breaks (widgets in frames; Turnstile to be checked). The headers belong
  to the web keys the Flutter starter already writes for a page.
- **A debug build misleads.** Its numbers are several times a release's:
  the docs must say to measure a release, and the debug default must be
  cheap (decision 3).
- **An animation that never stops is a standing cost.** A frame around a
  header drew 30 times a second for as long as the page was open. The
  starter needs: `pause-off-screen`, a still frame when nothing moves, and
  full rate only while something does (a pointer over it, the start).

Things of the engine an app trips over, for the starter to hide:

- Colours are linear light: an sRGB colour of the theme must be converted
  (the prototype's `SceneLight`), or the neon comes out white.
- An additive material leaves no alpha, so its light does not show outside
  the scene's own surfaces. A glow over the page is alpha blending with the
  brightness as alpha.
- `GetTime()` is not available in an unlit `.fmat`; time is a parameter fed
  from the scene's clock (`SceneScope.elapsed`).
- Per-frame values are set on the material in a listener of the clock, not
  by rebuilding widgets.
- The scene's clock starts when the scene does, also under the splash: an
  effect "at start" has passed by the time the page shows.
- A changed `.fmat` is picked up by a hot restart, with no new
  `flutter run`; right after it the scene can throw one null error in
  paint, then recovers.
- Generated assets are bound to the Flutter engine that compiled them:
  never committed, `flutter_scene_generated/` carries its own `.gitignore`.
- `flutter_scene` needs Flutter 3.47 or newer and compiles shaders with the
  SDK's `impellerc` in a build hook.

## Not checked yet

- Native platforms other than macOS. The showcase draws on macOS (its
  device test); iOS, Android, Windows and Linux are set up in it (Flutter
  GPU turned on in each platform's file, by hand: the generator could
  write that) and were not run.
- Phones: frames per second, heat, battery. The web views of apps
  (Telegram).
- CI with the hooks (the app's and the engine's).
- Several scenes on one page, and whether they can share one surface.
- A scene outside Flutter's canvas (the engine's WebGL canvas as an element
  of the page, composited by the browser): it would take away the redraw of
  the page per frame, and is not offered by the package.

## Parts (sketch)

| Part | What it is |
|---|---|
| `SceneProperties` | `spring.flutter.scene.*` as `@ConfigurationProperties` |
| `SceneAvailability` | Whether scenes draw here: the property, the device, the engine's start |
| `SceneEngine` | One start of the engine for the app (`Scene.initializeStaticResources`), eager or lazy, with its failure kept |
| The application's scene | A `Scene` bean made when `spring.flutter.scene.app.enabled` is set, placed under every screen or shown by views; `SceneCustomizer` beans change it |
| Events | The steps of the start and of every later load as application events with message keys; their steps in `StartupProgress`, so the splash waits and can say what is going on |
| Stereotypes (to think through) | `@SceneMaterial`, `@SceneModel`, `@SceneComponent`: scene resources as singleton and prototype beans, with typed values and injection |
| `SceneModels` | The models of the properties: loading, progress, warm-up, by name |
| `SpringSceneView` | `SceneView.declarative` with the properties applied: rate, pixel ratio, still frame, pause off screen, the placeholder |
| Theme: `scene` | `context.theme.scene`, typed keys generated as for the rest of the theme |
| Scene debug panel | A module of its own, out of release builds: every scene and model by name with frames, frame time, counters, memory, loading and the cost of each model |
| `@OnFrame` | A bean's method called on each frame of a scene, with the time passed |
| Generator | The app's hook, the asset entries, the shader list, resources into `flutter_scene_generated/`, the isolation headers, Flutter GPU on native |
| Widgets | `NeonFrame` and what it is made of (`NeonOutline`, `HologramPanel`, `FrameOutline`, `NeonPower`) as the first ones, each a proxy when scenes are off |
