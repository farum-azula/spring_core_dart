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
    this.maxFrameRate = 30,
    this.pixelRatio,
    this.pauseOffScreen = true,
    this.preload = SceneLoad.lazy,
    this.engineLog = true,
    this.models,
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

  /// The most frames a second a scene draws; a widget may ask for fewer.
  /// Every frame of a scene has Flutter draw the page again, so this is
  /// what a scene costs.
  final double maxFrameRate;

  /// The scenes' own pixel ratio, under the device's (`1` on a screen of
  /// `3` draws a ninth of the pixels). Not set: the device's.
  final double? pixelRatio;

  /// Whether a scene scrolled off the screen stops drawing.
  final bool pauseOffScreen;

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

  /// The scene of the whole application.
  final ApplicationSceneProperties app;

  /// The scenes' tab of the debug panel.
  final SceneDebugProperties debug;
}

/// How scenes draw, `spring.flutter.scene.render`.
enum SceneRenderMode {
  /// Up to `max-frame-rate` frames a second.
  animated,

  /// One frame that stands; drawn again when what it shows changes (its
  /// size, a property of a widget in it).
  still,

  /// No scene: the widgets show their placeholders.
  off,
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
