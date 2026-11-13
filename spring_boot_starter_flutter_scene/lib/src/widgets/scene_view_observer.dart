import 'package:flutter_scene/scene.dart';

/// Hears of every scene view of the starter while it is on the screen:
/// what the scenes' debug panel measures by. Without such a bean (a
/// release build) nothing is measured.
abstract interface class SceneViewObserver {
  /// A view called [name] began to draw [scene]; the answer is told of
  /// its frames until it is closed.
  SceneViewMeasure opened(String name, SceneViewState state);
}

/// What an observer keeps of one view.
abstract interface class SceneViewMeasure {
  /// The view drew a frame, [delta] after its last.
  void frame(Duration delta);

  /// What the view shows changed (its mode, its frame rate, its scene).
  void changed(SceneViewState state);

  /// The view left the screen.
  void closed();
}

/// What a scene view shows now, for a [SceneViewObserver].
final class SceneViewState {
  /// The state of a view.
  const SceneViewState({
    required this.scene,
    required this.animated,
    required this.frameRate,
    required this.pixelRatio,
    this.paused,
  });

  /// The engine's scene the view draws; `null` for a view that owns its
  /// scene and has not made it yet.
  final Scene? scene;

  /// Whether the view draws frames one after another, or one that stands.
  final bool animated;

  /// The frames a second it may draw.
  final double frameRate;

  /// Its own pixel ratio, `null` for the device's.
  final double? pixelRatio;

  /// Why it stands still though the app asks for motion: `still`
  /// (the properties), `motion` (the system asks for less), `off-screen`.
  final String? paused;
}
