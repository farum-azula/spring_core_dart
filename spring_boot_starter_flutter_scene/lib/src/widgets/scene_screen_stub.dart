import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_canvas_target.dart';

/// Whether the scenes are drawn on the engine's canvas: never off the web.
bool get sceneScreenOn => false;

/// A view's place on the engine's canvas; nothing off the web.
final class SceneScreenPlace implements SceneCanvasTarget {
  /// The place of [view], built again by [rebuild].
  SceneScreenPlace(BuildContext view, void Function() rebuild);

  /// The box the scene fills.
  set box(BuildContext? context) {}

  /// Whether the view is shown (an inactive route's is not).
  set visible(bool value) {}

  /// The device's pixels in a logical one.
  set ratio(double value) {}

  /// The size of the screen the view is on, in logical pixels.
  set screen(Size value) {}

  @override
  Widget build() => const SizedBox.shrink();

  @override
  bool present(void Function() draw) => false;

  @override
  void dispose() {}
}
