import 'package:spring_boot_dart/spring_boot_dart.dart';

// The settings of the starter that are properties. Each class is the one
// place that names its keys, describes them (the editor metadata is made
// from the fields) and, bound by the Binder, is what the code reads.

/// The app's 3D scenes, `spring.flutter.scene.*`.
@ConfigurationProperties('spring.flutter.scene')
final class SceneProperties {
  /// Settings with these values; the defaults are those of an app without
  /// any property.
  const SceneProperties({
    this.enabled = true,
    this.render = SceneRenderMode.animated,
    this.when,
    this.slow = const SceneSlowProperties(),
    this.maxFrameRate = 30,
    this.pixelRatio,
    this.canvas = SceneCanvas.page,
    this.pauseOffScreen = true,
    this.lightClustering = true,
    this.preload = SceneLoad.lazy,
    this.engineLog = true,
    this.models,
    this.materials,
    this.app = const ApplicationSceneProperties(),
    this.debug = const SceneDebugProperties(),
  });

  /// Whether the app has scenes. With `false` no scene bean exists, the
  /// engine never starts and every scene widget shows its placeholder.
  final bool enabled;

  /// How the scenes draw: `animated`, `still` (one frame, drawn again only
  /// when what it shows changes) or `off` (the widgets show their
  /// placeholders).
  final SceneRenderMode render;

  /// The mode scenes take while a condition holds, by the condition's
  /// name: `touch` (the main pointer is a finger), `slow` (frames too slow
  /// on this device, see [slow]) or one of the app's (a `SceneCondition`
  /// bean). `still` or `off`; the least of [render] and those of the
  /// conditions that hold wins. A condition not named here changes
  /// nothing.
  final Map<String, SceneRenderMode>? when;

  /// What makes frames slow, for `when.slow`.
  final SceneSlowProperties slow;

  /// The most frames a second a scene draws; a widget may ask for fewer.
  /// `0`: as many as the screen shows, as Flutter draws its own frames (in
  /// a browser each of its frames, 60, 120 or 144 a second by the
  /// monitor; elsewhere the display's refresh rate). Each frame of a
  /// scene is what it costs.
  final double maxFrameRate;

  /// The scenes' own pixel ratio, under the device's (`1` on a screen of
  /// `3` draws a ninth of the pixels). Not set: the device's.
  final double? pixelRatio;

  /// Which canvas the scenes are on in a browser: `page` (Flutter draws
  /// each frame of a scene into the page, which it draws again around
  /// it), `layer` (each scene is a canvas of its own under the page, its
  /// frames handed over by the browser, which copies them in Firefox and
  /// WebKit) or `engine` (the engine's own canvas under the page, the
  /// scenes drawn on it where they stand: nothing is handed over or
  /// copied). A view may say otherwise (`SpringSceneView.canvas`), but
  /// for `engine`, which is the whole app's.
  final SceneCanvas canvas;

  /// Whether a scene scrolled off the screen stops drawing.
  final bool pauseOffScreen;

  /// Whether the scenes' lamps (point, spot and area lights) are shaded
  /// through the engine's clustering: the view cut into cells, each with
  /// the lamps that reach it (`Scene.punctualLightClustering`, the
  /// engine's default). Without it every mesh shades the lamps that reach
  /// it, which costs less with a few lamps. The clustering keeps its lamp
  /// lists in textures sized to the lamps in the view: one coming into or
  /// leaving the view (a lamp scrolled out with its card) has the engine
  /// make them all anew, a frame of about 30 ms on an iPhone.
  final bool lightClustering;

  /// When the engine starts: `eager` with the splash, `lazy` when the
  /// first scene shows. A model has its own (`models.<name>.preload`).
  final SceneLoad preload;

  /// Whether the engine's own messages (it writes them with Flutter's
  /// `debugPrint`) are records of the application's log, under the logger
  /// `flutter_scene`: with a time and a level, set by
  /// `logging.level.flutter_scene`.
  final bool engineLog;

  /// The models by name, `spring.flutter.scene.models.<name>.*`.
  final Map<String, SceneModelProperties>? models;

  /// The materials by name, `spring.flutter.scene.materials.<name>.*`.
  final Map<String, SceneMaterialProperties>? materials;

  /// The scene of the whole application.
  final ApplicationSceneProperties app;

  /// The scenes' tab of the debug panel.
  final SceneDebugProperties debug;
}

/// When the scenes are slow, `spring.flutter.scene.slow.*`: for the
/// condition `slow` of `spring.flutter.scene.when`. It is decided by the
/// scenes' own frames while the first ones load, their placeholders
/// showing, so they show in the mode they keep; it never switches a scene
/// off in front of the user.
final class SceneSlowProperties {
  /// Settings with these values.
  const SceneSlowProperties({
    this.frameTime = const Duration(milliseconds: 16),
    this.after = const Duration(seconds: 3),
    this.probe = 24,
  });

  /// The time of a frame: a beat of the scenes (what drawing every moving
  /// scene once cost the page's thread, the middle one of those measured)
  /// taking more than half of it is slow.
  final Duration frameTime;

  /// How long beats are slow, on end, after the scenes showed, before the
  /// condition holds; it holds at the next moment no scene moves, and then
  /// for the rest of the run.
  final Duration after;

  /// How many frames of the first scenes are measured before they show,
  /// after the first few, on which the engine builds its programs.
  final int probe;
}

/// How scenes draw, `spring.flutter.scene.render`.
///
/// The order is from most to least: a condition asks for a later one.
enum SceneRenderMode {
  /// Up to `max-frame-rate` frames a second.
  animated,

  /// One frame that stands; drawn again when what it shows changes (its
  /// size, a property of a widget in it).
  still,

  /// No scene: the widgets show their placeholders.
  off,
}

/// Which canvas the scenes are on in a browser,
/// `spring.flutter.scene.canvas`. Elsewhere Flutter draws them.
enum SceneCanvas {
  /// The page's: Flutter draws a frame of a scene with the page around it.
  page,

  /// A canvas of each scene's own under the page; the browser hands each
  /// frame over to it (Chrome gives it away, Firefox reads it back from
  /// the GPU, WebKit copies it).
  layer,

  /// The engine's canvas itself, under the page: every scene is drawn on
  /// it where it stands on the screen, nothing handed over. A scene shows
  /// inside the first scene of the page and over what is drawn under that
  /// one.
  engine,
}

/// When something of a scene is loaded.
enum SceneLoad {
  /// While the splash shows: the app appears with it ready.
  eager,

  /// When it is first needed.
  lazy,
}

/// A model of `spring.flutter.scene.models.<name>`.
final class SceneModelProperties {
  /// Settings with these values.
  const SceneModelProperties({this.source, this.preload});

  /// Where the model's `.glb` file is: an asset of the app
  /// (`asset:assets/models/hero.glb`, listed under `flutter: assets:`) or
  /// an address (`https://cdn.example.com/hero.glb`; in a browser its
  /// server must allow the page's origin). Not a file of `lib/resources/`:
  /// those are embedded into the app's code, a megabyte at most.
  final String? source;

  /// When it is loaded: `eager` with the splash, `lazy` when a scene first
  /// shows it. Not set: as `spring.flutter.scene.preload`.
  final SceneLoad? preload;
}

/// A material of `spring.flutter.scene.materials.<name>`.
final class SceneMaterialProperties {
  /// Settings with these values.
  const SceneMaterialProperties({this.source, this.preload});

  /// The material's `.fmat` file, by its path from the app's root
  /// (`assets/materials/glass.fmat`). The app's build hook compiles it
  /// (`buildSceneAssets`) and fails when a material named here is not
  /// there; at run time the compiled material is loaded, not this file.
  final String? source;

  /// When its programs are loaded: `eager` while the splash shows, `lazy`
  /// when a scene first shows it. Not set: as
  /// `spring.flutter.scene.preload`.
  final SceneLoad? preload;
}

/// The scene of the whole application, `spring.flutter.scene.app.*`.
final class ApplicationSceneProperties {
  /// Settings with these values; no such scene by default.
  const ApplicationSceneProperties({
    this.enabled = false,
    this.placement = ApplicationScenePlacement.background,
    this.camera = const SceneCameraProperties(),
  });

  /// Whether the app has one scene of its own (the `applicationScene`
  /// bean), made with the splash.
  final bool enabled;

  /// Where it shows: `background` under every screen, `none` only where
  /// the app puts a `SpringSceneView`.
  final ApplicationScenePlacement placement;

  /// The camera it is seen through where a view gives none.
  final SceneCameraProperties camera;
}

/// Where the application's scene shows.
enum ApplicationScenePlacement {
  /// Under every screen of the app.
  background,

  /// Only in the `SpringSceneView` widgets of the app.
  none,
}

/// A camera, `spring.flutter.scene.app.camera.*`.
final class SceneCameraProperties {
  /// Settings with these values.
  const SceneCameraProperties({
    this.position = const [0, 0, -5],
    this.target = const [0, 0, 0],
    this.fov = 45,
  });

  /// Where the camera is: `x, y, z`.
  final List<double> position;

  /// What it looks at: `x, y, z`.
  final List<double> target;

  /// Its vertical field of view, in degrees.
  final double fov;
}

/// The scenes' tab of the debug panel, `spring.flutter.scene.debug.*`.
final class SceneDebugProperties {
  /// Settings with these values.
  const SceneDebugProperties({this.enabled});

  /// Whether the app has the tab: `true` in every build, `false` in none
  /// (the build leaves its code out), not set in debug and profile builds
  /// only (a release build compiles it away).
  final bool? enabled;
}
